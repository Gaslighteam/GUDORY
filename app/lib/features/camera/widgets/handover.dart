import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../feedback/instruction_text.dart';

/// Asks the owner which language the photographer speaks, right before
/// handing the phone over. Returns null when dismissed.
Future<String?> pickPhotographerLanguage(BuildContext context, String current) {
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
              '폰 건네기',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '찍어 주는 분이 쓰는 언어로 안내해요. 메뉴는 숨겨지고, 화면 위 자물쇠를 길게 누르면 돌아와요.',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            for (final entry in photographerLanguages.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  entry.value,
                  style: const TextStyle(color: AppColors.text, fontSize: 16),
                ),
                trailing: entry.key == current
                    ? const Icon(Icons.check, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Hand-over mode's only control: long-press to give the phone back to the
/// owner's normal screen.
class HandoverLockPill extends StatelessWidget {
  const HandoverLockPill({super.key, required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        onUnlock();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.bubble,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, color: Colors.white70, size: 16),
            SizedBox(width: 6),
            Text(
              '길게 눌러 해제',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
