// Turns pose frames into the current instruction for the camera screen.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/models.dart';
import 'framing.dart';
import 'shot_state.dart';

final coachingProvider = NotifierProvider<CoachingNotifier, CoachInstruction?>(
  CoachingNotifier.new,
);

class CoachingNotifier extends Notifier<CoachInstruction?> {
  StreamSubscription<PoseFrame>? _poses;
  Timer? _demo;

  @override
  CoachInstruction? build() {
    ref.onDispose(() {
      _poses?.cancel();
      _demo?.cancel();
    });
    final poseSource = ref.watch(poseSourceProvider);
    final engine = ref.watch(coachEngineProvider);
    if (poseSource != null && engine != null) {
      // Coordinates are re-expressed in the visible (= saved) part of the
      // frame, the same space as reference photos and category compositions.
      _poses = poseSource
          .poses(ref.watch(frameBusProvider))
          .listen(
            (frame) => state = engine.update(
              toVisible(frame, ref.read(visibleCropProvider)),
              _target(),
            ),
          );
    }
    return null;
  }

  /// Reference wins; otherwise the selected category's good composition.
  TargetComposition _target() {
    final reference = ref.read(referenceProvider);
    final active = reference.active;
    if (active != null) return active.target;
    final library = ref.read(compositionLibraryProvider);
    final categoryId = ref.read(categoryProvider).selectedId;
    if (library != null && categoryId != null) {
      return library.targetFor(categoryId);
    }
    return TargetComposition.fallback;
  }

  void reset() {
    _demo?.cancel();
    ref.read(coachEngineProvider)?.reset();
    state = null;
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
