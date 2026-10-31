import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../core/models.dart';

/// Top-left segmented toggle: 추천 | 맞춤.
class ModeToggle extends StatelessWidget {
  const ModeToggle({super.key, required this.mode, required this.onChanged});

  final ShootMode mode;
  final ValueChanged<ShootMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.bubble,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment('추천', ShootMode.recommend),
          _segment('맞춤', ShootMode.custom),
        ],
      ),
    );
  }

  Widget _segment(String label, ShootMode value) {
    final selected = mode == value;
    return GestureDetector(
      onTap: selected
          ? null
          : () {
              HapticFeedback.selectionClick();
              onChanged(value);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Recommend mode: 5 stops from 인물 중심 (1) to 배경 중심 (5).
/// Tap a stop or drag along the bar.
class LevelBar extends StatelessWidget {
  const LevelBar({super.key, required this.level, required this.onChanged});

  final int level;
  final ValueChanged<int> onChanged;

  static const _stops = 5;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      color: const Color(0xFF1C1C1E),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Text('인물 중심', style: _label),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                void pick(double dx) {
                  final i = (dx / box.maxWidth * _stops).floor().clamp(0, 4);
                  if (i + 1 != level) {
                    HapticFeedback.selectionClick();
                    onChanged(i + 1);
                  }
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => pick(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 2,
                        margin: EdgeInsets.symmetric(
                          horizontal: box.maxWidth / _stops / 2,
                        ),
                        color: Colors.white24,
                      ),
                      Row(
                        children: [
                          for (var i = 1; i <= _stops; i++)
                            Expanded(child: Center(child: _dot(i))),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Text('배경 중심', style: _label),
        ],
      ),
    );
  }

  Widget _dot(int i) {
    final selected = i == level;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: selected ? 22 : 10,
      height: selected ? 22 : 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.accent : Colors.white54,
        border: selected ? Border.all(color: Colors.black, width: 3) : null,
      ),
    );
  }

  static const _label = TextStyle(color: Colors.white70, fontSize: 13);
}
