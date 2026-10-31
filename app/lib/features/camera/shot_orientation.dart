// How the phone is held, for the portrait-locked UI: rotates icons and the
// bubble in place and decides the saved photo's orientation. The rule itself
// lives in core/orientation.dart (shared with PoseSource).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/orientation.dart';

export '../../core/orientation.dart' show HeldOrientation;

final heldOrientationProvider =
    NotifierProvider<HeldOrientationNotifier, HeldOrientation>(
      HeldOrientationNotifier.new,
    );

class HeldOrientationNotifier extends Notifier<HeldOrientation> {
  @override
  HeldOrientation build() {
    final sub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(_onAccel, onError: (_) {});
    ref.onDispose(sub.cancel);
    return HeldOrientation.portrait;
  }

  void _onAccel(AccelerometerEvent e) {
    final next = nextHeldOrientation(state, e.x, e.y);
    if (next != state) state = next;
  }
}
