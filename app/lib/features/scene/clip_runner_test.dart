import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
// Tests stay in Seojun's authorized directory. flutter_test is an existing
// dev_dependency; production entry points never import this file.
// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'clip_runner.dart';
import 'debug_test_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PNG fixture is deterministic and decodes to 448x224 RGB', () {
    expect(debugTestImage(), orderedEquals(debugTestImage()));
    final image = img.decodePng(debugTestImage())!;
    expect([image.width, image.height, image.numChannels], [448, 224, 3]);
  });

  test('center crop produces float32 [1,3,224,224] with RGB normalization', () {
    final values = clipPixels(debugTestImage());
    expect(values, isA<Float32List>());
    expect(clipInputShape, [1, 3, 224, 224]);
    expect(values.length, 150528);
    const means = [0.48145466, 0.4578275, 0.40821073];
    const stds = [0.26862954, 0.26130258, 0.27577711];
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < 224; y++) {
        for (var x = 0; x < 224; x++) {
          // Red and white outside the center must be cropped away.
          final channel = (x < 112 && c == 1) || (x >= 112 && c == 2) ? 1 : 0;
          expect(
            values[c * 50176 + y * 224 + x],
            closeTo((channel - means[c]) / stds[c], 1e-6),
          );
        }
      }
    }
  });

  test('portrait image resizes short side before cropping', () {
    final image = img.Image(width: 100, height: 300, numChannels: 3);
    for (final pixel in image) {
      pixel.setRgb(255, 0, 0);
    }
    final values = clipPixels(Uint8List.fromList(img.encodePng(image)));
    expect(values.length, 150528);
    expect(values.first, closeTo((1 - 0.48145466) / 0.26862954, 1e-6));
    expect(values[50176], closeTo(-0.4578275 / 0.26130258, 1e-6));
  });

  test('invalid image fails clearly', () {
    expect(() => clipPixels(Uint8List(8)), throwsFormatException);
  });

  test('L2 normalization preserves direction and exposes debug metrics', () {
    final raw = List<double>.filled(512, 0)..setRange(0, 2, [3, 4]);
    final normalized = normalizeClipEmbedding(raw);
    expect(normalized.take(2), [0.6, 0.8]);
    expect(vectorNorm(normalized), closeTo(1, 1e-12));
    final result = ClipDebugResult(
      inferenceDuration: const Duration(microseconds: 1500),
      embedding: normalized,
    );
    expect(result.embeddingDimensions, 512);
    expect(result.firstFive, [0.6, 0.8, 0, 0, 0]);
    expect(result.l2Norm, closeTo(1, 1e-12));
    expect(result.summary, contains('inference_ms=1.5'));
    expect(() => result.embedding[0] = 0, throwsUnsupportedError);
  });

  test('rejects zero, non-finite and wrong-dimensional embeddings', () {
    for (final vector in [
      List<double>.filled(512, 0),
      List<double>.filled(512, double.nan),
      List<double>.filled(512, double.infinity),
      List<double>.filled(511, 1),
    ]) {
      expect(() => normalizeClipEmbedding(vector), throwsFormatException);
    }
  });

  test('missing bundled model reports an error and permits retry', () async {
    final directory = await Directory.systemTemp.createTemp('gudory-missing-');
    final runner = ClipRunner(
      bundle: _MissingModelBundle(),
      directory: () async => directory,
    );
    try {
      await expectLater(runner.warmUp(), throwsA(isA<FlutterError>()));
      await expectLater(runner.warmUp(), throwsA(isA<FlutterError>()));
    } finally {
      await runner.dispose();
      await directory.delete(recursive: true);
    }
    expect(runner.warmUp, throwsStateError);
  });

  // Opt in with --dart-define=CLIP_MODEL_PATH=<absolute q8 ONNX path>.
  // Uses the installed plugin's native Windows DLL, not an Android device.
  const modelPath = String.fromEnvironment('CLIP_MODEL_PATH');
  test(
    'real q8 ONNX accepts float32 NCHW and returns finite [1,512]',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gudory-clip-test-',
      );
      final bundle = _FileModelBundle(modelPath);
      final runner = ClipRunner(
        bundle: bundle,
        directory: () async => directory,
      );
      try {
        await runner.warmUp();
        expect(bundle.loads, 1);
        final pending = runner.runBytes(debugTestImage());
        expect(() => runner.runBytes(debugTestImage()), throwsStateError);
        final first = await pending;
        final second = await runner.runAsset('scene-test.png');
        expect(first.embeddingDimensions, 512);
        expect(first.embedding.every((value) => value.isFinite), isTrue);
        expect(first.l2Norm, closeTo(1, 1e-6));
        expect(second.firstFive, orderedEquals(first.firstFive));
        expect(bundle.loads, 1);
      } finally {
        await runner.dispose();
        await directory.delete(recursive: true);
      }
      expect(() => runner.runBytes(debugTestImage()), throwsStateError);
    },
    skip: modelPath.isEmpty
        ? 'Set CLIP_MODEL_PATH for native integration'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _FileModelBundle extends CachingAssetBundle {
  _FileModelBundle(this.path);
  final String path;
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'scene-test.png') {
      return ByteData.sublistView(debugTestImage());
    }
    expect(key, 'assets/clip/vision_q8.onnx');
    loads++;
    return ByteData.sublistView(await File(path).readAsBytes());
  }
}

class _MissingModelBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw FlutterError('Unable to load asset: $key');
}
