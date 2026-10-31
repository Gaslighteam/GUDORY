import 'dart:math' as math;
import 'director_models.dart';

// Python uses ties-to-even rounding for Hough bins and support occupancy.
int evenRound(double v) {
  final lo = v.floor();
  final d = v - lo;
  return d == .5 ? (lo.isEven ? lo : lo + 1) : v.round();
}

SceneFeatures analyzeScene(DirectorFrame f) {
  if (!f.valid) return const SceneFeatures.invalid();
  final w = f.width, h = f.height;
  final known = List<bool>.filled(w * h, false),
      edges = List<double>.filled(w * h, 0);
  final points = <(int, int, double, double)>[];
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      var masked = false;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (f.mask[(y + dy) * w + x + dx] >= .35) masked = true;
        }
      }
      if (masked) continue;
      final i = y * w + x;
      known[i] = true;
      final gx = (f.gray[i + 1] - f.gray[i - 1]) / 2,
          gy = (f.gray[i + w] - f.gray[i - w]) / 2;
      edges[i] = hypot(gx, gy);
      if (edges[i] >= 28) points.add((x, y, gx, gy));
    }
  }
  final cells = <RegionCell>[];
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      var total = 0, n = 0, count = 0;
      var texture = 0.0, mean = 0.0;
      for (var y = row * h ~/ 3; y < (row + 1) * h ~/ 3; y++) {
        for (var x = col * w ~/ 3; x < (col + 1) * w ~/ 3; x++) {
          total++;
          final i = y * w + x;
          if (!known[i]) continue;
          n++;
          if (edges[i] >= 28) count++;
          texture += edges[i];
          mean += f.gray[i];
        }
      }
      cells.add(
        RegionCell(
          n / total,
          n == 0 ? 0 : count / n,
          n == 0 ? 0 : math.min(1, texture / n / 64),
          n == 0 ? 0 : mean / n / 255,
        ),
      );
    }
  }
  final count = f.mask.where((v) => v >= .5).length,
      knownCount = known.where((v) => v).length;
  final valid =
      count > 0 && count < known.length && knownCount / known.length >= .35;
  var lines = valid ? extractLines(points, w, h) : <BackgroundLine>[];
  final density = points.length / math.max(1, knownCount);
  final means = cells
      .where((c) => c.coverage >= .4)
      .map((c) => c.mean)
      .toList();
  final contrast = means.length < 2
      ? 0.0
      : means.reduce(math.max) - means.reduce(math.min);
  var confidence = valid
      ? math.min(
          1.0,
          .75 * lines.fold(0.0, (v, l) => math.max(v, l.strength)) +
              .8 * contrast +
              math.min(.25, density),
        )
      : 0.0;
  if (density > .4) {
    lines = [];
    confidence *= .25;
  }
  return SceneFeatures(
    cells,
    lines,
    vanishingPoint(lines, w / h),
    confidence,
    valid,
    valid ? 'ok' : 'mask-or-background-unavailable',
  );
}

