import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../feedback/instruction_text.dart';

/// The single instruction shown to the photographer, with a direction arrow.
class InstructionBubble extends StatelessWidget {
  const InstructionBubble({
    super.key,
    required this.text,
    this.direction = ArrowDirection.none,
    this.highlight = false,
  });

  final String text;
  final ArrowDirection direction;

  /// Aligned state: accent border.
  final bool highlight;

  static const _icons = {
    ArrowDirection.left: Icons.west,
    ArrowDirection.right: Icons.east,
    ArrowDirection.up: Icons.north,
    ArrowDirection.down: Icons.south,
    ArrowDirection.back: Icons.keyboard_double_arrow_down,
    ArrowDirection.forward: Icons.keyboard_double_arrow_up,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _icons[direction];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.bubble,
        borderRadius: BorderRadius.circular(AppRadius.bubble),
        border: highlight
            ? Border.all(color: AppColors.accent, width: 2)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: AppText.instruction,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (icon != null) ...[
            const SizedBox(height: 6),
            Icon(icon, color: AppColors.text, size: 30),
          ],
        ],
      ),
    );
  }
}
