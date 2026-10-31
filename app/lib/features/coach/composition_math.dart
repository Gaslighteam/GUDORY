import '../../core/models.dart';

// Shared with the training-data Python implementation (AGENTS.md §4):
// head = nose.y - (mean_shoulders.y - nose.y) / 2
// cx = mean_shoulders.x; cy = mean(left_eye.y, right_eye.y)
// spans L: chestUp=.28, waistUp=.80, kneeUp=1.15, fullBody=1.55 metres
// h[f] = anchor_mid_y[f] - head; person_scale = h[chestUp]
// If the requested anchor is unavailable, h[target] = h[visible] * L[target]
// / L[visible], using the lowest complete visible anchor pair. Do not clamp
// inferred live h: values >1 describe a person who does not fit in the crop.
const double landmarkVisibilityThreshold = 0.5;

double realSpanMeters(Framing framing) => switch (framing) {
  Framing.chestUp => 0.28,
  Framing.waistUp => 0.80,
  Framing.kneeUp => 1.15,
  Framing.fullBody => 1.55,
};

double estimateHeadTopY(double noseY, double shoulderMidY) =>
    noseY - (shoulderMidY - noseY) * 0.5;

class CompositionMetrics {
  const CompositionMetrics({
    required this.framing,
    required this.orientation,
    required this.topOfHeadY,
    required this.personHeightRatio,
    required this.personCenterX,
    required this.personCenterY,
    required this.personScale,
    required this.visibleFraming,
    required this.measuredFrom,
  });

  final Framing framing;
  final ShotOrientation orientation;
  final double topOfHeadY;
  final double personHeightRatio;
  final double personCenterX;
  final double personCenterY;

  /// Head-to-shoulder span, also used for the recommendation level scale.
  final double personScale;

  /// Lowest complete visible anchor pair, useful when analyzing references.
  final Framing visibleFraming;

  /// Anchor used for the requested span (possibly a different framing).
  final Framing measuredFrom;
  bool get estimated => measuredFrom != framing;
}

/// Measures live landmarks at the target's framing in the supplied shot space.
/// Both shoulders must be visible. Nose and eyes use the coordinates ML Kit
/// always estimates, whatever their visibility (AGENTS.md head reference), so
/// back views and profiles are measured too; the eye line uses indices 2 and 5.
/// Visibility exactly 0 is PoseSource's placeholder for a missing landmark.
CompositionMetrics? measureComposition(
  PoseFrame frame, {
  Framing framing = Framing.fullBody,
}) {
  final points = frame.landmarks;
  if (points == null || points.length != 33) return null;
  if (!_visible(points[11]) || !_visible(points[12])) return null;
  if (![0, 2, 5].every((index) => _estimated(points[index]))) return null;

  final shoulderY = (points[11].y + points[12].y) / 2;
  final headY = estimateHeadTopY(points[0].y, shoulderY);
  final spans = <Framing, double>{};
  for (final candidate in Framing.values) {
    final (left, right) = _anchorIndices(candidate);
    if (!_visible(points[left]) || !_visible(points[right])) continue;
    final span = (points[left].y + points[right].y) / 2 - headY;
    if (span.isFinite && span > 0) spans[candidate] = span;
  }
  // Invalid shoulder/nose geometry is not a usable pose.
  final scale = spans[Framing.chestUp];
  if (scale == null) return null;
  final visible = Framing.values.reversed.firstWhere(spans.containsKey);
  final from = spans.containsKey(framing) ? framing : visible;
  final ratio = from == framing
      ? spans[from]!
      : spans[from]! * realSpanMeters(framing) / realSpanMeters(from);
  return CompositionMetrics(
    framing: framing,
    orientation: frame.orientation,
    topOfHeadY: headY,
    personHeightRatio: ratio,
    personCenterX: (points[11].x + points[12].x) / 2,
    personCenterY: (points[2].y + points[5].y) / 2,
    personScale: scale,
    visibleFraming: visible,
    measuredFrom: from,
  );
}

(int, int) _anchorIndices(Framing framing) => switch (framing) {
  Framing.chestUp => (11, 12),
  Framing.waistUp => (23, 24),
  Framing.kneeUp => (25, 26),
  Framing.fullBody => (27, 28),
};

bool _finite(Landmark point) =>
    point.x.isFinite && point.y.isFinite && point.visibility.isFinite;

bool _estimated(Landmark point) => _finite(point) && point.visibility > 0;

bool _visible(Landmark point) =>
    _finite(point) &&
    point.visibility >= landmarkVisibilityThreshold &&
    point.x >= 0 &&
    point.x <= 1 &&
    point.y >= 0 &&
    point.y <= 1;
