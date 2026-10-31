import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../../core/models.dart';

/// Owned snapshot of one NV21 frame: Y rows, then interleaved VU rows.
/// Padded single-plane inputs use the same row stride for Y and VU. Separate
/// planes/unknown chroma strides are rejected instead of guessing their layout.
class Nv21FrameData {
  Nv21FrameData({
    required Uint8List bytes,
    required this.width,
    required this.height,
    required this.rowStride,
    required this.rotation,
    required this.mirror,
  }) : bytes = Uint8List.fromList(bytes) {
    if (width < 2 ||
        height < 2 ||
        width.isOdd ||
        height.isOdd ||
        rowStride < width ||
        rowStride.isOdd ||
        !const [0, 90, 180, 270].contains(rotation)) {
      throw const FormatException('Invalid NV21 size, stride or rotation');
    }
    // Last chroma row need not include trailing row padding.
    final minimum = rowStride * height + (height ~/ 2 - 1) * rowStride + width;
    if (bytes.length < minimum) {
      throw const FormatException('Truncated NV21 Y/VU buffer');
    }
  }

  factory Nv21FrameData.fromCameraFrame(CameraFrame frame) {
    final image = frame.image;
    if (image.format.group != ImageFormatGroup.nv21 ||
        image.format.raw != 17 ||
        image.planes.length != 1 ||
        (image.planes.single.bytesPerPixel != null &&
            image.planes.single.bytesPerPixel != 1)) {
      throw const FormatException(
        'Expected single-plane Android NV21 (raw 17)',
      );
    }
    return Nv21FrameData(
      bytes: image.planes.single.bytes,
      width: image.width,
      height: image.height,
      rowStride: image.planes.single.bytesPerRow,
      rotation: frame.sensorOrientation,
      mirror: frame.isFrontCamera,
    );
  }

  final Uint8List bytes;
  final int width, height, rowStride, rotation;
  final bool mirror;
  int get portraitWidth => rotation % 180 == 0 ? width : height;
  int get portraitHeight => rotation % 180 == 0 ? height : width;

  /// ML Kit fromByteArray ignores bytesPerRow on Android, so strip padding.
  Uint8List packedBytes() {
    final output = Uint8List(width * height * 3 ~/ 2);
    for (var y = 0; y < height; y++) {
      output.setRange(y * width, (y + 1) * width, bytes, y * rowStride);
    }
    for (var y = 0; y < height ~/ 2; y++) {
      final out = width * height + y * width;
      output.setRange(
        out,
        out + width,
        bytes,
        rowStride * height + y * rowStride,
      );
    }
    return output;
  }

  /// Source pixel -> upright, UNMIRRORED coordinates (ML Kit output space).
  (int, int) uprightPoint(int x, int y) => switch (rotation) {
    90 => (height - 1 - y, x),
    180 => (width - 1 - x, height - 1 - y),
    270 => (y, width - 1 - x),
    _ => (x, y),
  };

  String get summary =>
      'raw=17 NV21 planes=1 input=${width}x$height bytes=${bytes.length}\n'
      'Y_stride=$rowStride VU_stride=$rowStride VU_offset=${rowStride * height}\n'
      'sensor_rotation=$rotation front_mirror=$mirror sample_stride=4x4';
}