List<BackgroundLine> extractLines(
  List<(int, int, double, double)> points,
  int w,
  int h,
) {
  final diagonal = hypot(w.toDouble(), h.toDouble());
  if (points.length < 12) return [];
  final peaks = <BackgroundLine>[];
  for (var k = 0; k < 12; k++) {
    final theta = k * math.pi / 12,
        c = math.cos(k * math.pi / 12),
        s = math.sin(k * math.pi / 12);
    // Keep angle computation identical to the reference, including operation order.
    assert(theta.isFinite);
    final bins = <int, List<(int, int)>>{};
    for (final (x, y, gx, gy) in points) {
      if ((gx * c + gy * s).abs() < .93 * hypot(gx, gy)) continue;
      (bins[evenRound((x * c + y * s) / 2)] ??= []).add((x, y));
    }
    for (final support in bins.values) {
      if (support.length < math.max(10, diagonal * .12)) continue;
      final ts = support.map((p) => -p.$1 * s + p.$2 * c).toList()..sort();
      final runs = <List<double>>[];
      var run = <double>[ts.first];
      for (final t in ts.skip(1)) {
        if (t - run.last > 4) {
          runs.add(run);
          run = [];
        }
        run.add(t);
      }
      runs.add(run);
      var best = runs.first;
      for (final r in runs.skip(1)) {
        if (r.last - r.first > best.last - best.first) best = r;
      }
      final span = best.last - best.first,
          occupancy =
              best.map(evenRound).toSet().length /
              math.max(1, best.last - best.first);
      if (span < diagonal * .30 || occupancy < .45) continue;
      final rho =
          support.fold(0.0, (v, p) => v + p.$1 * c + p.$2 * s) / support.length;
      final x1 = rho * c - best.first * s,
          y1 = rho * s + best.first * c,
          x2 = rho * c - best.last * s,
          y2 = rho * s + best.last * c;
      peaks.add(
        BackgroundLine(
          x1 / (w - 1),
          y1 / (h - 1),
          x2 / (w - 1),
          y2 / (h - 1),
          math.min(1, span / diagonal * 1.8) * math.min(1, occupancy),
          (math.atan2(y2 - y1, x2 - x1) * 180 / math.pi) % 180,
        ),
      );
    }
  }
  peaks.sort((a, b) {
    for (final pair in [
      (-a.strength, -b.strength),
      (a.angle, b.angle),
      (a.x1, b.x1),
      (a.y1, b.y1),
    ]) {
      final n = pair.$1.compareTo(pair.$2);
      if (n != 0) return n;
    }
    return 0;
  });
  final chosen = <BackgroundLine>[];
  for (final l in peaks) {
    if (chosen.any(
      (p) =>
          math.min((l.angle - p.angle).abs(), 180 - (l.angle - p.angle).abs()) <
              17 &&
          hypot(
                (l.x1 + l.x2 - p.x1 - p.x2) / 2,
                (l.y1 + l.y2 - p.y1 - p.y2) / 2,
              ) <
              .08,
    )) {
      continue;
    }
    chosen.add(l);
    if (chosen.length == 6) break;
  }
  return chosen;
}

(double, double)? vanishingPoint(List<BackgroundLine> lines, double aspect) {
  for (var i = 0; i < lines.length; i++) {
    for (final b in lines.skip(i + 1)) {
      final a = lines[i],
          ux = a.x2 - a.x1,
          uy = a.y2 - a.y1,
          vx = b.x2 - b.x1,
          vy = b.y2 - b.y1;
      final det = ux * vy - uy * vx;
      if (det.abs() < .04) continue;
      final t = ((b.x1 - a.x1) * vy - (b.y1 - a.y1) * vx) / det,
          x = a.x1 + ((b.x1 - a.x1) * vy - (b.y1 - a.y1) * vx) / det * ux;
      final y = a.y1 + t * uy;
      if (x <= .05 || x >= .95 || y <= .05 || y >= .95) continue;
      final n = lines.where((l) {
        final dx = (l.x2 - l.x1) * aspect, dy = l.y2 - l.y1;
        return (dx * (y - l.y1) - dy * (x - l.x1) * aspect).abs() /
                    math.max(1e-6, hypot(dx, dy)) <
                .035 &&
            l.strength > .4;
      }).length;
      if (n >= 3) return (x, y);
    }
  }
  return null;
}

double sceneChange(SceneFeatures a, SceneFeatures b) {
  final pairs = <(RegionCell, RegionCell)>[];
  for (var i = 0; i < math.min(a.cells.length, b.cells.length); i++) {
    if (math.min(a.cells[i].coverage, b.cells[i].coverage) >= .4) {
      pairs.add((a.cells[i], b.cells[i]));
    }
  }
  if (pairs.isEmpty) return 1;
  return pairs.fold(
        0.0,
        (s, p) =>
            s +
            (p.$1.edges - p.$2.edges).abs() +
            .5 * (p.$1.texture - p.$2.texture).abs() +
            (p.$1.mean - p.$2.mean).abs(),
      ) /
      pairs.length;
}
