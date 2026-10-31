import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Deterministic 448x224 RGB PNG: red | green | blue | white vertical stripes.
/// Its center crop is exactly green (left half) and blue (right half).
/// Kept as source in Seojun's folder; no shared asset declaration is needed.
Uint8List debugTestImage() {
  final image = img.Image(width: 448, height: 224, numChannels: 3);
  const colors = [
    [255, 0, 0],
    [0, 255, 0],
    [0, 0, 255],
    [255, 255, 255],
  ];
  for (final pixel in image) {
    final color = colors[pixel.x ~/ 112];
    pixel.setRgb(color[0], color[1], color[2]);
  }
  return Uint8List.fromList(img.encodePng(image));
}
