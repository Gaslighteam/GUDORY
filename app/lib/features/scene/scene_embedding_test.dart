import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart'
    show SegmentationMask;

import '../../core/contracts.dart';
import '../../core/models.dart';
import 'clip_runner.dart';
import 'debug_test_image.dart';
import 'model_manager.dart';
import 'person_mask.dart';
import 'preprocess.dart';
import 'scene_embedding.dart';
import 'scene_test_frames.dart';
import 'recommender.dart';
import 'recommendation_test_fixtures.dart';
import 'dart:convert';

PersonMask halfMask() =>
    PersonMask(width: 2, height: 2, confidences: [1, 0, 1, 0]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'production tensor preserves Step 2 mapping for all sensor rotations and front lens',
    () async {
      for (final rotation in [0, 90, 180, 270]) {
        for (final mirror in [false, true]) {
          final frame = stripeNv21(rotation: rotation, mirror: mirror);
          final legacy = await preprocessData(frame, mask: halfMask());
          final pixels = prepareRecommendationPixels((
            frame,
            halfMask(),
            const SceneView(),
          ));
          expect(pixels, orderedEquals(legacy.pixels));
          expect(pixels.length, 150528);
          expect(pixels.every((v) => v.isFinite), isTrue);
        }
      }
    },
  );

  test(
    'both landscape sides rotate the filled shot using core quarterTurns convention',
    () async {
      final frame = stripeNv21();
      final legacy = await preprocessData(frame, mask: halfMask());
      final image = img.decodePng(legacy.maskedPreviewPng)!;
      for (final turn in [-1, 1]) {
        final pixels = prepareRecommendationPixels((
          frame,
          halfMask(),
          SceneView(quarterTurns: turn),
        ));
        expect(
          pixels,
          orderedEquals(
            clipImagePixels(img.copyRotate(image, angle: -90 * turn)),
          ),
        );
      }
    },
  );

  test('preview crop is applied once and mean is measured over that shot', () {
    final frame = stripeNv21();
    final raw = downsampleNv21(frame);
    final expected = img.copyCrop(raw, x: 0, y: 1, width: 2, height: 1);
    final a = expected.getPixel(0, 0), b = expected.getPixel(1, 0);
    final mean = [
      ((a.r + b.r) / 2).round(),
      ((a.g + b.g) / 2).round(),
      ((a.b + b.b) / 2).round(),
    ];
    a.setRgb(mean[0], mean[1], mean[2]);
    final pixels = prepareRecommendationPixels((
      frame,
      halfMask(),
      const SceneView(top: .5, height: .5),
    ));
    expect(pixels, orderedEquals(clipImagePixels(expected)));
  });

  test('invalid, empty and full person masks fail closed', () {
    for (final values in <List<double>>[
      [0.0, 0, 0, 0],
      [1.0, 1, 1, 1],
      [double.nan, 0, 1, 0],
    ]) {
      final mask = PersonMask(width: 2, height: 2, confidences: values);
      expect(
        () => prepareRecommendationPixels((
          stripeNv21(),
          mask,
          const SceneView(),
        )),
        throwsFormatException,
      );
    }
    expect(
      () => const SceneView(quarterTurns: 1).validate(ShotOrientation.portrait),
      throwsFormatException,
    );
    expect(
      () => const SceneView(
        left: .8,
        width: .5,
      ).validate(ShotOrientation.portrait),
      throwsFormatException,
    );
  });

  test(
    'native embedder rejects missing segmentation before any CLIP model use',
    () async {
      final manager = FixtureManager('unused');
      final embedder = NativeSceneEmbedder(
        modelManager: manager,
        masker: PersonMasker(process: (_) async => null),
      );
      await expectLater(
        embedder.embed(cameraFrameFixture(stripeNv21()), const SceneView()),
        throwsFormatException,
      );
      expect(manager.calls, 0);
      await embedder.dispose();
    },
  );

  test(
    'bundled manager copies once, coalesces calls and reports offline q8',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gudory-manager-',
      );
      final bundle = ModelBundle();
      final manager = BundledSceneModelManager(
        bundle: bundle,
        directory: () async => directory,
      );
      try {
        final paths = await Future.wait([
          manager.ensureBest(),
          manager.ensureBest(),
        ]);
        expect(paths[0], paths[1]);
        expect(bundle.loads, 1);
        expect(await File(paths.first).readAsBytes(), [1, 2, 3]);
        expect(manager.activeVariant, 'q8');
        expect(await manager.downloadProgress.toList(), isEmpty);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('bundled manager failure permits retry', () async {
    final directory = await Directory.systemTemp.createTemp(
      'gudory-manager-retry-',
    );
    final bundle = ModelBundle()..fail = true;
    final manager = BundledSceneModelManager(
      bundle: bundle,
      directory: () async => directory,
    );
    try {
      await expectLater(manager.ensureBest(), throwsStateError);
      bundle.fail = false;
      expect(await File(await manager.ensureBest()).exists(), isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  const path = String.fromEnvironment('CLIP_MODEL_PATH');
  test(
    'missing managed model returns loaded median through real pipeline',
    () async {
      final native = NativeSceneEmbedder(
        modelManager: FixtureManager('/gudory-deliberately-absent.onnx'),
        masker: PersonMasker(
          process: (_) async =>
              SegmentationMask(width: 2, height: 2, confidences: [1, 0, 1, 0]),
        ),
      );
      final rec = SceneRecommender(
        embedder: native,
        loadAsset: () async => jsonEncode(recommendationFixture()),
      );
      try {
        final r = await rec.recommend(
          cameraFrameFixture(stripeNv21()),
          3,
          ShotOrientation.portrait,
        );
        expect(r.neighbors, 0);
        expect(r.modelVariant, 'none');
        expect(r.target.personHeightRatio, closeTo(.6, 1e-12));
      } finally {
        await rec.dispose();
      }
    },
  );

  test(
    'real background CLIP and aggregate matching cache the result across level changes',
    () async {
      final native = NativeSceneEmbedder(
        modelManager: FixtureManager(path),
        masker: PersonMasker(
          process: (_) async =>
              SegmentationMask(width: 2, height: 2, confidences: [1, 0, 1, 0]),
        ),
      );
      final rec = SceneRecommender(
        embedder: native,
        loadAsset: () => File('assets/recommend.json').readAsString(),
      );
      try {
        await rec.warmUp();
        final frame = cameraFrameFixture(stripeNv21());
        final first = await rec.recommend(frame, 1, ShotOrientation.portrait);
        final next = await rec.recommend(frame, 5, ShotOrientation.portrait);
        expect(first.neighbors, greaterThan(0));
        expect(next.neighbors, greaterThan(0));
        expect(first.modelVariant, 'q8');
        expect(next.modelVariant, 'q8');
        expect(rec.lastDiagnostics!.cacheHit, isTrue);
        expect(rec.lastDiagnostics!.inferences, 1);
      } finally {
        await rec.dispose();
      }
    },
    skip: path.isEmpty ? 'Set CLIP_MODEL_PATH for native integration' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'managed worker session and preprocessed tensor run match verified still-image inference',
    () async {
      final manager = FixtureManager(path);
      final runner = ClipRunner(modelManager: manager);
      try {
        await runner.warmUp();
        manager.variant =
            'fp16'; // a manager update cannot relabel an open q8 session
        expect(runner.activeVariant, 'q8');
        final tensor = await runner.runPixels(clipPixels(debugTestImage()));
        final image = await runner.runBytes(debugTestImage());
        expect(manager.calls, 1);
        expect(tensor.embedding, orderedEquals(image.embedding));
        expect(tensor.l2Norm, closeTo(1, 1e-6));
        await expectLater(
          runner.runPixels(Float32List(1)),
          throwsFormatException,
        );
        await expectLater(
          runner.runPixels(Float32List(150528)..[0] = double.nan),
          throwsFormatException,
        );
      } finally {
        await runner.dispose();
      }
    },
    skip: path.isEmpty ? 'Set CLIP_MODEL_PATH for native integration' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class FixtureManager implements ModelManager {
  FixtureManager(this.path);
  final String path;
  int calls = 0;
  String variant = 'q8';
  @override
  String get activeVariant => variant;
  @override
  Stream<double> get downloadProgress => const Stream.empty();
  @override
  Future<String> ensureBest() async {
    calls++;
    return path;
  }
}

class ModelBundle extends CachingAssetBundle {
  int loads = 0;
  bool fail = false;
  @override
  Future<ByteData> load(String key) async {
    loads++;
    if (fail) throw StateError('missing bundle');
    return ByteData.sublistView(Uint8List.fromList([1, 2, 3]));
  }
}
