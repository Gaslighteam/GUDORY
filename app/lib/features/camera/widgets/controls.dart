import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
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
    this.quarterTurns = 0,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final String? tooltip;

  /// Landscape: the icon turns in place; the button does not move.
  final int quarterTurns;

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
          child: AnimatedRotation(
            turns: quarterTurns / 4,
            duration: const Duration(milliseconds: 250),
            child: Icon(
              icon,
              color: Colors.white,
              size: size * 0.52,
              semanticLabel: tooltip,
            ),
          ),
        ),
      ),
    );
  }
}

/// Zoom labels. Live value always has one decimal (0.9× / 1.0× / 1.1×);
/// the old formatter turned 0.95 into ".10".
abstract final class ZoomControlLabels {
  static String live(double z) => '${z.toStringAsFixed(1)}×';

  /// Compact preset chip label: .6 / 1 / 2 / 3.
  static String preset(double z) =>
      z < 1 ? '.${(z * 10).round()}' : '${z.round()}';
}

/// Zoom presets (`.6 / 1 / 2 / 3`); dragging the pill sideways (or pinching
/// the preview) opens a Galaxy-style ruler: ticks slide under a fixed centre
/// marker, the live value sits above it, and every 0.1× step ticks the
/// haptics (a stronger tick on .6 / 1 / 2 / 3 / 5 / 10).
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
  /// Ruler travel: pixels per unit of ln(zoom).
  static const _pxPerLog = 180.0;
  static const _majors = [0.6, 1.0, 2.0, 3.0, 5.0, 10.0];

  bool _ruler = false;
  bool _fromChip = false;

  /// Zoom being dragged to. The camera applies zoom asynchronously, so drag
  /// steps accumulate here instead of restarting from a stale widget.zoom.
  double? _dragZoom;

  double get _shown => _dragZoom ?? widget.zoom;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(ZoomControl old) {
    super.didUpdateWidget(old);
    final from = old.zoom, to = widget.zoom;
    if ((from - to).abs() < 1e-6) return;
    // Drags tick in _drag; here only chip taps and pinch zoom.
    if (_dragZoom == null) _haptics(from, to);
    // Pinch zoom (from the preview) also shows the ruler.
    if (!_fromChip) _showRuler();
    _fromChip = false;
  }

  /// Ticks for every 0.1× boundary crossed; stronger on the main presets.
  void _haptics(double from, double to) {
    final a = (from * 10).round();
    final b = (to * 10).round();
    if (a == b) return;
    final lo = math.min(a, b);
    final hi = math.max(a, b);
    final crossedMajor = _majors.any((m) {
      final t = (m * 10).round();
      return t >= lo && t <= hi && t != a;
    });
    if (crossedMajor) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  void _showRuler() {
    _hide?.cancel();
    if (!_ruler) setState(() => _ruler = true);
    _hide = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _ruler = false);
    });
  }

  void _drag(double dx) {
    _showRuler();
    // Like a dial: drag the scale left to bring higher values to the centre.
    final from = _shown;
    final next = math
        .exp(math.log(from) - dx / _pxPerLog)
        .clamp(widget.min, widget.max);
    _haptics(from, next);
    setState(() => _dragZoom = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.max - widget.min < 0.05) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) {
        _dragZoom = widget.zoom;
        _showRuler();
      },
      onHorizontalDragUpdate: (d) => _drag(d.delta.dx),
      onHorizontalDragEnd: (_) {
        _dragZoom = null;
        _showRuler();
      },
      onHorizontalDragCancel: () => _dragZoom = null,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: _ruler ? _rulerView() : _chips(),
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
              onTap: () {
                _fromChip = true;
                widget.onChanged(p);
              },
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
                  p == active
                      ? ZoomControlLabels.live(widget.zoom)
                      : ZoomControlLabels.preset(p),
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

  Widget _rulerView() {
    return Container(
      key: const ValueKey('ruler'),
      width: 260,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(32),
      ),
      clipBehavior: Clip.antiAlias,
      child: ShaderMask(
        // Fade the ends so ticks slide in and out like a dial.
        shaderCallback: (rect) => const LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0, 0.18, 0.82, 1],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: CustomPaint(
          painter: _ZoomRulerPainter(
            zoom: _shown,
            min: widget.min,
            max: widget.max,
            pxPerLog: _pxPerLog,
            majors: _majors,
          ),
        ),
      ),
    );
  }
}

/// Minor tick spacing in ln(zoom): 0.07 x 180 px = 12.6 px on screen.
const zoomRulerMinorStep = 0.07;

/// x of the zoom ruler's minor ticks: evenly spaced on screen (a fixed step in
/// ln(zoom)) so the gaps stay equal while scrolling; 0.1x steps bunch up on a
/// log scale. Ticks within half a step of a labelled major are left out.
@visibleForTesting
List<double> zoomRulerMinorTicks({
  required double zoom,
  required double min,
  required double max,
  required double width,
  required double pxPerLog,
  required List<double> majors,
}) {
  double xOf(double lnZ) => width / 2 + (lnZ - math.log(zoom)) * pxPerLog;
  final majorXs = [
    for (final m in majors)
      if (m >= min - 1e-6 && m <= max + 1e-6) xOf(math.log(m)),
  ];
  final gap = zoomRulerMinorStep * pxPerLog;
  return [
    for (
      var k = (math.log(min) / zoomRulerMinorStep).ceil();
      k <= (math.log(max) / zoomRulerMinorStep).floor();
      k++
    )
      if (xOf(k * zoomRulerMinorStep) case final x
          when x >= -10 &&
              x <= width + 10 &&
              !majorXs.any((m) => (m - x).abs() < gap / 2))
        x,
  ];
}

class _ZoomRulerPainter extends CustomPainter {
  const _ZoomRulerPainter({
    required this.zoom,
    required this.min,
    required this.max,
    required this.pxPerLog,
    required this.majors,
  });

  final double zoom;
  final double min;
  final double max;
  final double pxPerLog;
  final List<double> majors;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final baseY = size.height - 12;
    double xOf(double z) => cx + (math.log(z) - math.log(zoom)) * pxPerLog;

    final minor = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.2;
    final major = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;

    for (final x in zoomRulerMinorTicks(
      zoom: zoom,
      min: min,
      max: max,
      width: size.width,
      pxPerLog: pxPerLog,
      majors: majors,
    )) {
      canvas.drawLine(Offset(x, baseY), Offset(x, baseY - 8), minor);
    }
    for (final m in majors) {
      if (m < min - 1e-6 || m > max + 1e-6) continue;
      final x = xOf(m);
      if (x < -10 || x > size.width + 10) continue;
      canvas.drawLine(Offset(x, baseY), Offset(x, baseY - 16), major);
      _text(
        canvas,
        ZoomControlLabels.preset(m),
        Offset(x, baseY - 30),
        Colors.white70,
        11,
      );
    }
    // Fixed centre marker and the live value.
    canvas.drawLine(
      Offset(cx, baseY + 4),
      Offset(cx, baseY - 22),
      Paint()
        ..color = AppColors.accent
        ..strokeWidth = 2.5,
    );
    _text(
      canvas,
      ZoomControlLabels.live(zoom),
      Offset(cx, 10),
      AppColors.accent,
      14,
      bold: true,
    );
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
    double size, {
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_ZoomRulerPainter old) =>
      old.zoom != zoom || old.min != min || old.max != max;
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
    this.quarterTurns = 0,
  });

  final Widget reference;
  final int quarterTurns;
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
                      quarterTurns: quarterTurns,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
