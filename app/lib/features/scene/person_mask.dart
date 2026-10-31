import 'dart:ui';

import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

import '../../core/models.dart';
import 'nv21_frame.dart';

/// Upright, unmirrored, row-major confidences for the SAME input frame.
/// Resolution can differ from RGB; sampling uses original source coordinates.
class PersonMask {
  PersonMask({
    required this.width,
    required this.height,
    required List<double> confidences,
  }) : confidences = List.unmodifiable(confidences);
  final int width, height;
  final List<double> confidences;

  bool get isUsable =>
      width > 0 &&
      height > 0 &&
      confidences.length == width * height &&
      confidences.every((p) => p.isFinite && p >= 0 && p <= 1);

  double atSource(Nv21FrameData frame, int x, int y) {
    final (px, py) = frame.uprightPoint(x, y);
    final mx = ((px + 0.5) * width / frame.portraitWidth).floor().clamp(
      0,
      width - 1,
    );
    final my = ((py + 0.5) * height / frame.portraitHeight).floor().clamp(
      0,
      height - 1,
    );
    return confidences[my * width + mx];
  }
}

typedef SegmentImage = Future<SegmentationMask?> Function(InputImage image);

class PersonMasker {
  PersonMasker({SegmentImage? process, Future<void> Function()? close}) {
    if (process != null) {
      _process = process;
      _close = close ?? () async {};
    } else {
      // Sparse diagnostic frames may switch lens. Single-image mode avoids a
      // temporal mask from a previous lens/frame leaking into this frame.
      final segmenter = SelfieSegmenter(
        mode: SegmenterMode.single,
        enableRawSizeMask: true,
      );
      _process = segmenter.processImage;
      _close = segmenter.close;
    }
  }

  late final SegmentImage _process;
  late final Future<void> Function() _close;
  bool _closed = false;
  Future<PersonMask?>? _pending;
  String lastStatus = 'not-run';

  Future<PersonMask?> maskFor(CameraFrame frame) async {
    try {
      return await maskData(Nv21FrameData.fromCameraFrame(frame));
    } catch (_) {
      lastStatus = 'invalid-frame';
      return null;
    }
  }

  Future<PersonMask?> maskData(Nv21FrameData frame) {
    if (_closed || _pending != null) {
      lastStatus = _closed ? 'closed' : 'busy';
      return Future.value(null);
    }
    final future = _run(frame);
    _pending = future;
    return future.whenComplete(() => _pending = null);
  }

  Future<PersonMask?> _run(Nv21FrameData frame) async {
    try {
      final result = await _process(
        InputImage.fromBytes(
          bytes: frame.packedBytes(),
          metadata: InputImageMetadata(
            size: Size(frame.width.toDouble(), frame.height.toDouble()),
            rotation: InputImageRotationValue.fromRawValue(frame.rotation)!,
            format: InputImageFormat.nv21,
            bytesPerRow: frame.width,
          ),
        ),
      );
      if (result == null) {
        lastStatus = 'no-mask';
        return null;
      }
      final mask = PersonMask(
        width: result.width,
        height: result.height,
        confidences: result.confidences,
      );
      if (!mask.isUsable) {
        lastStatus = 'invalid-mask';
        return null;
      }
      lastStatus = 'ok ${mask.width}x${mask.height}';
      return mask;
    } catch (_) {
      lastStatus = 'segmentation-failed';
      return null;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _pending;
    try {
      await _close();
    } catch (_) {
      /* Cleanup must not crash the screen. */
    }
  }
}
