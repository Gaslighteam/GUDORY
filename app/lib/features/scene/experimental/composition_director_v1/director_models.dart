import 'dart:math' as math;

const spans = <String, double>{
  'chestUp': .28,
  'waistUp': .80,
  'kneeUp': 1.15,
  'fullBody': 1.55,
};
const anchors = <String, (int, int)>{
  'chestUp': (11, 12),
  'waistUp': (23, 24),
  'kneeUp': (25, 26),
  'fullBody': (27, 28),
};
double hypot(double x, double y) => math.sqrt(x * x + y * y);

class DirectorPerson {
  const DirectorPerson(
    this.x,
    this.eyeY,
    this.headY,
    this.scale,
    this.width, {
    this.framing = 'fullBody',
    this.confidence = 1,
  });
  final double x, eyeY, headY, scale, width, confidence;
  final String framing;
  bool get valid =>
      [x, eyeY, headY, scale, width, confidence].every((v) => v.isFinite) &&
      scale > 0 &&
      scale < .6 &&
      width > 0 &&
      width < 1 &&
      x >= 0 &&
      x <= 1 &&
      headY >= 0 &&
      headY < eyeY &&
      eyeY <= 1 &&
      spans.containsKey(framing) &&
      confidence >= .5 &&
      confidence <= 1;
  double span(String f) => scale * spans[f]! / .28;
  DirectorPerson shifted(double dx, double dy, double ds) => DirectorPerson(
    x + dx,
    eyeY + dy,
    headY + dy,
    scale + ds,
    width,
    framing: framing,
    confidence: confidence,
  );
  static DirectorPerson? fromPoints(List<(double, double, double)>? points) {
    if (points == null || points.length != 33) return null;
    bool finite(int i) =>
        [points[i].$1, points[i].$2, points[i].$3].every((v) => v.isFinite);
    bool visible(int i) =>
        finite(i) &&
        points[i].$3 >= .5 &&
        points[i].$1 >= 0 &&
        points[i].$1 <= 1 &&
        points[i].$2 >= 0 &&
        points[i].$2 <= 1;
    if (![11, 12].every(visible) || ![0, 2, 5].every(finite)) return null;
    final sy = (points[11].$2 + points[12].$2) / 2;
    final head = points[0].$2 - .5 * (sy - points[0].$2);
    final f = spans.keys.toList().reversed.firstWhere(
      (f) => visible(anchors[f]!.$1) && visible(anchors[f]!.$2),
    );
    final p = DirectorPerson(
      (points[11].$1 + points[12].$1) / 2,
      (points[2].$2 + points[5].$2) / 2,
      head,
      sy - head,
      math.max(.04, (points[11].$1 - points[12].$1).abs() * 1.4),
      framing: f,
    );
    return p.valid ? p : null;
  }
}

class DirectorFrame {
  const DirectorFrame(
    this.width,
    this.height,
    this.gray,
    this.mask,
    this.person,
    this.at, {
    this.orientation = 'portrait',
    this.level = 3,
    this.geometry = 'synthetic-fixed-view',
  });
  final int width, height, level;
  final List<double> gray, mask;
  final DirectorPerson? person;
  final double at;
  final String orientation, geometry;
  bool get valid =>
      width >= 12 &&
      width <= 128 &&
      height >= 12 &&
      height <= 128 &&
      gray.length == width * height &&
      mask.length == gray.length &&
      gray.every((v) => v.isFinite && v >= 0 && v <= 255) &&
      mask.every((v) => v.isFinite && v >= 0 && v <= 1) &&
      at.isFinite &&
      level >= 1 &&
      level <= 5 &&
      ['portrait', 'landscape'].contains(orientation) &&
      (orientation == 'portrait') == (height > width);
  String get key => '$orientation/$level/$geometry/$width/$height';
  factory DirectorFrame.fromJson(Map<String, dynamic> v) {
    final p = v['person'] as Map<String, dynamic>?;
    double n(Map<String, dynamic> a, String key) => (a[key] as num).toDouble();
    return DirectorFrame(
      v['width'] as int,
      v['height'] as int,
      (v['gray'] as List).map((x) => (x as num).toDouble()).toList(),
      (v['mask'] as List).map((x) => (x as num).toDouble()).toList(),
      p == null
          ? null
          : DirectorPerson(
              n(p, 'x'),
              n(p, 'eye_y'),
              n(p, 'head_y'),
              n(p, 'scale'),
              n(p, 'width'),
              framing: p['framing'] as String,
            ),
      n(v, 'at'),
      orientation: v['orientation'] as String,
      level: v['level'] as int,
      geometry: v['geometry_id'] as String,
    );
  }
}

class RegionCell {
  const RegionCell(this.coverage, this.edges, this.texture, this.mean);
  final double coverage, edges, texture, mean;
}

class BackgroundLine {
  const BackgroundLine(
    this.x1,
    this.y1,
    this.x2,
    this.y2,
    this.strength,
    this.angle,
  );
  final double x1, y1, x2, y2, strength, angle;
}

class SceneFeatures {
  const SceneFeatures(
    this.cells,
    this.lines,
    this.vanishing,
    this.confidence,
    this.valid,
    this.reason,
  );
  const SceneFeatures.invalid()
    : this(const [], const [], null, 0, false, 'invalid-input');
  final List<RegionCell> cells;
  final List<BackgroundLine> lines;
  final (double, double)? vanishing;
  final double confidence;
  final bool valid;
  final String reason;
}

class CompositionCandidate {
  const CompositionCandidate(
    this.x,
    this.eyeY,
    this.scale,
    this.framing,
    this.headY,
    this.width,
    this.score,
    this.terms,
  );
  final double x, eyeY, scale, headY, width, score;
  final String framing;
  final Map<String, double> terms;
}

class MeasuredMotion {
  const MeasuredMotion(
    this.actor,
    this.axis,
    this.dx,
    this.dy,
    this.ds,
    this.confidence,
    this.at,
    this.geometry, {
    this.preservation = 0,
  });
  final String actor, axis, geometry;
  final double dx, dy, ds, confidence, at, preservation;
}

class MovementContext {
  const MovementContext({
    this.motions = const [],
    this.safe = const {},
    this.safetyAt = -1,
    this.geometry = '',
  });
  final List<MeasuredMotion> motions;
  final Set<String> safe; // actor/direction, explicitly checked
  final double safetyAt;
  final String geometry;
}

class DirectorAction {
  const DirectorAction(
    this.actor,
    this.direction,
    this.magnitude,
    this.unit,
    this.text,
    this.confidence,
    this.valid,
    this.reason,
  );
  final String actor, direction, unit, text, reason;
  final double magnitude, confidence;
  final bool valid;
}

class DirectorDecision {
  const DirectorDecision(
    this.features,
    this.target,
    this.action,
    this.generation,
    this.progress,
  );
  final SceneFeatures features;
  final CompositionCandidate? target;
  final DirectorAction action;
  final int generation;
  final String progress;
}
