// User settings, persisted as JSON in the app support directory.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class AppSettings {
  const AppSettings({
    this.language = 'ko',
    this.beep = true,
    this.ding = true,
    this.vibration = true,
    this.grid = true,
    this.crosshair = true,
  });

  /// Instruction language: 'ko' / 'en' / 'ja'.
  final String language;

  /// Proximity beeps that speed up near the target.
  final bool beep;

  /// "Ding" when the composition is aligned.
  final bool ding;

  /// Vibration when the composition is aligned.
  final bool vibration;

  /// 3x3 grid lines on the preview.
  final bool grid;

  /// Dashed centre lines with the ringed dot.
  final bool crosshair;

  AppSettings copyWith({
    String? language,
    bool? beep,
    bool? ding,
    bool? vibration,
    bool? grid,
    bool? crosshair,
  }) => AppSettings(
    language: language ?? this.language,
    beep: beep ?? this.beep,
    ding: ding ?? this.ding,
    vibration: vibration ?? this.vibration,
    grid: grid ?? this.grid,
    crosshair: crosshair ?? this.crosshair,
  );

  Map<String, Object> toJson() => {
    'language': language,
    'beep': beep,
    'ding': ding,
    'vibration': vibration,
    'grid': grid,
    'crosshair': crosshair,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    const d = AppSettings();
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    final lang = json['language'];
    return AppSettings(
      language: lang is String && const {'ko', 'en', 'ja'}.contains(lang)
          ? lang
          : d.language,
      beep: flag('beep', d.beep),
      ding: flag('ding', d.ding),
      vibration: flag('vibration', d.vibration),
      grid: flag('grid', d.grid),
      crosshair: flag('crosshair', d.crosshair),
    );
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> {
  bool _changed = false;

  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  void update(AppSettings Function(AppSettings) change) {
    _changed = true;
    state = change(state);
    _save();
  }

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/settings.json');
  }

  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      // A change made while loading wins over the stored copy.
      if (json is Map<String, dynamic> && !_changed) {
        state = AppSettings.fromJson(json);
      }
    } catch (_) {
      // Defaults are fine (also in tests, where there is no plugin).
    }
  }

  Future<void> _save() async {
    try {
      await (await _file()).writeAsString(jsonEncode(state.toJson()));
    } catch (_) {
      // Settings simply won't survive a restart.
    }
  }
}
