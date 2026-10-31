import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';

import '../../core/models.dart';
import 'clip_runner.dart';
import 'recommendation_data.dart';
import 'recommendation_test_fixtures.dart';

RecommendationData data(Map<String, dynamic> value) =>
    RecommendationData.parse(jsonEncode(value));

void main() {
  test('committed asset decodes, renormalizes and has ten fallbacks', () {
    final parsed = RecommendationData.parse(
      File('assets/recommend.json').readAsStringSync(),
    );
    expect(parsed.clusters, isNotEmpty);
    for (final c in parsed.clusters) {
      expect(vectorNorm(c.center), closeTo(1, 1e-12));
    }
    for (final o in ShotOrientation.values) {
      for (var level = 1; level <= 5; level++) {
        final result = parsed.fallback(level, o);
        expect(result.target.orientation, o);
        expect(result.target.personHeightRatio, inExclusiveRange(0, 1.00001));
        expect(result.modelVariant, 'none');
        expect(result.neighbors, 0);
      }
    }
  });

  test(
    'same orientation only; exact level before a closer other-level cluster',
    () {
      final parsed = data(
        recommendationFixture(
          clusters: [
            clusterFixture(
              o: 'l',
              levels: {'3': compositionFixture(h: .9, n: 20)},
            ),
            clusterFixture(levels: {'2': compositionFixture(h: .8, n: 20)}),
            clusterFixture(
              cosine: .6,
              levels: {'3': compositionFixture(h: .4, n: 3)},
            ),
          ],
        ),
      );
      final result = parsed.match(
        embeddingFixture(),
        3,
        ShotOrientation.portrait,
        'q8',
      );
      expect(
        result.recommendation.target.personHeightRatio,
        closeTo(.4, 1e-12),
      );
      expect(result.recommendation.neighbors, 3);
      expect(result.selectedLevel, 3);
    },
  );

  test(
    'top three first; best framing and level contributor cosine weights',
    () {
      final parsed = data(
        recommendationFixture(
          clusters: [
            clusterFixture(
              cosine: 1,
              total: 1000,
              levels: {'3': compositionFixture(h: .3, n: 3)},
            ),
            clusterFixture(
              cosine: .8,
              levels: {'3': compositionFixture(f: 'chestUp', h: .9, n: 100)},
            ),
            clusterFixture(
              cosine: .6,
              levels: {'3': compositionFixture(h: .6, hy: .4, n: 6)},
            ),
            clusterFixture(
              cosine: .5,
              levels: {'3': compositionFixture(h: 1, n: 100)},
            ),
          ],
        ),
      );
      final result = parsed.match(
        embeddingFixture(),
        3,
        ShotOrientation.portrait,
        'q8',
      );
      final w = parsed.clusters[2].center[0] * 6;
      expect(
        result.recommendation.target.personHeightRatio,
        closeTo((.3 * 3 + .6 * w) / (3 + w), 1e-12),
      );
      expect(result.recommendation.target.horizonY, closeTo(.4, 1e-12));
      expect(result.recommendation.target.framing, Framing.fullBody);
      expect(result.recommendation.neighbors, 9);
    },
  );

  test('nearest level uses lower number for an equal distance', () {
    final parsed = data(
      recommendationFixture(
        clusters: [
          clusterFixture(levels: {'2': compositionFixture(h: .8, n: 3)}),
          clusterFixture(levels: {'4': compositionFixture(h: .4, n: 3)}),
        ],
      ),
    );
    final r = parsed.match(
      embeddingFixture(),
      3,
      ShotOrientation.portrait,
      'fp16',
    );
    expect(r.selectedLevel, 2);
    expect(r.recommendation.target.personHeightRatio, closeTo(.8, 1e-12));
    expect(r.recommendation.target.source, 'recommend:3');
    expect(r.recommendation.modelVariant, 'fp16');
  });

  test(
    'equal cosine keeps asset order and the top framing deterministically',
    () {
      final parsed = data(
        recommendationFixture(
          clusters: [
            clusterFixture(
              levels: {'3': compositionFixture(f: 'kneeUp', h: .7, n: 3)},
            ),
            clusterFixture(
              levels: {'3': compositionFixture(f: 'waistUp', h: .5, n: 3)},
            ),
          ],
        ),
      );
      expect(
        parsed
            .match(embeddingFixture(), 3, ShotOrientation.portrait, 'q8')
            .recommendation
            .target
            .framing,
        Framing.kneeUp,
      );
    },
  );

  test(
    'negative/zero cosine, empty clusters and unknown variants fall back',
    () {
      for (final clusters in <List<Map<String, dynamic>>>[
        [],
        [clusterFixture(cosine: -1)],
        [clusterFixture(cosine: 0)],
      ]) {
        final r = data(
          recommendationFixture(clusters: clusters),
        ).match(embeddingFixture(), 3, ShotOrientation.portrait, 'q8');
        expect(r.recommendation.neighbors, 0);
        expect(r.recommendation.modelVariant, 'none');
      }
      expect(
        data(recommendationFixture())
            .match(embeddingFixture(), 3, ShotOrientation.portrait, 'invalid')
            .recommendation
            .neighbors,
        0,
      );
    },
  );

  test('corrupt cluster records discard safely; valid fallback survives', () {
    final mutations = <void Function(Map<String, dynamic>)>[
      (c) => c['e'] = 'bad',
      (c) => c['e'] = base64Encode(List<int>.filled(512, 0)),
      (c) => c['e'] = base64Encode([128, ...List<int>.filled(511, 0)]),
      (c) => c['e'] = base64Encode(List<int>.filled(511, 1)),
      (c) => c['n'] = 2,
      (c) => c['n'] = 3.0,
      (c) => c['lv'] = {'3': {}},
      (c) => c['lv'] = {'6': compositionFixture(n: 3)},
      (c) => c['lv'] = {'3': compositionFixture(h: 0, n: 3)},
      (c) => c['lv'] = {'3': compositionFixture(cx: 2, n: 3)},
      (c) => c['lv'] = {'3': compositionFixture(n: 4)},
      (c) => c['o'] = 'unknown',
      (c) => c['photo_id'] = 'synthetic-forbidden',
    ];
    for (final mutate in mutations) {
      final c = clusterFixture();
      mutate(c);
      final parsed = data(recommendationFixture(clusters: [c]));
      expect(parsed.clusters, isEmpty);
      expect(
        parsed.fallback(3, ShotOrientation.portrait).target.personHeightRatio,
        closeTo(.6, 1e-12),
      );
    }
  });

  test('bad boundaries disable matching but preserve valid medians', () {
    final raw = recommendationFixture();
    raw['levels']['portrait'] = [.1, .2, .3, .4];
    final parsed = data(raw);
    expect(parsed.clusters, isEmpty);
    expect(
      parsed.fallback(1, ShotOrientation.portrait).target.personHeightRatio,
      .8,
    );
  });

  test(
    'missing medians use a safe baseline for every orientation and level',
    () {
      final raw = recommendationFixture();
      raw['fallback'] = {
        'portrait': {'1': compositionFixture(h: .73)},
      };
      final parsed = data(raw);
      expect(
        parsed.fallback(1, ShotOrientation.portrait).target.personHeightRatio,
        .73,
      );
      for (final o in ShotOrientation.values) {
        for (var lv = 1; lv <= 5; lv++) {
          expect(parsed.fallback(lv, o).target.orientation, o);
          expect(
            parsed.fallback(lv, o).target.personHeightRatio.isFinite,
            isTrue,
          );
        }
      }
      expect(
        parsed.fallback(-10, ShotOrientation.portrait).target.personHeightRatio,
        .73,
      );
      expect(
        parsed.fallback(99, ShotOrientation.landscape).target.personHeightRatio,
        parsed.fallback(5, ShotOrientation.landscape).target.personHeightRatio,
      );
    },
  );

  test('bad metadata/root fields, invalid JSON and oversized input reject', () {
    for (final key in ['dim', 'quant', 'model', 'photo_id']) {
      final raw = recommendationFixture();
      raw[key] = key == 'dim' ? 512.0 : 'bad';
      expect(() => data(raw), throwsFormatException);
    }
    expect(() => RecommendationData.parse('{'), throwsFormatException);
    expect(
      () => RecommendationData.parse(' ' * 1000000),
      throwsFormatException,
    );
  });
}
