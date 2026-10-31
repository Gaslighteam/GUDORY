import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../core/contracts.dart';
import '../../core/models.dart';
import 'clip_runner.dart';
import 'composition_model.dart';
import 'model_manager.dart';
import 'nv21_frame.dart';
import 'person_mask.dart';
import 'preprocess.dart';

/// Scalar runtime evidence only. Never carries camera bytes or mask arrays.
class SceneEmbeddingTrace {
  const SceneEmbeddingTrace({
    required this.width,
    required this.height,
    required this.sensorRotation,
    required this.quarterTurns,
    this.maskWidth = 0,
    this.maskHeight = 0,
    this.foreground = 0,
    this.pixels = 0,
    this.sourceForeground = 0,
    this.personX,
  });
  final int width, height, sensorRotation, quarterTurns;
  final int maskWidth, maskHeight, foreground, pixels;
  final int sourceForeground;

  /// Mean x of the masked person in the shot, 0~1 (recommender v2 side).
  final double? personX;
  String get summary =>
      'input=${width}x$height sensor=$sensorRotation '
      'q=$quarterTurns mask=${maskWidth}x$maskHeight foreground=$foreground/$pixels '
      'source_foreground=$sourceForeground'
      '${personX == null ? '' : ' person_x=${personX!.toStringAsFixed(2)}'}';
}

/// Bounded reason codes, not native exception messages or personal file paths.
class SceneFailure extends FormatException {
  const SceneFailure(this.code, {this.trace}) : super(code);
  final String code;
  final SceneEmbeddingTrace? trace;
}

