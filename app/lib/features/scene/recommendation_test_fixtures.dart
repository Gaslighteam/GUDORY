// Synthetic aggregate fixtures. No training-photo data.
import 'dart:convert';
import 'dart:math' as math;

Map<String, dynamic> compositionFixture({
  String f = 'fullBody',
  double h = .6,
  double cx = .5,
  double cy = .3,
  double? hy,
  int? n,
}) => {'f': f, 'h': h, 'cx': cx, 'cy': cy, 'hy': hy, 'n': ?n};

Map<String, dynamic> clusterFixture({
  String o = 'p',
  double cosine = 1,
  Map<String, dynamic>? levels,
  int? total,
}) {
  final lv = levels ?? {'3': compositionFixture(n: 3)};
  final bytes = List<int>.filled(512, 0);
  bytes[0] = (cosine * 127).round() & 255;
  bytes[1] = (math.sqrt(1 - cosine * cosine) * 127).round() & 255;
  return {
    'o': o,
    'e': base64Encode(bytes),
    'n': total ?? lv.values.fold<int>(0, (sum, c) => sum + (c['n'] as int)),
    'lv': lv,
  };
}

Map<String, dynamic> recommendationFixture({
  List<Map<String, dynamic>>? clusters,
}) => {
  'model': 'clip-vit-base-patch32',
  'dim': 512,
  'quant': 'int8',
  'levels': {
    'portrait': [.3, .2, .1, .05],
    'landscape': [.4, .3, .2, .1],
  },
  'fallback': {
    for (final o in ['portrait', 'landscape'])
      o: {
        for (var i = 1; i <= 5; i++) '$i': compositionFixture(h: .9 - i * .1),
      },
  },
  'clusters': clusters ?? [clusterFixture()],
};

List<double> embeddingFixture() => List<double>.filled(512, 0)..[0] = 1;
