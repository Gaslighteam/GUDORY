// How the phone is held, for the portrait-locked UI: rotates icons and the
// bubble in place and decides the saved photo's orientation.
// Same thresholds as PoseSource (AGENTS.md §4): |roll| > 60° → landscape,
// < 45° → portrait.
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/models.dart';

class HeldOrientation {
  const HeldOrientation(this.orientation, this.quarterTurns);

  static const portrait = HeldOrientation(ShotOrientation.portrait, 0);

  final ShotOrientation orientation;

  /// Clockwise quarter turns that keep UI content upright:
  /// 1 = phone turned counter-clockwise (top to the left), -1 = clockwise.
  final int quarterTurns;

  bool get isLandscape => orientation == ShotOrientation.landscape;
}

final heldOrientationProvider =
    NotifierProvider<HeldOrientationNotifier, HeldOrientation>(
      HeldOrientationNotifier.new,
    );

class HeldOrientationNotifier extends Notifier<HeldOrientation> {
  static const _toLandscape = 60.0;
  static const _toPortrait = 45.0;

  @override
  HeldOrientation build() {
    final sub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(_onAccel, onError: (_) {});
    ref.onDispose(sub.cancel);
    return HeldOrientation.portrait;
  }

  void _onAccel(AccelerometerEvent e) {
    // Ignore the phone lying flat: no reliable roll.
    if (math.sqrt(e.x * e.x + e.y * e.y) < 4) return;
    final roll = math.atan2(e.x, e.y) * 180 / math.pi; // + = top to the left
    final magnitude = roll.abs();
    final next = switch (state.orientation) {
      ShotOrientation.portrait when magnitude > _toLandscape => HeldOrientation(
        ShotOrientation.landscape,
        roll > 0 ? 1 : -1,
      ),
      ShotOrientation.landscape when magnitude < _toPortrait =>
        HeldOrientation.portrait,
      _ => state,
    };
    if (next.orientation != state.orientation ||
        next.quarterTurns != state.quarterTurns) {
      state = next;
    }
  }
}
