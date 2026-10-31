import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../core/models.dart';
import 'clip_runner.dart';
import 'nv21_frame.dart';
import 'person_mask.dart';

class PreparedSceneFrame {
  PreparedSceneFrame({
    required this.pixels,
    required this.originalPreviewPng,
    required this.maskedPreviewPng,
    required this.clipPreviewPng,
    required this.width,
    required this.height,
    required this.maskApplied,
    required this.maskedPixels,
    required this.meanColor,
    required this.frameSummary,
  });
  final Float32List pixels;
  final Uint8List originalPreviewPng, maskedPreviewPng, clipPreviewPng;
  final int width, height, maskedPixels;
  final bool maskApplied;
  final List<int> meanColor;
  final String frameSummary;
}

Future<PreparedSceneFrame> preprocessFrame(
  CameraFrame frame, {
  PersonMask? mask,
}) => preprocessData(Nv21FrameData.fromCameraFrame(frame), mask: mask);

Future<PreparedSceneFrame> preprocessData(
  Nv21FrameData frame, {
  PersonMask? mask,
}) => compute(_prepare, (frame, mask));

/// BT.601 limited-range integer conversion; NV21 is V then U (not NV12).
(int, int, int) nv21Rgb(int y, int v, int u) {
  final c = (y - 16).clamp(0, 255), d = u - 128, e = v - 128;
  return (
    ((298 * c + 409 * e + 128) >> 8).clamp(0, 255),
    ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255),
    ((298 * c + 516 * d + 128) >> 8).clamp(0, 255),
  );
}

/// Sample raw coordinates (0,0), (4,0), ... then (0,4), ... BEFORE resizing.
/// Ceil division keeps tiny even NV21 images safe (2x2 -> one RGB pixel).
img.Image downsampleNv21(Nv21FrameData frame) {
  final output = img.Image(
    width: (frame.width + 3) ~/ 4,
    height: (frame.height + 3) ~/ 4,
    numChannels: 3,
  );
  for (final pixel in output) {
    final x = pixel.x * 4, y = pixel.y * 4;
    final vu =
        frame.rowStride * frame.height +
        (y ~/ 2) * frame.rowStride +
        (x ~/ 2) * 2;
    final (r, g, b) = nv21Rgb(
      frame.bytes[y * frame.rowStride + x],
      frame.bytes[vu],
      frame.bytes[vu + 1],
    );
    pixel.setRgb(r, g, b);
  }
  return output;
}

PreparedSceneFrame _prepare((Nv21FrameData, PersonMask?) request) {
  final (frame, candidate) = request;
  final raw = downsampleNv21(frame);
  final mask = candidate != null && candidate.isUsable ? candidate : null;
  final sums = [0.0, 0.0, 0.0];
  for (final pixel in raw) {
    sums[0] += pixel.r;
    sums[1] += pixel.g;
    sums[2] += pixel.b;
  }
  final mean = sums
      .map((sum) => (sum / (raw.width * raw.height)).round())
      .toList();
  final filled = img.Image.from(raw);
  var count = 0;
  if (mask != null) {
    for (final pixel in filled) {
      // Sample mask at the exact original source pixel, not the center of an
      // approximate resized RGB cell. This also handles the 4-pixel grid phase
      // after 90/180/270 rotations and mask resolutions different from input.
      if (mask.atSource(frame, pixel.x * 4, pixel.y * 4) >= 0.5) {
        pixel.setRgb(mean[0], mean[1], mean[2]);
        count++;
      }
    }
  }
  img.Image upright(img.Image image) {
    final rotated = img.copyRotate(image, angle: frame.rotation);
    return frame.mirror ? img.flipHorizontal(rotated) : rotated;
  }

  final original = upright(raw), processed = upright(filled);
  return PreparedSceneFrame(
    pixels: clipImagePixels(processed),
    originalPreviewPng: Uint8List.fromList(img.encodePng(original)),
    maskedPreviewPng: Uint8List.fromList(img.encodePng(processed)),
    clipPreviewPng: Uint8List.fromList(img.encodePng(clipImageCrop(processed))),
    width: processed.width,
    height: processed.height,
    maskApplied: mask != null,
    maskedPixels: count,
    meanColor: mean,
    frameSummary: frame.summary,
  );
}
