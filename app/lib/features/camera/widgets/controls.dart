import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models.dart';
import '../shot_state.dart';

/// Round translucent icon button (flash, flip).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: Colors.white,
            size: size * 0.5,
            semanticLabel: tooltip,
          ),
        ),
      ),
    );
  }
}

/// `.5 / 1x / 3` zoom presets.
class ZoomChips extends StatelessWidget {
  const ZoomChips({
    super.key,
    required this.levels,
    required this.selected,
    required this.onSelect,
  });

  final List<double> levels;
  final double selected;
  final ValueChanged<double> onSelect;

  static String _format(double level) {
    if (level < 1) return '.${(level * 10).round()}';
    return level == level.roundToDouble() ? '${level.round()}' : '$level';
  }

  @override
  Widget build(BuildContext context) {
    if (levels.length < 2) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final level in levels)
            GestureDetector(
              onTap: () => onSelect(level),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (selected - level).abs() < 0.01
                      ? Colors.black.withValues(alpha: 0.6)
                      : Colors.transparent,
                ),
                child: Text(
                  (selected - level).abs() < 0.01
                      ? '${_format(level)}x'
                      : _format(level),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: (selected - level).abs() < 0.01
                        ? AppColors.accent
                        : AppColors.text,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Scene categories: primary filled, suggestions dotted, manual pin outlined.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.suggestedIds,
    required this.manualId,
    required this.onTap,
  });

  final List<CategoryInfo> categories;
  final String? selectedId;
  final List<String> suggestedIds;
  final String? manualId;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (var i = 0; i < categories.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 18,
                color: Colors.white.withValues(alpha: 0.25),
              ),
            _chip(categories[i]),
          ],
        ],
      ),
    );
  }

  Widget _chip(CategoryInfo category) {
    final selected = category.id == selectedId;
    final pinned = category.id == manualId;
    final suggested = !selected && suggestedIds.contains(category.id);
    return GestureDetector(
      onTap: () => onTap(category.id),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.chipSelected : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: pinned
              ? Border.all(color: AppColors.accent, width: 1.5)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              category.label,
              style: TextStyle(
                fontSize: AppText.chip,
                color: AppColors.text,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            if (suggested) ...[
              const SizedBox(width: 5),
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Top-center pill: add / analyzing / in use (✕ clears).
class ReferencePill extends StatelessWidget {
  const ReferencePill({
    super.key,
    required this.state,
    required this.onAdd,
    required this.onClear,
  });

  final ReferenceState state;
  final VoidCallback onAdd;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (state.status) {
      ReferenceStatus.none => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            color: Colors.white,
            size: 18,
          ),
          SizedBox(width: 6),
          Text('레퍼런스 추가', style: TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
      ReferenceStatus.analyzing => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 8),
          Text(
            '레퍼런스 분석 중',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
      ReferenceStatus.set => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(state.path!),
              width: 26,
              height: 26,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '레퍼런스 사용 중',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onClear,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    };
    return GestureDetector(
      onTap: state.status == ReferenceStatus.analyzing ? null : onAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      ),
    );
  }
}

/// Thumbnail · shutter · flip.
class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.thumbnailPath,
    required this.onThumbnail,
    required this.onShutter,
    required this.onFlip,
    required this.armed,
    required this.busy,
  });

  final String? thumbnailPath;
  final VoidCallback? onThumbnail;
  final VoidCallback? onShutter;
  final VoidCallback? onFlip;

  /// Aligned: yellow ring.
  final bool armed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: onThumbnail,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              clipBehavior: Clip.antiAlias,
              child: thumbnailPath == null
                  ? null
                  : Image.file(File(thumbnailPath!), fit: BoxFit.cover),
            ),
          ),
          GestureDetector(
            onTap: busy ? null : onShutter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 80,
              height: 80,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: armed ? AppColors.accent : Colors.white,
                  width: 4,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: busy ? Colors.white54 : Colors.white,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: onFlip == null
                ? null
                : RoundIconButton(
                    icon: Icons.cameraswitch_outlined,
                    onPressed: onFlip,
                    size: 52,
                    tooltip: '카메라 전환',
                  ),
          ),
        ],
      ),
    );
  }
}
