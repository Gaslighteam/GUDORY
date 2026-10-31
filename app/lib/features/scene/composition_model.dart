// Recommender v2 (tools/train_recommender_v2.py, tools/report_v2.md): a small
// linear model over the person-masked background CLIP embedding.
//
// features = PCA(embedding) [k] + one-hot[(level - 1) + 5 * orientationIndex]
// framing  = argmax(coef · features + intercept)
// offset   = |cx - 0.5| (ridge), eye line cy (ridge), height = table lookup
// The side is not learned: the person stays on the side they already stand on
// (person mask centroid). Medians of a left/right mix collapse to the centre,
// which is why v1 recommended the middle 80~90% of the time.
import 'dart:convert';
import 'dart:math' as math;

import '../../core/models.dart';

class CompositionModel {
  CompositionModel._(
    this.photos,
    this._mean,
    this._components,
    this._framingCoef,
    this._framingIntercept,
    this._offsetCoef,
    this._offsetIntercept,
    this._maxOffset,
    this._eyeCoef,
    this._eyeIntercept,
    this._height,
  );

  /// Training photos behind the model (Recommendation.neighbors).
  final int photos;
  final List<double> _mean;
  final List<List<double>> _components;
  final List<List<double>> _framingCoef;
  final List<double> _framingIntercept;
  final List<double> _offsetCoef;
  final double _offsetIntercept, _maxOffset;
  final List<double> _eyeCoef;
  final double _eyeIntercept;
  final Map<(ShotOrientation, int, Framing), double> _height;

  static const _dim = 512;

  /// Throws [FormatException] on anything malformed; callers fall back to v1.
  static CompositionModel parse(String text) {
    final root = jsonDecode(text);
    if (root is! Map<String, dynamic> ||
        root['model'] != 'gudory-recommender-v2' ||
        root['dim'] != _dim) {
      throw const FormatException('Unsupported recommender v2 asset');
    }
    final k = root['k'];
    if (k is! int || k < 1 || k > 128) throw const FormatException('k');
    final features = k + 10;
    final framings = (root['framings'] as List).cast<String>();
    if (framings.join(',') != Framing.values.map((f) => f.name).join(',')) {
      throw const FormatException('framings');
    }
    final components = _matrix(root['components'], k, _dim);
    final framing = root['framing'] as Map<String, dynamic>;
    final offset = root['offset'] as Map<String, dynamic>;
    final eye = root['eyeY'] as Map<String, dynamic>;
    final height = <(ShotOrientation, int, Framing), double>{};
    final table = root['height'] as Map<String, dynamic>;
    for (final o in ShotOrientation.values) {
      final byLevel = table[o.name] as Map<String, dynamic>;
      for (var level = 1; level <= 5; level++) {
        final byFraming = byLevel['$level'] as Map<String, dynamic>;
        for (final f in Framing.values) {
          final h = _number(byFraming[f.name]);
          if (h <= 0 || h > 1) throw const FormatException('height');
          height[(o, level, f)] = h;
        }
      }
    }
    final photos = root['photos'];
    return CompositionModel._(
      photos is int && photos > 0 ? photos : 1,
      _vector(root['mean'], _dim),
      components,
      _matrix(framing['coef'], Framing.values.length, features),
      _vector(framing['intercept'], Framing.values.length),
      _vector(offset['coef'], features),
      _number(offset['intercept']),
      _number(offset['max']).clamp(0.0, 0.5),
      _vector(eye['coef'], features),
      _number(eye['intercept']),
      height,
    );
  }

  /// [personX]: centroid x of the person mask in the shot, 0~1 (null = unknown).
  TargetComposition predict(
    List<double> embedding,
    int level,
    ShotOrientation orientation, {
    double? personX,
  }) {
    if (embedding.length != _dim) throw const FormatException('embedding');
    final lv = level.clamp(1, 5);
    final x = <double>[
      for (final row in _components) _dot(row, embedding, _mean),
      for (var i = 0; i < 10; i++)
        i == (lv - 1) + 5 * orientation.index ? 1.0 : 0.0,
    ];
    var best = 0;
    var bestScore = double.negativeInfinity;
    for (var c = 0; c < _framingCoef.length; c++) {
      final score = _dot(_framingCoef[c], x) + _framingIntercept[c];
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    final framing = Framing.values[best];
    final offset = (_dot(_offsetCoef, x) + _offsetIntercept).clamp(
      0.0,
      _maxOffset,
    );
    final side = personX == null || !personX.isFinite || personX >= 0.5
        ? 1.0
        : -1.0;
    final cy = (_dot(_eyeCoef, x) + _eyeIntercept).clamp(0.0, 1.0);
    if (!offset.isFinite || !cy.isFinite || !bestScore.isFinite) {
      throw const FormatException('non-finite prediction');
    }
    return TargetComposition(
      framing: framing,
      personHeightRatio: _height[(orientation, lv, framing)]!,
      personCenterX: 0.5 + side * offset,
      personCenterY: cy,
      orientation: orientation,
      source: 'recommend-v2:$lv',
    );
  }

  static double _dot(List<double> a, List<double> b, [List<double>? minus]) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * (minus == null ? b[i] : b[i] - minus[i]);
    }
    return sum;
  }

  static double _number(dynamic v) {
    if (v is! num || !v.isFinite) throw const FormatException('number');
    return v.toDouble();
  }

  static List<double> _vector(dynamic v, int length) {
    if (v is! List || v.length != length) throw const FormatException('vector');
    return List.unmodifiable(v.map(_number));
  }

  static List<List<double>> _matrix(dynamic v, int rows, int cols) {
    if (v is! List || v.length != rows) throw const FormatException('matrix');
    return List.unmodifiable(v.map((r) => _vector(r, cols)));
  }
}

/// Mean x of the masked person pixels, for [CompositionModel.predict].
double? personCentroidX(double sumX, int count, int width) =>
    count > 0 && width > 0 ? math.min(1.0, sumX / count / width) : null;
