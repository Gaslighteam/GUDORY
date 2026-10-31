import 'dart:convert';

import '../../core/models.dart';
import 'clip_runner.dart';

int recommendationLevel(int level) => level.clamp(1, 5);

class SceneComposition {
  const SceneComposition(
    this.framing,
    this.h,
    this.cx,
    this.cy,
    this.hy,
    this.n,
  );
  final Framing framing;
  final double h, cx, cy;
  final double? hy;
  final int n;

  TargetComposition target(ShotOrientation orientation, String source) =>
      TargetComposition(
        framing: framing,
        personHeightRatio: h,
        personCenterX: cx,
        personCenterY: cy,
        horizonY: hy,
        orientation: orientation,
        source: source,
      );
}

class SceneCluster {
  SceneCluster(this.orientation, this.center, this.levels, {int? support})
    : support = support ?? levels.values.fold<int>(0, (sum, c) => sum + c.n);
  final int support;
  final ShotOrientation orientation;
  final List<double> center;
  final Map<int, SceneComposition> levels;
}

class SceneMatch {
  const SceneMatch(this.recommendation, this.cosine, this.selectedLevel);
  final Recommendation recommendation;
  final double? cosine;
  final int? selectedLevel;
}

/// Immutable aggregate data only. Invalid records are never used for matching.
class RecommendationData {
  RecommendationData(this.fallbacks, this.clusters);
  final Map<ShotOrientation, Map<int, SceneComposition>> fallbacks;
  final List<SceneCluster> clusters;

  static RecommendationData empty() => RecommendationData(const {}, const []);

  static RecommendationData parse(String text) {
    if (text.length >= 1000000 || utf8.encode(text).length >= 1000000) {
      throw const FormatException('Recommendation asset exceeds size limit');
    }
    final root = _map(jsonDecode(text));
    _keys(root, {'model', 'dim', 'quant', 'levels', 'fallback', 'clusters'});
    if (root['model'] != 'clip-vit-base-patch32' ||
        root['dim'] is! int ||
        root['dim'] != 512 ||
        root['quant'] != 'int8') {
      throw const FormatException('Unsupported recommendation encoder');
    }
    final fallbacks = <ShotOrientation, Map<int, SceneComposition>>{};
    final usableOrientations = <ShotOrientation>{};
    for (final o in ShotOrientation.values) {
      final compositions = <int, SceneComposition>{};
      for (var level = 1; level <= 5; level++) {
        try {
          final raw = _map(_map(root['fallback'])[o.name]);
          compositions[level] = _composition(raw['$level'], false);
        } catch (_) {
          /* Missing median uses the embedded safe baseline. */
        }
      }
      fallbacks[o] = Map.unmodifiable(compositions);
      try {
        final edges = _map(root['levels'])[o.name];
        if (edges is! List || edges.length != 4) throw const FormatException();
        final values = edges.map(_unit).toList();
        if (values.any((v) => v <= 0)) throw const FormatException();
        for (var i = 1; i < values.length; i++) {
          if (values[i] > values[i - 1]) throw const FormatException();
        }
        usableOrientations.add(o);
      } catch (_) {
        /* Invalid boundaries disable matching for that orientation. */
      }
    }
    final clusters = <SceneCluster>[];
    final counts = <ShotOrientation, int>{};
    final rawClusters = root['clusters'];
    if (rawClusters is List && rawClusters.length <= 128) {
      for (final raw in rawClusters) {
        try {
          final c = _map(raw);
          _keys(c, {'o', 'e', 'n', 'lv'});
          final o = switch (c['o']) {
            'p' => ShotOrientation.portrait,
            'l' => ShotOrientation.landscape,
            _ => throw const FormatException('Invalid orientation'),
          };
          if (!usableOrientations.contains(o) || (counts[o] ?? 0) >= 64) {
            continue;
          }
          final n = _support(c['n']);
          final encoded = c['e'];
          if (encoded is! String || encoded.length != 684) {
            throw const FormatException();
          }
          final bytes = base64Decode(encoded);
          if (bytes.length != 512 ||
              base64Encode(bytes) != encoded ||
              bytes.contains(128)) {
            throw const FormatException('Invalid int8 centre');
          }
          final vector = bytes
              .map((b) => (b > 127 ? b - 256 : b) / 127)
              .toList();
          final norm = vectorNorm(vector);
          if (norm <= .85 || norm >= 1.15) {
            throw const FormatException('Invalid centre norm');
          }
          final levels = <int, SceneComposition>{};
          for (final entry in _map(c['lv']).entries) {
            final level = int.tryParse(entry.key);
            if (level == null ||
                level < 1 ||
                level > 5 ||
                entry.key != '$level') {
              throw const FormatException('Invalid level');
            }
            levels[level] = _composition(entry.value, true);
          }
          if (levels.isEmpty ||
              levels.values.fold<int>(0, (sum, v) => sum + v.n) > n) {
            throw const FormatException('Invalid level support');
          }
          clusters.add(
            SceneCluster(
              o,
              List.unmodifiable(normalizeClipEmbedding(vector)),
              Map.unmodifiable(levels),
              support: n,
            ),
          );
          counts[o] = (counts[o] ?? 0) + 1;
        } catch (_) {
          /* A corrupt cluster cannot invalidate valid medians. */
        }
      }
    }
    return RecommendationData(
      Map.unmodifiable(fallbacks),
      List.unmodifiable(clusters),
    );
  }

