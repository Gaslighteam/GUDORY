import 'dart:math' as math;

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

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 10),
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
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          if (direction != ArrowDirection.none) _arrow(),
        ],
      ),
    );
  }

  Widget _arrow() {
    // One long arrow glyph, rotated; back/forward use a double chevron.
    final (IconData icon, double turns) = switch (direction) {
      ArrowDirection.right => (Icons.arrow_right_alt, 0.0),
      ArrowDirection.left => (Icons.arrow_right_alt, 0.5),
      ArrowDirection.up => (Icons.arrow_right_alt, -0.25),
      ArrowDirection.down => (Icons.arrow_right_alt, 0.25),
      ArrowDirection.back => (Icons.keyboard_double_arrow_down, 0.0),
      ArrowDirection.forward => (Icons.keyboard_double_arrow_up, 0.0),
      ArrowDirection.none => (Icons.circle, 0.0),
    };
    return Transform.rotate(
      angle: turns * 2 * math.pi,
      child: Icon(icon, color: AppColors.text, size: 40),
    );
  }
}
