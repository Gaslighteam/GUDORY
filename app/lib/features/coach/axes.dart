import 'dart:math' as math;

import '../../core/models.dart';
import 'composition_math.dart';

export 'composition_math.dart' show CompositionMetrics, measureComposition;

class AxisErrors {
  AxisErrors({
    required Map<CoachAxis, double> errors,
    required this.currentRatio,
    required this.targetRatio,
    required this.framing,
    required this.orientation,
  }) : errors = Map.unmodifiable(errors);

  final Map<CoachAxis, double> errors;
  final double currentRatio;
  final double targetRatio;
  final Framing framing;
  final ShotOrientation orientation;
}

/// Positive: portrait-relative Roll, person too close, right, or low.
/// Spatial errors use shot-space shoulder x and eye-line y. PoseSource already
/// applies orientation and front-camera mirroring; do not rotate again here.
AxisErrors calculateAxisErrors(
  CompositionMetrics current,
  TargetComposition target, {
  required double rollDeg,
}) {
  if (current.framing != target.framing) {
    throw ArgumentError('Measure the live pose at target.framing first');
  }
  _requirePositive(target.tolRollDeg, 'tolRollDeg');
  _requirePositive(target.tolHeight, 'tolHeight');
  _requirePositive(target.tolX, 'tolX');
  _requirePositive(target.tolY, 'tolY');
  _requireFinite(rollDeg, 'rollDeg');
  _requireFinite(current.personCenterX, 'current.personCenterX');
  _requireFinite(current.personCenterY, 'current.personCenterY');
  _requireFinite(target.personCenterX, 'target.personCenterX');
  _requireFinite(target.personCenterY, 'target.personCenterY');
  _requirePositive(current.personHeightRatio, 'currentRatio');
  _requirePositive(target.personHeightRatio, 'targetRatio');
  return AxisErrors(
    errors: {
      CoachAxis.level: rollDeg / target.tolRollDeg,
      CoachAxis.distance:
          (current.personHeightRatio - target.personHeightRatio) /
          target.tolHeight,
      CoachAxis.horizontal:
          (current.personCenterX - target.personCenterX) / target.tolX,
      CoachAxis.height:
          (current.personCenterY - target.personCenterY) / target.tolY,
    },
    currentRatio: current.personHeightRatio,
    targetRatio: target.personHeightRatio,
    framing: target.framing,
    orientation: current.orientation,
  );
}

/// Camera field of view rotates with shot space, not the portrait-locked UI.
double verticalFovDegrees(ShotOrientation orientation) =>
    orientation == ShotOrientation.portrait ? 65 : 50;
double horizontalFovDegrees(ShotOrientation orientation) =>
    orientation == ShotOrientation.portrait ? 50 : 65;

double _fovSpan(double degrees) => 2 * math.tan(degrees * math.pi / 360);

double estimateDistanceMeters(
  double ratio, {
  Framing framing = Framing.fullBody,
  ShotOrientation orientation = ShotOrientation.portrait,
}) {
  _requirePositive(ratio, 'ratio');
  return realSpanMeters(framing) /
      (ratio * _fovSpan(verticalFovDegrees(orientation)));
}

/// Nearest 0.5, ties up, minimum 0.5; direction stays in the signed errors.
double roundAmount(double amount) {
  _requireFinite(amount, 'amount');
  return math.max(0.5, (amount.abs() * 2).round() / 2);
}

/// Both ratios refer to the same framing and shot orientation. Orientation
/// mismatch guidance is the engine's responsibility before movement coaching.
double distanceSteps(
  double currentRatio,
  double targetRatio, {
  Framing framing = Framing.fullBody,
  ShotOrientation orientation = ShotOrientation.portrait,
}) => roundAmount(
  (estimateDistanceMeters(
            currentRatio,
            framing: framing,
            orientation: orientation,
          ) -
          estimateDistanceMeters(
            targetRatio,
            framing: framing,
            orientation: orientation,
          )) /
      0.6,
);

double horizontalSteps(
  double deltaX,
  double distanceMeters, {
  ShotOrientation orientation = ShotOrientation.portrait,
}) {
  _requireFinite(deltaX, 'deltaX');
  _requirePositive(distanceMeters, 'distanceMeters');
  return roundAmount(
    deltaX * distanceMeters * _fovSpan(horizontalFovDegrees(orientation)) / 0.6,
  );
}

double heightFists(
  double deltaY,
  double distanceMeters, {
  ShotOrientation orientation = ShotOrientation.portrait,
}) {
  _requireFinite(deltaY, 'deltaY');
  _requirePositive(distanceMeters, 'distanceMeters');
  return roundAmount(
    deltaY * distanceMeters * _fovSpan(verticalFovDegrees(orientation)) / 0.1,
  );
}

void _requireFinite(double value, String name) {
  if (!value.isFinite) throw ArgumentError.value(value, name, 'Must be finite');
}

void _requirePositive(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(value, name, 'Must be finite and positive');
  }
}
