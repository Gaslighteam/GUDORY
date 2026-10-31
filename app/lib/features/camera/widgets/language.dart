import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../feedback/instruction_text.dart';

/// Top-bar button showing the current instruction language (KO / EN / JA).
class LanguageButton extends StatelessWidget {
  const LanguageButton({
    super.key,
    required this.lang,
    required this.onPressed,
    this.size = 44,
    this.quarterTurns = 0,
  });

  final String lang;
  final VoidCallback onPressed;
  final double size;
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: AnimatedRotation(
            turns: quarterTurns / 4,
            duration: const Duration(milliseconds: 250),
            child: Center(
              child: Text(
                lang.toUpperCase(),
                semanticsLabel: '안내 언어',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Language sheet for the on-screen instructions. Returns null when dismissed.
Future<String?> pickLanguage(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '안내 언어',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '화면 안내를 고른 언어로 보여 줘요. 외국인에게 찍어 달라고 할 때 바꿔 주세요.',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            for (final entry in instructionLanguages.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  entry.value,
                  style: const TextStyle(color: AppColors.text, fontSize: 16),
                ),
                trailing: entry.key == current
                    ? const Icon(Icons.check, color: AppColors.accent)
                    : null,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(context, entry.key);
                },
              ),
          ],
        ),
      ),
    ),
  );
}
