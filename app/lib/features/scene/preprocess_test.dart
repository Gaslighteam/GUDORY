import 'package:flutter/foundation.dart';
// Existing dev dependency; tests stay inside Seojun's authorized directory.
// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'clip_runner.dart';
import 'nv21_frame.dart';
import 'person_mask.dart';
import 'preprocess.dart';
import 'scene_test_frames.dart';

List<int> rgb(img.Image image, int x, int y) {
  final p = image.getPixel(x, y);
  return [p.r.toInt(), p.g.toInt(), p.b.toInt()];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('NV21 uses VU and correct limited-range BT.601 conversion', () {
    expect(nv21Rgb(16, 128, 128), (0, 0, 0));
    expect(nv21Rgb(235, 128, 128), (255, 255, 255));
    expect(nv21Rgb(82, 240, 90), (255, 1, 0));
    expect(nv21Rgb(145, 34, 54), (0, 255, 1));
    expect(nv21Rgb(41, 110, 240), (0, 0, 255));
    expect(nv21Rgb(0, 0, 255), (0, 54, 255));
  });

  test('stride four samples exact raw coordinates on both spatial axes', () {
    final data = stripeNv21(width: 6, height: 10);
    final image = downsampleNv21(data);
    expect([image.width, image.height], [2, 3]);
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 2; x++) {
        final sx = x * 4, sy = y * 4;
        final vu = data.rowStride * data.height + sy ~/ 2 * data.rowStride + sx;
        final (r, g, b) = nv21Rgb(
          data.bytes[sy * data.rowStride + sx],
          data.bytes[vu],
          data.bytes[vu + 1],
        );
        expect(rgb(image, x, y), [r, g, b]);
      }
    }
  });

  test(
    'padded Y and VU rows, including missing last padding, are stripped',
    () {
      final packed = stripeNv21(), padded = stripeNv21(rowStride: 12);
      expect(padded.packedBytes(), orderedEquals(packed.bytes));
      expect(
        downsampleNv21(padded).getBytes(),
        orderedEquals(downsampleNv21(packed).getBytes()),
      );
      final shortTail = Nv21FrameData(
        bytes: Uint8List.sublistView(padded.bytes, 0, padded.bytes.length - 4),
        width: 8,
        height: 8,
        rowStride: 12,
        rotation: 0,
        mirror: false,
      );
      expect(shortTail.packedBytes(), orderedEquals(packed.bytes));
    },
  );

  test(
    'small even NV21 frames produce a safe one-pixel sample and full tensor',
    () async {
      final result = await preprocessData(stripeNv21(width: 2, height: 2));
      expect([result.width, result.height], [1, 1]);
      expect(result.pixels.length, 150528);
      expect(result.pixels.every((p) => p.isFinite), isTrue);
    },
  );

  test('rejects truncated/odd/ambiguous layouts and invalid rotation', () {
    expect(
      () => Nv21FrameData(
        bytes: Uint8List(20),
        width: 8,
        height: 8,
        rowStride: 8,
        rotation: 0,
        mirror: false,
      ),
      throwsFormatException,
    );
    expect(
      () => Nv21FrameData(
        bytes: Uint8List(20),
        width: 3,
        height: 2,
        rowStride: 4,
        rotation: 0,
        mirror: false,
      ),
      throwsFormatException,
    );
    expect(() => stripeNv21(rotation: 45), throwsFormatException);
    expect(
      () => Nv21FrameData.fromCameraFrame(
        cameraFrameFixture(stripeNv21(), format: 35),
      ),
      throwsFormatException,
    );
  });

  test('CameraFrame snapshot verifies actual metadata and owns its bytes', () {
    final source = stripeNv21(rowStride: 12, rotation: 270, mirror: true);
    final frame = cameraFrameFixture(source);
    final data = Nv21FrameData.fromCameraFrame(frame);
    source.bytes[0] = 0;
    expect(data.bytes[0], 82);
    expect(data.rowStride, 12);
    expect(data.rotation, 270);
    expect(data.mirror, isTrue);
  });

  const expected = {
    0: [
      [255, 1, 0],
      [0, 255, 1],
      [0, 0, 255],
      [255, 255, 255],
    ],
    90: [
      [0, 0, 255],
      [255, 1, 0],
      [255, 255, 255],
      [0, 255, 1],
    ],
    180: [
      [255, 255, 255],
      [0, 0, 255],
      [0, 255, 1],
      [255, 1, 0],
    ],
    270: [
      [0, 255, 1],
      [255, 255, 255],
      [255, 1, 0],
      [0, 0, 255],
    ],
  };
  for (final angle in expected.keys) {
    for (final front in [false, true]) {
      test(
        'rotation $angle and front mirror $front match RGB and lower-res mask',
        () async {
          final frame = stripeNv21(rotation: angle, mirror: front);
          final mask = PersonMask(
            width: 2,
            height: 2,
            confidences: [1, 0, 0, 0],
          );
          final result = await preprocessData(frame, mask: mask);
          final original = img.decodePng(result.originalPreviewPng)!;
          final filled = img.decodePng(result.maskedPreviewPng)!;
          expect(result.maskApplied, isTrue);
          expect(result.maskedPixels, 1);
          expect(result.meanColor, [128, 128, 128]);
          for (var y = 0; y < 2; y++) {
            for (var x = 0; x < 2; x++) {
              final unmirroredX = front ? 1 - x : x;
              final color = expected[angle]![y * 2 + unmirroredX];
              expect(rgb(original, x, y), color);
              expect(
                rgb(filled, x, y),
                y == 0 && unmirroredX == 0 ? result.meanColor : color,
              );
            }
          }
          expect(result.pixels, orderedEquals(clipImagePixels(filled)));
          final clip = img.decodePng(result.clipPreviewPng)!;
          expect([clip.width, clip.height], [224, 224]);
        },
      );
    }
  }

  test(
    'non-square input swaps dimensions and respects source sampling phase',
    () async {
      final data = stripeNv21(width: 6, height: 10, rotation: 90, mirror: true);
      // Upright source width=10, height=6. Point (0,0) maps to (9,0).
      final mask = PersonMask(
        width: 10,
        height: 6,
        confidences: List<double>.filled(60, 0)..[9] = 1,
      );
      final result = await preprocessFrame(
        cameraFrameFixture(data),
        mask: mask,
      );
      expect([result.width, result.height], [3, 2]);
      expect(result.maskedPixels, 1);
      final filled = img.decodePng(result.maskedPreviewPng)!;
      expect(rgb(filled, 0, 0), result.meanColor);
    },
  );

  test('invalid masks fall back to the exact unmasked tensor', () async {
    final data = stripeNv21();
    final unmasked = await preprocessData(data);
    for (final mask in [
      PersonMask(width: 0, height: 0, confidences: []),
      PersonMask(width: 2, height: 2, confidences: [1]),
      PersonMask(width: 1, height: 1, confidences: [double.nan]),
      PersonMask(width: 1, height: 1, confidences: [double.infinity]),
      PersonMask(width: 1, height: 1, confidences: [-0.1]),
      PersonMask(width: 1, height: 1, confidences: [1.1]),
    ]) {
      final result = await preprocessData(data, mask: mask);
      expect(result.maskApplied, isFalse);
      expect(result.maskedPixels, 0);
      expect(result.pixels, orderedEquals(unmasked.pixels));
      expect(result.maskedPreviewPng, orderedEquals(result.originalPreviewPng));
    }
  });

  test(
    'larger mask and threshold fill only person pixels with full-image mean',
    () async {
      final mask = PersonMask(
        width: 16,
        height: 16,
        confidences: List.generate(256, (i) => i % 16 < 8 ? 0.5 : 0.49),
      );
      final result = await preprocessData(stripeNv21(), mask: mask);
      expect(result.maskedPixels, 2);
      final image = img.decodePng(result.maskedPreviewPng)!;
      expect(rgb(image, 0, 0), [128, 128, 128]);
      expect(rgb(image, 0, 1), [128, 128, 128]);
      expect(rgb(image, 1, 0), [0, 255, 1]);
      expect(rgb(image, 1, 1), [255, 255, 255]);
    },
  );

  test('empty-person and all-person masks behave predictably', () async {
    final none = await preprocessData(
      stripeNv21(),
      mask: PersonMask(width: 1, height: 1, confidences: [0]),
    );
    expect(none.maskedPixels, 0);
    expect(none.originalPreviewPng, orderedEquals(none.maskedPreviewPng));
    final all = await preprocessData(
      stripeNv21(),
      mask: PersonMask(width: 1, height: 1, confidences: [1]),
    );
    expect(all.maskedPixels, 4);
    for (final pixel in img.decodePng(all.maskedPreviewPng)!) {
      expect([pixel.r, pixel.g, pixel.b], [128, 128, 128]);
    }
  });
}
