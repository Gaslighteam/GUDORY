import 'package:flutter/material.dart';

/// 3×3 rule-of-thirds grid.
class GridOverlay extends StatelessWidget {
  const GridOverlay({super.key});

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: CustomPaint(painter: _GridPainter(), size: Size.infinite),
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 0.8;
    for (final f in [1 / 3, 2 / 3]) {
      canvas.drawLine(
        Offset(size.width * f, 0),
        Offset(size.width * f, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, size.height * f),
        Offset(size.width, size.height * f),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Dashed center lines with a ringed dot where they cross.
class CenterCrosshair extends StatelessWidget {
  const CenterCrosshair({super.key});

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: CustomPaint(painter: _CrosshairPainter(), size: Size.infinite),
  );
}

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter();

  static const _dash = 5.0;
  static const _gap = 4.0;
  static const _ring = 11.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 1;
    _dashed(
      canvas,
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      center,
      line,
    );
    _dashed(
      canvas,
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      center,
      line,
    );
    canvas.drawCircle(
      center,
      _ring,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(center, 3.5, Paint()..color = Colors.white);
  }

  /// Dashed line that leaves a gap around the center ring.
  void _dashed(
    Canvas canvas,
    Offset from,
    Offset to,
    Offset center,
    Paint paint,
  ) {
    final total = (to - from).distance;
    final dir = (to - from) / total;
    for (var d = 0.0; d < total; d += _dash + _gap) {
      final a = from + dir * d;
      final b = from + dir * (d + _dash).clamp(0, total);
      if ((a - center).distance < _ring + 3 ||
          (b - center).distance < _ring + 3) {
        continue;
      }
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
