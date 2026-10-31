import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../coach/pose_geometry.dart';
import 'director_models.dart';

/// Display state only. Neither switch enters the director or its calibration.
class BackgroundOverlayOptions {
  const BackgroundOverlayOptions({this.lines = true, this.heatmap = false});
  final bool lines, heatmap;
  BackgroundOverlayOptions withLines(bool value) =>
      BackgroundOverlayOptions(lines: value, heatmap: heatmap);
  BackgroundOverlayOptions withHeatmap(bool value) =>
      BackgroundOverlayOptions(lines: lines, heatmap: value);
}

Offset shotPointToPreview(Offset p, Size size, int quarterTurns) {
  final portrait = shotToPortrait(p, quarterTurns: quarterTurns);
  return Offset(portrait.dx * size.width, portrait.dy * size.height);
}

Rect shotRectToPreview(Rect rect, Size size, int quarterTurns) =>
    Rect.fromPoints(
      shotPointToPreview(rect.topLeft, size, quarterTurns),
      shotPointToPreview(rect.bottomRight, size, quarterTurns),
    );

class HeatCellDisplay {
  const HeatCellDisplay(this.region, this.cell, this.supported);
  final Rect region;
  final RegionCell cell;
  final bool supported;
  double? get value => supported ? cell.texture : null;
  String get label => supported
      ? '${(cell.texture * 100).round()} · bg ${(cell.coverage * 100).round()}%'
      : '— · bg ${(cell.coverage * 100).round()}%';
  Color get color => supported
      ? Color.lerp(
          const Color(0xFF448AFF),
          const Color(0xFFFF7043),
          cell.texture.clamp(0.0, 1.0),
        )!.withValues(alpha: .14 + .14 * cell.texture.clamp(0.0, 1.0))
      : Colors.white.withValues(alpha: .055);
}

/// One immutable display snapshot. Geometry uses the capture's orientation,
/// not newer accelerometer readings while a frame is still being analyzed.
/// RGB/mask are already mirrored, rotated and visible-frame normalized. This
/// projection applies no second mirror/crop; the painter fills CameraPreview's
/// exact aspect-ratio rectangle inside its letterboxing.
class BackgroundOverlaySnapshot {
  BackgroundOverlaySnapshot(this.frame, this.features, this.quarterTurns) {
    final w = frame.width, h = frame.height;
    if (!frame.valid) return;
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        if (features.cells.length != 9) continue;
        final c = features.cells[row * 3 + col];
        cells.add(
          HeatCellDisplay(
            Rect.fromLTRB(
              (col * w ~/ 3) / w,
              (row * h ~/ 3) / h,
              ((col + 1) * w ~/ 3) / w,
              ((row + 1) * h ~/ 3) / h,
            ),
            c,
            features.valid && c.coverage >= .5,
          ),
        );
      }
    }
    // The SAME one-pixel-dilated unknown mask as the gradient extractor. Run
    // rectangles keep clip construction small without fabricating background.
    bool known(int x, int y) {
      if (x <= 0 || x >= w - 1 || y <= 0 || y >= h - 1) return false;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (frame.mask[(y + dy) * w + x + dx] >= .35) return false;
        }
      }
      return true;
    }

    for (var y = 1; y < h - 1; y++) {
      var x = 1;
      while (x < w - 1) {
        if (!known(x, y)) {
          x++;
          continue;
        }
        final start = x;
        do {
          x++;
        } while (x < w - 1 && known(x, y));
        final rect = Rect.fromLTRB(start / w, y / h, x / w, (y + 1) / h);
        backgroundPath.addRect(
          shotRectToPreview(rect, const Size(1, 1), quarterTurns),
        );
      }
    }
  }
  final DirectorFrame frame;
  final SceneFeatures features;
  final int quarterTurns;
  final cells = <HeatCellDisplay>[];
  final backgroundPath = Path();
  int get detectedLineCount => features.lines.length;
  int lineCount(BackgroundOverlayOptions options) =>
      options.lines ? detectedLineCount : 0;
  int get supportedCellCount => cells.where((c) => c.supported).length;
  String get summary => supportedCellCount == 0
      ? '배경 근거 부족 · —는 측정 불가'
      : '복잡도 0–100 · bg는 관측 비율 · 낮음 ≠ 좋은 구도';
  String get heatValuesLabel => cells.length != 9
      ? '값 대기'
      : List.generate(
          3,
          (row) => cells
              .skip(row * 3)
              .take(3)
              .map((c) => c.value == null ? '—' : '${(c.value! * 100).round()}')
              .join('  '),
        ).join(' / ');
  double lineOpacity(BackgroundLine line) =>
      (.55 + .30 * line.strength.clamp(0.0, 1.0)) *
      (.70 + .30 * features.confidence.clamp(0.0, 1.0));
}

