import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/features/scene/recommendation_test_fixtures.dart';
import 'package:gudory/features/scene/recommender.dart';
import 'package:gudory/features/scene/scene_embedding.dart';
import 'package:gudory/features/scene/scene_test_frames.dart';

class _Embedder implements SceneEmbedder {
  _Embedder(this.personX);
  final double? personX;
  @override
  Future<void> warmUp() async {}
  @override
  Future<SceneEmbedding> embed(CameraFrame frame, SceneView view) async =>
      SceneEmbedding(
        embeddingFixture(),
        'q8',
        trace: SceneEmbeddingTrace(
          width: 8,
          height: 8,
          sensorRotation: 90,
          quarterTurns: 0,
          personX: personX,
        ),
      );
  @override
  Future<void> dispose() async {}
}

SceneRecommender _recommender(
  Future<String> Function() model, {
  double? personX = .2,
}) => SceneRecommender(
  embedder: _Embedder(personX),
  loadAsset: () async => jsonEncode(
    recommendationFixture(
      clusters: [
        clusterFixture(
          o: 'p',
          levels: {
            for (var i = 1; i <= 5; i++)
              '$i': compositionFixture(h: .9 - i * .1, n: 3),
          },
        ),
      ],
    ),
  ),
  loadModelAsset: model,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final frame = cameraFrameFixture(stripeNv21());
  final bundled = File('assets/recommend_v2.json').readAsStringSync();

  test('uses v2 when its asset loads, on the side the person stands', () async {
    final rec = _recommender(() async => bundled);
    final left = await rec.recommend(frame, 3, ShotOrientation.portrait);
    expect(left.target.source, 'recommend-v2:3');
    expect(left.target.personCenterX, lessThan(.5));
    expect(left.neighbors, greaterThan(100));
    expect(rec.lastDiagnostics!.status, 'matched/v2');
    await rec.dispose();

    final right = _recommender(() async => bundled, personX: .8);
    final r = await right.recommend(frame, 3, ShotOrientation.portrait);
    expect(r.target.personCenterX, greaterThan(.5));
    await right.dispose();
  });

  test('a missing or broken v2 asset keeps the v1 recommendation', () async {
    for (final load in <Future<String> Function()>[
      () async => throw StateError('missing'),
      () async => '{"model":"gudory-recommender-v2"}',
    ]) {
      final rec = _recommender(load);
      final result = await rec.recommend(frame, 3, ShotOrientation.portrait);
      expect(result.target.source, 'recommend:3');
      expect(rec.lastDiagnostics!.status, 'matched');
      await rec.dispose();
    }
  });
}
