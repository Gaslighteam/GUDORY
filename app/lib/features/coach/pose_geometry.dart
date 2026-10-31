import 'dart:math' as math;
import 'dart:ui';

import '../../core/models.dart';
import '../../core/orientation.dart';

/// Immutable sensor snapshot used for both detector rotation and output data.
class ShotAttitude {
  const ShotAttitude({
    required this.held,
    required this.rawRollDeg,
    required this.rollDeg,
    required this.pitchDeg,
    required this.rollReliable,
  });

  const ShotAttitude.initial()
    : held = HeldOrientation.portrait,
      rawRollDeg = 0,
      rollDeg = 0,
      pitchDeg = 0,
      rollReliable = false;

  final HeldOrientation held;
  final double rawRollDeg;
  final double rollDeg;
  final double pitchDeg;
  final bool rollReliable;

  ShotOrientation get orientation => held.orientation;
  int get quarterTurns => held.quarterTurns;
}

ShotAttitude updateShotAttitude(
  ShotAttitude previous, {
  required double ax,
  required double ay,
  required double az,
}) {
  final held = nextHeldOrientation(previous.held, ax, ay);
  final reliable = isRollReliable(ax, ay);
  final rawRoll = reliable ? accelRollDeg(ax, ay) : previous.rawRollDeg;
  final pitch = pitchDegrees(ax, ay, az);
  return ShotAttitude(
    held: held,
    rawRollDeg: rawRoll,
    rollDeg: reliable ? levelRollDeg(rawRoll, held) : previous.rollDeg,
    pitchDeg: pitch.isFinite ? pitch : previous.pitchDeg,
    rollReliable: reliable,
  );
}

/// Keeps the direction of each particular frame available to the debug page.
/// core's binary orientation and corrected roll cannot distinguish +/-90°.
/// Consumers may use this as PoseFrame; rollReliable is on the base contract.
class CoachPoseFrame extends PoseFrame {
  CoachPoseFrame({
    required super.landmarks,
    required super.imageWidth,
    required super.imageHeight,
    required this.attitude,
    required super.at,
  }) : super(
         orientation: attitude.orientation,
         rollDeg: attitude.rollDeg,
         pitchDeg: attitude.pitchDeg,
         rollReliable: attitude.rollReliable,
       );

  final ShotAttitude attitude;
}

/// Android rotation compensation using physical orientation, not locked UI.
/// ML Kit returns coordinates in this rotated image, so do not rotate them again.
({int rotationDegrees, int width, int height}) shotImageGeometry({
  required int sensorOrientation,
  required bool isFrontCamera,
  required int quarterTurns,
  required int rawWidth,
  required int rawHeight,
}) {
  if (![0, 90, 180, 270].contains(sensorOrientation) ||
      ![-1, 0, 1].contains(quarterTurns) ||
      rawWidth <= 0 ||
      rawHeight <= 0) {
    throw ArgumentError(
      'Invalid sensor rotation, shot direction or image size',
    );
  }
  final compensation = quarterTurns * 90;
  final rotation =
      (sensorOrientation + (isFrontCamera ? compensation : -compensation)) %
      360;
  final swap = rotation == 90 || rotation == 270;
  return (
    rotationDegrees: rotation,
    width: swap ? rawHeight : rawWidth,
    height: swap ? rawWidth : rawHeight,
  );
}

/// Coordinates returned by ML Kit already include the shot rotation.
Landmark normalizeShotLandmark({
  required double x,
  required double y,
  required int shotWidth,
  required int shotHeight,
  required bool isFrontCamera,
  required double visibility,
}) {
  final normalizedX = x / shotWidth;
  return Landmark(
    x: (isFrontCamera ? 1 - normalizedX : normalizedX).clamp(0.0, 1.0),
    y: (y / shotHeight).clamp(0.0, 1.0),
    visibility: visibility.clamp(0.0, 1.0),
  );
}

/// Compatibility helper for existing portrait-only callers/tests.
Landmark normalizePortraitLandmark({
  required double x,
  required double y,
  required int portraitWidth,
  required int portraitHeight,
  required bool isFrontCamera,
  required double visibility,
}) => normalizeShotLandmark(
  x: x,
  y: y,
  shotWidth: portraitWidth,
  shotHeight: portraitHeight,
  isFrontCamera: isFrontCamera,
  visibility: visibility,
);

/// Inverse of framing.dart's saved-photo rotation. Mirroring is already applied.
Offset shotToPortrait(Offset point, {required int quarterTurns}) =>
    switch (quarterTurns) {
      0 => point,
      1 => Offset(1 - point.dy, point.dx),
      -1 => Offset(point.dy, 1 - point.dx),
      _ => throw ArgumentError.value(quarterTurns, 'quarterTurns'),
    };

/// Portrait Roll sign was verified on device: positive = top tilted left.
double rollDegrees(double ax, double ay) => accelRollDeg(ax, ay);

/// Zero upright, approaching 90 degrees when lying flat (either face).
double pitchDegrees(double ax, double ay, double az) =>
    math.atan2(az.abs(), math.sqrt(ax * ax + ay * ay)) * 180 / math.pi;
