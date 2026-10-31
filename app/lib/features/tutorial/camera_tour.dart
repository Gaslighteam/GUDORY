// How-to tour on the real camera screen: the screen is dimmed except for a
// hole around one control at a time. Touches outside the hole are blocked;
// on "try it" steps the control itself works, and using it moves the tour on.
// Shown on the first launch and from ⠿ → 사용법 / 설정 → 사용법 다시 보기.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';

/// First-launch flag stored as an empty file in the app support directory.
abstract final class TutorialGate {
  static Future<File> _flag() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/tutorial_seen');
  }

  static Future<bool> shouldShow() async {
    try {
      return !await (await _flag()).exists();
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      await (await _flag()).create(recursive: true);
    } catch (_) {
      // Worst case the tour shows again next launch.
    }
  }
}

class TourStep {
  const TourStep({
    required this.title,
    required this.body,
    this.target,
    this.tryIt = false,
    this.advanceOnUse = false,
    this.onLeave,
  });

  final String title;
  final String body;

  /// Control to cut out; null = a centred card over the dimmed screen.
  /// Steps whose control is not on screen are skipped.
  final GlobalKey? target;

  /// The highlighted control takes touches (otherwise it is only shown).
  final bool tryIt;

  /// Lifting the finger inside the hole goes to the next step.
  final bool advanceOnUse;

  /// Runs when the tour moves past this step (e.g. close an opened panel).
  final VoidCallback? onLeave;
}

class CameraTour extends StatefulWidget {
  const CameraTour({super.key, required this.steps, required this.onDone});

  final List<TourStep> steps;
  final VoidCallback onDone;

  @override
  State<CameraTour> createState() => _CameraTourState();
}

class _CameraTourState extends State<CameraTour>
    with SingleTickerProviderStateMixin {
  // Re-measures the target every frame: panels open, the zoom ruler grows,
  // the camera restarts, so the hole follows the control as it moves.
  late final Ticker _ticker = createTicker((_) => _measure());
  int _index = 0;
  Rect? _hole;
  bool _advancing = false;

  TourStep get _step => widget.steps[_index];

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Rect? _rectOf(GlobalKey? key) {
    final target = key?.currentContext?.findRenderObject();
    final me = context.findRenderObject();
    if (target is! RenderBox ||
        !target.attached ||
        !target.hasSize ||
        me is! RenderBox ||
        !me.hasSize) {
      return null;
    }
    final topLeft = me.globalToLocal(target.localToGlobal(Offset.zero));
    return (topLeft & target.size).inflate(6);
  }

  void _measure() {
    if (_step.target == null) return;
    final rect = _rectOf(_step.target);
    if (rect != null && rect != _hole) setState(() => _hole = rect);
  }

  void _go(int index) {
    _step.onLeave?.call();
    var i = index;
    while (i < widget.steps.length &&
        widget.steps[i].target != null &&
        _rectOf(widget.steps[i].target) == null) {
      i++;
    }
    if (i >= widget.steps.length) {
      widget.onDone();
      return;
    }
    setState(() {
      _index = i;
      _advancing = false;
      _hole = _rectOf(widget.steps[i].target);
    });
  }

  void _next() => _go(_index + 1);

  /// The control was used: give its own reaction (panel opening, zoom) a
  /// moment on screen before moving on.
  void _used() {
    if (_advancing) return;
    _advancing = true;
    final from = _index;
    Timer(const Duration(milliseconds: 450), () {
      if (mounted && _index == from) _next();
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    final hole = step.target == null ? null : _hole;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: TweenAnimationBuilder<Rect?>(
                  tween: RectTween(
                    end:
                        hole ??
                        Rect.fromCenter(
                          center: size.center(Offset.zero),
                          width: 0,
                          height: 0,
                        ),
                  ),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (context, rect, _) =>
                      CustomPaint(painter: _DimPainter(rect)),
                ),
              ),
            ),
            // Touch control: only the hole of a "try it" step lets through.
            if (hole == null || !step.tryIt)
              const Positioned.fill(child: _Blocker())
            else
              for (final r in _around(hole, size))
                Positioned.fromRect(rect: r, child: const _Blocker()),
            if (hole != null && step.tryIt && step.advanceOnUse)
              Positioned.fromRect(
                rect: hole,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerUp: (_) => _used(),
                ),
              ),
            _card(size, hole, step),
          ],
        );
      },
    );
  }

  /// Four rectangles covering everything but [hole].
  static List<Rect> _around(Rect hole, Size size) {
    final h = hole.intersect(Offset.zero & size);
    return [
      Rect.fromLTRB(0, 0, size.width, h.top),
      Rect.fromLTRB(0, h.bottom, size.width, size.height),
      Rect.fromLTRB(0, h.top, h.left, h.bottom),
      Rect.fromLTRB(h.right, h.top, size.width, h.bottom),
    ].where((r) => r.width > 0 && r.height > 0).toList();
  }

  Widget _card(Size size, Rect? hole, TourStep step) {
    final last = _index == widget.steps.length - 1;
    final card = Material(
      key: ValueKey(_index),
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_index + 1} / ${widget.steps.length}',
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              step.title,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                step.body,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14.5,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (!last)
                  TextButton(
                    onPressed: widget.onDone,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white54,
                    ),
                    child: const Text('건너뛰기'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _next,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: Text(last ? '시작하기' : '다음'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final animated = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: card,
    );
    if (hole == null) {
      return Positioned.fill(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: animated,
          ),
        ),
      );
    }
    // Below the control when it sits in the upper half, above otherwise.
    final below = hole.center.dy < size.height / 2;
    return Positioned(
      left: 20,
      right: 20,
      top: below ? hole.bottom + 14 : null,
      bottom: below ? null : size.height - hole.top + 14,
      child: animated,
    );
  }
}

class _Blocker extends StatelessWidget {
  const _Blocker();

  @override
  Widget build(BuildContext context) =>
      const AbsorbPointer(child: SizedBox.expand());
}

class _DimPainter extends CustomPainter {
  const _DimPainter(this.hole);

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.72);
    final full = Offset.zero & size;
    final h = hole;
    if (h == null || h.isEmpty) {
      canvas.drawRect(full, dim);
      return;
    }
    final rrect = RRect.fromRectAndRadius(
      h,
      Radius.circular(math.min(h.shortestSide / 2, 28)),
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(full)
        ..addRRect(rrect),
      dim,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole;
}
