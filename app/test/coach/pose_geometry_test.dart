import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/core/orientation.dart';
import 'package:gudory/features/coach/pose_geometry.dart';

void main() {
  shotGeometryTests();
  test('upright portrait has zero roll and pitch', () {
    expect(rollDegrees(0, 9.81), 0);
    expect(pitchDegrees(0, 9.81, 0), 0);
  });

  test('roll uses atan2 ax ay with opposite signs for left and right', () {
    expect(rollDegrees(1, 1), closeTo(45, 1e-9));
    expect(rollDegrees(-1, 1), closeTo(-45, 1e-9));
  });

  test('pitch increases lying down in either face direction', () {
    expect(pitchDegrees(0, 1, 1), closeTo(45, 1e-9));
    expect(pitchDegrees(0, 0, 9.81), closeTo(90, 1e-9));
    expect(pitchDegrees(0, 0, -9.81), closeTo(90, 1e-9));
  });

  test('roll tilt alone does not increase pitch', () {
    expect(pitchDegrees(5, 5, 0), 0);
  });

  test('90/270 rotated ML Kit output uses swapped portrait dimensions', () {
    final point = normalizePortraitLandmark(
      x: 120,
      y: 480,
      portraitWidth: 480,
      portraitHeight: 640,
      isFrontCamera: false,
      visibility: 0.9,
    );
    expect(point.x, 0.25);
    expect(point.y, 0.75);
    expect(point.visibility, 0.9);
  });

  test('front camera mirrors x once and preserves y', () {
    final point = normalizePortraitLandmark(
      x: 120,
      y: 480,
      portraitWidth: 480,
      portraitHeight: 640,
      isFrontCamera: true,
      visibility: 1,
    );
    expect(point.x, 0.75);
    expect(point.y, 0.75);
  });

  test('offscreen joints stay in normalized contract bounds', () {
    final point = normalizePortraitLandmark(
      x: -10,
      y: 700,
      portraitWidth: 480,
      portraitHeight: 640,
      isFrontCamera: false,
      visibility: 0.2,
    );
    expect(point.x, 0);
    expect(point.y, 1);
  });
}

ShotAttitude tilt(ShotAttitude previous, double degrees) {
  final radians = degrees * math.pi / 180;
  return updateShotAttitude(
    previous,
    ax: 9.81 * math.sin(radians),
    ay: 9.81 * math.cos(radians),
    az: 0,
  );
}

