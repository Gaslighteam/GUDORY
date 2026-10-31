import 'dart:convert';
import 'dart:math' as math;

import '../../core/models.dart';
import 'candidate_stability.dart';
import 'clip_runner.dart';
import 'recommendation_data.dart';

class LayoutScoringConfig {
  const LayoutScoringConfig({this.clipWeight = .85, this.supportWeight = .15});
  final double clipWeight, supportWeight;
  void validate() {
    if (![clipWeight, supportWeight].every((v) => v.isFinite && v >= 0) ||
        clipWeight + supportWeight <= 0) {
      throw ArgumentError('Invalid candidate scoring weights');
    }
  }
}

class LayoutPrototype {
  const LayoutPrototype(this.id, this.composition, this.confidence);
  final String id;
  final SceneComposition composition;
  final double confidence;
}

class _PrototypeCluster {
  const _PrototypeCluster(this.background, this.levels);
  final SceneCluster background;
  final Map<int, List<LayoutPrototype>> levels;
}

/// Optional sidecar: legacy recommend.json remains byte-for-byte compatible.
/// Every prototype centre must match a centre in the loaded legacy asset.
class LayoutPrototypeData {
  const LayoutPrototypeData._(this._clusters, this._backgrounds);
  final List<_PrototypeCluster> _clusters;
  final List<SceneCluster> _backgrounds;

  static LayoutPrototypeData parse(String text, RecommendationData base) {
    if (utf8.encode(text).length >= 1000000) {
      throw const FormatException('Layout asset exceeds size limit');
    }
    final root = _object(jsonDecode(text), {'version', 'clusters'});
    if (root['version'] is! int ||
        root['version'] != 1 ||
        root['clusters'] is! List ||
        (root['clusters'] as List).length > 128) {
      throw const FormatException('Invalid layout schema');
    }
    final clusters = <_PrototypeCluster>[];
    final seen = <SceneCluster>{};
    final ids = <String>{};
    for (final raw in root['clusters'] as List) {
      final c = _object(raw, {'o', 'e', 'lv'});
      final orientation = switch (c['o']) {
        'p' => ShotOrientation.portrait,
        'l' => ShotOrientation.landscape,
        _ => throw const FormatException('Invalid orientation'),
      };
      final encoded = c['e'];
      if (encoded is! String || encoded.length != 684) {
        throw const FormatException('Invalid centre');
      }
      final bytes = base64Decode(encoded);
      if (bytes.length != 512 ||
          bytes.contains(128) ||
          base64Encode(bytes) != encoded) {
        throw const FormatException('Invalid centre');
      }
      final vector = bytes.map((v) => (v > 127 ? v - 256 : v) / 127).toList();
      final norm = vectorNorm(vector);
      if (norm <= .85 || norm >= 1.15) {
        throw const FormatException('Invalid centre norm');
      }
      final normalized = normalizeClipEmbedding(vector);
      final related = base.clusters.where(
        (b) =>
            b.orientation == orientation &&
            List.generate(
              512,
              (i) => (b.center[i] - normalized[i]).abs(),
            ).every((difference) => difference < 1e-12),
      );
      if (related.length != 1 || !seen.add(related.single)) {
        throw const FormatException('Duplicate or unrelated background');
      }
      final background = related.single;
      final levels = <int, List<LayoutPrototype>>{};
      var totalSupport = 0;
      for (final entry in _map(c['lv']).entries) {
        final level = int.tryParse(entry.key);
        if (level == null ||
            entry.key != '$level' ||
            !background.levels.containsKey(level) ||
            entry.value is! List ||
            (entry.value as List).isEmpty ||
            (entry.value as List).length > 16) {
          throw const FormatException('Invalid layout level');
        }
        final modes = <LayoutPrototype>[];
        for (final value in entry.value as List) {
          final m = _object(value, {
            'id',
            'f',
            'h',
            'cx',
            'cy',
            'hy',
            'n',
            'spread',
            'confidence',
          });
          final id = m['id'];
          if (id is! String ||
              id.length > 80 ||
              !RegExp(r'^[pl]-[0-9a-f]{24}-[1-5]-[0-9]+$').hasMatch(id) ||
              !id.startsWith('${c['o']}-') ||
              !id.contains('-$level-') ||
              !ids.add(id)) {
            throw const FormatException('Invalid aggregate candidate ID');
          }
          final n = m['n'];
          final h = _unit(m['h']);
          final confidence = _unit(m['confidence']);
          final spread = m['spread'];
          if (n is! int ||
              n < 3 ||
              h <= 0 ||
              confidence <= 0 ||
              m['hy'] != null ||
              spread is! num ||
              !spread.isFinite ||
              spread < 0) {
            throw const FormatException('Invalid prototype support/spread');
          }
          totalSupport += n;
          modes.add(
            LayoutPrototype(
              id,
              SceneComposition(
                Framing.values.byName(m['f'] as String),
                h,
                _unit(m['cx']),
                _unit(m['cy']),
                null,
                n,
              ),
              confidence,
            ),
          );
        }
        levels[level] = List.unmodifiable(modes);
      }
      if (levels.isEmpty || totalSupport > background.support) {
        throw const FormatException('Invalid aggregate support');
      }
      clusters.add(_PrototypeCluster(background, Map.unmodifiable(levels)));
    }
    return LayoutPrototypeData._(List.unmodifiable(clusters), base.clusters);
  }

