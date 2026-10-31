import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/core/orientation.dart';

/// Accelerometer x/y for a phone upright in its plane, rolled by [deg]
/// (+ = top to the left).
(double, double) tilt(double deg) {
  final r = deg * math.pi / 180;
  return (9.81 * math.sin(r), 9.81 * math.cos(r));
}

HeldOrientation step(HeldOrientation h, double deg) {
  final (x, y) = tilt(deg);
  return nextHeldOrientation(h, x, y);
}

void main() {
  test('roll sign: + when the top tilts left', () {
    final (x, y) = tilt(30);
    expect(accelRollDeg(x, y), closeTo(30, 1e-9));
  });

  test('portrait stays portrait until 60°', () {
    expect(step(HeldOrientation.portrait, 55), HeldOrientation.portrait);
    expect(step(HeldOrientation.portrait, 65).quarterTurns, 1);
    expect(step(HeldOrientation.portrait, -65).quarterTurns, -1);
  });

  test('landscape stays landscape until below 45°', () {
    const left = HeldOrientation(ShotOrientation.landscape, 1);
    expect(step(left, 50), left);
    expect(step(left, 40), HeldOrientation.portrait);
  });

  test('flipping sides switches direction', () {
    const left = HeldOrientation(ShotOrientation.landscape, 1);
    expect(step(left, -80).quarterTurns, -1);
  });

  test('flat phone keeps the previous decision', () {
    const left = HeldOrientation(ShotOrientation.landscape, 1);
    expect(nextHeldOrientation(left, 0.5, 0.3), left);
  });

  test('level roll is measured from ±90° in landscape', () {
    const left = HeldOrientation(ShotOrientation.landscape, 1);
    const right = HeldOrientation(ShotOrientation.landscape, -1);
    expect(levelRollDeg(92, left), closeTo(2, 1e-9));
    expect(levelRollDeg(-88, right), closeTo(2, 1e-9));
    expect(levelRollDeg(3, HeldOrientation.portrait), 3);
  });

  test('roll is unreliable only below the flat guard', () {
    expect(isRollReliable(0.5, 0.3), isFalse);
    expect(isRollReliable(0, 9.81), isTrue);
    expect(isRollReliable(3, 3), isTrue); // 4.24 m/s²
  });
}
