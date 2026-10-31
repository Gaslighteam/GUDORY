import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as ml;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../core/contracts.dart';
import '../../core/models.dart';
import 'composition_math.dart';

/// A reference is already a finished shot: no preview crop, accelerometer
/// rotation or camera mirroring is applied to its EXIF-corrected pixels.
class MlKitReferenceAnalyzer implements ReferenceAnalyzer {
  MlKitReferenceAnalyzer({Future<Directory> Function()? temporaryDirectory})
    : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
      _detector = ml.PoseDetector(
        options: ml.PoseDetectorOptions(mode: ml.PoseDetectionMode.single),
      );

  final Future<Directory> Function() _temporaryDirectory;
  final ml.PoseDetector _detector;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;
  bool _disposed = false;

  @override
  Future<TargetComposition> analyze(String imagePath) {
    if (_disposed) {
      return Future.error(StateError('ReferenceAnalyzer is disposed'));
    }
    // Serialize accepted jobs: bound decode memory and avoid detector/close
    // races. A failed job must not poison later references in the queue.
    final result = _tail.then((_) => _analyze(imagePath));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<TargetComposition> _analyze(String imagePath) async {
    Directory? work;
    try {
      final prepared = await compute(
        _prepareReference,
        await File(imagePath).readAsBytes(),
      );
      final parent = await _temporaryDirectory();
      work = await parent.createTemp('gudory-reference-');
      final normalized = await File(
        '${work.path}/normalized.png',
      ).writeAsBytes(prepared.bytes, flush: true);
      final poses = await _detector.processImage(
        ml.InputImage.fromFilePath(normalized.path),
      );
      if (poses.isEmpty) throw const NoPersonException();
      final pose = poses.first;
      final landmarks = ml.PoseLandmarkType.values
          .map((type) {
            final point = pose.landmarks[type];
            if (point == null) {
              return const Landmark(x: 0, y: 0, visibility: 0);
            }
            // Preserve out-of-image coordinates so visibility/anchor checks reject
            // them; clamping an inferred ankle would falsely make it visible.
            return Landmark(
              x: point.x / prepared.width,
              y: point.y / prepared.height,
              visibility: point.likelihood,
            );
          })
          .toList(growable: false);
      return referenceTargetFromLandmarks(
        landmarks: landmarks,
        imageWidth: prepared.width,
        imageHeight: prepared.height,
      );
    } finally {
      if (work != null && await work.exists()) {
        await work.delete(recursive: true);
      }
    }
  }

  /// Finishes all accepted analyses (including cleanup), then closes once.
  /// New analyses are rejected immediately after disposal starts.
  Future<void> dispose() => _closing ??= _close();

  Future<void> _close() async {
    _disposed = true;
    await _tail;
    await _detector.close();
  }
}

/// Pure mapping from normalized, EXIF-corrected reference landmarks.
/// Square images use portrait. Reference framing is actually visible, not an
/// inferred full-body span; the latter is reserved for live coaching.
TargetComposition referenceTargetFromLandmarks({
  required List<Landmark>? landmarks,
  required int imageWidth,
  required int imageHeight,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) {
    throw ArgumentError('Reference image dimensions must be positive');
  }
  if (landmarks == null || landmarks.length != 33) {
    throw const NoPersonException();
  }
  // Shoulders must be visible. Nose and eyes may have any visibility above 0
  // (estimated positions: back views and profiles, AGENTS.md head reference)
  // but must lie inside the reference image.
  for (final index in [0, 2, 5, 11, 12]) {
    final point = landmarks[index];
    final head = index == 0 || index == 2 || index == 5;
    if (!point.x.isFinite ||
        !point.y.isFinite ||
        !point.visibility.isFinite ||
        (head
            ? point.visibility <= 0
            : point.visibility < landmarkVisibilityThreshold) ||
        point.x < 0 ||
        point.x > 1 ||
        point.y < 0 ||
        point.y > 1) {
      throw const NoPersonException();
    }
  }
  final orientation = imageWidth > imageHeight
      ? ShotOrientation.landscape
      : ShotOrientation.portrait;
  final frame = PoseFrame(
    landmarks: landmarks,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    orientation: orientation,
    rollDeg: 0,
    pitchDeg: 0,
    rollReliable: false, // A still image does not supply sensor measurements.
    at: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
  final initial = measureComposition(frame);
  if (initial == null) throw const NoPersonException();
  final metrics = measureComposition(frame, framing: initial.visibleFraming)!;
  final span = metrics.personHeightRatio;
  if (!span.isFinite || span <= 0 || span > 1) {
    throw const FormatException('사진에서 유효한 인물 구도를 계산할 수 없어요');
  }
  return TargetComposition(
    framing: metrics.framing,
    personHeightRatio: span,
    personCenterX: metrics.personCenterX,
    personCenterY: metrics.personCenterY,
    orientation: orientation,
    horizonY: null,
    tolHeight: 0.10,
    tolX: 0.08,
    tolY: 0.08,
    tolRollDeg: 3,
    source: 'reference',
  );
}

class _PreparedReference {
  const _PreparedReference(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

_PreparedReference _prepareReference(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('지원하지 않는 이미지 형식이에요');
  final normalized = img.bakeOrientation(decoded);
  // Explicitly remove even a no-op orientation=1. ML Kit must not perform a
  // second EXIF rotation or reflection on the prepared PNG.
  normalized.exif.imageIfd.orientation = null;
  return _PreparedReference(
    img.encodePng(normalized),
    normalized.width,
    normalized.height,
  );
}
