// Cross-module wiring. Owned by the team lead.
// Each provider starts with a Fake (or null) and is switched to the real
// module when it lands.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/contracts.dart';
import '../features/camera/camera_service.dart';
import '../features/camera/fakes/fake_recommender.dart';
import '../features/camera/fakes/fake_reference_analyzer.dart';
import '../features/coach/coach_engine.dart';
import '../features/coach/pose_source.dart';

/// Live camera frames for pose (Eungyu) and scene (Seojun) analysis.
final frameBusProvider = Provider<FrameBus>(
  (ref) => ref.watch(cameraServiceProvider),
);

/// TODO(lead): switch to Eungyu's ReferenceAnalyzer when feat/coach lands.
final referenceAnalyzerProvider = Provider<ReferenceAnalyzer>(
  (ref) => FakeReferenceAnalyzer(),
);

/// Eungyu's ML Kit pose + sensors. One stream per instance, so the debug
/// pose page makes its own.
final poseSourceProvider = Provider<PoseSource?>((ref) {
  final source = MlKitPoseSource();
  ref.onDispose(source.dispose);
  return source;
});

/// Eungyu's instruction selection (four axes, hysteresis, 1.5 s hold).
final coachEngineProvider = Provider<CoachEngine?>(
  (ref) => DefaultCoachEngine(),
);

/// TODO(lead): switch to Seojun's Recommender when feat/scene lands.
final recommenderProvider = Provider<Recommender>((ref) => FakeRecommender());
