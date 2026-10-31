import 'dart:convert';
import 'dart:math' as math;

import '../../core/models.dart';
import 'candidate_stability.dart';
import 'clip_runner.dart';
import 'recommendation_data.dart';
import 'spatial_asset_digest.dart';
import 'spatial_features.dart';

class SpatialScoring {
  const SpatialScoring({
    this.alpha = 1,
    this.beta = .8,
    this.gamma = .08,
    this.clipFloor = .15,
    this.clipMargin = .08,
  });
  final double alpha, beta, gamma, clipFloor, clipMargin;
  void validate() {
    if (![
          alpha,
          beta,
          gamma,
          clipFloor,
          clipMargin,
        ].every((v) => v.isFinite && v >= 0) ||
        alpha <= 0 ||
        clipFloor > 1 ||
        clipMargin > 2) {
      throw ArgumentError('Invalid spatial scoring');
    }
  }
}

class SpatialPrototype {
  const SpatialPrototype(
    this.id,
    this.composition,
    this.scale,
    this.mass,
    this.confidence,
    this.cluster,
    this.index,
  );
  final String id;
  final SceneComposition composition;
  final double scale, mass, confidence;
  final int cluster, index;
}

class SpatialParent {
  const SpatialParent(this.orientation, this.center, this.levels);
  final ShotOrientation orientation;
  final List<double> center;
  final Map<int, List<SpatialPrototype>> levels;
}

class SpatialAggregate {
  const SpatialAggregate(
    this.confidence,
    this.grid,
    this.gridVariance,
    this.relation,
    this.relationVariance,
  );
  final double confidence;
  final List<double> grid, gridVariance, relation, relationVariance;
}

class SpatialCandidate {
  SpatialCandidate(
    this.prototype,
    this.score,
    this.cosine,
    this.selectedLevel,
    this.spatialWeight,
    this.compatibility,
    this.canChallenge,
  );
  final SpatialPrototype prototype;
  double score;
  final double cosine, spatialWeight;
  final double? compatibility;
  final int selectedLevel;
  bool canChallenge;
  ScoredLayoutCandidate scored(
    int requested,
    ShotOrientation orientation,
    String variant,
  ) => ScoredLayoutCandidate(
    id: prototype.id,
    score: score,
    canChallenge: canChallenge,
    recommendation: Recommendation(
      target: prototype.composition.target(orientation, 'recommend:$requested'),
      neighbors: prototype.composition.n,
      modelVariant: variant,
    ),
  );
}

/// Optional experimental data, supplied explicitly, never registered in assets
/// or providers. Invalid/missing B data retains the parsed Phase A candidates.
class SpatialLayoutData {
  SpatialLayoutData._(this.base, this.parents, this.prototypes, this.records);
  final RecommendationData base;
  final List<SpatialParent> parents;
  final Map<String, SpatialPrototype> prototypes;
  final Map<String, SpatialAggregate> records;

