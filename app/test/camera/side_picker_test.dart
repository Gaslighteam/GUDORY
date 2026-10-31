import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/features/camera/side_picker.dart';

TargetComposition t(double cx, String source) => TargetComposition(
  personHeightRatio: 0.6,
  personCenterX: cx,
  personCenterY: 0.3,
  source: source,
);

void main() {
  final t0 = DateTime(2026, 11, 1);
  const key = (3, ShotOrientation.portrait);

  test('first reading decides the side immediately', () {
    final p = SidePicker();
    expect(p.update(0.30, t0, key), FrameSide.left);
    final q = SidePicker();
    expect(q.update(0.50, t0, key), FrameSide.center);
    final r = SidePicker();
    expect(r.update(0.70, t0, key), FrameSide.right);
  });

  test('moving toward the centre keeps the side (no flip-flop)', () {
    final p = SidePicker()..update(0.30, t0, key);
    expect(
      p.update(0.50, t0.add(const Duration(seconds: 5)), key),
      FrameSide.left,
    );
  });

  test('switches only after staying on the other side for 2 s', () {
    final p = SidePicker()..update(0.30, t0, key);
    expect(
      p.update(0.70, t0.add(const Duration(milliseconds: 100)), key),
      FrameSide.left,
    );
    expect(
      p.update(0.72, t0.add(const Duration(seconds: 1)), key),
      FrameSide.left,
    );
    expect(
      p.update(0.71, t0.add(const Duration(milliseconds: 2200)), key),
      FrameSide.right,
    );
  });

  test('a new level or orientation starts over', () {
    final p = SidePicker()..update(0.30, t0, key);
    expect(p.update(0.70, t0, (4, ShotOrientation.portrait)), FrameSide.right);
  });

  test('pick falls back to the overall target when a side is missing', () {
    final rec = Recommendation(
      target: t(0.5, 'all'),
      left: t(0.3, 'left'),
      neighbors: 10,
      modelVariant: 'q8',
    );
    expect(SidePicker.pick(rec, FrameSide.left).source, 'left');
    expect(SidePicker.pick(rec, FrameSide.right).source, 'all');
    expect(SidePicker.pick(rec, FrameSide.center).source, 'all');
  });

  test('shoulderMidX needs both shoulders visible', () {
    PoseFrame frame(double vis) => PoseFrame(
      landmarks: [
        for (var i = 0; i < 33; i++)
          Landmark(
            x: i == 11 ? 0.2 : (i == 12 ? 0.4 : 0.5),
            y: 0.5,
            visibility: (i == 11 || i == 12) ? vis : 1,
          ),
      ],
      imageWidth: 1080,
      imageHeight: 1440,
      rollDeg: 0,
      pitchDeg: 0,
      at: t0,
    );
    expect(shoulderMidX(frame(0.9)), closeTo(0.3, 1e-9));
    expect(shoulderMidX(frame(0.2)), isNull);
  });
}