  /// Current-input scores for all supported candidates, with top-three
  /// backgrounds eligible to challenge. Never average target coordinates.
  List<ScoredLayoutCandidate> rank(
    List<double> embedding,
    int requested,
    ShotOrientation orientation,
    String variant, {
    LayoutScoringConfig config = const LayoutScoringConfig(),
  }) {
    config.validate();
    if (variant != 'q8' && variant != 'fp16') return const [];
    final level = recommendationLevel(requested);
    final query = normalizeClipEmbedding(embedding);
    final retrieval = <(int, SceneCluster, double)>[];
    for (var i = 0; i < _backgrounds.length; i++) {
      final c = _backgrounds[i];
      if (c.orientation != orientation || !c.levels.containsKey(level)) {
        continue;
      }
      var score = 0.0;
      for (var j = 0; j < 512; j++) {
        score += query[j] * c.center[j];
      }
      if (score > 0) retrieval.add((i, c, score));
    }
    retrieval.sort((a, b) {
      final byScore = b.$3.compareTo(a.$3);
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });
    // Missing prototype support in the nearest backgrounds must not silently
    // substitute a more distant background. Keep the legacy result instead.
    final nearest = retrieval.take(3).map((r) => r.$2).toSet();
    final scored = <(int, _PrototypeCluster, double)>[];
    for (var i = 0; i < _clusters.length; i++) {
      final c = _clusters[i];
      if (c.background.orientation != orientation ||
          !c.levels.containsKey(level)) {
        continue;
      }
      var score = 0.0;
      for (var j = 0; j < 512; j++) {
        score += query[j] * c.background.center[j];
      }
      if (score > 0) scored.add((i, c, score.clamp(0.0, 1.0)));
    }
    scored.sort((a, b) {
      final byScore = b.$3.compareTo(a.$3);
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });
    final result = <ScoredLayoutCandidate>[];
    for (var i = 0; i < scored.length; i++) {
      final (_, cluster, cosine) = scored[i];
      for (final p in cluster.levels[level]!) {
        final score =
            (config.clipWeight * cosine + config.supportWeight * p.confidence) /
            (config.clipWeight + config.supportWeight);
        result.add(
          ScoredLayoutCandidate(
            id: p.id,
            score: math.min(1, score),
            canChallenge: nearest.contains(cluster.background),
            recommendation: Recommendation(
              target: p.composition.target(orientation, 'recommend:$level'),
              neighbors: p.composition.n,
              modelVariant: variant,
            ),
          ),
        );
      }
    }
    return List.unmodifiable(result);
  }
}

Map<String, dynamic> _map(dynamic v) {
  if (v is! Map<String, dynamic>) {
    throw const FormatException('Expected object');
  }
  return v;
}

Map<String, dynamic> _object(dynamic v, Set<String> keys) {
  final m = _map(v);
  if (m.length != keys.length || !m.keys.every(keys.contains)) {
    throw const FormatException('Unexpected fields');
  }
  return m;
}

double _unit(dynamic v) {
  if (v is! num || !v.isFinite || v < 0 || v > 1) {
    throw const FormatException('Invalid normalized value');
  }
  return v.toDouble();
}