  static SpatialLayoutData parse(String phaseAText, String? phaseBText) {
    if (utf8.encode(phaseAText).length >= 1000000) {
      throw const FormatException('Phase A too large');
    }
    final a = _object(jsonDecode(phaseAText), {
      'schema',
      'version',
      'model',
      'dim',
      'quant',
      'config',
      'levels',
      'fallback',
      'clusters',
    });
    if (a['schema'] != 'gudory-layout-prototypes' ||
        a['version'] is! int ||
        a['version'] != 1 ||
        a['model'] != 'clip-vit-base-patch32' ||
        a['dim'] is! int ||
        a['dim'] != 512 ||
        a['quant'] != 'int8') {
      throw const FormatException('Invalid Phase A schema');
    }
    final config = _object(a['config'], {
      'x_unit',
      'y_unit',
      'log_span_unit',
      'log_scale_unit',
      'minimum_gain',
      'minimum_separation',
      'minimum_gap',
      'gap_multiplier',
      'max_leaves',
      'confidence_prior',
    });
    if (!config.values.every((v) => v is num && v.isFinite && v > 0) ||
        config['max_leaves'] is! int ||
        config['max_leaves'] > 32 ||
        config['minimum_gain'] >= 1) {
      throw const FormatException('Invalid Phase A config');
    }
    final skeleton = {
      for (final k in ['model', 'dim', 'quant', 'levels', 'fallback']) k: a[k],
      'clusters': <dynamic>[],
    };
    final base = RecommendationData.parse(jsonEncode(skeleton));
    final raw = a['clusters'];
    if (raw is! List || raw.length > 128) {
      throw const FormatException('Invalid clusters');
    }
    final parents = <SpatialParent>[],
        prototypes = <String, SpatialPrototype>{},
        counts = <ShotOrientation, int>{};
    for (var ci = 0; ci < raw.length; ci++) {
      final c = _object(raw[ci], {'o', 'e', 'n', 'lv'});
      final o = switch (c['o']) {
        'p' => ShotOrientation.portrait,
        'l' => ShotOrientation.landscape,
        _ => throw const FormatException('Invalid orientation'),
      };
      counts[o] = (counts[o] ?? 0) + 1;
      if (counts[o]! > 64) {
        throw const FormatException('Too many clusters');
      }
      final n = _count(c['n']);
      final encoded = c['e'];
      if (encoded is! String || encoded.length != 684) {
        throw const FormatException('Invalid center');
      }
      final bytes = base64Decode(encoded);
      if (bytes.length != 512 ||
          bytes.contains(128) ||
          base64Encode(bytes) != encoded) {
        throw const FormatException('Invalid int8');
      }
      final values = bytes.map((v) => (v > 127 ? v - 256 : v) / 127).toList();
      final norm = vectorNorm(values);
      if (norm <= .85 || norm >= 1.15) {
        throw const FormatException('Invalid center norm');
      }
      final levels = <int, List<SpatialPrototype>>{};
      var used = 0;
      for (final entry in _map(c['lv']).entries) {
        final lv = int.tryParse(entry.key), list = entry.value;
        if (lv == null ||
            lv < 1 ||
            lv > 5 ||
            '$lv' != entry.key ||
            list is! List ||
            list.isEmpty ||
            list.length > 128) {
          throw const FormatException('Invalid level');
        }
        final modes = <SpatialPrototype>[];
        for (var pi = 0; pi < list.length; pi++) {
          final p = _object(list[pi], {
            'f',
            'h',
            's',
            'cx',
            'cy',
            'hy',
            'n',
            'w',
            'confidence',
          });
          final support = _count(p['n']), h = _unit(p['h']), s = _unit(p['s']);
          final w = _finite(p['w']), confidence = _unit(p['confidence']);
          if (s <= 0 ||
              s > h ||
              w < support ||
              w > 3 * support ||
              confidence <= 0) {
            throw const FormatException('Invalid support/scale');
          }
          final comp = SceneComposition(
            Framing.values.byName(p['f'] as String),
            h,
            _unit(p['cx']),
            _unit(p['cy']),
            p['hy'] == null ? null : _unit(p['hy']),
            support,
          );
          final id = '${c['o']}-$ci-$lv-$pi';
          final proto = SpatialPrototype(id, comp, s, w, confidence, ci, pi);
          modes.add(proto);
          prototypes[id] = proto;
          used += support;
        }
        levels[lv] = List.unmodifiable(modes);
      }
      if (used > n || levels.isEmpty) {
        throw const FormatException('Invalid actual support');
      }
      parents.add(
        SpatialParent(
          o,
          List.unmodifiable(normalizeClipEmbedding(values)),
          Map.unmodifiable(levels),
        ),
      );
    }
    final records = <String, SpatialAggregate>{};
    if (phaseBText != null) {
      try {
        if (utf8.encode(phaseBText).length >= 1000000) {
          throw const FormatException('Phase B too large');
        }
        final b = _object(jsonDecode(phaseBText), {
          'schema',
          'version',
          'feature_spec',
          'phase_a_sha256',
          'records',
        });
        if (b['schema'] != 'gudory-spatial-layout' ||
            b['version'] is! int ||
            b['version'] != 2 ||
            b['feature_spec'] != spatialFeatureSpec ||
            b['phase_a_sha256'] != spatialAssetDigest(phaseAText)) {
          throw const FormatException('Wrong spatial version/link');
        }
        for (final entry in _map(b['records']).entries) {
          final p = prototypes[entry.key];
          if (p == null) {
            throw const FormatException('Unknown prototype');
          }
          final r = _object(entry.value, {
            'n',
            'w',
            'confidence',
            'grid',
            'grid_var',
            'rel',
            'rel_var',
            'placement_var',
          });
          final n = _count(r['n']),
              w = _finite(r['w']),
              confidence = _unit(r['confidence']);
          if (n > p.composition.n || w < n || w > 3 * n || confidence <= 0) {
            throw const FormatException('Invalid spatial support');
          }
          _array(r['placement_var'], 4);
          records[entry.key] = SpatialAggregate(
            confidence,
            _array(r['grid'], 18),
            _array(r['grid_var'], 18),
            _array(r['rel'], 4),
            _array(r['rel_var'], 4),
          );
        }
      } catch (_) {
        records.clear();
      }
    }
    return SpatialLayoutData._(
      base,
      List.unmodifiable(parents),
      Map.unmodifiable(prototypes),
      Map.unmodifiable(records),
    );
  }

