import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as ml;
import 'package:image/image.dart' as img;
import '../../../../core/models.dart';
import '../../nv21_frame.dart';
import '../../person_mask.dart';
import '../../preprocess.dart';
import 'director_models.dart';

class LiveSample {
  const LiveSample(
    this.frame,
    this.points,
    this.poseMs,
    this.maskMs,
    this.prepMs, {
    required this.quarterTurns,
  });
  final int quarterTurns;
  final DirectorFrame frame;
  final List<(double, double, double)>? points;
  final double poseMs, maskMs, prepMs;
}

class LiveDirectorAnalyzer {
  final _detector = ml.PoseDetector(
    options: ml.PoseDetectorOptions(mode: ml.PoseDetectionMode.stream),
  );
  final _masker = PersonMasker();
  Future<LiveSample> process(
    CameraFrame camera, {
    required int quarterTurns,
    required int level,
    required double at,
    required String geometry,
  }) async {
    // One owned NV21 snapshot goes to BOTH native models and preprocessing.
    final data = Nv21FrameData.fromCameraFrame(camera);
    final timer = Stopwatch()..start();
    final detected = await _detector.processImage(
      ml.InputImage.fromBytes(
        bytes: data.packedBytes(),
        metadata: ml.InputImageMetadata(
          size: Size(data.width.toDouble(), data.height.toDouble()),
          rotation: ml.InputImageRotationValue.fromRawValue(data.rotation)!,
          format: ml.InputImageFormat.nv21,
          bytesPerRow: data.width,
        ),
      ),
    );
    final poseMs = timer.elapsedMicroseconds / 1000;
    timer.reset();
    final mask = await _masker.maskData(data);
    final maskMs = timer.elapsedMicroseconds / 1000;
    List<(double, double, double)>? points;
    if (detected.length == 1) {
      points = ml.PoseLandmarkType.values.map((type) {
        final p = detected.single.landmarks[type];
        if (p == null) return (0.0, 0.0, 0.0);
        var x = p.x / data.portraitWidth, y = p.y / data.portraitHeight;
        if (data.mirror) x = 1 - x;
        final (sx, sy) = switch (quarterTurns) {
          1 => (y, 1 - x),
          -1 => (1 - y, x),
          _ => (x, y),
        };
        return (sx, sy, p.likelihood);
      }).toList();
    }
    timer.reset();
    final frame = await compute(prepareVisibleFrame, (
      data,
      mask,
      points,
      quarterTurns,
      level,
      at,
      geometry,
    ));
    return LiveSample(
      frame,
      points,
      poseMs,
      maskMs,
      timer.elapsedMicroseconds / 1000,
      quarterTurns: quarterTurns,
    );
  }

  Future<void> close() async {
    await _detector.close();
    await _masker.close();
  }
}

DirectorFrame prepareVisibleFrame(
  (
    Nv21FrameData,
    PersonMask?,
    List<(double, double, double)>?,
    int,
    int,
    double,
    String,
  )
  job,
) {
  final (data, mask, points, q, level, at, geometry) = job;
  // Reuse the production RGB conversion and source-mask mapping, without its
  // CLIP mean fill or square center crop. The preview shows the full stream.
  var rgb = downsampleNv21(data);
  var foreground = img.Image(
    width: rgb.width,
    height: rgb.height,
    numChannels: 1,
  );
  if (mask != null && mask.isUsable) {
    for (final p in foreground) {
      // Conservative local maximum instead of allowing resampling to erase a
      // thin foreground boundary. Coordinates remain in original source space.
      var confidence = 0.0;
      for (var dy = 0; dy < 4; dy++) {
        for (var dx = 0; dx < 4; dx++) {
          final x = (p.x * 4 + dx).clamp(0, data.width - 1),
              y = (p.y * 4 + dy).clamp(0, data.height - 1);
          final v = mask.atSource(data, x, y);
          if (v > confidence) confidence = v;
        }
      }
      p.r = (confidence * 255).round();
    }
  }
  img.Image shot(img.Image image) {
    image = img.copyRotate(image, angle: data.rotation);
    if (data.mirror) image = img.flipHorizontal(image);
    return q == 0 ? image : img.copyRotate(image, angle: -90 * q);
  }

  rgb = shot(rgb);
  foreground = shot(foreground);
  final scale = 96 / (rgb.width > rgb.height ? rgb.width : rgb.height);
  final w = (rgb.width * scale).round().clamp(12, 128),
      h = (rgb.height * scale).round().clamp(12, 128);
  final gray = Float64List(w * h), maskValues = Float64List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      // Average RGB luminance, max pool foreground over the SAME source region.
      var sum = 0.0, maxMask = 0.0;
      var n = 0;
      final x0 = x * rgb.width ~/ w,
          x1 = ((x + 1) * rgb.width / w).ceil().clamp(x0 + 1, rgb.width);
      final y0 = y * rgb.height ~/ h,
          y1 = ((y + 1) * rgb.height / h).ceil().clamp(y0 + 1, rgb.height);
      for (var sy = y0; sy < y1; sy++) {
        for (var sx = x0; sx < x1; sx++) {
          final p = rgb.getPixel(sx, sy);
          sum += .299 * p.r + .587 * p.g + .114 * p.b;
          n++;
          final m = foreground.getPixel(sx, sy).r / 255;
          if (m > maxMask) maxMask = m;
        }
      }
      gray[y * w + x] = sum / n;
      maskValues[y * w + x] = maxMask;
    }
  }
  return DirectorFrame(
    w,
    h,
    gray,
    maskValues,
    DirectorPerson.fromPoints(points),
    at,
    orientation: q == 0 ? 'portrait' : 'landscape',
    level: level,
    geometry: geometry,
  );
}
