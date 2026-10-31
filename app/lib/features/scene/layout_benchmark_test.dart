// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'layout_prototypes.dart';
import 'recommendation_data.dart';

void main() {
  test('host-only matching overhead on committed aggregate centres', () {
    final raw =
        jsonDecode(File('assets/recommend.json').readAsStringSync())
            as Map<String, dynamic>;
    final base = RecommendationData.parse(jsonEncode(raw));
    // Benchmark fixture only: ONE already-published aggregate median per entry.
    // This is not re-training or evidence of multi-mode quality on real photos.
    final sidecar = {
      'version': 1,
      'clusters': [
        for (var i = 0; i < (raw['clusters'] as List).length; i++)
          {
            'o': raw['clusters'][i]['o'],
            'e': raw['clusters'][i]['e'],
            'lv': {
              for (final entry
                  in (raw['clusters'][i]['lv'] as Map<String, dynamic>).entries)
                entry.key: [
                  {
                    ...entry.value as Map<String, dynamic>,
                    'id':
                        '${raw['clusters'][i]['o']}-${i.toRadixString(16).padLeft(24, '0')}-${entry.key}-0',
                    'spread': 0,
                    'confidence': .5,
                  },
                ],
            },
          },
      ],
    };
    final prototypes = LayoutPrototypeData.parse(jsonEncode(sidecar), base);
    final oldTimes = <int>[], newTimes = <int>[];
    for (var i = 0; i < 125; i++) {
      final cluster = base.clusters[i % base.clusters.length];
      final lv = cluster.levels.keys.first;
      final oldWatch = Stopwatch()..start();
      final old = base.match(cluster.center, lv, cluster.orientation, 'q8');
      oldWatch.stop();
      final watch = Stopwatch()..start();
      final ranked = prototypes.rank(
        cluster.center,
        lv,
        cluster.orientation,
        'q8',
      );
      watch.stop();
      expect(old.recommendation.target.orientation, cluster.orientation);
      expect(ranked.where((c) => c.canChallenge), isNotEmpty);
      if (i >= 25) {
        oldTimes.add(oldWatch.elapsedMicroseconds);
        newTimes.add(watch.elapsedMicroseconds);
      }
    }
    oldTimes.sort();
    newTimes.sort();
    // Timing is diagnostic, not a flaky wall-time assertion or Android claim.
    // ignore: avoid_print
    print(
      'LAYOUT_HOST_ONLY count=100 legacy_us_p50=${oldTimes[49]} p95=${oldTimes[94]} '
      'prototype_us_p50=${newTimes[49]} p95=${newTimes[94]}',
    );
    expect(sidecar['clusters'], hasLength(base.clusters.length));
  });
}
