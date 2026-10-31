import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/features/coach/photo_rules.dart';

/// A standing person, centered, facing the camera unless [noseX] says
/// otherwise. y grows downwards, 0~1 in the visible frame.
PoseFrame _pose({double noseX = 0.5}) {
  final points = List.generate(
    33,
    (_) => const Landmark(x: 0.5, y: 0.5, visibility: 1),
  );
  void put(int i, double x, double y) =>
      points[i] = Landmark(x: x, y: y, visibility: 1);
  put(0, noseX, 0.20); // nose
  put(2, 0.48, 0.18); // eyes
  put(5, 0.52, 0.18);
  put(7, 0.46, 0.19); // ears
  put(8, 0.54, 0.19);
  put(11, 0.42, 0.30); // shoulders
  put(12, 0.58, 0.30);
  put(23, 0.45, 0.55); // hips
  put(24, 0.55, 0.55);
  put(25, 0.45, 0.72); // knees
  put(26, 0.55, 0.72);
  put(27, 0.45, 0.90); // ankles
  put(28, 0.55, 0.90);
  return PoseFrame(
    landmarks: points,
    imageWidth: 900,
    imageHeight: 1200,
    rollDeg: 0,
    pitchDeg: 0,
    at: DateTime(2026),
  );
}

TargetComposition _target({
  Framing framing = Framing.waistUp,
  double h = 0.5,
  double cx = 0.5,
  double cy = 0.3,
}) => TargetComposition(
  framing: framing,
  personHeightRatio: h,
  personCenterX: cx,
  personCenterY: cy,
  source: 'recommend:2',
);

void main() {
  test('facing right moves a centred target left by the minimum offset', () {
    final out = applyPhotoRules(_target(), _pose(noseX: 0.56));
    expect(out.personCenterX, closeTo(0.5 - minLeadOffset, 1e-9));
    expect(out.source, 'recommend:2+rules');
  });

  test('facing left moves a centred target right by the minimum offset', () {
    final out = applyPhotoRules(_target(), _pose(noseX: 0.44));
    expect(out.personCenterX, closeTo(0.5 + minLeadOffset, 1e-9));
  });

  test('facing keeps the recommended offset and only picks the side', () {
    // Recommender v2 put the person 0.16 right of centre; facing right flips
    // them to 0.16 left of centre so the room is in front of them.
    final right = applyPhotoRules(_target(cx: 0.66), _pose(noseX: 0.56));
    expect(right.personCenterX, closeTo(0.34, 1e-9));
    final left = applyPhotoRules(_target(cx: 0.66), _pose(noseX: 0.44));
    expect(left.personCenterX, closeTo(0.66, 1e-9));
  });

  test('facing the camera keeps the recommended x', () {
    final out = applyPhotoRules(_target(cx: 0.45), _pose());
    expect(out.personCenterX, 0.45);
  });

  test('a bottom edge on the knees is pulled back inside the frame', () {
    // Live head top 0.15, knees 0.72. Place the knees right at the edge.
    final t = _target(framing: Framing.kneeUp, h: 0.95, cy: 0.1);
    final out = applyPhotoRules(t, _pose());
    expect(out.personHeightRatio, lessThan(t.personHeightRatio));
  });

  test('too much head room is clamped for half-body framings', () {
    // Head would sit far below the top edge.
    final out = applyPhotoRules(_target(cy: 0.6, h: 0.3), _pose());
    final k = out.personHeightRatio / (0.55 - 0.15);
    final top = out.personCenterY - k * (0.18 - 0.15);
    expect(top, closeTo(maxHeadRoom, 1e-9));
  });

  test('no pose leaves the target unchanged', () {
    final t = _target();
    final empty = PoseFrame(
      landmarks: null,
      imageWidth: 1,
      imageHeight: 1,
      rollDeg: 0,
      pitchDeg: 0,
      at: DateTime(2026),
    );
    expect(identical(applyPhotoRules(t, empty), t), isTrue);
  });
}
