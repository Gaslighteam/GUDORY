import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import 'shot_state.dart';

class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key, required this.shot});

  final ShotResult shot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(categoryProvider);
    final tags = [
      if (shot.categoryId != null) category.labelOf(shot.categoryId!),
      for (final id in shot.hashtagIds) category.hashtagLabels[id] ?? '#$id',
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        title: Text(
          shot.savedToGallery ? '갤러리에 저장했어요' : '저장하지 못했어요',
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: shot.referencePath == null
                  ? _photo(shot.path)
                  : Row(
                      children: [
                        Expanded(child: _labeled('레퍼런스', shot.referencePath!)),
                        const SizedBox(width: 4),
                        Expanded(child: _labeled('촬영', shot.path)),
                      ],
                    ),
            ),
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final tag in tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.chipSelected,
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => context.pop(),
                  child: const Text(
                    '다시 찍기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photo(String path) =>
      Image.file(File(path), fit: BoxFit.contain, width: double.infinity);

  Widget _labeled(String label, String path) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
      Expanded(child: _photo(path)),
    ],
  );
}
