import 'dart:math' as math;
import 'director_models.dart';

class ScoringWeights {
  const ScoringWeights({
    this.overlap = 4,
    this.space = 1.4,
    this.structure = .8,
    this.balance = .45,
    this.emphasis = 3,
    this.feasibility = 1.2,
    this.unknown = 2,
  });
  final double overlap,
      space,
      structure,
      balance,
      emphasis,
      feasibility,
      unknown;
  Map<String, double> get values => {
    'overlap': overlap,
    'space': space,
    'structure': structure,
    'balance': balance,
    'emphasis': emphasis,
    'feasibility': feasibility,
    'unknown': unknown,
  };
}

double lineInside(BackgroundLine l, (double, double, double, double) box) {
  var n = 0;
  for (var t = 0; t < 25; t++) {
    final x = l.x1 + (l.x2 - l.x1) * t / 24, y = l.y1 + (l.y2 - l.y1) * t / 24;
    if (x >= box.$1 && x <= box.$3 && y >= box.$2 && y <= box.$4) n++;
  }
  return n / 25;
}

List<CompositionCandidate> generateCandidates(
  DirectorFrame f,
  SceneFeatures features, [
  ScoringWeights weights = const ScoringWeights(),
]) {
  final p = f.person;
  if (p == null || !p.valid || !features.valid) return [];
  final xs = {
    p.x,
    math.max(.12, p.x - .16),
    math.min(.88, p.x + .16),
    .22,
    .5,
    .78,
  }.toList()..sort();
  final ys = {
    p.eyeY,
    math.max(.12, p.eyeY - .07),
    math.min(.68, p.eyeY + .07),
  }.toList()..sort();
  final scales = {p.scale, p.scale * .8, p.scale * 1.2}.toList()..sort();
  final framings = spans.keys
      .where((v) => spans[v]! <= spans[p.framing]!)
      .toList();
  final desired = [.22, .16, .10, .075, .05][f.level - 1];
  final result = <CompositionCandidate>[];
  for (final x in xs) {
    for (final y in ys) {
      for (final scale in scales) {
        final factor = scale / p.scale,
            head = y - (p.eyeY - p.headY) * scale / p.scale,
            width = p.width * factor;
        final fitting = framings
            .where((v) => head + scale * spans[v]! / .28 <= .97)
            .toList();
        if (fitting.isEmpty) continue;
        final framing = fitting.last,
            bottom = head + scale * spans[fitting.last]! / .28;
        if (head < .035 ||
            bottom > .97 ||
            x - width / 2 < .035 ||
            x + width / 2 > .965) {
          continue;
        }
        final row = math.min(2, (y * 3).toInt()),
            col = math.min(2, (x * 3).toInt());
        final cell = features.cells[row * 3 + col];
        final box = (
          x - width / 2 - .045,
          math.max(0.0, head - .04),
          x + width / 2 + .045,
          math.min(bottom, head + scale * 2),
        );
        final overlap = features.lines.fold(
          0.0,
          (v, l) => v + l.strength * math.min(1, lineInside(l, box) * 5),
        );
        final observed = <RegionCell>[];
        for (var r = math.max(0, row - 1); r < math.min(3, row + 2); r++) {
          for (var c = math.max(0, col - 1); c < math.min(3, col + 2); c++) {
            final cell = features.cells[r * 3 + c];
            if (cell.coverage >= .5) observed.add(cell);
          }
        }
        final complexity =
            observed.fold(0.0, (v, c) => v + c.texture) /
            math.max(1, observed.length);
        final space = cell.coverage >= .5
            ? math.max(0, cell.texture - complexity) +
                  math.max(0, cell.edges - .25) * .4
            : .4;
        final structure = features.lines.fold(
          0.0,
          (v, l) =>
              v +
              l.strength *
                  lineInside(l, (x - width / 2, head, x + width / 2, bottom)),
        );
        final mass = features.cells.fold(
          0.0,
          (v, c) => v + c.texture * c.coverage,
        );
        var massX = .5;
        if (mass > .05) {
          massX = 0;
          for (var i = 0; i < 9; i++) {
            massX +=
                ((i % 3 + .5) / 3) *
                features.cells[i].texture *
                features.cells[i].coverage;
          }
          massX /= mass;
        }
        final terms = <String, double>{
          'overlap': overlap,
          'space': space,
          'structure': structure,
          'balance': mass > .15 ? ((x + massX) / 2 - .5).abs() : 0,
          'emphasis':
              (scale - desired).abs() / math.max(.05, desired) +
              (spans[framing]! / 1.55 - f.level / 5).abs() * .25,
          'feasibility':
              (x - p.x).abs() +
              (y - p.eyeY).abs() +
              (scale / p.scale - 1).abs(),
          'unknown': math.max(0, .5 - cell.coverage),
        };
        final score = -terms.entries.fold(
          0.0,
          (v, e) => v + weights.values[e.key]! * e.value,
        );
        result.add(
          CompositionCandidate(x, y, scale, framing, head, width, score, terms),
        );
      }
    }
  }
  return result;
}

CompositionCandidate? selectCandidate(List<CompositionCandidate> candidates) {
  CompositionCandidate? best;
  for (final c in candidates) {
    if (best == null || c.score > best.score) best = c;
  }
  return best;
}

double compositionError(DirectorPerson p, CompositionCandidate t) =>
    hypot((p.x - t.x) / .08, (p.eyeY - t.eyeY) / .08) +
    (p.scale - t.scale).abs() / math.max(.012, t.scale * .10);
