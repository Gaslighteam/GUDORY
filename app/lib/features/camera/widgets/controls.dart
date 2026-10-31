import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../core/models.dart';
import '../shot_state.dart';

/// Round translucent icon button (close, flash).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.color,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? Colors.black.withValues(alpha: 0.4),
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
            size: size * 0.52,
            semanticLabel: tooltip,
          ),
        ),
      ),
    );
  }
}

/// Zoom presets (`.5 / 1x / 3`) plus continuous zoom: drag the pill
/// sideways to open a slider covering every level the camera supports.
class ZoomControl extends StatefulWidget {
  const ZoomControl({
    super.key,
    required this.min,
    required this.max,
    required this.zoom,
    required this.presets,
    required this.onChanged,
  });

  final double min;
  final double max;
  final double zoom;
  final List<double> presets;
  final ValueChanged<double> onChanged;

  @override
  State<ZoomControl> createState() => _ZoomControlState();
}

class _ZoomControlState extends State<ZoomControl> {
  bool _sliding = false;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  static String format(double z) {
    if (z < 1) return '.${(z * 10).round()}';
    final rounded = (z * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? '${rounded.round()}'
        : rounded.toStringAsFixed(1);
  }

  // Log scale so 0.5→1 and 1→10 get comparable travel.
  double _toT(double z) =>
      (math.log(z) - math.log(widget.min)) /
      (math.log(widget.max) - math.log(widget.min));
  double _fromT(double t) => math.exp(
    math.log(widget.min) + t * (math.log(widget.max) - math.log(widget.min)),
  );

  void _startSlide() {
    _hide?.cancel();
    setState(() => _sliding = true);
  }

  void _endSlide() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _sliding = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.max - widget.min < 0.05) return const SizedBox.shrink();
    return GestureDetector(
      onHorizontalDragStart: (_) => _startSlide(),
      onHorizontalDragUpdate: (d) {
        final t = (_toT(widget.zoom) + d.delta.dx / 260).clamp(0.0, 1.0);
        widget.onChanged(_fromT(t));
      },
      onHorizontalDragEnd: (_) => _endSlide(),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: _sliding ? _slider() : _chips(),
      ),
    );
  }

  Widget _chips() {
    // The preset at or below the current zoom shows the live value.
    final active = widget.presets.lastWhere(
      (p) => p <= widget.zoom + 0.01,
      orElse: () => widget.presets.first,
    );
    return Container(
      key: const ValueKey('chips'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in widget.presets)
            GestureDetector(
              onTap: () => widget.onChanged(p),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p == active
                      ? Colors.black.withValues(alpha: 0.6)
                      : Colors.transparent,
                ),
                child: Text(
                  p == active ? '${format(widget.zoom)}x' : format(p),
                  style: TextStyle(
                    fontSize: p == active ? 14 : 13,
                    fontWeight: FontWeight.w600,
                    color: p == active ? AppColors.accent : AppColors.text,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _slider() {
    return Container(
      key: const ValueKey('slider'),
      width: 300,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${format(widget.zoom)}x',
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: Colors.white38,
              thumbColor: AppColors.accent,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: _toT(widget.zoom).clamp(0.0, 1.0),
              onChangeStart: (_) => _startSlide(),
              onChanged: (t) => widget.onChanged(_fromT(t)),
              onChangeEnd: (_) => _endSlide(),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${format(widget.min)}x', style: _small),
              Text('${format(widget.max)}x', style: _small),
            ],
          ),
        ],
      ),
    );
  }

  static const _small = TextStyle(color: Colors.white70, fontSize: 11);
}

/// Scene categories as a swipeable wheel: the centered item is the
/// selection and snaps into place with a haptic tick. Auto guesses scroll
/// the wheel; a swipe or tap pins that category (yellow outline).
/// Suggestions carry a yellow dot.
class CategoryWheel extends StatefulWidget {
  const CategoryWheel({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.suggestedIds,
    required this.manualId,
    required this.onPin,
  });

