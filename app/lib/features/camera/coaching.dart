// Turns pose frames into the current instruction for the camera screen.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/models.dart';
import '../coach/photo_rules.dart';
import 'framing.dart';
import 'shot_orientation.dart';
import 'shot_state.dart';

final coachingProvider = NotifierProvider<CoachingNotifier, CoachInstruction?>(
  CoachingNotifier.new,
);

class CoachingNotifier extends Notifier<CoachInstruction?> {
  StreamSubscription<PoseFrame>? _poses;
  StreamSubscription<CameraFrame>? _frames;
  Timer? _demo;

  // Recommend mode: latest recommendation and what it was computed for.
  CameraFrame? _lastFrame;
  TargetComposition? _recommended;
  int? _recLevel;
  ShotOrientation? _recOrientation;
  DateTime _recAt = DateTime(0);
  bool _recBusy = false;

  // Recommend levels 1~3: photographer rules on top of the recommendation,
  // held for the refresh period so the instruction does not flicker.
  TargetComposition? _ruledFrom;
  TargetComposition? _ruledTarget;
  DateTime _ruledAt = DateTime(0);

  static const _refreshEvery = Duration(seconds: 3);

  static const _addReference = CoachInstruction(
    key: InstructionKey.addReference,
    axis: null,
    who: Who.camera,
    amount: 0.5,
    error: 0,
    aligned: false,
    errors: {},
  );

  @override
  CoachInstruction? build() {
    ref.onDispose(() {
      _poses?.cancel();
      _frames?.cancel();
      _demo?.cancel();
    });

    // Switching modes starts the coaching over.
    ref.listen<ModeState>(modeProvider, (previous, next) {
      if (previous?.mode != next.mode) reset();
      _syncAddReference();
    });
    ref.listen<ReferenceState>(
      referenceProvider,
      (_, _) => _syncAddReference(),
    );

    // Front camera is a plain camera: no pose, no engine, no recommendation.
    if (ref.watch(frontCameraProvider)) return null;

    final poseSource = ref.watch(poseSourceProvider);
    final engine = ref.watch(coachEngineProvider);
    if (poseSource != null && engine != null) {
      final bus = ref.watch(frameBusProvider);
      _frames = bus.frames.listen((frame) => _lastFrame = frame);
      _poses = poseSource.poses(bus).listen((frame) {
        final target = _target(frame.orientation);
        if (target == null) {
          state = _addReference;
          return;
        }
        // Same space as the saved photo: the visible part of the frame,
        // rotated like the photo when the phone is held sideways.
        final crop = cropInShotSpace(
          ref.read(visibleCropProvider),
          ref.read(heldOrientationProvider).quarterTurns,
        );
        final visible = toVisible(frame, crop);
        final mode = ref.read(modeProvider);
        final useRules = mode.mode == ShootMode.recommend && mode.level <= 3;
        state = engine.update(
          visible,
          useRules ? _ruled(target, visible) : target,
        );
      });
    }
    return _needsReference() ? _addReference : null;
  }

  TargetComposition _ruled(TargetComposition t, PoseFrame live) {
    final cached = _ruledTarget;
    if (cached != null &&
        identical(t, _ruledFrom) &&
        DateTime.now().difference(_ruledAt) < _refreshEvery) {
      return cached;
    }
    _ruledFrom = t;
    _ruledAt = DateTime.now();
    return _ruledTarget = applyPhotoRules(t, live);
  }

  bool _needsReference() =>
      !ref.read(frontCameraProvider) &&
      ref.read(modeProvider).mode == ShootMode.custom &&
      ref.read(referenceProvider).isEmpty;

  /// Shows / clears the "add a reference" prompt without waiting for a pose.
  void _syncAddReference() {
    if (_needsReference()) {
      state = _addReference;
    } else if (state?.key == InstructionKey.addReference) {
      state = null;
    }
  }

  /// custom → active reference (null = ask for one);
  /// recommend → latest recommendation for the level and orientation.
  TargetComposition? _target(ShotOrientation orientation) {
    final mode = ref.read(modeProvider);
    if (mode.mode == ShootMode.custom) {
      return ref.read(referenceProvider).active?.target;
    }
    final stale =
        _recLevel != mode.level ||
        _recOrientation != orientation ||
        DateTime.now().difference(_recAt) > _refreshEvery;
    if (stale) _refreshRecommendation(mode.level, orientation);
    final current = _recommended;
    if (current != null &&
        _recLevel == mode.level &&
        _recOrientation == orientation) {
      return current;
    }
    return TargetComposition(
      framing: TargetComposition.fallback.framing,
      personHeightRatio: TargetComposition.fallback.personHeightRatio,
      personCenterX: TargetComposition.fallback.personCenterX,
      personCenterY: TargetComposition.fallback.personCenterY,
      orientation: orientation,
      source: 'fallback',
    );
  }

  Future<void> _refreshRecommendation(
    int level,
    ShotOrientation orientation,
  ) async {
    final frame = _lastFrame;
    if (_recBusy || frame == null) return;
    // Right at a portrait/landscape transition the pose stream can already
    // say landscape while the UI's held orientation has no side yet. Guessing
    // the side would feed CLIP an upside-down background, so wait for the next
    // refresh and keep the current target.
    if (orientation != ShotOrientation.portrait &&
        ref.read(heldOrientationProvider).quarterTurns == 0) {
      return;
    }
    _recBusy = true;
    try {
      final rec = await ref
          .read(recommenderProvider)
          .recommend(frame, level, orientation);
      _recommended = rec.target;
      _recLevel = level;
      _recOrientation = orientation;
      _recAt = DateTime.now();
    } catch (_) {
      // Recommender never throws by contract; keep the previous target.
    } finally {
      _recBusy = false;
    }
  }

  void reset() {
    _demo?.cancel();
    ref.read(coachEngineProvider)?.reset();
    state = _needsReference() ? _addReference : null;
  }

  bool get isDemoRunning => _demo?.isActive ?? false;

  /// Debug only: plays a scripted coaching session so voice, beeps,
  /// haptics and auto capture can be checked before the coach module lands.
  void runDemo() {
    _demo?.cancel();
    const script = [
      (InstructionKey.holdPhoneUpright, CoachAxis.level, 0.5, 3.0),
      (InstructionKey.stepBack, CoachAxis.distance, 1.5, 4.0),
      (InstructionKey.stepBack, CoachAxis.distance, 0.5, 2.0),
      (InstructionKey.stepRight, CoachAxis.horizontal, 0.5, 1.6),
      (InstructionKey.phoneDown, CoachAxis.height, 1.0, 1.3),
      (InstructionKey.aligned, null, 0.5, 0.4),
    ];
    var i = 0;
    void emit() {
      final (key, axis, amount, error) = script[i];
      state = CoachInstruction(
        key: key,
        axis: axis,
        who: Who.camera,
        amount: amount,
        error: error,
        aligned: key == InstructionKey.aligned,
        errors: const {},
      );
    }

    emit();
    _demo = Timer.periodic(const Duration(milliseconds: 2500), (timer) {
      i++;
      if (i >= script.length) {
        timer.cancel();
        return;
      }
      emit();
    });
  }
}
