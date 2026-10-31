// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import '../../core/models.dart';
import 'experimental_spatial_recommender.dart';
import 'recommendation_test_fixtures.dart';
import 'scene_embedding.dart';
import 'scene_test_frames.dart';
import 'spatial_features.dart';
import 'spatial_layout.dart';
import 'spatial_test_fixtures.dart';

class SpatialFakeEmbedder implements SceneEmbedder {
  int calls = 0;
  bool fail = false, closed = false;
  SpatialFeatures? feature = spatialPatternFeature('right');
  Future<SceneEmbedding> Function()? handler;
  final started = Completer<void>();
  @override
  Future<void> warmUp() async {}
  @override
  Future<SceneEmbedding> embed(CameraFrame frame, SceneView view) async {
    calls++;
    if (!started.isCompleted) started.complete();
    if (handler != null) return handler!();
    if (fail) throw StateError('synthetic failure');
    return SceneEmbedding(embeddingFixture(), 'q8', spatial: feature);
  }

  @override
  Future<void> dispose() async {
    closed = true;
  }
}

ExperimentalSpatialRecommender spatialRec(
  SpatialFakeEmbedder fake, {
  Duration Function()? clock,
  SpatialScoring scoring = const SpatialScoring(beta: 0),
  Future<String> Function()? loadA,
  Future<String> Function()? loadB,
}) {
  final selection = spatialParityFixture()['selection'] as Map<String, dynamic>;
  return ExperimentalSpatialRecommender(
    embedder: fake,
    candidateClock: clock,
    scoring: scoring,
    now: () => DateTime.utc(2026),
    requestTimeout: const Duration(seconds: 3),
    loadLegacy: () async => jsonEncode(recommendationFixture()),
    loadPhaseA: loadA ?? () async => selection['phase_a_text'] as String,
    loadPhaseB: loadB ?? () async => jsonEncode(selection['phase_b']),
    viewForFrame: (_, o) =>
        SceneView(quarterTurns: o == ShotOrientation.portrait ? 0 : 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final frame = cameraFrameFixture(stripeNv21());
  test(
    'Level changes reuse CLIP and spatial embedding cache, reset selection context',
    () async {
      final fake = SpatialFakeEmbedder(),
          rec = spatialRec(SpatialFakeEmbedder());
      await rec.dispose();
      final cached = spatialRec(fake);
      await cached.warmUp();
      for (final lv in [1, 3, 5]) {
        final answer = await cached.recommend(
          frame,
          lv,
          ShotOrientation.portrait,
        );
        expect(answer.neighbors, greaterThanOrEqualTo(3));
        expect(answer.target.source, 'recommend:$lv');
      }
      expect(fake.calls, 1);
      expect(cached.inferences, 1);
      await cached.dispose();
      expect(fake.closed, isTrue);
    },
  );
  test(
    'Opt-in spatial switching obeys six seconds, same-ID timing and failure retention',
    () async {
      var at = Duration.zero;
      final fake = SpatialFakeEmbedder(),
          rec = spatialRec(SpatialFakeEmbedder());
      await rec.dispose();
      final spatial = spatialRec(
        fake,
        clock: () => at,
        scoring: const SpatialScoring(beta: 5),
      );
      await spatial.warmUp();
      final first = await spatial.recommend(frame, 1, ShotOrientation.portrait);
      expect(first.target.personCenterX, closeTo(.2, 1e-9));
      fake.feature = spatialPatternFeature('left');
      spatial.invalidateEmbedding();
      at = const Duration(milliseconds: 5900);
      expect(
        (await spatial.recommend(
          frame,
          1,
          ShotOrientation.portrait,
        )).target.personCenterX,
        first.target.personCenterX,
      );
      at = const Duration(seconds: 6);
      final changed = await spatial.recommend(
        frame,
        1,
        ShotOrientation.portrait,
      );
      expect(changed.target.personCenterX, closeTo(.8, 1e-9));
      expect(spatial.selectedAt, const Duration(seconds: 6));
      at = const Duration(seconds: 7);
      await spatial.recommend(frame, 1, ShotOrientation.portrait);
      expect(spatial.selectedAt, const Duration(seconds: 6));
      at = const Duration(seconds: 20);
      fake.feature = const SpatialFeatures();
      spatial.invalidateEmbedding();
      expect(
        (await spatial.recommend(
          frame,
          1,
          ShotOrientation.portrait,
        )).target.personCenterX,
        changed.target.personCenterX,
      );
      fake.fail = true;
      spatial.invalidateEmbedding();
      expect(
        (await spatial.recommend(
          frame,
          1,
          ShotOrientation.portrait,
        )).target.personCenterX,
        changed.target.personCenterX,
      );
      spatial.setMode(ShootMode.custom);
      expect(spatial.selectedId, isNull);
      expect(
        (await spatial.recommend(
          frame,
          1,
          ShotOrientation.portrait,
        )).modelVariant,
        'none',
      );
      await spatial.dispose();
    },
  );
  test(
    'Old async level request cannot restore an obsolete candidate',
    () async {
      final fake = SpatialFakeEmbedder(), done = Completer<SceneEmbedding>();
      fake.handler = () => done.future;
      final rec = spatialRec(fake);
      await rec.warmUp();
      final old = rec.recommend(frame, 1, ShotOrientation.portrait);
      await fake.started.future;
      final newer = rec.recommend(frame, 5, ShotOrientation.portrait);
      done.complete(
        SceneEmbedding(
          embeddingFixture(),
          'q8',
          spatial: spatialPatternFeature('right'),
        ),
      );
      await old;
      final latest = await newer;
      expect(latest.target.source, 'recommend:5');
      expect(rec.selectedId, isNotNull);
      expect(
        (await rec.recommend(frame, 5, ShotOrientation.portrait)).target.source,
        'recommend:5',
      );
      expect(fake.calls, 1);
      await rec.dispose();
    },
  );
  test(
    'Mode epochs invalidate late inference and cannot repopulate the selector',
    () async {
      final fake = SpatialFakeEmbedder(), done = Completer<SceneEmbedding>();
      fake.handler = () => done.future;
      final rec = spatialRec(fake);
      await rec.warmUp();
      final old = rec.recommend(frame, 3, ShotOrientation.portrait);
      await fake.started.future;
      rec.setMode(ShootMode.custom);
      rec.setMode(ShootMode.recommend);
      done.complete(
        SceneEmbedding(
          embeddingFixture(),
          'q8',
          spatial: spatialPatternFeature('right'),
        ),
      );
      await old;
      expect(rec.selectedId, isNull);
      fake.handler = null;
      final answer = await rec.recommend(frame, 3, ShotOrientation.landscape);
      expect(answer.target.orientation, ShotOrientation.landscape);
      expect(answer.neighbors, greaterThanOrEqualTo(3));
      await rec.dispose();
    },
  );
  test(
    'Missing B uses Phase A; invalid A uses legacy; recommend never leaks failures',
    () async {
      final a = spatialRec(
        SpatialFakeEmbedder(),
        loadB: () async => throw StateError('missing'),
      );
      expect(
        (await a.recommend(frame, 3, ShotOrientation.portrait)).neighbors,
        greaterThanOrEqualTo(3),
      );
      await a.dispose();
      final b = spatialRec(SpatialFakeEmbedder(), loadA: () async => '{}');
      expect(
        (await b.recommend(frame, 3, ShotOrientation.portrait)).modelVariant,
        'none',
      );
      await b.dispose();
      final fake = SpatialFakeEmbedder()..fail = true,
          c = spatialRec(SpatialFakeEmbedder());
      await c.dispose();
      final failed = spatialRec(fake);
      expect(
        (await failed.recommend(
          frame,
          3,
          ShotOrientation.portrait,
        )).modelVariant,
        'none',
      );
      await failed.dispose();
    },
  );
}
