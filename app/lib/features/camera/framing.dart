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

/// The visible crop in shot space. The crop is measured on the portrait
/// frame; when the phone is held sideways the saved photo is rotated by
/// [quarterTurns] (1 = top of the phone to the left), so is the crop.
Rect cropInShotSpace(Rect portraitCrop, int quarterTurns) {
  final c = portraitCrop;
  return switch (quarterTurns) {
    // Photo rotated counter-clockwise: (x, y) -> (y, 1 - x).
    1 => Rect.fromLTWH(c.top, 1 - c.right, c.height, c.width),
    // Photo rotated clockwise: (x, y) -> (1 - y, x).
    -1 => Rect.fromLTWH(1 - c.bottom, c.left, c.height, c.width),
    _ => c,
  };
}

/// Re-expresses landmarks (already in shot space) in the visible crop.
/// Points outside it get visibility 0, so the engine treats them as out of
/// frame.
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
    orientation: frame.orientation,
    rollDeg: frame.rollDeg,
    rollReliable: frame.rollReliable,
    pitchDeg: frame.pitchDeg,
    at: frame.at,
  );
}

class _ShotJob {
  const _ShotJob(this.path, this.previewAspect, this.crop, this.quarterTurns);

  final String path;
  final double previewAspect;
  final Rect crop;
  final int quarterTurns;
}

/// Turns the captured still (always taken in portrait) into the final photo:
/// crop to what the preview showed, then rotate when the phone was held
/// sideways. Runs in a background isolate; returns the new file path, or the
/// original path if the file cannot be decoded.
Future<String> finishShot(
  String path, {
  required double previewAspect,
  required Rect crop,
  required int quarterTurns,
}) => compute(_finish, _ShotJob(path, previewAspect, crop, quarterTurns));

String _finish(_ShotJob job) {
  final bytes = File(job.path).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return job.path;
  var photo = img.bakeOrientation(decoded);

  // 1) The still may have a different aspect than the preview stream
  //    (e.g. 4:3 vs 16:9); center-crop it to the preview's field of view.
  final fov = coverCrop(job.previewAspect, photo.width / photo.height);
  // 2) Then the part of the preview that was visible on screen.
  final region = Rect.fromLTWH(
    fov.left + job.crop.left * fov.width,
    fov.top + job.crop.top * fov.height,
    job.crop.width * fov.width,
    job.crop.height * fov.height,
  );
  if (region != const Rect.fromLTWH(0, 0, 1, 1)) {
    photo = img.copyCrop(
      photo,
      x: (region.left * photo.width).round(),
      y: (region.top * photo.height).round(),
      width: (region.width * photo.width).round(),
      height: (region.height * photo.height).round(),
    );
  }
  // 3) Landscape: copyRotate's positive angle is clockwise.
  if (job.quarterTurns != 0) {
    photo = img.copyRotate(photo, angle: -90 * job.quarterTurns);
  }
  if (identical(photo, decoded)) return job.path;

  final base = job.path.replaceFirst(
    RegExp(r'\.(jpe?g)$', caseSensitive: false),
    '',
  );
  final file = File('${base}_gudory.jpg')
    ..writeAsBytesSync(Uint8List.fromList(img.encodeJpg(photo, quality: 95)));
  return file.path;
}
