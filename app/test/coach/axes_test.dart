import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/features/coach/axes.dart';
import 'package:gudory/features/coach/composition_math.dart';

void main() {
  // Test-owned contract values: never inherit product fallback defaults.
  const target = TargetComposition(
    framing: Framing.fullBody,
    personHeightRatio: 0.6,
    personCenterX: 0.4,
    personCenterY: 0.18,
    orientation: ShotOrientation.portrait,
    source: 'reference',
  );

  group('latest composition contract', () {
    test('head coefficient 0.5, shoulder x and eye-line y', () {
      final metrics = measureComposition(pose())!;
      expect(metrics.topOfHeadY, closeTo(0.15, 1e-12));
      expect(metrics.personHeightRatio, closeTo(0.75, 1e-12));
      expect(metrics.personScale, closeTo(0.15, 1e-12));
      expect(metrics.personCenterX, closeTo(0.4, 1e-12));
      expect(metrics.personCenterY, closeTo(0.18, 1e-12));
      expect(metrics.framing, Framing.fullBody);
      expect(metrics.visibleFraming, Framing.fullBody);
      expect(metrics.estimated, isFalse);
    });

    test('hip movement does not change shoulder x or eye-line y', () {
      final points = List<Landmark>.of(pose().landmarks!);
      points[23] = const Landmark(x: 0.9, y: 0.7, visibility: 1);
      points[24] = const Landmark(x: 0.95, y: 0.8, visibility: 1);
      final result = measureComposition(frame(points))!;
      expect(result.personCenterX, closeTo(0.4, 1e-12));
      expect(result.personCenterY, closeTo(0.18, 1e-12));
    });

    for (final (framing, span) in [
      (Framing.chestUp, 0.15),
      (Framing.waistUp, 0.45),
      (Framing.kneeUp, 0.65),
      (Framing.fullBody, 0.75),
    ]) {
      test(
        '$framing measures its own anchor even if lower joints are visible',
        () {
          final metrics = measureComposition(pose(), framing: framing)!;
          expect(metrics.personHeightRatio, closeTo(span, 1e-12));
          expect(metrics.measuredFrom, framing);
          expect(metrics.estimated, isFalse);
        },
      );
    }

    test('visibility exactly 0.5 counts as a measured anchor', () {
      final metrics = measureComposition(pose(ankleVisibility: 0.5))!;
      expect(metrics.measuredFrom, Framing.fullBody);
      expect(metrics.estimated, isFalse);
    });

    test('either ankle below 0.5 uses visible knees instead', () {
      for (final index in [27, 28]) {
        final points = List<Landmark>.of(pose().landmarks!);
        final old = points[index];
        points[index] = Landmark(x: old.x, y: old.y, visibility: 0.49);
        final metrics = measureComposition(frame(points))!;
        expect(metrics.measuredFrom, Framing.kneeUp);
        expect(metrics.personHeightRatio, closeTo(0.8760869565217392, 1e-12));
      }
    });

    test('out-of-crop anchor is ignored even with high likelihood', () {
      final metrics = measureComposition(pose(ankleY: 1.1))!;
      expect(metrics.estimated, isTrue);
      expect(metrics.measuredFrom, Framing.kneeUp);
    });

    test(
      'nonfinite hidden lower joints do not invalidate visible upper body',
      () {
        final points = List<Landmark>.of(pose().landmarks!);
        points[27] = const Landmark(
          x: double.nan,
          y: double.nan,
          visibility: 0,
        );
        final metrics = measureComposition(frame(points))!;
        expect(metrics.measuredFrom, Framing.kneeUp);
        expect(metrics.personHeightRatio.isFinite, isTrue);
      },
    );

    test(
      'no person, incomplete pose or invalid head geometry returns null',
      () {
        expect(measureComposition(frame(null)), isNull);
        expect(measureComposition(frame(const [])), isNull);
        expect(
          measureComposition(
            frame(
              List.filled(28, const Landmark(x: 0.5, y: 0.5, visibility: 1)),
            ),
          ),
          isNull,
        );
        expect(measureComposition(pose(noseY: 0.4)), isNull);
      },
    );

    test('nose and both shoulders must be visible and finite', () {
      for (final index in [0, 11, 12]) {
        final points = List<Landmark>.of(pose().landmarks!);
        final old = points[index];
        points[index] = Landmark(x: old.x, y: old.y, visibility: 0.49);
        expect(measureComposition(frame(points)), isNull);
      }
      final points = List<Landmark>.of(pose().landmarks!);
      points[11] = const Landmark(x: double.nan, y: 0.3, visibility: 1);
      expect(measureComposition(frame(points)), isNull);
    });

    test(
      'nonfinite eye line is rejected rather than producing NaN guidance',
      () {
        final points = List<Landmark>.of(pose().landmarks!);
        points[2] = const Landmark(x: 0.4, y: double.nan, visibility: 1);
        expect(measureComposition(frame(points)), isNull);
      },
    );
  });

  group('cropped-person estimation at target framing', () {
    for (final (requested, available, expected) in [
      (Framing.waistUp, Framing.chestUp, 0.4285714285714286),
      (Framing.kneeUp, Framing.waistUp, 0.646875),
      (Framing.fullBody, Framing.kneeUp, 0.8760869565217392),
      (Framing.fullBody, Framing.waistUp, 0.871875),
      (Framing.fullBody, Framing.chestUp, 0.8303571428571428),
    ]) {
      test('$requested inferred from $available using real-span ratios', () {
        final current = pose(visibleThrough: available);
        final metrics = measureComposition(current, framing: requested)!;
        expect(metrics.framing, requested);
        expect(metrics.measuredFrom, available);
        expect(metrics.visibleFraming, available);
        expect(metrics.estimated, isTrue);
        expect(metrics.personHeightRatio, closeTo(expected, 1e-12));
      });
    }

    test(
      'a missing waist anchor can be estimated from visible lower anchors',
      () {
        final points = List<Landmark>.of(pose().landmarks!);
        for (final index in [23, 24]) {
          points[index] = const Landmark(x: 0.5, y: 0.6, visibility: 0);
        }
        final metrics = measureComposition(
          frame(points),
          framing: Framing.waistUp,
        )!;
        expect(metrics.measuredFrom, Framing.fullBody);
        expect(metrics.personHeightRatio, closeTo(0.3870967741935484, 1e-12));
      },
    );

    test(
      'a cropped large person yields positive distance error, never a fit gate',
      () {
        final current = scaledPose(fullBodySpan: 1.4);
        final metrics = measureComposition(current, framing: target.framing)!;
        final result = calculateAxisErrors(metrics, target, rollDeg: 0);
        expect(metrics.estimated, isTrue);
        expect(metrics.measuredFrom, Framing.waistUp);
        expect(metrics.personHeightRatio, closeTo(1.4, 1e-12));
        expect(result.errors[CoachAxis.distance], closeTo(8, 1e-12));
        expect(result.errors.length, 4);
      },
    );

    test('only shoulders are enough to infer all target spans', () {
      final current = scaledPose(
        fullBodySpan: 0.6,
        visibleThrough: Framing.chestUp,
      );
      for (final (framing, expected) in [
        (Framing.chestUp, 0.10838709677419356),
        (Framing.waistUp, 0.3096774193548387),
        (Framing.kneeUp, 0.4451612903225806),
        (Framing.fullBody, 0.6),
      ]) {
        expect(
          measureComposition(current, framing: framing)!.personHeightRatio,
          closeTo(expected, 1e-12),
        );
      }
    });

    test(
      'a waist-up reference always compares hip span, regardless of ankles',
      () {
        const waistTarget = TargetComposition(
          framing: Framing.waistUp,
          personHeightRatio: 0.45,
          personCenterX: 0.4,
          personCenterY: 0.18,
          source: 'reference',
        );
        for (final visible in [Framing.waistUp, Framing.fullBody]) {
          final metrics = measureComposition(
            pose(visibleThrough: visible),
            framing: waistTarget.framing,
          )!;
          final errors = calculateAxisErrors(metrics, waistTarget, rollDeg: 0);
          expect(errors.errors[CoachAxis.distance], closeTo(0, 1e-12));
        }
      },
    );

    test('wrong live measurement framing is rejected', () {
      const waistTarget = TargetComposition(
        framing: Framing.waistUp,
        personHeightRatio: 0.4,
        personCenterX: 0.4,
        personCenterY: 0.18,
        source: 'reference',
      );
      expect(
        () => calculateAxisErrors(
          measureComposition(pose())!,
          waistTarget,
          rollDeg: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('normalized axis signs', () {
    test('level preserves positive and negative Roll', () {
      final current = measureComposition(pose())!;
      expect(
        calculateAxisErrors(
          current,
          target,
          rollDeg: 6,
        ).errors[CoachAxis.level],
        2,
      );
      expect(
        calculateAxisErrors(
          current,
          target,
          rollDeg: -6,
        ).errors[CoachAxis.level],
        -2,
      );
    });

    test(
      'larger ratio is positive (stepBack), smaller is negative (stepForward)',
      () {
        final near = measureComposition(pose())!; // .9 - .15 = .75
        final far = measureComposition(pose(ankleY: 0.6))!; // .6 - .15 = .45
        expect(
          calculateAxisErrors(
            near,
            target,
            rollDeg: 0,
          ).errors[CoachAxis.distance],
          closeTo(1.5, 1e-12),
        );
        expect(
          calculateAxisErrors(
            far,
            target,
            rollDeg: 0,
          ).errors[CoachAxis.distance],
          closeTo(-1.5, 1e-12),
        );
      },
    );

    for (final orientation in ShotOrientation.values) {
      test('$orientation: shoulder right/left preserves horizontal sign', () {
        final t = targetIn(orientation);
        for (final sign in [-1, 1]) {
          final metrics = measureComposition(
            pose(dx: sign * 0.16, orientation: orientation),
          )!;
          expect(
            calculateAxisErrors(
              metrics,
              t,
              rollDeg: 0,
            ).errors[CoachAxis.horizontal],
            closeTo(sign * 2, 1e-12),
          );
        }
      });

      test('$orientation: eye line low/high preserves height sign', () {
        final t = targetIn(orientation);
        for (final sign in [-1, 1]) {
          final metrics = measureComposition(
            pose(eyeY: 0.18 + sign * 0.16, orientation: orientation),
          )!;
          expect(
            calculateAxisErrors(
              metrics,
              t,
              rollDeg: 0,
            ).errors[CoachAxis.height],
            closeTo(sign * 2, 1e-12),
          );
        }
      });
    }

    test('hip low alone no longer changes the height error', () {
      final metrics = measureComposition(pose(hipY: 0.9))!;
      expect(
        calculateAxisErrors(
          metrics,
          target,
          rollDeg: 0,
        ).errors[CoachAxis.height],
        closeTo(0, 1e-12),
      );
    });

    test('matching composition gives zero on all four axes', () {
      final metrics = measureComposition(pose(ankleY: 0.75))!;
      final result = calculateAxisErrors(metrics, target, rollDeg: 0);
      expect(result.errors.keys.toSet(), CoachAxis.values.toSet());
      for (final error in result.errors.values) {
        expect(error, closeTo(0, 1e-12));
      }
      expect(() => result.errors[CoachAxis.level] = 1, throwsUnsupportedError);
    });

    test('each explicit tolerance divides its own raw error', () {
      const custom = TargetComposition(
        framing: Framing.fullBody,
        personHeightRatio: 0.6,
        personCenterX: 0.3,
        personCenterY: 0.08,
        tolHeight: 0.2,
        tolX: 0.1,
        tolY: 0.05,
        tolRollDeg: 2,
        source: 'reference',
      );
      final errors = calculateAxisErrors(
        measureComposition(pose())!,
        custom,
        rollDeg: 4,
      ).errors;
      expect(errors[CoachAxis.level], 2);
      expect(errors[CoachAxis.distance], closeTo(0.75, 1e-12));
      expect(errors[CoachAxis.horizontal], closeTo(1, 1e-12));
      expect(errors[CoachAxis.height], closeTo(2, 1e-12));
    });
  });

  group('framing lengths and camera field of view', () {
    for (final (framing, metres, portrait, landscape) in [
      (Framing.chestUp, 0.28, 0.3662599679940811, 0.500384948118897),
      (Framing.waistUp, 0.80, 1.0464570514116602, 1.4296712803397058),
      (Framing.kneeUp, 1.15, 1.5042820114042614, 2.0551524654883266),
      (Framing.fullBody, 1.55, 2.027510537110092, 2.7699881056581797),
    ]) {
      test(
        '$framing real span and independent distance goldens for both orientations',
        () {
          expect(realSpanMeters(framing), metres);
          expect(
            estimateDistanceMeters(0.6, framing: framing),
            closeTo(portrait, 1e-12),
          );
          expect(
            estimateDistanceMeters(
              0.6,
              framing: framing,
              orientation: ShotOrientation.landscape,
            ),
            closeTo(landscape, 1e-12),
          );
          expect(
            estimateDistanceMeters(0.3, framing: framing),
            closeTo(portrait * 2, 1e-12),
          );
        },
      );
    }

    test('landscape swaps the vertical and horizontal FOVs', () {
      expect(verticalFovDegrees(ShotOrientation.portrait), 65);
      expect(horizontalFovDegrees(ShotOrientation.portrait), 50);
      expect(verticalFovDegrees(ShotOrientation.landscape), 50);
      expect(horizontalFovDegrees(ShotOrientation.landscape), 65);
    });

    for (final (framing, portrait, landscape) in [
      (Framing.chestUp, 0.5, 1.0),
      (Framing.waistUp, 1.5, 2.5),
      (Framing.kneeUp, 2.5, 3.5),
      (Framing.fullBody, 3.5, 4.5),
    ]) {
      test('$framing distance steps use 0.6m and orientation FOV', () {
        expect(distanceSteps(0.6, 0.3, framing: framing), portrait);
        expect(distanceSteps(0.3, 0.6, framing: framing), portrait);
        expect(
          distanceSteps(
            0.6,
            0.3,
            framing: framing,
            orientation: ShotOrientation.landscape,
          ),
          landscape,
        );
      });
    }

    test(
      'horizontal steps and height fists use the appropriate FOV and units',
      () {
        for (final sign in [-1, 1]) {
          expect(horizontalSteps(sign * 0.2, 3), 1);
          expect(
            horizontalSteps(
              sign * 0.2,
              3,
              orientation: ShotOrientation.landscape,
            ),
            1.5,
          );
          expect(heightFists(sign * 0.1, 3), 4);
          expect(
            heightFists(sign * 0.1, 3, orientation: ShotOrientation.landscape),
            3,
          );
        }
        expect(horizontalSteps(0.1, 6), 1);
        expect(heightFists(0.2, 1.5), 4);
      },
    );

    test('round nearest half, ties up, minimum half for either sign', () {
      for (final value in [0.0, 0.01, 0.24, 0.25, 0.74]) {
        expect(roundAmount(value), 0.5);
        expect(roundAmount(-value), 0.5);
      }
      expect(roundAmount(0.75), 1);
      expect(roundAmount(1.24), 1);
      expect(roundAmount(1.25), 1.5);
      expect(roundAmount(-1.25), 1.5);
      expect(distanceSteps(0.6, 0.6), 0.5);
    });

    test('invalid distance and amount inputs are rejected', () {
      for (final ratio in [0.0, -0.1, double.nan, double.infinity]) {
        expect(() => estimateDistanceMeters(ratio), throwsArgumentError);
      }
      expect(() => horizontalSteps(0.1, 0), throwsArgumentError);
      expect(() => heightFists(0.1, -1), throwsArgumentError);
      expect(() => roundAmount(double.infinity), throwsArgumentError);
    });

    test('zero tolerance is rejected', () {
      const invalid = TargetComposition(
        framing: Framing.fullBody,
        personHeightRatio: 0.6,
        personCenterX: 0.4,
        personCenterY: 0.18,
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

TargetComposition targetIn(ShotOrientation orientation) => TargetComposition(
  framing: Framing.fullBody,
  personHeightRatio: 0.6,
  personCenterX: 0.4,
  personCenterY: 0.18,
  orientation: orientation,
  source: 'reference',
);

PoseFrame frame(
  List<Landmark>? points, {
  ShotOrientation orientation = ShotOrientation.portrait,
}) => PoseFrame(
  landmarks: points,
  imageWidth: orientation == ShotOrientation.portrait ? 480 : 640,
  imageHeight: orientation == ShotOrientation.portrait ? 640 : 480,
  orientation: orientation,
  rollDeg: 0,
  pitchDeg: 0,
  at: DateTime.utc(2026, 10, 31),
);

PoseFrame pose({
  double noseY = 0.2,
  double shoulderY = 0.3,
  double eyeY = 0.18,
  double hipY = 0.6,
  double kneeY = 0.8,
  double ankleY = 0.9,
  double dx = 0,
  double ankleVisibility = 1,
  Framing visibleThrough = Framing.fullBody,
  ShotOrientation orientation = ShotOrientation.portrait,
}) {
  final points = List.filled(33, const Landmark(x: 0, y: 0, visibility: 0));
  void point(int index, double x, double y, [double visibility = 1]) {
    points[index] = Landmark(x: x + dx, y: y, visibility: visibility);
  }

  point(0, 0.4, noseY);
  point(2, 0.33, eyeY - 0.01);
  point(5, 0.47, eyeY + 0.01);
  point(11, 0.2, shoulderY - 0.02);
  point(12, 0.6, shoulderY + 0.02);
  point(23, 0.5, hipY - 0.02, visibleThrough.index >= 1 ? 1 : 0);
  point(24, 0.7, hipY + 0.02, visibleThrough.index >= 1 ? 1 : 0);
  point(25, 0.4, kneeY - 0.02, visibleThrough.index >= 2 ? 1 : 0);
  point(26, 0.6, kneeY + 0.02, visibleThrough.index >= 2 ? 1 : 0);
  point(
    27,
    0.4,
    ankleY - 0.02,
    visibleThrough.index >= 3 ? ankleVisibility : 0,
  );
  point(
    28,
    0.6,
    ankleY + 0.02,
    visibleThrough.index >= 3 ? ankleVisibility : 0,
  );
  return frame(points, orientation: orientation);
}

PoseFrame scaledPose({
  required double fullBodySpan,
  Framing visibleThrough = Framing.fullBody,
}) {
  // Synthetic body with known reference proportions; hidden anchors may lie
  // outside the viewport. This is input geometry, not a call to production math.
  const head = 0.1;
  final shoulder = head + fullBodySpan * 0.28 / 1.55;
  return pose(
    noseY: head + (shoulder - head) / 3,
    shoulderY: shoulder,
    eyeY: 0.12,
    hipY: head + fullBodySpan * 0.80 / 1.55,
    kneeY: head + fullBodySpan * 1.15 / 1.55,
    ankleY: head + fullBodySpan,
    visibleThrough: visibleThrough,
  );
}