class BackgroundOverlayControls extends StatelessWidget {
  const BackgroundOverlayControls({
    super.key,
    required this.options,
    required this.onChanged,
    required this.detectedLines,
  });
  final BackgroundOverlayOptions options;
  final ValueChanged<BackgroundOverlayOptions> onChanged;
  final int detectedLines;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      FilterChip(
        key: const ValueKey('background-lines-toggle'),
        label: const Text('배경 선'),
        avatar: const Icon(Icons.timeline, size: 16),
        selected: options.lines,
        showCheckmark: false,
        onSelected: (v) => onChanged(options.withLines(v)),
      ),
      FilterChip(
        key: const ValueKey('background-heatmap-toggle'),
        label: const Text('복잡도'),
        avatar: const Icon(Icons.grid_view, size: 16),
        selected: options.heatmap,
        showCheckmark: false,
        onSelected: (v) => onChanged(options.withHeatmap(v)),
      ),
      Text(
        '선 검출 $detectedLines/6 · 표시 ${options.lines ? detectedLines : 0}',
        style: const TextStyle(fontSize: 11),
      ),
    ],
  );
}

class BackgroundOverlayPainter extends CustomPainter {
  BackgroundOverlayPainter(this.snapshot, this.options, {this.onPaint});
  final BackgroundOverlaySnapshot snapshot;
  final BackgroundOverlayOptions options;
  final ValueChanged<double>? onPaint;
  void _clipBackground(Canvas canvas, Size size) {
    canvas.scale(size.width, size.height);
    canvas.clipPath(snapshot.backgroundPath);
    canvas.scale(1 / size.width, 1 / size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final timer = Stopwatch()..start();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (options.heatmap) {
      canvas.save();
      _clipBackground(canvas, size);
      for (final c in snapshot.cells) {
        final rect = shotRectToPreview(c.region, size, snapshot.quarterTurns);
        canvas.drawRect(rect, Paint()..color = c.color);
        if (!c.supported) {
          canvas.save();
          canvas.clipRect(rect);
          for (var x = rect.left - rect.height; x < rect.right; x += 14) {
            canvas.drawLine(
              Offset(x, rect.bottom),
              Offset(x + rect.height, rect.top),
              Paint()
                ..color = Colors.white12
                ..strokeWidth = 1,
            );
          }
          canvas.restore();
        }
      }
      canvas.restore();
      for (final c in snapshot.cells) {
        final rect = shotRectToPreview(c.region, size, snapshot.quarterTurns);
        canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.white38
            ..strokeWidth = .7
            ..style = PaintingStyle.stroke,
        );
        final text = TextPainter(
          text: TextSpan(
            text: c.label,
            style: TextStyle(
              color: c.supported ? Colors.white : Colors.white70,
              fontSize: 9,
              backgroundColor: Colors.black54,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: math.max(1, rect.width - 6));
        canvas.save();
        _clipBackground(canvas, size);
        text.paint(canvas, rect.topLeft + const Offset(3, 3));
        canvas.restore();
      }
    }
    if (options.lines) {
      canvas.save();
      _clipBackground(canvas, size);
      // No top-2 slice or new geometry. Draw the exact retained scoring list.
      for (final l in snapshot.features.lines) {
        canvas.drawLine(
          shotPointToPreview(Offset(l.x1, l.y1), size, snapshot.quarterTurns),
          shotPointToPreview(Offset(l.x2, l.y2), size, snapshot.quarterTurns),
          Paint()
            ..color = Colors.orange.withValues(alpha: snapshot.lineOpacity(l))
            ..strokeWidth = 1 + 2 * l.strength.clamp(0.0, 1.0),
        );
      }
      canvas.restore();
    }
    canvas.restore();
    onPaint?.call(timer.elapsedMicroseconds / 1000);
  }

  @override
  bool shouldRepaint(covariant BackgroundOverlayPainter old) =>
      snapshot != old.snapshot ||
      options.lines != old.options.lines ||
      options.heatmap != old.options.heatmap;
}
