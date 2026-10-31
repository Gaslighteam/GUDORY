import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'spatial_features.dart';

Map<String, dynamic> spatialParityFixture() =>
    jsonDecode(File('../tools/phase_b_parity.json').readAsStringSync())
        as Map<String, dynamic>;

/// Public procedural pixels, not private photographs or captured camera data.
(Uint8List, List<double>) spatialPattern({
  int width = 96,
  int height = 96,
  String side = 'right',
  int maskX = 48,
  int personValue = 255,
}) {
  final rgb = Uint8List(width * height * 3),
      mask = List<double>.filled(width * height, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final gx = x * 96 ~/ width, gy = y * 96 ~/ height, i = y * width + x;
      final structured = side == 'right'
          ? gx >= 64
          : side == 'left'
          ? gx < 32
          : false;
      final value = structured
          ? ((gx ~/ 4 + gy ~/ 4) % 2 == 1 ? 220 : 30)
          : 100;
      final person = (gx - maskX).abs() < 5 && gy >= 38 && gy < 68;
      mask[i] = person ? 1 : 0;
      rgb[i * 3] = person ? personValue : value;
      rgb[i * 3 + 1] = person ? 0 : value;
      rgb[i * 3 + 2] = person ? 0 : value;
    }
  }
  return (rgb, mask);
}

SpatialFeatures spatialPatternFeature(String side) {
  final (rgb, mask) = spatialPattern(side: side);
  return extractSpatial(rgb, 96, 96, mask, 96, 96);
}
