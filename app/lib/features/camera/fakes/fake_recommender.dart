import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/contracts.dart';
import '../../../core/models.dart';

/// Stand-in until Seojun's Recommender lands: returns the level median from
/// `recommend.json`'s `fallback` (no CLIP).
class FakeRecommender implements Recommender {
  Map<String, dynamic>? _fallback;

  @override
  Future<void> warmUp() async {
    final raw =
        jsonDecode(await rootBundle.loadString('assets/recommend.json'))
            as Map<String, dynamic>;
    _fallback = raw['fallback'] as Map<String, dynamic>;
  }

  @override
  Future<Recommendation> recommend(
    CameraFrame frame,
    int level,
    ShotOrientation orientation,
  ) async {
    if (_fallback == null) await warmUp();
    return Recommendation(
      target: fallbackTarget(_fallback!, level, orientation),
      neighbors: 0,
      modelVariant: 'none',
    );
  }

  static TargetComposition fallbackTarget(
    Map<String, dynamic> fallback,
    int level,
    ShotOrientation orientation,
  ) {
    final byLevel = fallback[orientation.name] as Map<String, dynamic>?;
    final m = byLevel?['$level'] as Map<String, dynamic>?;
    if (m == null) return TargetComposition.fallback;
    return TargetComposition(
      framing: Framing.values.firstWhere(
        (f) => f.name == m['f'],
        orElse: () => Framing.fullBody,
      ),
      personHeightRatio: (m['h'] as num).toDouble(),
      personCenterX: (m['cx'] as num).toDouble(),
      personCenterY: (m['cy'] as num).toDouble(),
      horizonY: (m['hy'] as num?)?.toDouble(),
      orientation: orientation,
      source: 'recommend:$level',
    );
  }
}
