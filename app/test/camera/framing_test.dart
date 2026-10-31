import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/features/camera/framing.dart';

void main() {
  group('coverCrop', () {
    test('9:16 frame in a taller 9:19.5 box cuts left and right', () {
      final crop = coverCrop(9 / 19.5, 9 / 16);
      expect(crop.top, 0);
      expect(crop.height, 1);
      expect(crop.width, closeTo((9 / 19.5) / (9 / 16), 1e-9));
      expect(crop.left, closeTo((1 - crop.width) / 2, 1e-9));
    });

    test('3:4 frame in a wider 1:1 box cuts top and bottom', () {
      final crop = coverCrop(1, 3 / 4);
      expect(crop.left, 0);
      expect(crop.width, 1);
      expect(crop.height, closeTo(0.75, 1e-9));
      expect(crop.top, closeTo(0.125, 1e-9));
    });

    test('same aspect keeps the whole frame', () {
      expect(coverCrop(0.5, 0.5), const Rect.fromLTWH(0, 0, 1, 1));
    });
  });

  group('toVisible', () {
    PoseFrame frameWith(List<Landmark> points) => PoseFrame(
      landmarks: points,
      imageWidth: 720,
      imageHeight: 1280,
      rollDeg: 0,
      pitchDeg: 0,
      at: DateTime(2026),
    );

    test('maps the crop center to 0.5 and keeps visibility inside', () {
      const crop = Rect.fromLTWH(0.2, 0, 0.6, 1);
      final out = toVisible(
        frameWith(const [Landmark(x: 0.5, y: 0.5, visibility: 0.9)]),
        crop,
      );
      expect(out.landmarks!.single.x, closeTo(0.5, 1e-9));
      expect(out.landmarks!.single.y, closeTo(0.5, 1e-9));
      expect(out.landmarks!.single.visibility, 0.9);
      expect(out.imageWidth, 432);
    });

    test('points cut off by the crop become invisible', () {
      const crop = Rect.fromLTWH(0.2, 0, 0.6, 1);
      final out = toVisible(
        frameWith(const [Landmark(x: 0.1, y: 0.5, visibility: 0.9)]),
        crop,
      );
      expect(out.landmarks!.single.x, lessThan(0));
      expect(out.landmarks!.single.visibility, 0);
    });
  });

  group('cropInShotSpace', () {
    // Portrait crop cutting left/right: x 0.2..0.8, full height.
    const crop = Rect.fromLTWH(0.2, 0, 0.6, 1);

    test('portrait keeps the crop', () {
      expect(cropInShotSpace(crop, 0), crop);
    });

    test('top-left landscape turns side cuts into top/bottom cuts', () {
      final r = cropInShotSpace(crop, 1);
      expect(r.left, closeTo(0, 1e-9));
      expect(r.width, closeTo(1, 1e-9));
      expect(r.top, closeTo(0.2, 1e-9));
      expect(r.height, closeTo(0.6, 1e-9));
    });

    test('top-right landscape is the mirror', () {
      const offCenter = Rect.fromLTWH(0.1, 0, 0.6, 1);
      final left = cropInShotSpace(offCenter, 1);
      final right = cropInShotSpace(offCenter, -1);
      expect(left.top, closeTo(0.3, 1e-9));
      expect(right.top, closeTo(0.1, 1e-9));
    });
  });

  test('toVisible keeps every non-landmark field', () {
    final frame = PoseFrame(
      landmarks: const [Landmark(x: 0.5, y: 0.5, visibility: 1)],
      imageWidth: 1080,
      imageHeight: 1440,
      orientation: ShotOrientation.landscape,
      rollDeg: 4,
      pitchDeg: -7,
      rollReliable: false,
      at: DateTime(2026, 10, 31, 21),
    );
    final out = toVisible(frame, const Rect.fromLTWH(0.1, 0, 0.8, 1));
    expect(out.rollReliable, isFalse);
    expect(out.orientation, ShotOrientation.landscape);
    expect(out.rollDeg, 4);
    expect(out.pitchDeg, -7);
    expect(out.at, frame.at);
  });
}