  final List<CategoryInfo> categories;
  final String? selectedId;
  final List<String> suggestedIds;
  final String? manualId;
  final ValueChanged<String> onPin;

  @override
  State<CategoryWheel> createState() => _CategoryWheelState();
}

class _CategoryWheelState extends State<CategoryWheel> {
  static const _itemWidth = 92.0;

  PageController? _pages;
  double _viewport = 0;

  /// True while the wheel moves because of a guess, not the user.
  bool _programmatic = false;

  int get _selectedIndex {
    final i = widget.categories.indexWhere((c) => c.id == widget.selectedId);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(CategoryWheel old) {
    super.didUpdateWidget(old);
    final pages = _pages;
    if (pages == null || !pages.hasClients) return;
    final current = pages.page?.round() ?? pages.initialPage;
    if (current != _selectedIndex) _animateTo(_selectedIndex);
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  Future<void> _animateTo(int index) async {
    _programmatic = true;
    await _pages!.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    _programmatic = false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.categories.isEmpty) return const SizedBox(height: 64);
    return SizedBox(
      height: 64,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (_pages == null || constraints.maxWidth != _viewport) {
            _viewport = constraints.maxWidth;
            final old = _pages;
            _pages = PageController(
              initialPage: _selectedIndex,
              viewportFraction: (_itemWidth / _viewport).clamp(0.15, 0.5),
            );
            old?.dispose();
          }
          return Stack(
            alignment: Alignment.center,
            children: [
              PageView.builder(
                controller: _pages,
                itemCount: widget.categories.length,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (i) {
                  HapticFeedback.selectionClick();
                  if (!_programmatic) widget.onPin(widget.categories[i].id);
                },
                itemBuilder: (context, i) => _item(i),
              ),
              // Soft fade at both ends so items slide in and out.
              IgnorePointer(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF1C1C1E),
                        Color(0x001C1C1E),
                        Color(0x001C1C1E),
                        Color(0xFF1C1C1E),
                      ],
                      stops: [0, 0.18, 0.82, 1],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _item(int i) {
    final category = widget.categories[i];
    final selected = i == _selectedIndex;
    final pinned = category.id == widget.manualId;
    final suggested = !selected && widget.suggestedIds.contains(category.id);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.onPin(category.id);
        _animateTo(i);
      },
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.chipSelected : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: pinned
                ? Border.all(color: AppColors.accent, width: 1.5)
                : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Text(
                category.label,
                style: TextStyle(
                  fontSize: AppText.chip,
                  color: selected ? AppColors.text : Colors.white70,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (suggested)
                Positioned(
                  right: -8,
                  top: -2,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-left slot: the active reference photo (tap to manage/add).
class ReferenceThumb extends StatelessWidget {
  const ReferenceThumb({super.key, required this.state, required this.onTap});

  final ReferenceState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = state.active;
    return GestureDetector(
      onTap: state.analyzing ? null : onTap,
      child: SizedBox(
        width: 60,
        height: 60,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(12),
                border: active == null
                    ? null
                    : Border.all(color: AppColors.accent, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: active == null
                  ? const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: Colors.white70,
                      size: 26,
                    )
                  : Image.file(File(active.path), fit: BoxFit.cover),
            ),
            if (state.analyzing)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            if (state.items.length > 1)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${state.items.length}',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reference slot · shutter · flip.
class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.reference,
    required this.onShutter,
    required this.onFlip,
    required this.armed,
    required this.busy,
  });

  final Widget reference;
  final VoidCallback? onShutter;
  final VoidCallback? onFlip;

  /// Aligned: yellow ring.
  final bool armed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 18, 36, 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          reference,
          GestureDetector(
            onTap: busy ? null : onShutter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 82,
              height: 82,
              padding: const EdgeInsets.all(5),
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
            width: 60,
            child: onFlip == null
                ? null
                : Center(
                    child: RoundIconButton(
                      icon: Icons.sync,
                      onPressed: onFlip,
                      size: 56,
                      color: const Color(0xFF2C2C2E),
                      tooltip: '카메라 전환',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
