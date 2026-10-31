// Settings: guidance (language, sounds, vibration), screen overlays, saving
// info, help and app info. Pops with 'tour' to replay the camera tour.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../feedback/instruction_text.dart';
import 'app_settings.dart';

/// Keep in sync with `version:` in pubspec.yaml.
const _appVersion = '0.1.0';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    void update(AppSettings Function(AppSettings) change) {
      HapticFeedback.selectionClick();
      ref.read(settingsProvider.notifier).update(change);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          '설정',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        // Clear the navigation bar (edge-to-edge) at the end of the list.
        padding: EdgeInsets.only(
          bottom: 32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset('assets/brand/logo_on_dark.png', height: 26),
                const SizedBox(height: 8),
                const Text(
                  '사진 감각, 빌려드릴게요',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
          const _Section('안내'),
          _Group(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('안내 언어', style: _title),
                    const SizedBox(height: 2),
                    const Text('외국인에게 찍어 달라고 할 때 바꿔 주세요.', style: _subtitle),
                    const SizedBox(height: 12),
                    _LanguageChoice(
                      value: s.language,
                      onChanged: (lang) =>
                          update((s) => s.copyWith(language: lang)),
                    ),
                  ],
                ),
              ),
              _Switch(
                title: '거리 알림음',
                subtitle: '목표에 가까워질수록 삐- 소리가 빨라져요.',
                value: s.beep,
                onChanged: (v) => update((s) => s.copyWith(beep: v)),
              ),
              _Switch(
                title: '완료 소리',
                subtitle: '구도가 맞으면 \'띵\' 소리가 나요.',
                value: s.ding,
                onChanged: (v) => update((s) => s.copyWith(ding: v)),
              ),
              _Switch(
                title: '진동',
                subtitle: '구도가 맞으면 짧게 진동해요.',
                value: s.vibration,
                onChanged: (v) => update((s) => s.copyWith(vibration: v)),
              ),
            ],
          ),
          const _Section('화면'),
          _Group(
            children: [
              _Switch(
                title: '격자선',
                subtitle: '화면을 3×3으로 나눠 보여 줘요.',
                value: s.grid,
                onChanged: (v) => update((s) => s.copyWith(grid: v)),
              ),
              _Switch(
                title: '가운데 표시',
                subtitle: '화면 가운데 점선과 점을 보여 줘요.',
                value: s.crosshair,
                onChanged: (v) => update((s) => s.copyWith(crosshair: v)),
              ),
            ],
          ),
          const _Section('촬영'),
          const _Group(
            children: [
              _Info(
                title: '저장 위치',
                subtitle: '찍은 사진은 원본 화질 그대로 저장돼요.',
                value: '앨범 › GUDORY',
              ),
            ],
          ),
          const _Section('도움말'),
          _Group(
            children: [
              _Link(
                icon: Icons.touch_app_outlined,
                title: '사용법 다시 보기',
                onTap: () => context.pop('tour'),
              ),
            ],
          ),
          const _Section('정보'),
          _Group(
            children: [
              const _Info(title: '버전', value: _appVersion),
              const _Info(title: '만든 팀', value: 'Gaslighteam · InThon 2026'),
              _Link(
                icon: Icons.description_outlined,
                title: '오픈소스 · 데이터 라이선스',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'GUDORY',
                  applicationVersion: _appVersion,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _title = TextStyle(
  color: AppColors.text,
  fontSize: 16,
  fontWeight: FontWeight.w600,
);
const _subtitle = TextStyle(color: Colors.white54, fontSize: 13, height: 1.35);

class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 24, 20, 8),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColors.accent,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Rounded card holding a section's rows, separated by hairlines.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(18),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            const Divider(
              height: 1,
              thickness: 0.5,
              indent: 16,
              color: Colors.white12,
            ),
          children[i],
        ],
      ],
    ),
  );
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    value: value,
    onChanged: onChanged,
    title: Text(title, style: _title),
    subtitle: Text(subtitle, style: _subtitle),
    contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
  );
}

class _Info extends StatelessWidget {
  const _Info({required this.title, required this.value, this.subtitle});

  final String title;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title, style: _title),
    subtitle: subtitle == null ? null : Text(subtitle!, style: _subtitle),
    trailing: Text(
      value,
      style: const TextStyle(color: Colors.white70, fontSize: 14),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
  );
}

class _Link extends StatelessWidget {
  const _Link({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: Colors.white),
    title: Text(title, style: _title),
    trailing: const Icon(Icons.chevron_right, color: Colors.white38),
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
  );
}

/// 한국어 · English · 日本語 as a segmented pill (same look as the ⠿ panel).
class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        for (final entry in instructionLanguages.entries)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: entry.key == value ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(19),
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    color: entry.key == value ? Colors.black : AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