  SpatialCandidate? rescoreIncumbent(
    List<double> embedding,
    ShotOrientation orientation,
    SpatialFeatures? feature,
    List<SpatialCandidate> candidates,
    String? identity, {
    SpatialScoring config = const SpatialScoring(),
  }) {
    if (identity == null || candidates.any((c) => c.prototype.id == identity)) {
      return null;
    }
    final p = prototypes[identity];
    if (p == null || parents[p.cluster].orientation != orientation) {
      return null;
    }
    final vector = normalizeClipEmbedding(embedding),
        parent = parents[p.cluster];
    var cosine = 0.0;
    for (var i = 0; i < 512; i++) {
      cosine += vector[i] * parent.center[i];
    }
    cosine = cosine.clamp(-1.0, 1.0);
    if (cosine <= 0) {
      return null;
    }
    final mass = math.max(
      p.mass,
      candidates.fold<double>(0, (sum, c) => sum + c.prototype.mass),
    );
    final support = math.log(1 + p.mass) / math.log(1 + mass),
        r = records[identity];
    var b = 0.0;
    double? spatial;
    final best = candidates.isEmpty
        ? cosine
        : candidates.map((c) => c.cosine).reduce(math.max);
    if (candidates.any((c) => c.spatialWeight > 0) &&
        feature != null &&
        feature.valid &&
        r != null &&
        cosine >= math.max(config.clipFloor, best - config.clipMargin)) {
      final rel = feature.relation(p.composition.cx, p.composition.cy);
      var gd = 0.0, rd = 0.0;
      for (var i = 0; i < 18; i++) {
        gd +=
            math.pow(feature.grid[i] - r.grid[i], 2) /
            (r.gridVariance[i] + .0025);
      }
      for (var i = 0; i < 4; i++) {
        rd +=
            math.pow(rel[i] - r.relation[i], 2) /
            (r.relationVariance[i] + .0025);
      }
      spatial = math.exp(-math.min(50, .3 * gd / 18 + .7 * rd / 4));
      b = config.beta * feature.confidence * r.confidence;
    }
    final score =
        (config.alpha * cosine +
            config.gamma * support +
            (b > 0 ? b * spatial! : 0)) /
        (config.alpha + config.gamma + b);
    return SpatialCandidate(
      p,
      score,
      cosine,
      int.parse(identity.split('-')[2]),
      b,
      spatial,
      false,
    );
  }

