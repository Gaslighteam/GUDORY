import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/features/coach/pose_geometry.dart';

void main() {
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
