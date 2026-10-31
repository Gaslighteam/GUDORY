import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../core/models.dart';

/// Top-left mode switch: the selected mode is a text pill, the other one is
/// a compact icon button; the change animates.
class ModeToggle extends StatelessWidget {
  const ModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
    this.quarterTurns = 0,
  });

  final ShootMode mode;
  final ValueChanged<ShootMode> onChanged;
  final int quarterTurns;

  static const _labels = {ShootMode.recommend: '추천', ShootMode.custom: '맞춤'};
  static const _icons = {
    ShootMode.recommend: Icons.auto_awesome_outlined,
    ShootMode.custom: Icons.photo_library_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final other = mode == ShootMode.recommend
        ? ShootMode.custom
        : ShootMode.recommend;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.bubble,
        borderRadius: BorderRadius.circular(22),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Keep a stable order (추천 left, 맞춤 right) so the toggle
            // doesn't jump when switching.
            for (final m in ShootMode.values)
              m == mode ? _selected(m) : _icon(other),
          ],
        ),
      ),
    );
  }

  Widget _selected(ShootMode m) => Container(
    height: 38,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
    ),
    child: Text(
      _labels[m]!,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Colors.black,
      ),
    ),
  );

  Widget _icon(ShootMode m) => Tooltip(
    message: _labels[m]!,
    child: InkResponse(
      radius: 24,
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(m);
      },
      child: SizedBox(
        width: 40,
        height: 38,
        child: AnimatedRotation(
          turns: quarterTurns / 4,
          duration: const Duration(milliseconds: 250),
          child: Icon(_icons[m], color: Colors.white, size: 20),
        ),
      ),
    ),
  );
}

/// Recommend mode: opens the 5-step composition panel. The badge shows the
/// current level so the setting is visible while the panel is closed.
class CompositionButton extends StatelessWidget {
  const CompositionButton({
    super.key,
    required this.level,
    required this.onPressed,
    this.quarterTurns = 0,
  });

  final int level;
  final VoidCallback onPressed;
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '인물 ↔ 배경 비중',
      child: Material(
        color: Colors.black.withValues(alpha: 0.4),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: AnimatedRotation(
              turns: quarterTurns / 4,
              duration: const Duration(milliseconds: 250),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.person_outline,
                    color: Colors.white,
                    size: 22,
                  ),
                  Positioned(
                    right: 2,
                    bottom: 4,
                    child: Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$level',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The expanded composition control: × on the left, then five person
/// silhouettes from large (1, 인물 중심) to small (5, 배경 중심). Tap or drag;
/// each step ticks. Closes itself 3 s after the last touch.
class CompositionPanel extends StatefulWidget {
  const CompositionPanel({
    super.key,
    required this.level,
    required this.onChanged,
    required this.onClose,
    this.quarterTurns = 0,
  });

  final int level;
  final ValueChanged<int> onChanged;
  final VoidCallback onClose;
  final int quarterTurns;

  @override
  State<CompositionPanel> createState() => _CompositionPanelState();
}

class _CompositionPanelState extends State<CompositionPanel> {
  static const _sizes = [34.0, 29.0, 24.0, 20.0, 16.0];
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    _touch();
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  void _touch() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 3), widget.onClose);
  }

  void _pick(double dx, double width) {
    _touch();
    final level = (dx / width * 5).floor().clamp(0, 4) + 1;
    if (level != widget.level) {
      HapticFeedback.selectionClick();
      widget.onChanged(level);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: '닫기',
          ),
          const Text('인물', style: _label),
          const SizedBox(width: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _pick(d.localPosition.dx, box.maxWidth),
                child: Row(
                  children: [
                    for (var i = 0; i < 5; i++)
                      Expanded(
                        child: Center(
                          child: AnimatedRotation(
                            turns: widget.quarterTurns / 4,
                            duration: const Duration(milliseconds: 250),
                            child: Icon(
                              Icons.person,
                              size: _sizes[i],
                              color: i + 1 == widget.level
                                  ? AppColors.accent
                                  : Colors.white60,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text('배경', style: _label),
        ],
      ),
    );
  }

  static const _label = TextStyle(color: Colors.white70, fontSize: 12);
}

/// Bottom-right ⠿ menu button (2×2 dots).
class MenuDotsButton extends StatelessWidget {
  const MenuDotsButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    Widget dot() => Container(
      width: 5,
      height: 5,
      margin: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
    return Tooltip(
      message: '메뉴',
      child: Material(
        color: Colors.black.withValues(alpha: 0.4),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [dot(), dot()],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [dot(), dot()],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ⠿ menu: how-to and instruction language.
Future<void> showCameraMenu(
  BuildContext context, {
  required String languageLabel,
  required VoidCallback onTutorial,
  required VoidCallback onLanguage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.help_outline, color: Colors.white),
              title: const Text(
                '사용법 보기',
                style: TextStyle(color: AppColors.text),
              ),
              onTap: () {
                Navigator.pop(sheet);
                onTutorial();
              },
            ),
            ListTile(
              leading: const Icon(Icons.translate, color: Colors.white),
              title: const Text(
                '안내 언어',
                style: TextStyle(color: AppColors.text),
              ),
              trailing: Text(
                languageLabel,
                style: const TextStyle(color: Colors.white60),
              ),
              onTap: () {
                Navigator.pop(sheet);
                onLanguage();
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Recommend mode / front camera: the last saved photo, display only.
class LastShotThumb extends StatelessWidget {
  const LastShotThumb({super.key, required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: path == null
          ? null
          : Image.file(File(path!), fit: BoxFit.cover, cacheWidth: 180),
    );
  }
}
