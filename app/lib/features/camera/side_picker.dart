// Which side of the frame the user put the subject on, so recommend mode can
// keep a composition framed on purpose instead of pulling it to the centre.
import '../../core/models.dart';

enum FrameSide { center, left, right }

/// Picks the side from the live subject's shoulder-midpoint x (0~1, visible
/// crop). The first reading for a level/orientation decides immediately;
/// after that the side only changes when the subject stays past the other
/// threshold for [switchAfter], so instructions don't flip-flop while the
/// subject is being coached.
class SidePicker {
  SidePicker({
    this.leftEdge = 0.45,
    this.rightEdge = 0.55,
    this.switchAfter = const Duration(seconds: 2),
  });

  final double leftEdge;
  final double rightEdge;
  final Duration switchAfter;

  FrameSide _side = FrameSide.center;
  FrameSide? _candidate;
  DateTime? _candidateSince;
  Object? _key;

  FrameSide get side => _side;

  FrameSide classify(double x) => x < leftEdge
      ? FrameSide.left
      : x > rightEdge
      ? FrameSide.right
      : FrameSide.center;

  /// [x] = shoulder-midpoint x, or null when the shoulders aren't visible.
  /// [key] identifies the request (level + orientation); a new key starts over.
  FrameSide update(double? x, DateTime now, Object key) {
    if (key != _key) {
      _key = key;
      _candidate = null;
      _side = x == null ? FrameSide.center : classify(x);
      return _side;
    }
    if (x == null) return _side;
    final seen = classify(x);
    if (seen == _side || seen == FrameSide.center) {
      _candidate = null;
      return _side;
    }
    if (_candidate != seen) {
      _candidate = seen;
      _candidateSince = now;
      return _side;
    }
    if (now.difference(_candidateSince!) >= switchAfter) {
      _side = seen;
      _candidate = null;
    }
    return _side;
  }

  void reset() {
    _key = null;
    _candidate = null;
    _side = FrameSide.center;
  }

  /// The recommendation for [side], falling back to the overall target when
  /// the data has no (or too few) photos on that side.
  static TargetComposition pick(Recommendation rec, FrameSide side) =>
      switch (side) {
        FrameSide.left => rec.left ?? rec.target,
        FrameSide.right => rec.right ?? rec.target,
        FrameSide.center => rec.target,
      };
}

/// Shoulder midpoint x of a pose (ML Kit indices 11 / 12), or null when
/// either shoulder is not visible enough.
double? shoulderMidX(PoseFrame frame, {double minVisibility = 0.5}) {
  final landmarks = frame.landmarks;
  if (landmarks == null || landmarks.length <= 12) return null;
  final left = landmarks[11];
  final right = landmarks[12];
  if (left.visibility < minVisibility || right.visibility < minVisibility) {
    return null;
  }
  return (left.x + right.x) / 2;
}
