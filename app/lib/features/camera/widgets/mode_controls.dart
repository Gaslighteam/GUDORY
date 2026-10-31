import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../core/models.dart';
import '../../feedback/instruction_text.dart';

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
    // The whole pill switches modes: the icon alone was too small a target.
    return Semantics(
      button: true,
      label: '${_labels[other]} 모드로 바꾸기',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(other);
        },
        child: _pill(other),
      ),
    );
  }

  Widget _pill(ShootMode other) => Container(
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

  Widget _icon(ShootMode m) => SizedBox(
    width: 40,
    height: 38,
    child: AnimatedRotation(
      turns: quarterTurns / 4,
      duration: const Duration(milliseconds: 250),
      child: Icon(_icons[m], color: Colors.white, size: 20),
    ),
  );
}

/// Top-centre popup after a mode change (fades out in the camera screen).
class ModeNotice extends StatelessWidget {
  const ModeNotice({super.key, required this.mode});

  final ShootMode mode;

  static const _details = {
    ShootMode.recommend: '배경에 어울리는 구도를 추천해요',
    ShootMode.custom: '레퍼런스 사진의 구도로 안내해요',
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 20, 10),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ModeToggle._icons[mode], color: AppColors.accent, size: 22),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${ModeToggle._labels[mode]} 모드',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              _details[mode]!,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ],
        ),
      ],
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

/// Grows a pill-shaped panel out of the round button it replaces: at 0 only
/// the [alignment] end (the button's spot) shows, at 1 the whole panel.
class ExpandFromButton extends AnimatedWidget {
  const ExpandFromButton({
    super.key,
    required Animation<double> animation,
    required this.alignment,
    required this.child,
  }) : super(listenable: animation);

  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    return Align(
      alignment: alignment,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: ConstrainedBox(
          // Start from the button's own width, not from nothing.
          constraints: const BoxConstraints(minWidth: 44),
          child: Align(
            alignment: alignment,
            widthFactor: t,
            child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
          ),
        ),
      ),
    );
  }
}

/// The ⠿ menu, expanded in place from its button: how-to, instruction
/// language and settings; × (where the button was) closes it. 언어 morphs the same pill
/// into the three languages, with the current one selected.
class CameraMenuPanel extends StatefulWidget {
  const CameraMenuPanel({
    super.key,
    required this.language,
    required this.onTutorial,
    required this.onSettings,
    required this.onLanguage,
    required this.onClose,
    this.quarterTurns = 0,
  });

  /// Current instruction language code (`ko` / `en` / `ja`).
  final String language;
  final VoidCallback onTutorial;
  final VoidCallback onSettings;
  final ValueChanged<String> onLanguage;
  final VoidCallback onClose;
  final int quarterTurns;

  @override
  State<CameraMenuPanel> createState() => _CameraMenuPanelState();
}

class _CameraMenuPanelState extends State<CameraMenuPanel> {
  bool _languages = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerRight,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerRight,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0.12, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _languages ? _languageRow() : _menuRow(),
            ),
          ),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: '닫기',
          ),
        ],
      ),
    );
  }

  Widget _menuRow() => Row(
    key: const ValueKey('menu'),
    mainAxisSize: MainAxisSize.min,
    children: [
      _item(Icons.help_outline, '사용법', widget.onTutorial),
      _item(
        Icons.translate,
        instructionLanguages[widget.language] ?? '한국어',
        () => setState(() => _languages = true),
      ),
      IconButton(
        onPressed: widget.onSettings,
        tooltip: '설정',
        icon: AnimatedRotation(
          turns: widget.quarterTurns / 4,
          duration: const Duration(milliseconds: 250),
          child: const Icon(Icons.settings_outlined, color: Colors.white),
        ),
      ),
    ],
  );

  Widget _languageRow() => Row(
    key: const ValueKey('languages'),
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final entry in instructionLanguages.entries)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(19),
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onLanguage(entry.key);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: entry.key == widget.language
                    ? Colors.white
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(19),
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  color: entry.key == widget.language
                      ? Colors.black
                      : AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _item(IconData icon, String label, VoidCallback onTap) => InkWell(
    borderRadius: BorderRadius.circular(22),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedRotation(
            turns: widget.quarterTurns / 4,
            duration: const Duration(milliseconds: 250),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
