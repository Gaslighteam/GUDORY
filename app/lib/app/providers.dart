// Cross-module wiring. Owned by the team lead.
// Each provider starts with a Fake (or null) and is switched to the real
// module when it lands.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/contracts.dart';
import '../core/models.dart';
import '../features/camera/camera_service.dart';
import '../features/camera/framing.dart';
import '../features/camera/shot_orientation.dart';
import '../features/coach/coach_engine.dart';
import '../features/coach/pose_source.dart';
import '../features/coach/reference_analyzer.dart';
import '../features/scene/recommender.dart';

/// Live camera frames for pose (Eungyu) and scene (Seojun) analysis.
final frameBusProvider = Provider<FrameBus>(
  (ref) => ref.watch(cameraServiceProvider),
);

/// Eungyu's ML Kit analysis of a picked reference photo (EXIF-corrected).
final referenceAnalyzerProvider = Provider<ReferenceAnalyzer>((ref) {
  final analyzer = MlKitReferenceAnalyzer();
  ref.onDispose(analyzer.dispose);
  return analyzer;
});

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

/// Seojun's CLIP background matcher over recommend.json. It needs the visible
/// preview crop and which way the phone is held; it falls back to the level
/// median when the model or geometry is unavailable.
final recommenderProvider = Provider<Recommender>((ref) {
  final recommender = SceneRecommender(
    viewForFrame: (_, orientation) {
      final crop = ref.read(visibleCropProvider);
      final left = crop.left.clamp(0.0, 1.0);
      final top = crop.top.clamp(0.0, 1.0);
      return SceneView(
        // The pose stream and the UI apply the same rule (core/orientation.dart)
        // to separate sensor reads; right at a transition they can disagree.
        // SceneView rejects landscape with quarterTurns 0, so keep them aligned.
        quarterTurns: switch ((
          orientation,
          ref.read(heldOrientationProvider).quarterTurns,
        )) {
          (ShotOrientation.portrait, _) => 0,
          (_, 0) => 1,
          (_, final turns) => turns,
        },
        left: left,
        top: top,
        width: crop.width.clamp(0.01, 1.0 - left),
        height: crop.height.clamp(0.01, 1.0 - top),
      );
    },
  );
  // Load the model off the first recommendation's critical path.
  unawaited(recommender.warmUp());
  ref.onDispose(recommender.dispose);
  return recommender;
});
