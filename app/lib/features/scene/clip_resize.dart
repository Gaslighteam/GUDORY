import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 8-bit RGB bicubic convolution with Pillow-compatible pixel centres,
/// downsampling antialias support and per-pass fixed-point rounding.
/// Numerical reference: python-pillow/Pillow src/libImaging/Resample.c.
/// Kept local to CLIP; camera preview and unrelated image transforms are unchanged.
img.Image resizeClipRgb(img.Image rgb, int width, int height) {
  if (width < 1 || height < 1 || rgb.width < 1 || rgb.height < 1) {
    throw const FormatException('Invalid CLIP resize dimensions');
  }
  if (width == rgb.width && height == rgb.height) return rgb;
  final bytes = rgb.getBytes(order: img.ChannelOrder.rgb);
  final horizontal = _pass(bytes, rgb.width, rgb.height, width, true);
  final output = _pass(horizontal, width, rgb.height, height, false);
  return img.Image.fromBytes(
    width: width,
    height: height,
    bytes: output.buffer,
    bytesOffset: output.offsetInBytes,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
}

const _precision = 22;
const _one = 1 << _precision;

class _Weights {
  const _Weights(this.first, this.values);
  final int first;
  final List<int> values;
}

double _cubic(double distance) {
  final x = distance.abs();
  if (x < 1) return (1.5 * x - 2.5) * x * x + 1;
  if (x < 2) return -.5 * (((x - 5) * x + 8) * x - 4);
  return 0;
}

List<_Weights> _weights(int source, int target) {
  final scale = source / target;
  final filterScale = math.max(1.0, scale);
  final support = 2 * filterScale;
  return List.generate(target, (i) {
    final center = (i + .5) * scale;
    final first = (center - support + .5).toInt().clamp(0, source);
    final last = (center + support + .5).toInt().clamp(0, source);
    final values = [
      for (var x = first; x < last; x++)
        _cubic((x - center + .5) / filterScale),
    ];
    final sum = values.fold<double>(0, (a, b) => a + b);
    return _Weights(
      first,
      values.map((v) => (v / sum * _one).round()).toList(),
    );
  }, growable: false);
}

Uint8List _pass(Uint8List input, int width, int height, int size, bool across) {
  final source = across ? width : height;
  if (source == size) return input;
  final coefficients = _weights(source, size);
  final outWidth = across ? size : width;
  final outHeight = across ? height : size;
  final output = Uint8List(outWidth * outHeight * 3);
  for (var y = 0; y < outHeight; y++) {
    for (var x = 0; x < outWidth; x++) {
      final taps = coefficients[across ? x : y];
      for (var c = 0; c < 3; c++) {
        var accumulator = _one ~/ 2;
        for (var k = 0; k < taps.values.length; k++) {
          final px = across ? taps.first + k : x;
          final py = across ? y : taps.first + k;
          accumulator += input[(py * width + px) * 3 + c] * taps.values[k];
        }
        output[(y * outWidth + x) * 3 + c] = (accumulator >> _precision).clamp(
          0,
          255,
        );
      }
    }
  }
  return output;
}
