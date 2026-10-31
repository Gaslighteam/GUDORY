import 'dart:math' as math;
import 'dart:typed_data';

const spatialFeatureSpec = 'grid96-luma77-150-29-edge4-range9-dilate2-v1';

/// Already-oriented, already-cropped shot coordinates. No semantic detections.
class SpatialFeatures {
  const SpatialFeatures({
    this.grid = const [],
    this.centroid = const [.5, .5],
    this.asymmetry = const [0, 0],
    this.confidence = 0,
    this.coverage = 0,
    this.reason = 'unavailable',
  });
  final List<double> grid, centroid, asymmetry;
  final double confidence, coverage;
  final String reason;
  bool get valid =>
      reason == 'ok' &&
      confidence >= .1 &&
      confidence <= 1 &&
      grid.length == 18 &&
      centroid.length == 2 &&
      asymmetry.length == 2 &&
      [
        ...grid,
        ...centroid,
        coverage,
      ].every((v) => v.isFinite && v >= 0 && v <= 1) &&
      asymmetry.every((v) => v.isFinite && v >= -1 && v <= 1);

  List<double> relation(double cx, double cy) {
    if (!valid ||
        !cx.isFinite ||
        !cy.isFinite ||
        cx < 0 ||
        cx > 1 ||
        cy < 0 ||
        cy > 1) {
      throw const FormatException(
        'Reliable spatial feature and normalized target required',
      );
    }
    return [
      (cx - centroid[0] + 1) / 2,
      (cy - centroid[1] + 1) / 2,
      .5 + (cx - .5) * asymmetry[0],
      .5 + (cy - .5) * asymmetry[1],
    ];
  }
}

/// Integer nearest-center sampling and luma match tools/spatial_features.py.
/// The supplied mask is aligned with the shot (resolution may differ). Masked
/// pixels plus a two-grid-pixel halo never enter gradient/texture measurements.
SpatialFeatures extractSpatial(
  Uint8List rgb,
  int width,
  int height,
  List<double> mask,
  int maskWidth,
  int maskHeight,
) {
  if (width < 3 ||
      height < 3 ||
      rgb.length != width * height * 3 ||
      maskWidth < 1 ||
      maskHeight < 1 ||
      mask.length != maskWidth * maskHeight ||
      !mask.every((v) => v.isFinite && v >= 0 && v <= 1)) {
    return const SpatialFeatures(reason: 'invalid-input');
  }
  const size = 96;
  final luma = Int32List(size * size), person = Uint8List(size * size);
  for (var y = 0; y < size; y++) {
    final sy = ((2 * y + 1) * height) ~/ (2 * size),
        my = ((2 * y + 1) * maskHeight) ~/ (2 * size);
    for (var x = 0; x < size; x++) {
      final sx = ((2 * x + 1) * width) ~/ (2 * size),
          mx = ((2 * x + 1) * maskWidth) ~/ (2 * size);
      final p = (sy * width + sx) * 3, i = y * size + x;
      luma[i] = (77 * rgb[p] + 150 * rgb[p + 1] + 29 * rgb[p + 2] + 128) ~/ 256;
      person[i] = mask[my * maskWidth + mx] >= .5 ? 1 : 0;
    }
  }
  final counts = List<int>.filled(9, 0),
      edges = List<int>.filled(9, 0),
      textures = List<int>.filled(9, 0);
  for (var y = 2; y < 94; y++) {
    for (var x = 2; x < 94; x++) {
      var keep = true;
      for (var dy = -2; dy <= 2 && keep; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          if (person[(y + dy) * size + x + dx] != 0) {
            keep = false;
            break;
          }
        }
      }
      if (!keep) continue;
      final i = y * size + x, cell = (y ~/ 32) * 3 + x ~/ 32, v = luma[i];
      counts[cell]++;
      edges[cell] +=
          (v - luma[i - 1]).abs() +
          (v - luma[i + 1]).abs() +
          (v - luma[i - size]).abs() +
          (v - luma[i + size]).abs();
      var low = 255, high = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final n = luma[(y + dy) * size + x + dx];
          low = math.min(low, n);
          high = math.max(high, n);
        }
      }
      textures[cell] += high - low;
    }
  }
  final es = <double>[], ts = <double>[], coverages = <double>[];
  for (var i = 0; i < 9; i++) {
    if (counts[i] == 0) return const SpatialFeatures(reason: 'coverage');
    final row = i ~/ 3, col = i % 3;
    final potential =
        (math.min((row + 1) * 32, 94) - math.max(row * 32, 2)) *
        (math.min((col + 1) * 32, 94) - math.max(col * 32, 2));
    coverages.add(counts[i] / potential);
    es.add(edges[i] / (counts[i] * 1020));
    ts.add(textures[i] / (counts[i] * 255));
  }
  final coverage = counts.reduce((a, b) => a + b) / (92 * 92);
  final minimum = coverages.reduce(math.min);
  if (minimum < .25 || coverage < .55) {
    return SpatialFeatures(coverage: coverage, reason: 'coverage');
  }
  final energy = List<double>.generate(9, (i) => (es[i] + ts[i]) / 2);
  final total = energy.reduce((a, b) => a + b),
      contrast = energy.reduce(math.max) - energy.reduce(math.min);
  if (total / 9 < .005 || contrast < .005) {
    return SpatialFeatures(coverage: coverage, reason: 'uninformative');
  }
  final confidence =
      math.min(1.0, (minimum - .25) / .4) *
      math.min(1.0, (coverage - .55) / .3) *
      math.min(1.0, contrast / .03);
  if (confidence < .1) {
    return SpatialFeatures(coverage: coverage, reason: 'low-confidence');
  }
  var cx = 0.0, cy = 0.0, ax = 0.0, ay = 0.0;
  for (var i = 0; i < 9; i++) {
    cx += energy[i] * ((i % 3 + .5) / 3);
    cy += energy[i] * ((i ~/ 3 + .5) / 3);
    ax +=
        energy[i] *
        (i % 3 == 0
            ? -1
            : i % 3 == 2
            ? 1
            : 0);
    ay +=
        energy[i] *
        (i ~/ 3 == 0
            ? -1
            : i ~/ 3 == 2
            ? 1
            : 0);
  }
  final grid = <double>[];
  for (final values in [es, ts]) {
    final denominator = 4 * math.max(values.reduce((a, b) => a + b) / 9, .005);
    grid.addAll(values.map((v) => math.min(1.0, v / denominator)));
  }
  return SpatialFeatures(
    grid: List.unmodifiable(grid),
    centroid: [cx / total, cy / total],
    asymmetry: [ax / total, ay / total],
    confidence: confidence,
    coverage: coverage,
    reason: 'ok',
  );
}
