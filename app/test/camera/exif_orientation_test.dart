import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/features/camera/exif_orientation.dart';
import 'package:image/image.dart' as img;

Uint8List jpegWithOrientation(int orientation) {
  final image = img.Image(width: 8, height: 4);
  image.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(image));
}

int? orientationOf(Uint8List bytes) =>
    img.decodeJpgExif(bytes)?.imageIfd.orientation;

void main() {
  test('portrait capture (6) turned for top-left landscape becomes 1', () {
    final out = rotateExifOrientation(jpegWithOrientation(6), 1)!;
    expect(orientationOf(out), 1);
  });

  test('portrait capture (6) turned for top-right landscape becomes 3', () {
    final out = rotateExifOrientation(jpegWithOrientation(6), -1)!;
    expect(orientationOf(out), 3);
  });

  test('only the tag changes; the image data is untouched', () {
    final src = jpegWithOrientation(6);
    final out = rotateExifOrientation(src, 1)!;
    expect(out.length, src.length);
    var diff = 0;
    for (var i = 0; i < src.length; i++) {
      if (src[i] != out[i]) diff++;
    }
    expect(diff, lessThanOrEqualTo(2));
  });

  test('no EXIF or a mirrored value falls back (null)', () {
    final plain = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 4, height: 4)),
    );
    expect(rotateExifOrientation(plain, 1), isNull);
    expect(rotateExifOrientation(jpegWithOrientation(2), 1), isNull);
  });
}
