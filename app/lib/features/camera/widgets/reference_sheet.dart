import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../shot_state.dart';

/// Manage references: pick the active one, add more, remove, reset all.
Future<void> showReferenceSheet(
  BuildContext context, {
  required Future<void> Function() onAdd,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(referenceProvider);
        final notifier = ref.read(referenceProvider.notifier);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '레퍼런스 ${state.items.length}장',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (!state.isEmpty)
                      TextButton(
                        onPressed: () {
                          notifier.clear();
                          Navigator.pop(context);
                        },
                        child: const Text(
                          '모두 지우기',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '노란 테두리 사진의 구도로 안내해요. 탭해서 바꿀 수 있어요.',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 96,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < state.items.length; i++)
                        _tile(
                          path: state.items[i].path,
                          active: i == state.activeIndex,
                          onTap: () => notifier.select(i),
                          onRemove: () => notifier.remove(i),
                        ),
                      GestureDetector(
                        onTap: state.analyzing ? null : onAdd,
                        child: Container(
                          width: 72,
                          height: 96,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2C2C2E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: state.analyzing
                              ? const Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add, color: Colors.white),
                                    SizedBox(height: 4),
                                    Text(
                                      '추가',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _tile({
  required String path,
  required bool active,
  required VoidCallback onTap,
  required VoidCallback onRemove,
}) {
  return Padding(
    padding: const EdgeInsets.only(right: 10),
    child: GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 72,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? AppColors.accent : Colors.transparent,
                width: 2.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.file(File(path), fit: BoxFit.cover),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
