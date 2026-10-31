import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/features/coach/axes.dart';

void main() {
  const target = TargetComposition.fallback;

  group('composition measurements', () {
    test('head estimate, mean ankles, four-point x and mean hip y', () {
      final metrics = measureComposition(pose())!;
      expect(metrics.topOfHeadY, closeTo(0.14, 1e-12));
      expect(metrics.personHeightRatio, closeTo(0.76, 1e-12));
      expect(metrics.shoulderHipRatio, closeTo(0.30, 1e-12));
      expect(metrics.personCenterX, closeTo(0.50, 1e-12));
      expect(metrics.hipY, closeTo(0.60, 1e-12));
      expect(metrics.isFullBody, isTrue);
    });

    test('either ankle below 0.5 means not full body', () {
      expect(
        measureComposition(pose(leftVisibility: 0.49))!.isFullBody,
        isFalse,
      );
      expect(
        measureComposition(pose(rightVisibility: 0.49))!.isFullBody,
        isFalse,
      );
    });

    test('both ankles exactly 0.5 count as full body', () {
      expect(
        measureComposition(
          pose(leftVisibility: 0.5, rightVisibility: 0.5),
        )!.isFullBody,
        isTrue,
      );
    });

    test('no person or incomplete pose returns null', () {
      expect(measureComposition(frame(null)), isNull);
      expect(measureComposition(frame(const [])), isNull);
      expect(
        measureComposition(
          frame(List.filled(28, const Landmark(x: 0, y: 0, visibility: 1))),
        ),
        isNull,
      );
    });

    test('nonfinite landmark is rejected', () {
      final points = List<Landmark>.of(pose().landmarks!);
      points[11] = const Landmark(x: double.nan, y: 0.3, visibility: 1);
      expect(measureComposition(frame(points)), isNull);
    });
  });

  group('normalized axis errors and directions', () {
    test('level preserves positive and negative roll signs', () {
      final metrics = measureComposition(pose())!;
      expect(
        calculateAxisErrors(
          metrics,
          target,
          rollDeg: 6,
        ).errors[CoachAxis.level],
        2,
      );
      expect(
        calculateAxisErrors(
          metrics,
          target,
          rollDeg: -6,
        ).errors[CoachAxis.level],
        -2,
      );
    });

    test(
      'larger ratio is positive (stepBack), smaller is negative (stepForward)',
      () {
        final near = measureComposition(pose())!; // 0.76 vs 0.60
        final far = measureComposition(pose(ankleY: 0.58))!; // 0.44
        expect(
          calculateAxisErrors(
            near,
            target,
            rollDeg: 0,
          ).errors[CoachAxis.distance],
          closeTo(1.6, 1e-12),
        );
        expect(
          calculateAxisErrors(
            far,
            target,
            rollDeg: 0,
          ).errors[CoachAxis.distance],
          closeTo(-1.6, 1e-12),
        );
      },
    );

    test(
      'person right is positive (stepRight), left is negative (stepLeft)',
      () {
        final right = measureComposition(pose(xShift: 0.16))!;
        final left = measureComposition(pose(xShift: -0.16))!;
        expect(
          calculateAxisErrors(
            right,
            target,
            rollDeg: 0,
          ).errors[CoachAxis.horizontal],
          closeTo(2, 1e-12),
        );
        expect(
          calculateAxisErrors(
            left,
            target,
            rollDeg: 0,
          ).errors[CoachAxis.horizontal],
          closeTo(-2, 1e-12),
        );
      },
    );

    test('hip low is positive (phoneDown), high is negative (phoneUp)', () {
      final low = measureComposition(pose(yShift: 0.16))!;
      final high = measureComposition(pose(yShift: -0.16))!;
      expect(
        calculateAxisErrors(low, target, rollDeg: 0).errors[CoachAxis.height],
        closeTo(2, 1e-12),
      );
      expect(
        calculateAxisErrors(high, target, rollDeg: 0).errors[CoachAxis.height],
        closeTo(-2, 1e-12),
      );
    });

    test('matching composition gives zero on all four axes', () {
      final metrics = measureComposition(pose(ankleY: 0.74))!;
      final result = calculateAxisErrors(metrics, target, rollDeg: 0);
      expect(result.errors.keys.toSet(), CoachAxis.values.toSet());
      for (final error in result.errors.values) {
        expect(error, closeTo(0, 1e-12));
      }
    });

    test('each custom tolerance divides its own raw error', () {
      const custom = TargetComposition(
        personHeightRatio: 0.6,
        personCenterX: 0.4,
        personCenterY: 0.5,
        tolHeight: 0.2,
        tolX: 0.1,
        tolY: 0.05,
        tolRollDeg: 2,
        source: 'reference',
      );
      final result = calculateAxisErrors(
        measureComposition(pose())!,
        custom,
        rollDeg: 4,
      );
      expect(result.errors[CoachAxis.level], 2);
      expect(result.errors[CoachAxis.distance], closeTo(0.8, 1e-12));
      expect(result.errors[CoachAxis.horizontal], closeTo(1, 1e-12));
      expect(result.errors[CoachAxis.height], closeTo(2, 1e-12));
    });
  });

  group('full and half body', () {
    test(
      'cropped live pose with full-body target requests whole-body framing',
      () {
        final current = measureComposition(pose(leftVisibility: 0.1))!;
        final result = calculateAxisErrors(current, target, rollDeg: 0);
        expect(result.needsWholeBody, isTrue);
        expect(result.usesShoulderHipRatio, isFalse);
        expect(result.errors.length, 4);
      },
    );

    test(
      'both half-body uses shoulder-hip ratio, ignoring inferred ankle y',
      () {
        final current = measureComposition(
          pose(leftVisibility: 0.1, ankleY: 0.1),
        )!;
        final result = calculateAxisErrors(
          current,
          target,
          rollDeg: 0,
          targetIsFullBody: false,
          targetShoulderHipRatio: 0.2,
        );
        expect(result.needsWholeBody, isFalse);
        expect(result.usesShoulderHipRatio, isTrue);
        expect(result.currentRatio, closeTo(0.3, 1e-12));
        expect(result.targetRatio, 0.2);
        expect(result.errors[CoachAxis.distance], closeTo(1, 1e-12));
      },
    );

    test('half-body distance error can be negative', () {
      final result = calculateAxisErrors(
        measureComposition(pose(rightVisibility: 0.1))!,
        target,
        rollDeg: 0,
        targetIsFullBody: false,
        targetShoulderHipRatio: 0.4,
      );
      expect(result.errors[CoachAxis.distance], closeTo(-1, 1e-12));
    });

    test('half-body reference remains on torso metric as ankles appear', () {
      final result = calculateAxisErrors(
        measureComposition(pose())!,
        target,
        rollDeg: 0,
        targetIsFullBody: false,
        targetShoulderHipRatio: 0.3,
      );
      expect(result.needsWholeBody, isFalse);
      expect(result.errors[CoachAxis.distance], closeTo(0, 1e-12));
    });

    test(
      'half-body target requires explicit metadata, never guessed from height',
      () {
        expect(
          () => calculateAxisErrors(
            measureComposition(pose(leftVisibility: 0.1))!,
            target,
            rollDeg: 0,
            targetIsFullBody: false,
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('movement amounts', () {
    test('distance uses 1.65m and 65 degree vertical field of view', () {
      expect(estimateDistanceMeters(0.6), closeTo(2.158317668536549, 1e-8));
      expect(
        estimateDistanceMeters(0.3),
        closeTo(2 * estimateDistanceMeters(0.6), 1e-12),
      );
    });

    test('distance steps use absolute difference divided by 0.6m', () {
      expect(distanceSteps(0.6, 0.3), 3.5);
      expect(distanceSteps(0.3, 0.6), 3.5);
      expect(distanceSteps(0.6, 0.6), 0.5);
    });

    test('horizontal steps use 50 degree horizontal FOV and 0.6m step', () {
      expect(horizontalSteps(0.2, 3), 1);
      expect(horizontalSteps(-0.2, 3), 1);
      expect(horizontalSteps(0.1, 6), 1);
    });

    test('height uses 65 degree vertical FOV and 0.1m fist', () {
      expect(heightFists(0.1, 3), 4);
      expect(heightFists(-0.1, 3), 4);
      expect(heightFists(0.2, 1.5), 4);
    });

    test('rounds nearest half, half-way up, minimum half for either sign', () {
      for (final value in [0.0, 0.01, 0.24, 0.25, 0.74]) {
        expect(roundAmount(value), 0.5);
        expect(roundAmount(-value), 0.5);
      }
      expect(roundAmount(0.75), 1);
      expect(roundAmount(1.24), 1);
      expect(roundAmount(1.25), 1.5);
      expect(roundAmount(-1.25), 1.5);
    });

    test('invalid distance inputs do not create infinite movement amounts', () {
      for (final ratio in [0.0, -0.1, double.nan, double.infinity]) {
        expect(() => estimateDistanceMeters(ratio), throwsArgumentError);
      }
      expect(() => horizontalSteps(0.1, 0), throwsArgumentError);
      expect(() => heightFists(0.1, -1), throwsArgumentError);
      expect(() => roundAmount(double.infinity), throwsArgumentError);
    });

    test('zero tolerance is rejected', () {
      const invalid = TargetComposition(
        personHeightRatio: 0.6,
        personCenterX: 0.5,
        personCenterY: 0.6,
        tolX: 0,
        source: 'reference',
      );
      expect(
        () => calculateAxisErrors(
          measureComposition(pose())!,
          invalid,
          rollDeg: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}

PoseFrame frame(List<Landmark>? points) => PoseFrame(
  landmarks: points,
  imageWidth: 480,
  imageHeight: 640,
  rollDeg: 0,
  pitchDeg: 0,
  at: DateTime.utc(2026, 10, 31),
);

PoseFrame pose({
  double xShift = 0,
  double yShift = 0,
  double ankleY = 0.9,
  double leftVisibility = 1,
  double rightVisibility = 1,
}) {
  final points = List.filled(33, const Landmark(x: 0.5, y: 0.5, visibility: 1));
  void setPoint(int index, double x, double y, [double visibility = 1]) {
    points[index] = Landmark(
      x: x + xShift,
      y: y + yShift,
      visibility: visibility,
    );
  }

  setPoint(0, 0.5, 0.2);
  setPoint(11, 0.2, 0.28);
  setPoint(12, 0.6, 0.32);
  setPoint(23, 0.5, 0.58);
  setPoint(24, 0.7, 0.62);
  setPoint(27, 0.4, ankleY - 0.02, leftVisibility);
  setPoint(28, 0.6, ankleY + 0.02, rightVisibility);
  return frame(points);
}
