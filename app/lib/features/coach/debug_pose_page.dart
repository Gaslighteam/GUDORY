import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/contracts.dart';
import '../../core/models.dart';

/// The caller owns camera startup, portrait lock, and PoseSource disposal.
class DebugPosePage extends StatefulWidget {
  const DebugPosePage({
    super.key,
    required this.controller,
    required this.frameBus,
    required this.poseSource,
  });

  final CameraController controller;
  final FrameBus frameBus;
  final PoseSource poseSource;

  @override
  State<DebugPosePage> createState() => _DebugPosePageState();
}

class _DebugPosePageState extends State<DebugPosePage> {
  late Stream<PoseFrame> _poses;

  @override
  void initState() {
    super.initState();
    _poses = widget.poseSource.poses(widget.frameBus);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(title: const Text('자세 좌표 확인')),
    body: StreamBuilder<PoseFrame>(
      stream: _poses,
      builder: (context, snapshot) {
        final frame = snapshot.data;
        final preview = widget.controller.value.previewSize;
        if (!widget.controller.value.isInitialized || preview == null) {
          return const Center(child: Text('카메라를 준비하고 있어요'));
        }
        final width = frame?.imageWidth.toDouble() ?? preview.height;
        final height = frame?.imageHeight.toDouble() ?? preview.width;
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(widget.controller),
                      CustomPaint(painter: PoseDotsPainter(frame)),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    snapshot.hasError
                        ? '자세 분석 오류: ${snapshot.error}'
                        : frame == null
                        ? '분석을 기다리고 있어요'
                        : '좌우 기울기 ${frame.rollDeg.toStringAsFixed(1)}°  '
                              '눕힘 ${frame.pitchDeg.toStringAsFixed(1)}°\n'
                              '${frame.landmarks == null ? "사람 없음" : "관절 33점"}  '
                              '${frame.imageWidth} × ${frame.imageHeight}',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
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

class PoseDotsPainter extends CustomPainter {
  const PoseDotsPainter(this.frame);

  final PoseFrame? frame;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFFD60A);
    for (final point in frame?.landmarks ?? const <Landmark>[]) {
      if (point.visibility < 0.5) continue;
      canvas.drawCircle(
        Offset(point.x * size.width, point.y * size.height),
        size.width / 120,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PoseDotsPainter oldDelegate) =>
      oldDelegate.frame != frame;
}
