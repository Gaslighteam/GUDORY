// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../core/models.dart';
import 'layout_prototypes_test.dart' show layoutMode;
import 'recommendation_test_fixtures.dart';
import 'recommender.dart';
import 'scene_embedding.dart';
import 'scene_test_frames.dart';

class _Embedder implements SceneEmbedder {
  Future<SceneEmbedding> Function()? handler;
  List<double> vector = embeddingFixture();
  @override
  Future<void> warmUp() async {}
  @override
  Future<SceneEmbedding> embed(CameraFrame f, SceneView v) =>
      handler?.call() ?? Future.value(SceneEmbedding(vector, 'q8'));
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var time = Duration.zero;
  late _Embedder fake;
  late SceneRecommender rec;
  late Map<String, dynamic> base, sidecar;
  final frame = cameraFrameFixture(stripeNv21());
  Future<Recommendation> recommend([
    int lv = 3,
    ShotOrientation o = ShotOrientation.portrait,
  ]) => rec.recommend(frame, lv, o);
  setUp(() {
    time = Duration.zero;
    fake = _Embedder();
    base = recommendationFixture(
      clusters: [
        for (final o in ['p', 'l'])
          for (final cosine in [1.0, .6])
            clusterFixture(
              o: o,
              cosine: cosine,
              levels: {
                for (var lv = 1; lv <= 5; lv++) '$lv': compositionFixture(n: 3),
              },
            ),
      ],
    );
    sidecar = {
      'version': 1,
      'clusters': [
        for (var i = 0; i < 4; i++)
          {
            'o': base['clusters'][i]['o'],
            'e': base['clusters'][i]['e'],
            'lv': {
              for (var lv = 1; lv <= 5; lv++)
                '$lv': [
                  {
                    ...layoutMode(
                      '${base['clusters'][i]['o']}-${i.toRadixString(16).padLeft(24, '0')}-$lv-0',
                      i.isEven ? .3 : .7,
                    ),
                  },
                ],
            },
          },
      ],
    };
    rec = SceneRecommender(
      embedder: fake,
      cacheDuration: Duration.zero,
      candidateClock: () => time,
      loadAsset: () async => jsonEncode(base),
      loadLayoutAsset: () async => jsonEncode(sidecar),
      viewForFrame: (_, o) =>
          SceneView(quarterTurns: o == ShotOrientation.portrait ? 0 : 1),
    );
  });
  tearDown(() => rec.dispose());
  void favorRight() {
    // Unit vector parallel to the fixture's second, quantized background.
    fake.vector = List.filled(512, 0)
      ..[0] = 76 / 127
      ..[1] = 102 / 127;
  }

  test(
    'native-path adapter holds 5.9s and switches at 6s with stronger evidence',
    () async {
      final first = await recommend();
      expect(first.target.personCenterX, .3);
      time = const Duration(milliseconds: 5900);
      favorRight();
      expect((await recommend()).target, same(first.target));
      time = const Duration(seconds: 6);
      expect((await recommend()).target.personCenterX, .7);
      expect(rec.lastDiagnostics!.candidateSelectedAt, time);
    },
  );
  test(
    'inference failure retains selected target instead of falling back to center',
    () async {
      final first = await recommend();
      fake.handler = () => throw const SceneFailure('mask/empty');
      time = const Duration(seconds: 12);
      final result = await recommend();
      expect(result.target, same(first.target));
      expect(rec.lastDiagnostics!.status, 'held/fallback/mask/empty');
      expect(rec.lastDiagnostics!.candidateSelectedAt, Duration.zero);
    },
  );
  test('explicit level and orientation changes bypass old hold', () async {
    await recommend();
    favorRight();
    expect((await recommend(4)).target.personCenterX, .7);
    fake.vector = embeddingFixture();
    expect(
      (await recommend(4, ShotOrientation.landscape)).target.personCenterX,
      .3,
    );
  });
  test(
    'explicit mode hook invalidates even with no calls during custom mode',
    () async {
      await recommend();
      rec.setMode(ShootMode.custom);
      rec.setMode(ShootMode.recommend);
      favorRight();
      expect((await recommend()).target.personCenterX, .7);
    },
  );
  test('same ID and cached re-observations do not restart hold', () async {
    await recommend();
    time = const Duration(seconds: 3);
    await recommend();
    expect(rec.lastDiagnostics!.candidateSelectedAt, Duration.zero);
    time = const Duration(seconds: 6);
    favorRight();
    expect((await recommend()).target.personCenterX, .7);
  });
  test(
    'missing or corrupt sidecar uses unchanged legacy recommendation',
    () async {
      await rec.dispose();
      for (final loader in <Future<String> Function()>[
        () async => throw StateError('not bundled'),
        () async => '{',
      ]) {
        final r = SceneRecommender(
          embedder: fake,
          loadAsset: () async => jsonEncode(base),
          loadLayoutAsset: loader,
        );
        final result = await r.recommend(frame, 3, ShotOrientation.portrait);
        expect(result.target.personCenterX, .5);
        expect(r.lastDiagnostics!.layoutStatus, 'unavailable/legacy-matching');
        await r.dispose();
      }
    },
  );
  test('mode change discards in-flight candidate selection', () async {
    final gate = Completer<SceneEmbedding>(), started = Completer<void>();
    fake.handler = () {
      started.complete();
      return gate.future;
    };
    final pending = recommend();
    await started.future;
    rec.setMode(ShootMode.custom);
    gate.complete(SceneEmbedding(embeddingFixture(), 'q8'));
    expect((await pending).neighbors, 0);
    expect(rec.lastDiagnostics!.candidateId, isNull);
  });
}
