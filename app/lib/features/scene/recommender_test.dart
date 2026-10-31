import 'dart:async';
import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';

import '../../core/models.dart';
import 'recommendation_test_fixtures.dart';
import 'recommender.dart';
import 'scene_embedding.dart';
import 'scene_test_frames.dart';

class FakeEmbedder implements SceneEmbedder {
  int calls = 0;
  bool closed = false, failWarmUp = false;
  final started = Completer<void>();
  Future<SceneEmbedding> Function()? handler;
  @override
  Future<void> warmUp() async {
    if (failWarmUp) throw StateError('model failed');
  }

  @override
  Future<SceneEmbedding> embed(CameraFrame frame, SceneView view) {
    calls++;
    if (!started.isCompleted) started.complete();
    return handler?.call() ??
        Future.value(SceneEmbedding(embeddingFixture(), 'q8'));
  }

  @override
  Future<void> dispose() async {
    closed = true;
  }
}

SceneRecommender recommender(
  FakeEmbedder fake, {
  DateTime Function()? now,
  SceneView Function(CameraFrame, ShotOrientation)? view,
  Duration? timeout,
}) => SceneRecommender(
  embedder: fake,
  now: now,
  viewForFrame: view,
  requestTimeout: timeout ?? const Duration(seconds: 3),
  loadAsset: () async => jsonEncode(
    recommendationFixture(
      clusters: [
        for (final o in ['p', 'l'])
          clusterFixture(
            o: o,
            levels: {
              for (var i = 1; i <= 5; i++)
                '$i': compositionFixture(h: .9 - i * .1, n: 3),
            },
          ),
      ],
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final frame = cameraFrameFixture(stripeNv21());

  test(
    'diagnostics distinguish mask rejection from empty orientation clusters',
    () async {
      final fake = FakeEmbedder()
        ..handler = () async => throw const SceneFailure(
          'mask/empty',
          trace: SceneEmbeddingTrace(
            width: 8,
            height: 8,
            sensorRotation: 90,
            quarterTurns: -1,
            maskWidth: 2,
            maskHeight: 2,
            foreground: 0,
            pixels: 4,
          ),
        );
      final rec = recommender(
        fake,
        view: (_, _) => const SceneView(quarterTurns: -1),
      );
      await rec.recommend(frame, 3, ShotOrientation.landscape);
      expect(rec.lastDiagnostics!.status, 'fallback/mask/empty');
      expect(rec.lastDiagnostics!.trace!.foreground, 0);
      expect(rec.lastDiagnostics!.clusterCount, 1);
      await rec.dispose();
      final empty = SceneRecommender(
        embedder: FakeEmbedder(),
        loadAsset: () async => jsonEncode(recommendationFixture(clusters: [])),
      );
      await empty.recommend(frame, 3, ShotOrientation.landscape);
      expect(empty.lastDiagnostics!.status, 'fallback/matching/no-clusters');
      expect(empty.lastDiagnostics!.inferences, 0);
      await empty.dispose();
    },
  );

  test(
    'diagnostics distinguish orientation mismatch from an invalid crop',
    () async {
      for (final entry in {
        const SceneView(): 'fallback/geometry/orientation-mismatch',
        const SceneView(quarterTurns: -1, width: 2):
            'fallback/geometry/invalid-crop',
      }.entries) {
        final fake = FakeEmbedder();
        final rec = recommender(fake, view: (_, _) => entry.key);
        await rec.recommend(frame, 3, ShotOrientation.landscape);
        expect(rec.lastDiagnostics!.status, entry.value);
        expect(fake.calls, 0);
        await rec.dispose();
      }
    },
  );

  test(
    'five level changes reuse embedding across new frames; TTL and invalidate refresh',
    () async {
      var now = DateTime(2026);
      final fake = FakeEmbedder();
      final rec = recommender(fake, now: () => now);
      for (var level = 1; level <= 5; level++) {
        final r = await rec.recommend(
          cameraFrameFixture(stripeNv21()),
          level,
          ShotOrientation.portrait,
        );
        expect(r.target.source, 'recommend:$level');
        expect(r.neighbors, 3);
      }
      expect(fake.calls, 1);
      expect(rec.lastDiagnostics!.cacheHit, isTrue);
      now = now.add(const Duration(seconds: 4));
      await rec.recommend(frame, 3, ShotOrientation.portrait);
      expect(fake.calls, 2);
      rec.invalidateEmbedding();
      await rec.recommend(frame, 3, ShotOrientation.portrait);
      expect(fake.calls, 3);
      now = DateTime(2025); // a backwards wall clock must not extend the cache
      await rec.recommend(frame, 3, ShotOrientation.portrait);
      expect(fake.calls, 4);
      await rec.dispose();
      expect(fake.closed, isTrue);
    },
  );

  test(
    'orientation, landscape side, crop and lens changes invalidate cache',
    () async {
      var view = const SceneView();
      final fake = FakeEmbedder();
      final rec = recommender(fake, view: (_, _) => view);
      await rec.recommend(frame, 3, ShotOrientation.portrait);
      view = const SceneView(quarterTurns: 1);
      final r = await rec.recommend(frame, 3, ShotOrientation.landscape);
      expect(r.target.orientation, ShotOrientation.landscape);
      view = const SceneView(quarterTurns: -1);
      await rec.recommend(frame, 3, ShotOrientation.landscape);
      view = const SceneView(quarterTurns: -1, top: .1, height: .8);
      await rec.recommend(frame, 3, ShotOrientation.landscape);
      await rec.recommend(
        cameraFrameFixture(stripeNv21(mirror: true)),
        3,
        ShotOrientation.landscape,
      );
      expect(fake.calls, 5);
      await rec.dispose();
    },
  );

  test('slow capture does not extend cache age from completion time', () async {
    var now = DateTime(2026);
    final gate = Completer<SceneEmbedding>();
    final fake = FakeEmbedder()..handler = () => gate.future;
    final rec = recommender(fake, now: () => now);
    final first = rec.recommend(frame, 3, ShotOrientation.portrait);
    await fake.started.future.timeout(const Duration(seconds: 2));
    now = now.add(const Duration(seconds: 4));
    gate.complete(SceneEmbedding(embeddingFixture(), 'q8'));
    await first;
    fake.handler = null;
    await rec.recommend(frame, 5, ShotOrientation.portrait);
    expect(fake.calls, 2);
    expect(rec.lastDiagnostics!.cacheHit, isFalse);
    await rec.dispose();
  });

  test(
    'missing asset and failed model warmUp never throw; all ten medians survive',
    () async {
      final fake = FakeEmbedder()..failWarmUp = true;
      final rec = SceneRecommender(
        embedder: fake,
        loadAsset: () => throw StateError('missing'),
      );
      await rec.warmUp();
      for (final o in ShotOrientation.values) {
        for (var level = 1; level <= 5; level++) {
          final r = await rec.recommend(frame, level, o);
          expect(r.target.orientation, o);
          expect(r.target.personHeightRatio.isFinite, isTrue);
          expect(r.neighbors, 0);
          expect(r.modelVariant, 'none');
        }
      }
      expect(fake.calls, 0);
      await rec.dispose();
    },
  );

  test('malformed/empty asset does not invoke CLIP', () async {
    for (final text in ['{', jsonEncode(recommendationFixture(clusters: []))]) {
      final fake = FakeEmbedder();
      final rec = SceneRecommender(embedder: fake, loadAsset: () async => text);
      expect(
        (await rec.recommend(frame, 3, ShotOrientation.portrait)).neighbors,
        0,
      );
      expect(fake.calls, 0);
      await rec.dispose();
    }
  });

  test('synchronous and asynchronous inference failures allow retry', () async {
    for (final fail in <Future<SceneEmbedding> Function()>[
      () => throw StateError('synchronous'),
      () async => throw StateError('asynchronous'),
      () async => SceneEmbedding(List<double>.filled(511, 0), 'q8'),
      () async => SceneEmbedding(List<double>.filled(512, double.nan), 'q8'),
    ]) {
      final fake = FakeEmbedder()..handler = fail;
      final rec = recommender(fake);
      final r = await rec.recommend(frame, 3, ShotOrientation.portrait);
      expect(r.neighbors, 0);
      expect(r.target.personHeightRatio, closeTo(.6, 1e-12));
      fake.handler = null;
      expect(
        (await rec.recommend(frame, 3, ShotOrientation.portrait)).neighbors,
        3,
      );
      expect(fake.calls, 2);
      await rec.dispose();
    }
  });

  test('concurrent same-geometry level requests share one inference', () async {
    final gate = Completer<SceneEmbedding>();
    final fake = FakeEmbedder()..handler = () => gate.future;
    final rec = recommender(fake);
    final first = rec.recommend(frame, 1, ShotOrientation.portrait);
    final second = rec.recommend(frame, 5, ShotOrientation.portrait);
    await fake.started.future.timeout(const Duration(seconds: 2));
    gate.complete(SceneEmbedding(embeddingFixture(), 'q8'));
    final results = await Future.wait([first, second]);
    expect(fake.calls, 1);
    expect(results.map((r) => r.target.source), ['recommend:1', 'recommend:5']);
    await rec.dispose();
  });

  test(
    'timeout returns fallback, prevents overlapping native jobs and discards late result',
    () async {
      final gate = Completer<SceneEmbedding>();
      final fake = FakeEmbedder()..handler = () => gate.future;
      final rec = recommender(fake, timeout: const Duration(milliseconds: 200));
      await rec.warmUp();
      expect(
        (await rec.recommend(frame, 3, ShotOrientation.portrait)).neighbors,
        0,
      );
      expect(
        (await rec.recommend(frame, 4, ShotOrientation.portrait)).neighbors,
        0,
      );
      expect(fake.calls, 1);
      gate.complete(SceneEmbedding(embeddingFixture(), 'q8'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      fake.handler = null;
      expect(
        (await rec.recommend(frame, 3, ShotOrientation.portrait)).neighbors,
        3,
      );
      expect(fake.calls, 2);
      await rec.dispose();
    },
  );

  test(
    'different geometry while busy returns correct orientation fallback',
    () async {
      final gate = Completer<SceneEmbedding>();
      final fake = FakeEmbedder()..handler = () => gate.future;
      final rec = recommender(
        fake,
        view: (_, o) =>
            SceneView(quarterTurns: o == ShotOrientation.portrait ? 0 : 1),
      );
      final first = rec.recommend(frame, 3, ShotOrientation.portrait);
      await fake.started.future.timeout(const Duration(seconds: 2));
      final other = await rec.recommend(frame, 3, ShotOrientation.landscape);
      expect(other.target.orientation, ShotOrientation.landscape);
      expect(other.neighbors, 0);
      expect(fake.calls, 1);
      gate.complete(SceneEmbedding(embeddingFixture(), 'q8'));
      await first;
      await rec.dispose();
    },
  );

  test(
    'dispose waits for native work, suppresses late matches and remains safe',
    () async {
      final gate = Completer<SceneEmbedding>();
      final fake = FakeEmbedder()..handler = () => gate.future;
      final rec = recommender(fake);
      final first = rec.recommend(frame, 3, ShotOrientation.portrait);
      await fake.started.future.timeout(const Duration(seconds: 2));
      final closing = rec.dispose();
      expect(fake.closed, isFalse);
      gate.complete(SceneEmbedding(embeddingFixture(), 'q8'));
      expect((await first).neighbors, 0);
      await closing;
      expect(fake.closed, isTrue);
      expect(
        (await rec.recommend(frame, 99, ShotOrientation.landscape)).neighbors,
        0,
      );
    },
  );

  test(
    'geometry errors and missing landscape direction fall back without guessing',
    () async {
      final fake = FakeEmbedder();
      final rec = recommender(fake);
      expect(
        (await rec.recommend(frame, 3, ShotOrientation.landscape)).neighbors,
        0,
      );
      expect(fake.calls, 0);
      await rec.dispose();
      final invalid = recommender(
        FakeEmbedder(),
        view: (_, _) => const SceneView(width: double.nan),
      );
      expect(
        (await invalid.recommend(frame, 3, ShotOrientation.portrait)).neighbors,
        0,
      );
      await invalid.dispose();
    },
  );

  test(
    'explicit asset reload recovers from missing asset and clears cached work',
    () async {
      var missing = true;
      final rec = SceneRecommender(
        embedder: FakeEmbedder(),
        loadAsset: () async {
          if (missing) throw StateError('missing');
          return jsonEncode(recommendationFixture());
        },
      );
      expect(
        (await rec.recommend(frame, 3, ShotOrientation.portrait)).neighbors,
        0,
      );
      missing = false;
      await rec.reloadAssets();
      expect(
        (await rec.recommend(frame, 3, ShotOrientation.portrait)).neighbors,
        3,
      );
      await rec.dispose();
    },
  );
}
