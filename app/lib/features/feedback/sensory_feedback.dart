// Proximity beeps + ding + haptics: the senses the photographer follows
// besides the on-screen instruction (voice guidance was removed by team decision).
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';

import '../../core/contracts.dart';

final feedbackProvider = Provider<SensoryFeedback>((ref) {
  final feedback = SensoryFeedback()..init();
  ref.onDispose(feedback.dispose);
  return feedback;
});

class SensoryFeedback implements FeedbackService {
  final _beep = AudioPlayer();
  final _ding = AudioPlayer();
  final _shutter = AudioPlayer();
  Timer? _beepTimer;
  double _error = 0;
  bool _hasVibrator = false;

  bool beepOn = true;

  Future<void> init() async {
    try {
      await _beep.setReleaseMode(ReleaseMode.stop);
      await _beep.setSource(AssetSource('sounds/beep.wav'));
      await _ding.setReleaseMode(ReleaseMode.stop);
      await _ding.setSource(AssetSource('sounds/ding.wav'));
      await _shutter.setReleaseMode(ReleaseMode.stop);
      await _shutter.setSource(AssetSource('sounds/shutter.wav'));
      _hasVibrator = await Vibration.hasVibrator();
    } catch (_) {
      // Feedback is best-effort; the on-screen bubble still works.
    }
  }

  /// Beeps speed up as [error] approaches 1.0 (parking-sensor style).
  @override
  void proximity(double error) {
    _error = error.abs();
    if (!beepOn || _error <= 1) {
      _beepTimer?.cancel();
      _beepTimer = null;
      return;
    }
    _beepTimer ??= Timer(_interval(_error), _tick);
  }

  @override
  void aligned() {
    _beepTimer?.cancel();
    _beepTimer = null;
    _ding.stop();
    _ding.resume();
    if (_hasVibrator) Vibration.vibrate(duration: 300);
  }

  @override
  void stop() {
    _beepTimer?.cancel();
    _beepTimer = null;
  }

  /// Camera shutter click (team-made sound) at the moment of capture.
  void shutter() {
    _shutter.stop();
    _shutter.resume();
  }

  void dispose() {
    stop();
    _beep.dispose();
    _ding.dispose();
    _shutter.dispose();
  }

  void _tick() {
    _beepTimer = null;
    if (!beepOn || _error <= 1) return;
    _beep.stop();
    _beep.resume();
    _beepTimer = Timer(_interval(_error), _tick);
  }

  /// error 1 → 150 ms, error >= 5 → 1000 ms.
  static Duration _interval(double error) {
    final t = ((error - 1) / 4).clamp(0.0, 1.0);
    return Duration(milliseconds: (150 + t * 850).round());
  }
}