void shotGeometryTests() {
  const initial = ShotAttitude.initial();
  group('shared sensor orientation', () {
    test('starts portrait with unmeasured Roll marked unreliable', () {
      expect(initial.orientation, ShotOrientation.portrait);
      expect(initial.quarterTurns, 0);
      expect(initial.rollReliable, isFalse);
      expect(initial.rollDeg, 0);
    });

    test('60/45 hysteresis boundaries and both landscape directions', () {
      for (final sign in [-1, 1]) {
        final at60 = tilt(initial, sign * 60);
        expect(at60.orientation, ShotOrientation.portrait);
        final entered = tilt(at60, sign * 60.01);
        expect(entered.orientation, ShotOrientation.landscape);
        expect(entered.quarterTurns, sign);
        expect(tilt(entered, sign * 50).held, entered.held);
        expect(
          updateShotAttitude(entered, ax: sign * 6.0, ay: 6, az: 0).held,
          entered.held,
        );
        expect(tilt(entered, sign * 44.99).held, HeldOrientation.portrait);
      }
    });

    test('direct landscape side flip follows core exactly', () {
      final left = tilt(initial, 92);
      final right = tilt(left, -88);
      expect(right.quarterTurns, -1);
      expect(right.rollDeg, closeTo(2, 1e-9));
      expect(tilt(right, 92).quarterTurns, 1);
    });

    test('level Roll is based on signed 90 degrees', () {
      expect(tilt(initial, 90).rollDeg, closeTo(0, 1e-9));
      expect(tilt(initial, -90).rollDeg, closeTo(0, 1e-9));
      expect(tilt(initial, 100).rollDeg, closeTo(10, 1e-9));
      expect(tilt(initial, -100).rollDeg, closeTo(-10, 1e-9));
      expect(tilt(initial, 10).rollDeg, closeTo(10, 1e-9));
    });

    test('flat guard retains last reliable corrected Roll and orientation', () {
      for (final degrees in [12.0, 100.0, -100.0]) {
        final valid = tilt(initial, degrees);
        final flat = updateShotAttitude(valid, ax: 0.2, ay: -0.3, az: 9.81);
        expect(flat.rollReliable, isFalse);
        expect(flat.held, valid.held);
        expect(flat.rollDeg, valid.rollDeg);
        expect(flat.rawRollDeg, valid.rawRollDeg);
        expect(flat.pitchDeg, greaterThan(85));
        final recovered = tilt(flat, degrees);
        expect(recovered.rollReliable, isTrue);
        expect(recovered.rollDeg, closeTo(valid.rollDeg, 1e-9));
      }
    });

    test('gravity projection of exactly 4 is reliable, below 4 is not', () {
      final landscape = tilt(initial, 95);
      final at4 = updateShotAttitude(landscape, ax: 0, ay: 4, az: 9);
      expect(at4.rollReliable, isTrue);
      expect(at4.orientation, ShotOrientation.portrait);
      final below4 = updateShotAttitude(landscape, ax: 0, ay: 3.999, az: 9);
      expect(below4.rollReliable, isFalse);
      expect(below4.held, landscape.held);
      expect(below4.rollDeg, landscape.rollDeg);
    });

    test(
      'held state always matches the camera shared function for a sequence',
      () {
        var state = initial;
        var held = HeldOrientation.portrait;
        for (final degrees in [0, 59, 61, 55, 45, 44, -61, -92, 92, 40]) {
          final radians = degrees * math.pi / 180;
          final ax = 9.81 * math.sin(radians);
          final ay = 9.81 * math.cos(radians);
          held = nextHeldOrientation(held, ax, ay);
          state = updateShotAttitude(state, ax: ax, ay: ay, az: 0);
          expect(state.held, held);
        }
      },
    );
  });

  group('shot rotation and coordinates', () {
    for (final (sensor, front, expected) in [
      (90, false, [90, 0, 180]),
      (270, false, [270, 180, 0]),
      (90, true, [90, 180, 0]),
      (270, true, [270, 0, 180]),
    ]) {
      test('sensor $sensor front=$front rotation and dimensions', () {
        for (var i = 0; i < 3; i++) {
          final q = [0, 1, -1][i];
          final geometry = shotImageGeometry(
            sensorOrientation: sensor,
            isFrontCamera: front,
            quarterTurns: q,
            rawWidth: 640,
            rawHeight: 480,
          );
          expect(geometry.rotationDegrees, expected[i]);
          expect(geometry.width, q == 0 ? 480 : 640);
          expect(geometry.height, q == 0 ? 640 : 480);
        }
      });
    }

    test('0/180 degree sensors also produce portrait and landscape sizes', () {
      for (final sensor in [0, 180]) {
        for (final front in [false, true]) {
          for (final q in [0, 1, -1]) {
            final geometry = shotImageGeometry(
              sensorOrientation: sensor,
              isFrontCamera: front,
              quarterTurns: q,
              rawWidth: 480,
              rawHeight: 640,
            );
            expect(geometry.width, q == 0 ? 480 : 640);
            expect(geometry.height, q == 0 ? 640 : 480);
          }
        }
      }
    });

    test('shot-space normalization does not apply a second rotation', () {
      for (final front in [false, true]) {
        final point = normalizeShotLandmark(
          x: 120,
          y: 360,
          shotWidth: 640,
          shotHeight: 480,
          isFrontCamera: front,
          visibility: 0.8,
        );
        expect(point.x, front ? 0.8125 : 0.1875);
        expect(point.y, 0.75);
        expect(point.visibility, 0.8);
      }
    });

    test(
      'both landscape mappings return asymmetric shot points to portrait UI',
      () {
        expect(
          shotToPortrait(const Offset(0.3, 0.8), quarterTurns: 1),
          offsetCloseTo(const Offset(0.2, 0.3), 1e-9),
        );
        expect(
          shotToPortrait(const Offset(0.7, 0.2), quarterTurns: -1),
          offsetCloseTo(const Offset(0.2, 0.3), 1e-9),
        );
        expect(
          shotToPortrait(const Offset(0.2, 0.3), quarterTurns: 0),
          const Offset(0.2, 0.3),
        );
      },
    );

    test(
      'corners and centre inverse-match saved-photo rotation in either direction',
      () {
        for (final portrait in [
          Offset.zero,
          const Offset(1, 0),
          const Offset(0, 1),
          const Offset(1, 1),
          const Offset(0.5, 0.5),
          const Offset(0.23, 0.67),
        ]) {
          final leftShot = Offset(portrait.dy, 1 - portrait.dx);
          final rightShot = Offset(1 - portrait.dy, portrait.dx);
          expect(
            shotToPortrait(leftShot, quarterTurns: 1),
            offsetCloseTo(portrait, 1e-9),
          );
          expect(
            shotToPortrait(rightShot, quarterTurns: -1),
            offsetCloseTo(portrait, 1e-9),
          );
        }
      },
    );

    test('front mirroring happens once before inverse preview mapping', () {
      for (final (q, pixelX, pixelY) in [
        (1, 448.0, 384.0),
        (-1, 192.0, 96.0),
      ]) {
        final point = normalizeShotLandmark(
          x: pixelX,
          y: pixelY,
          shotWidth: 640,
          shotHeight: 480,
          isFrontCamera: true,
          visibility: 1,
        );
        expect(
          shotToPortrait(Offset(point.x, point.y), quarterTurns: q),
          offsetCloseTo(const Offset(0.2, 0.3), 1e-9),
        );
      }
    });

    test('invalid geometry inputs are rejected', () {
      expect(
        () => shotImageGeometry(
          sensorOrientation: 45,
          isFrontCamera: false,
          quarterTurns: 0,
          rawWidth: 640,
          rawHeight: 480,
        ),
        throwsArgumentError,
      );
      expect(
        () => shotToPortrait(Offset.zero, quarterTurns: 2),
        throwsArgumentError,
      );
    });

    test(
      'CoachPoseFrame forwards reliability, orientation and corrected Roll',
      () {
        final valid = tilt(initial, -100);
        final flat = updateShotAttitude(valid, ax: 0, ay: 0, az: 9.81);
        final PoseFrame frame = CoachPoseFrame(
          landmarks: null,
          imageWidth: 640,
          imageHeight: 480,
          attitude: flat,
          at: DateTime.utc(2026, 10, 31),
        );
        expect(frame.orientation, ShotOrientation.landscape);
        expect(frame.rollDeg, closeTo(-10, 1e-9));
        expect(frame.rollReliable, isFalse);
        expect(frame.pitchDeg, 90);
      },
    );
  });
}

Matcher offsetCloseTo(Offset expected, double tolerance) => isA<Offset>()
    .having((point) => point.dx, 'dx', closeTo(expected.dx, tolerance))
    .having((point) => point.dy, 'dy', closeTo(expected.dy, tolerance));