  Recommendation fallback(int level, ShotOrientation orientation) =>
      Recommendation(
        target:
            (fallbacks[orientation]?[recommendationLevel(level)] ??
                    _safeBaseline(orientation, recommendationLevel(level)))
                .target(orientation, 'fallback'),
        neighbors: 0,
        modelVariant: 'none',
      );

  SceneMatch match(
    List<double> embedding,
    int requested,
    ShotOrientation orientation,
    String variant,
  ) {
    final level = recommendationLevel(requested);
    final vector = normalizeClipEmbedding(embedding);
    final same = clusters.where((c) => c.orientation == orientation).toList();
    final available = same.expand((c) => c.levels.keys).toSet().toList()
      ..sort((a, b) {
        final distance = (a - level).abs().compareTo((b - level).abs());
        return distance != 0 ? distance : a.compareTo(b);
      });
    if (available.isEmpty) {
      return SceneMatch(fallback(level, orientation), null, null);
    }
    final selected = available.first;
    final scored = <(int, SceneCluster, double)>[];
    for (var i = 0; i < same.length; i++) {
      final c = same[i];
      if (!c.levels.containsKey(selected)) continue;
      var score = 0.0;
      for (var j = 0; j < 512; j++) {
        score += vector[j] * c.center[j];
      }
      score = score.clamp(-1.0, 1.0);
      if (score > 0) scored.add((i, c, score));
    }
    scored.sort((a, b) {
      final byScore = b.$3.compareTo(a.$3);
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });
    if (scored.isEmpty) {
      return SceneMatch(fallback(level, orientation), null, selected);
    }
    final framing = scored.first.$2.levels[selected]!.framing;
    double weight = 0, h = 0, cx = 0, cy = 0, hy = 0, horizonWeight = 0;
    var neighbors = 0;
    // Select three first; do not backfill a fourth after filtering framing.
    for (final (_, cluster, score) in scored.take(3)) {
      final c = cluster.levels[selected]!;
      if (c.framing != framing) continue;
      final w = score * c.n; // actual contributors at this level/framing
      weight += w;
      h += w * c.h;
      cx += w * c.cx;
      cy += w * c.cy;
      neighbors += c.n;
      if (c.hy != null) {
        hy += w * c.hy!;
        horizonWeight += w;
      }
    }
    if (!weight.isFinite ||
        weight <= 0 ||
        (variant != 'q8' && variant != 'fp16')) {
      return SceneMatch(
        fallback(level, orientation),
        scored.first.$3,
        selected,
      );
    }
    final composition = SceneComposition(
      framing,
      (h / weight).clamp(0.0, 1.0),
      (cx / weight).clamp(0.0, 1.0),
      (cy / weight).clamp(0.0, 1.0),
      horizonWeight > 0 ? (hy / horizonWeight).clamp(0.0, 1.0) : null,
      neighbors,
    );
    return SceneMatch(
      Recommendation(
        target: composition.target(orientation, 'recommend:$level'),
        neighbors: neighbors,
        modelVariant: variant,
      ),
      scored.first.$3,
      selected,
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected object');
  }
  return value;
}

void _keys(Map<String, dynamic> value, Set<String> keys) {
  if (value.length != keys.length || !value.keys.every(keys.contains)) {
    throw const FormatException('Unexpected fields');
  }
}

double _unit(dynamic value) {
  if (value is! num || !value.isFinite || value < 0 || value > 1) {
    throw const FormatException('Invalid normalized composition');
  }
  return value.toDouble();
}

int _support(dynamic value) {
  if (value is! int || value < 3) {
    throw const FormatException('Insufficient support');
  }
  return value;
}

SceneComposition _composition(dynamic value, bool clustered) {
  final c = _map(value);
  _keys(c, {'f', 'h', 'cx', 'cy', 'hy', if (clustered) 'n'});
  final framing = Framing.values.byName(c['f'] as String);
  final h = _unit(c['h']);
  if (h <= 0) throw const FormatException('Invalid span');
  return SceneComposition(
    framing,
    h,
    _unit(c['cx']),
    _unit(c['cy']),
    c['hy'] == null ? null : _unit(c['hy']),
    clustered ? _support(c['n']) : 0,
  );
}

// Emergency medians copied from the verified 797-photo aggregate baseline.
// Loaded asset medians always take precedence; these are not per-photo data.
SceneComposition _safeBaseline(ShotOrientation o, int level) {
  const p = [
    (
      Framing.chestUp,
      .34151695668697357,
      .5164077679316204,
      .33755815029144287,
    ),
    (
      Framing.waistUp,
      .47546084225177765,
      .5294006575052053,
      .25846366584300995,
    ),
    (
      Framing.fullBody,
      .6950831487774849,
      .5052800476551056,
      .21004103124141693,
    ),
    (
      Framing.fullBody,
      .5589739233255386,
      .49739086627960205,
      .24461490660905838,
    ),
    (
      Framing.fullBody,
      .39422476291656494,
      .4824052006006241,
      .3526468575000763,
    ),
  ];
  const l = [
    (Framing.chestUp, .3649735003709793, .5139625072479248, .4236085116863251),
    (
      Framing.waistUp,
      .42234115302562714,
      .5437610894441605,
      .33135688304901123,
    ),
    (Framing.fullBody, .5706796497106552, .5355785340070724, .2612886279821396),
    (
      Framing.fullBody,
      .46630173176527023,
      .566758930683136,
      .33149343729019165,
    ),
    (
      Framing.fullBody,
      .34351275116205215,
      .4726949483156204,
      .4072829484939575,
    ),
  ];
  final c = (o == ShotOrientation.portrait ? p : l)[level - 1];
  return SceneComposition(c.$1, c.$2, c.$3, c.$4, null, 0);
}
