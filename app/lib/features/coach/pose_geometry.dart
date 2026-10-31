import 'dart:math' as math;

import '../../core/models.dart';

/// ML Kit Android coordinates already include InputImageMetadata.rotation.
Landmark normalizePortraitLandmark({
  required double x,
  required double y,
  required int portraitWidth,
  required int portraitHeight,
  required bool isFrontCamera,
  required double visibility,
}) {
  final normalizedX = x / portraitWidth;
  return Landmark(
    x: (isFrontCamera ? 1 - normalizedX : normalizedX).clamp(0.0, 1.0),
    y: (y / portraitHeight).clamp(0.0, 1.0),
    visibility: visibility.clamp(0.0, 1.0),
  );
}

/// Positive when the top of the phone tilts left; verify on the device.
double rollDegrees(double ax, double ay) => math.atan2(ax, ay) * 180 / math.pi;

/// Zero upright, approaching 90 degrees when lying flat (either face).
double pitchDegrees(double ax, double ay, double az) =>
    math.atan2(az.abs(), math.sqrt(ax * ax + ay * ay)) * 180 / math.pi;
