// Voice + proximity beeps + haptics: the "senses" the photographer follows.
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';

import '../../core/contracts.dart';
import '../../core/models.dart';
import 'instruction_text.dart';

final feedbackProvider = Provider<SensoryFeedback>((ref) {
  final feedback = SensoryFeedback()..init();
  ref.onDispose(feedback.dispose);
  return feedback;
});

class SensoryFeedback implements FeedbackService {
  final _tts = FlutterTts();
  final _beep = AudioPlayer();
  final _ding = AudioPlayer();
  Timer? _beepTimer;
  double _error = 0;
  String? _lastSpoken;
  DateTime _lastSpokenAt = DateTime(0);
  bool _hasVibrator = false;
  String _ttsLang = 'ko';

  bool voiceOn = true;
  bool beepOn = true;

  /// Same sentence is not repeated within this window.
  static const _repeatAfter = Duration(seconds: 4);

  Future<void> init() async {
    try {
      await _tts.setLanguage('ko-KR');
      await _tts.setSpeechRate(0.5);
      await _beep.setReleaseMode(ReleaseMode.stop);
      await _beep.setSource(AssetSource('sounds/beep.wav'));
      await _ding.setReleaseMode(ReleaseMode.stop);
      await _ding.setSource(AssetSource('sounds/ding.wav'));
      _hasVibrator = await Vibration.hasVibrator();
    } catch (_) {
      // Feedback is best-effort; the on-screen bubble still works.
    }
  }

  @override
  void announce(CoachInstruction instruction, String lang) {
    say(InstructionText.of(instruction.key, instruction.amount, lang), lang);
  }

  /// Speaks [text] in [lang] ('ko' / 'en' / 'ja'); the same sentence is not
  /// repeated within 4 s.
  Future<void> say(String text, String lang) async {
    if (!voiceOn) return;
    final now = DateTime.now();
    if (text == _lastSpoken && now.difference(_lastSpokenAt) < _repeatAfter) {
      return;
    }
    _lastSpoken = text;
    _lastSpokenAt = now;
    await _tts.stop();
    if (lang != _ttsLang) {
      _ttsLang = lang;
      await _tts.setLanguage(ttsLocales[lang] ?? 'ko-KR');
    }
    await _tts.speak(text);
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
    _tts.stop();
    _lastSpoken = null;
  }

  void dispose() {
    stop();
    _beep.dispose();
    _ding.dispose();
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
