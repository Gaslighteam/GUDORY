// Synthetic RGB reference checksums generated independently with Pillow 13.0.0.
// Formula and reference procedure are in LANDSCAPE_DIAGNOSIS.md. No photo data.
import 'package:image/image.dart' as img;
// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';

import 'clip_runner.dart';
import 'clip_parity_check.dart';

void main() {
  for (final fixture in clipParityCases) {
    test('Pillow RGB resize/crop golden ${fixture.$1}x${fixture.$2}', () {
      final image = clipParityImage(fixture.$1, fixture.$2);
      final original = image.getBytes(order: img.ChannelOrder.rgb).toList();
      final crop = clipImageCrop(image);
      expect([crop.width, crop.height], [224, 224]);
      expect(clipRgbChecksum(crop), fixture.$3);
      expect(
        image.getBytes(order: img.ChannelOrder.rgb),
        orderedEquals(original),
      );
    });
  }
}
