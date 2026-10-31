// Photographer rules for person-centric recommend levels (1~3): nudge the
// recommended target so the frame edge avoids joints, the head has room,
// and the person stands on the side opposite to where they face.
import 'dart:math' as math;

import '../../core/models.dart';

// ML Kit landmark indices.
const _nose = 0, _leftEye = 2, _rightEye = 5, _leftEar = 7, _rightEar = 8;
const _shoulders = [11, 12], _hips = [23, 24], _knees = [25, 26];
const _ankles = [27, 28];

// Starting values; tune with Seojun's per-framing statistics.
const minHeadRoom = 0.04; // head top to the top edge, 0~1
const maxHeadRoom = 0.15;
const jointMargin = 0.03; // bottom edge this close to a joint = a cut
const facingThreshold = 0.35; // nose offset from the ears / shoulder width
// Smallest lead-room offset from the centre when the person faces sideways
// (v1/fallback targets sit near the centre; v2 learns its own offset).
const minLeadOffset = 0.10;

/// Returns [t] adjusted by the rules, using the live body proportions.
/// Returns [t] unchanged when the pose cannot be measured.
TargetComposition applyPhotoRules(TargetComposition t, PoseFrame live) {
  final p = live.landmarks;
  if (p == null || p.length != 33) return t;
  double midY(List<int> i) => (p[i[0]].y + p[i[1]].y) / 2;

  final shoulderY = midY(_shoulders);
  final nose = p[_nose];
  final headTop = nose.y - 0.5 * (shoulderY - nose.y);
  final eyeY = (p[_leftEye].y + p[_rightEye].y) / 2;
  final anchorY = switch (t.framing) {
    Framing.chestUp => shoulderY,
    Framing.waistUp => midY(_hips),
    Framing.kneeUp => midY(_knees),
    Framing.fullBody => midY(_ankles),
  };
  final liveSpan = anchorY - headTop;
  if (!liveSpan.isFinite || liveSpan <= 0.01) return t;

  // Live body placed into the target: scale k, head top at `top`.
  var k = t.personHeightRatio / liveSpan;
  var top = t.personCenterY - k * (eyeY - headTop);

  // 1. Head room (not for full body, where a small person is intended).
  if (t.framing != Framing.fullBody) {
    top = top.clamp(minHeadRoom, maxHeadRoom).toDouble();
  }

  // 2. Never let the bottom edge cut through a joint: shrink until the
  //    joint is comfortably inside the frame.
  for (final joint in [_shoulders, _hips, _knees, _ankles]) {
    final offset = midY(joint) - headTop;
    if (offset <= 0) continue;
    final y = top + k * offset;
    if ((y - 1).abs() < jointMargin) {
      k = (1 - 2 * jointMargin - top) / offset;
      break;
    }
  }

  // 3. Lead room: facing right → stand left of centre, and vice versa. Keep
  //    the recommended distance from the centre (recommender v2 learns it);
  //    the facing direction only picks the side.
  var cx = t.personCenterX;
  final shoulderW = (p[_shoulders[0]].x - p[_shoulders[1]].x).abs();
  if (shoulderW > 0.02) {
    final earMid = (p[_leftEar].x + p[_rightEar].x) / 2;
    final facing = (nose.x - earMid) / shoulderW;
    if (facing.abs() > facingThreshold) {
      final offset = math.max((cx - 0.5).abs(), minLeadOffset);
      cx = facing > 0 ? 0.5 - offset : 0.5 + offset;
    }
  }

  final height = k * liveSpan;
  final centerY = top + k * (eyeY - headTop);
  if (!height.isFinite || !centerY.isFinite || height <= 0) return t;

  return TargetComposition(
    framing: t.framing,
    personHeightRatio: height,
    personCenterX: cx,
    personCenterY: centerY,
    horizonY: t.horizonY,
    orientation: t.orientation,
    tolHeight: t.tolHeight,
    tolX: t.tolX,
    tolY: t.tolY,
    tolRollDeg: t.tolRollDeg,
    source: '${t.source}+rules',
  );
}
