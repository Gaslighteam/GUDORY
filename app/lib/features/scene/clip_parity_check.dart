// Synthetic reference cases generated with the pinned Python/Pillow pipeline.
// Used by tests and the standalone Android diagnostic, never by live inference.
import 'package:image/image.dart' as img;

import 'clip_runner.dart';

const clipParityCases = [
  (16, 12, 0x3cffb0ff),
  (12, 16, 0x10657302),
  (500, 300, 0xac17f106),
  (300, 500, 0x94d7c620),
  (227, 331, 0x9a1a99c0),
  (331, 227, 0xd41d7e85),
  (448, 224, 0x7567cec5),
  (1, 5, 0xaab4b9c5),
  (5, 1, 0xab523b45),
];

img.Image clipParityImage(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (final p in image) {
    p.setRgb(
      (p.x * 17 + p.y * 29) % 256,
      (p.x * p.x * 7 + p.y * 13) % 256,
      (p.x * 3 + p.y * p.y * 11) % 256,
    );
  }
  return image;
}

/// Non-cryptographic FNV-1a over every synthetic RGB output byte, not a photo ID.
int clipRgbChecksum(img.Image image) {
  var value = 2166136261;
  for (final b in image.getBytes(order: img.ChannelOrder.rgb)) {
    value = ((value ^ b) * 16777619) & 0xffffffff;
  }
  return value;
}

String checkClipRgbParity(Object? _) {
  var passed = 0;
  for (final (width, height, expected) in clipParityCases) {
    final image = clipImageCrop(clipParityImage(width, height));
    if (clipRgbChecksum(image) == expected) passed++;
  }
  return 'synthetic_rgb=$passed/${clipParityCases.length}';
}