  List<SpatialCandidate> rank(
    List<double> embedding,
    int requested,
    ShotOrientation orientation,
    SpatialFeatures? feature, {
    SpatialScoring config = const SpatialScoring(),
  }) {
    config.validate();
    final level = recommendationLevel(requested),
        vector = normalizeClipEmbedding(embedding);
    final same = parents.where((p) => p.orientation == orientation).toList();
    final available = same.expand((p) => p.levels.keys).toSet().toList()
      ..sort((a, b) {
        final d = (a - level).abs().compareTo((b - level).abs());
        return d != 0 ? d : a.compareTo(b);
      });
    if (available.isEmpty) return [];
    final selected = available.first, scored = <(int, SpatialParent, double)>[];
    for (var i = 0; i < same.length; i++) {
      if (!same[i].levels.containsKey(selected)) continue;
      var cosine = 0.0;
      for (var j = 0; j < 512; j++) {
        cosine += vector[j] * same[i].center[j];
      }
      if (cosine > 0) scored.add((i, same[i], cosine.clamp(-1.0, 1.0)));
    }
    scored.sort((a, b) {
      final d = b.$3.compareTo(a.$3);
      return d != 0 ? d : a.$1.compareTo(b.$1);
    });
    final top = scored.take(3).toList();
    if (top.isEmpty) return [];
    final mass = top.fold<double>(
      0,
      (sum, p) =>
          sum + p.$2.levels[selected]!.fold<double>(0, (s, v) => s + v.mass),
    );
    final answer = <SpatialCandidate>[];
    for (final (_, parent, cosine) in top) {
      for (final p in parent.levels[selected]!) {
        final support = math.log(1 + p.mass) / math.log(1 + mass),
            r = records[p.id];
        var b = 0.0;
        double? spatial;
        final clipOk =
            cosine >=
            math.max(config.clipFloor, top.first.$3 - config.clipMargin);
        if (config.beta > 0 &&
            feature != null &&
            feature.valid &&
            r != null &&
            clipOk) {
          final rel = feature.relation(p.composition.cx, p.composition.cy);
          var gd = 0.0, rd = 0.0;
          for (var i = 0; i < 18; i++) {
            gd +=
                math.pow(feature.grid[i] - r.grid[i], 2) /
                (r.gridVariance[i] + .0025);
          }
          for (var i = 0; i < 4; i++) {
            rd +=
                math.pow(rel[i] - r.relation[i], 2) /
                (r.relationVariance[i] + .0025);
          }
          spatial = math.exp(-math.min(50, .3 * gd / 18 + .7 * rd / 4));
          b = config.beta * feature.confidence * r.confidence;
        }
        final score =
            (config.alpha * cosine +
                config.gamma * support +
                (b > 0 ? b * spatial! : 0)) /
            (config.alpha + config.gamma + b);
        answer.add(
          SpatialCandidate(p, score, cosine, selected, b, spatial, clipOk),
        );
      }
    }
    final active = answer.any((c) => c.spatialWeight > 0);
    if (!active) {
      for (final c in answer) {
        c.canChallenge = true;
      }
    }
    final eligible = answer.where((c) => c.canChallenge).toList();
    if (eligible.isEmpty) return [];
    final high = eligible.map((c) => c.score).reduce(math.max);
    final width =
        .005 / (config.alpha + config.gamma + (active ? config.beta : 0));
    final tied = eligible.where((c) => high - c.score <= width).toList()
      ..sort((a, b) {
        var d = b.prototype.mass.compareTo(a.prototype.mass);
        if (d != 0) return d;
        d = b.prototype.composition.n.compareTo(a.prototype.composition.n);
        if (d != 0) return d;
        d = a.prototype.cluster.compareTo(b.prototype.cluster);
        return d != 0 ? d : a.prototype.index.compareTo(b.prototype.index);
      });
    final chosen = tied.first;
    if (active && chosen.spatialWeight == 0) {
      // An unobserved candidate must not gain an advantage solely because
      // other candidates have spatial evidence. Use equivalent Phase A.
      return rank(embedding, requested, orientation, null, config: config);
    }
    for (final c in tied) {
      c.score = identical(c, chosen) ? high : math.max(0, high - 1e-10);
    }
    answer.sort((a, b) {
      if (identical(a, chosen)) return -1;
      if (identical(b, chosen)) return 1;
      final d = b.score.compareTo(a.score);
      return d != 0 ? d : a.prototype.id.compareTo(b.prototype.id);
    });
    return answer;
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected object');
  }
  return value;
}

Map<String, dynamic> _object(dynamic value, Set<String> keys) {
  final m = _map(value);
  if (m.length != keys.length || !m.keys.every(keys.contains)) {
    throw const FormatException('Unexpected fields');
  }
  return m;
}

double _finite(dynamic v) {
  if (v is! num || !v.isFinite) {
    throw const FormatException('Expected finite number');
  }
  return v.toDouble();
}

double _unit(dynamic v) {
  final x = _finite(v);
  if (x < 0 || x > 1) {
    throw const FormatException('Expected normalized value');
  }
  return x;
}

int _count(dynamic v) {
  if (v is! int || v < 3) {
    throw const FormatException('Insufficient support');
  }
  return v;
}

List<double> _array(dynamic v, int length) {
  if (v is! List || v.length != length) {
    throw const FormatException('Invalid vector');
  }
  return List.unmodifiable(v.map(_unit));
}
