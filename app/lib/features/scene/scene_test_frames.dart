// Deterministic test fixtures only. Production diagnostics use real FrameBus.
import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../../core/models.dart';
import 'nv21_frame.dart';

Nv21FrameData stripeNv21({
  int width = 8,
  int height = 8,
  int? rowStride,
  int rotation = 0,
  bool mirror = false,
}) {
  final stride = rowStride ?? width;
  final bytes = Uint8List(stride * height * 3 ~/ 2)
    ..fillRange(0, stride * height * 3 ~/ 2, 7);
  // Red, green, blue, white: BT.601 limited-range Y,V,U values.
  const colors = [
    [82, 240, 90],
    [145, 34, 54],
    [41, 110, 240],
    [235, 128, 128],
  ];
  int color(int x, int y) => ((y ~/ 4) % 2) * 2 + ((x ~/ 4) % 2);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      bytes[y * stride + x] = colors[color(x, y)][0];
    }
  }
  for (var y = 0; y < height; y += 2) {
    for (var x = 0; x < width; x += 2) {
      final offset = stride * height + y ~/ 2 * stride + x;
      bytes[offset] = colors[color(x, y)][1];
      bytes[offset + 1] = colors[color(x, y)][2];
    }
  }
  return Nv21FrameData(
    bytes: bytes,
    width: width,
    height: height,
    rowStride: stride,
    rotation: rotation,
    mirror: mirror,
  );
}

/// The camera package does not export CameraImageData's constructors. Use its
/// public compatibility constructor in tests, without a new direct dependency.
CameraFrame cameraFrameFixture(Nv21FrameData data, {int format = 17}) {
  // ignore: deprecated_member_use
  final image = CameraImage.fromPlatformData({
    'format': format,
    'width': data.width,
    'height': data.height,
    'planes': [
      {'bytes': data.bytes, 'bytesPerRow': data.rowStride, 'bytesPerPixel': 1},
    ],
  });
  return CameraFrame(
    image: image,
    sensorOrientation: data.rotation,
    isFrontCamera: data.mirror,
  );
}