/// Snapshot supplied by integration, in the portrait preview's coordinates.
/// quarterTurns uses core/orientation.dart: +1 = top left (photo rotates CCW).
class SceneView {
  const SceneView({
    this.quarterTurns = 0,
    this.left = 0,
    this.top = 0,
    this.width = 1,
    this.height = 1,
  });
  final int quarterTurns;
  final double left, top, width, height;
  void validate(ShotOrientation orientation) {
    if (![-1, 0, 1].contains(quarterTurns)) {
      throw const SceneFailure('geometry/invalid-quarter-turns');
    }
    if ((orientation == ShotOrientation.portrait) != (quarterTurns == 0)) {
      throw const SceneFailure('geometry/orientation-mismatch');
    }
    if (![left, top, width, height].every((v) => v.isFinite) ||
        left < 0 ||
        top < 0 ||
        width <= 0 ||
        height <= 0 ||
        left + width > 1 ||
        top + height > 1) {
      throw const SceneFailure('geometry/invalid-crop');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SceneView &&
      quarterTurns == other.quarterTurns &&
      left == other.left &&
      top == other.top &&
      width == other.width &&
      height == other.height;
  @override
  int get hashCode => Object.hash(quarterTurns, left, top, width, height);
}

class SceneEmbedding {
  SceneEmbedding(List<double> values, this.variant, {this.trace})
    : values = List.unmodifiable(normalizeClipEmbedding(values));
  final List<double> values;
  final String variant;
  final SceneEmbeddingTrace? trace;
}

abstract class SceneEmbedder {
  Future<void> warmUp();
  Future<SceneEmbedding> embed(CameraFrame frame, SceneView view);
  Future<void> dispose();
}

class NativeSceneEmbedder implements SceneEmbedder {
  NativeSceneEmbedder({ModelManager? modelManager, PersonMasker? masker})
    : _manager = modelManager ?? BundledSceneModelManager(),
      _masker = masker ?? PersonMasker() {
    _runner = ClipRunner(modelManager: _manager);
  }
  final ModelManager _manager;
  final PersonMasker _masker;
  late final ClipRunner _runner;
  @override
  Future<void> warmUp() => _runner.warmUp();
  @override
  Future<SceneEmbedding> embed(CameraFrame frame, SceneView view) async {
    late final Nv21FrameData data;
    try {
      data = Nv21FrameData.fromCameraFrame(frame);
    } catch (_) {
      throw const SceneFailure('camera/invalid-frame');
    }
    final mask = await _masker.maskData(data);
    if (mask == null || !mask.isUsable) {
      throw SceneFailure(
        'mask/${_masker.lastStatus.split(' ').first}',
        trace: SceneEmbeddingTrace(
          width: data.width,
          height: data.height,
          sensorRotation: data.rotation,
          quarterTurns: view.quarterTurns,
        ),
      );
    }
    final prepared = await compute(prepareRecommendationInput, (
      data,
      mask,
      view,
    ));
    try {
      await _runner.warmUp();
    } catch (_) {
      throw SceneFailure('model/load-failed', trace: prepared.trace);
    }
    try {
      final result = await _runner.runPixels(prepared.pixels);
      return SceneEmbedding(
        result.embedding,
        _runner.activeVariant,
        trace: prepared.trace,
      );
    } catch (_) {
      throw SceneFailure('clip/inference-failed', trace: prepared.trace);
    }
  }

  @override
  Future<void> dispose() async {
    await _masker.close();
    await _runner.dispose();
  }
}

/// Same NV21 sampling, source-to-mask mapping and CLIP normalization as Step 2.
/// Production path omits PNG previews and fails closed for absent/full masks.
Float32List prepareRecommendationPixels(
  (Nv21FrameData, PersonMask, SceneView) job,
) => prepareRecommendationInput(job).pixels;

class PreparedRecommendationInput {
  const PreparedRecommendationInput(this.pixels, this.trace);
  final Float32List pixels;
  final SceneEmbeddingTrace trace;
}

PreparedRecommendationInput prepareRecommendationInput(
  (Nv21FrameData, PersonMask, SceneView) job,
) {
  final (frame, mask, view) = job;
  view.validate(
    view.quarterTurns == 0
        ? ShotOrientation.portrait
        : ShotOrientation.landscape,
  );
  if (!mask.isUsable) throw const SceneFailure('mask/invalid-mask');
  final raw = downsampleNv21(frame);
  final foreground = img.Image(
    width: raw.width,
    height: raw.height,
    numChannels: 1,
  );
  var sourceForeground = 0;
  for (final p in foreground) {
    p.r = mask.atSource(frame, p.x * 4, p.y * 4) >= .5 ? 255 : 0;
    if (p.r > 0) sourceForeground++;
  }
  img.Image shot(img.Image source) {
    var image = img.copyRotate(source, angle: frame.rotation);
    if (frame.mirror) image = img.flipHorizontal(image);
    final x = (view.left * image.width).round().clamp(0, image.width - 1);
    final y = (view.top * image.height).round().clamp(0, image.height - 1);
    image = img.copyCrop(
      image,
      x: x,
      y: y,
      width: (view.width * image.width).round().clamp(1, image.width - x),
      height: (view.height * image.height).round().clamp(1, image.height - y),
    );
    return view.quarterTurns == 0
        ? image
        : img.copyRotate(image, angle: -90 * view.quarterTurns);
  }

  final image = shot(raw), person = shot(foreground);
  final sums = [0.0, 0.0, 0.0];
  for (final p in image) {
    sums[0] += p.r;
    sums[1] += p.g;
    sums[2] += p.b;
  }
  final pixelCount = image.width * image.height;
  final mean = sums.map((s) => (s / pixelCount).round()).toList();
  var filled = 0;
  var sumX = 0.0;
  for (final p in image) {
    if (person.getPixel(p.x, p.y).r >= 128) {
      p.setRgb(mean[0], mean[1], mean[2]);
      filled++;
      sumX += p.x;
    }
  }
  final trace = SceneEmbeddingTrace(
    width: frame.width,
    height: frame.height,
    sensorRotation: frame.rotation,
    quarterTurns: view.quarterTurns,
    maskWidth: mask.width,
    maskHeight: mask.height,
    foreground: filled,
    pixels: pixelCount,
    sourceForeground: sourceForeground,
    personX: personCentroidX(sumX, filled, image.width),
  );
  if (filled == 0) {
    throw SceneFailure(
      sourceForeground > 0 ? 'mask/empty-crop' : 'mask/empty',
      trace: trace,
    );
  }
  if (filled == pixelCount) {
    throw SceneFailure('mask/full', trace: trace);
  }
  return PreparedRecommendationInput(clipImagePixels(image), trace);
}
