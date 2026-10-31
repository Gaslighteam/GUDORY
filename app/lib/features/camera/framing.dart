// What you see is what you get: the saved photo and the coaching coordinates
// both use exactly the part of the camera frame visible in the preview.
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../core/models.dart';

/// Visible part of the portrait camera frame, normalized 0~1.
/// The preview is shown with BoxFit.cover, so one axis is cropped.
final visibleCropProvider = NotifierProvider<VisibleCropNotifier, Rect>(
  VisibleCropNotifier.new,
);

class VisibleCropNotifier extends Notifier<Rect> {
  @override
  Rect build() => const Rect.fromLTWH(0, 0, 1, 1);

  /// [viewport] = preview area on screen; [frameAspect] = width / height of
  /// the portrait camera frame.
  void update(Size viewport, double frameAspect) {
    final next = coverCrop(viewport.width / viewport.height, frameAspect);
    if (next != state) state = next;
  }
}

/// Normalized crop that BoxFit.cover applies to a frame of [frameAspect]
/// shown in a box of [viewAspect] (both width / height).
Rect coverCrop(double viewAspect, double frameAspect) {
  if (frameAspect > viewAspect) {
    // Frame is wider: left/right are cut.
    final w = viewAspect / frameAspect;
    return Rect.fromLTWH((1 - w) / 2, 0, w, 1);
  }
  final h = frameAspect / viewAspect;
  return Rect.fromLTWH(0, (1 - h) / 2, 1, h);
}

/// Re-expresses landmarks in the visible crop. Points outside it get
/// visibility 0, so the engine treats them as out of frame.
PoseFrame toVisible(PoseFrame frame, Rect crop) {
  final landmarks = frame.landmarks;
  if (landmarks == null || crop == const Rect.fromLTWH(0, 0, 1, 1)) {
    return frame;
  }
  return PoseFrame(
    landmarks: [
      for (final l in landmarks)
        () {
          final x = (l.x - crop.left) / crop.width;
          final y = (l.y - crop.top) / crop.height;
          final inside = x >= 0 && x <= 1 && y >= 0 && y <= 1;
          return Landmark(x: x, y: y, visibility: inside ? l.visibility : 0);
        }(),
    ],
    imageWidth: (frame.imageWidth * crop.width).round(),
    imageHeight: (frame.imageHeight * crop.height).round(),
    rollDeg: frame.rollDeg,
    pitchDeg: frame.pitchDeg,
    at: frame.at,
  );
}

class _CropJob {
  const _CropJob(this.path, this.previewAspect, this.crop);

  final String path;
  final double previewAspect;
  final Rect crop;
}

/// Crops the captured still to what the preview showed and returns the new
/// file path. Runs in a background isolate. Returns the original path if the
/// file cannot be decoded.
Future<String> cropToVisible(
  String path, {
  required double previewAspect,
  required Rect crop,
}) => compute(_crop, _CropJob(path, previewAspect, crop));

String _crop(_CropJob job) {
  final bytes = File(job.path).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return job.path;
  var photo = img.bakeOrientation(decoded);

  // 1) The still may have a different aspect than the preview stream
  //    (e.g. 4:3 vs 16:9); center-crop it to the preview's field of view.
  final photoAspect = photo.width / photo.height;
  final fov = coverCrop(job.previewAspect, photoAspect);
  // 2) Then the part of the preview that was visible on screen.
  final region = Rect.fromLTWH(
    fov.left + job.crop.left * fov.width,
    fov.top + job.crop.top * fov.height,
    job.crop.width * fov.width,
    job.crop.height * fov.height,
  );
  if (region == const Rect.fromLTWH(0, 0, 1, 1)) return job.path;

  photo = img.copyCrop(
    photo,
    x: (region.left * photo.width).round(),
    y: (region.top * photo.height).round(),
    width: (region.width * photo.width).round(),
    height: (region.height * photo.height).round(),
  );
  final out = job.path.replaceFirst(
    RegExp(r'\.(jpe?g)$', caseSensitive: false),
    '',
  );
  final file = File('${out}_framed.jpg')
    ..writeAsBytesSync(Uint8List.fromList(img.encodeJpg(photo, quality: 95)));
  return file.path;
}
