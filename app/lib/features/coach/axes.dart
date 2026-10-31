import 'dart:math' as math;

import '../../core/models.dart';

/// Measurements use the portrait coordinates supplied by PoseSource unchanged.
/// Step 1's device validation is pending; sensor/coordinate signs stay upstream.
class CompositionMetrics {
  const CompositionMetrics({
    required this.topOfHeadY,
    required this.personHeightRatio,
    required this.shoulderHipRatio,
    required this.personCenterX,
    required this.hipY,
    required this.isFullBody,
  });

  final double topOfHeadY;
  final double personHeightRatio;

  /// Vertical distance from mean shoulder y to mean hip y / frame height.
  final double shoulderHipRatio;
  final double personCenterX;
  final double hipY;
  final bool isFullBody;
}

class AxisErrors {
  AxisErrors({
    required Map<CoachAxis, double> errors,
    required this.currentRatio,
    required this.targetRatio,
    required this.needsWholeBody,
    required this.usesShoulderHipRatio,
  }) : errors = Map.unmodifiable(errors);

  final Map<CoachAxis, double> errors;
  final double currentRatio;
  final double targetRatio;

  /// When true, request full-body framing before using errors or amounts.
  /// The distance error is still reported for debug, using the ankle estimate.
  final bool needsWholeBody;
  final bool usesShoulderHipRatio;
}

/// null means there is no complete, finite 33-joint pose to measure.
CompositionMetrics? measureComposition(PoseFrame frame) {
  final points = frame.landmarks;
  if (points == null || points.length != 33) return null;
  // ML Kit PoseLandmarkType order: nose, shoulders, hips, ankles.
  final nose = points[0];
  final leftShoulder = points[11];
  final rightShoulder = points[12];
  final leftHip = points[23];
  final rightHip = points[24];
  final leftAnkle = points[27];
  final rightAnkle = points[28];
  for (final point in [
    nose,
    leftShoulder,
    rightShoulder,
    leftHip,
    rightHip,
    leftAnkle,
    rightAnkle,
  ]) {
    if (!point.x.isFinite || !point.y.isFinite || !point.visibility.isFinite) {
      return null;
    }
  }
  final shoulderY = (leftShoulder.y + rightShoulder.y) / 2;
  final hipY = (leftHip.y + rightHip.y) / 2;
  final topY = nose.y - (shoulderY - nose.y) * 0.6;
  final ankleY = (leftAnkle.y + rightAnkle.y) / 2;
  return CompositionMetrics(
    topOfHeadY: topY,
    personHeightRatio: ankleY - topY,
    shoulderHipRatio: hipY - shoulderY,
    personCenterX:
        (leftShoulder.x + rightShoulder.x + leftHip.x + rightHip.x) / 4,
    hipY: hipY,
    isFullBody: leftAnkle.visibility >= 0.5 && rightAnkle.visibility >= 0.5,
  );
}

/// Positive signs: roll as supplied, too close, person right, person low.
/// These correspond to upright, stepBack, stepRight and phoneDown guidance.
///
/// Half-body metadata is coach-local because core's target has no such fields.
/// A half-body target requires its measured shoulder-to-hip ratio. Compare that
/// same metric even when the live ankles are visible, so visibility changes do
/// not switch the distance error to a different physical length.
AxisErrors calculateAxisErrors(
  CompositionMetrics current,
  TargetComposition target, {
  required double rollDeg,
  bool targetIsFullBody = true,
  double? targetShoulderHipRatio,
}) {
  _requirePositive(target.tolRollDeg, 'tolRollDeg');
  _requirePositive(target.tolHeight, 'tolHeight');
  _requirePositive(target.tolX, 'tolX');
  _requirePositive(target.tolY, 'tolY');
  _requireFinite(rollDeg, 'rollDeg');
  _requireFinite(current.personCenterX, 'current.personCenterX');
  _requireFinite(current.hipY, 'current.hipY');
  _requireFinite(target.personCenterX, 'target.personCenterX');
  _requireFinite(target.personCenterY, 'target.personCenterY');

  final useTorso = !targetIsFullBody;
  if (useTorso && targetShoulderHipRatio == null) {
    throw ArgumentError('Half-body targets require targetShoulderHipRatio');
  }
  final currentRatio = useTorso
      ? current.shoulderHipRatio
      : current.personHeightRatio;
  final targetRatio = useTorso
      ? targetShoulderHipRatio!
      : target.personHeightRatio;
  _requireFinite(currentRatio, 'currentRatio');
  _requirePositive(targetRatio, 'targetRatio');

  return AxisErrors(
    errors: {
      CoachAxis.level: rollDeg / target.tolRollDeg,
      CoachAxis.distance: (currentRatio - targetRatio) / target.tolHeight,
      CoachAxis.horizontal:
          (current.personCenterX - target.personCenterX) / target.tolX,
      CoachAxis.height: (current.hipY - target.personCenterY) / target.tolY,
    },
    currentRatio: currentRatio,
    targetRatio: targetRatio,
    needsWholeBody: targetIsFullBody && !current.isFullBody,
    usesShoulderHipRatio: useTorso,
  );
}

final double _verticalSpan = 2 * math.tan(32.5 * math.pi / 180);
final double _horizontalSpan = 2 * math.tan(25 * math.pi / 180);

/// Specified 1.65 m calibration. For torso ratios this is a heuristic scale,
/// not a calibrated physical distance to a full-height 1.65 m person.
double estimateDistanceMeters(double ratio) {
  _requirePositive(ratio, 'ratio');
  return 1.65 / (ratio * _verticalSpan);
}

/// Nearest 0.5, with ties rounded up and minimum 0.5. Sign is carried by errors.
double roundAmount(double amount) {
  _requireFinite(amount, 'amount');
  return math.max(0.5, (amount.abs() * 2).round() / 2);
}

double distanceSteps(double currentRatio, double targetRatio) => roundAmount(
  (estimateDistanceMeters(currentRatio) - estimateDistanceMeters(targetRatio)) /
      0.6,
);

double horizontalSteps(double deltaX, double distanceMeters) {
  _requireFinite(deltaX, 'deltaX');
  _requirePositive(distanceMeters, 'distanceMeters');
  return roundAmount(deltaX * distanceMeters * _horizontalSpan / 0.6);
}

double heightFists(double deltaY, double distanceMeters) {
  _requireFinite(deltaY, 'deltaY');
  _requirePositive(distanceMeters, 'distanceMeters');
  return roundAmount(deltaY * distanceMeters * _verticalSpan / 0.1);
}

void _requireFinite(double value, String name) {
  if (!value.isFinite) throw ArgumentError.value(value, name, 'Must be finite');
}

void _requirePositive(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(value, name, 'Must be finite and positive');
  }
}
