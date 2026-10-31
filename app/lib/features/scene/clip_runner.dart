import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/contracts.dart';

/// Verified against the downloaded Xenova vision_model_quantized.onnx graph.
/// The graph's input axes are symbolic; CLIP ViT-B/32 uses this concrete shape.
const clipInputName = 'pixel_values';
const clipOutputName = 'image_embeds';
const clipInputShape = [1, 3, 224, 224];
const clipEmbeddingDimensions = 512;
const clipFp16Url =
    'https://huggingface.co/Xenova/clip-vit-base-patch32/resolve/main/onnx/vision_model_fp16.onnx';

class ClipDebugResult {
  ClipDebugResult({
    required this.inferenceDuration,
    required List<double> embedding,
  }) : embedding = List.unmodifiable(embedding);

  /// Native Run only; excludes model loading, decode, tensor allocation and L2.
  final Duration inferenceDuration;
  final List<double> embedding;
  int get embeddingDimensions => embedding.length;
  List<double> get firstFive => List.unmodifiable(embedding.take(5));
  double get l2Norm => vectorNorm(embedding);

  String get summary =>
      'inference_ms=${inferenceDuration.inMicroseconds / 1000}\n'
      'dimensions=$embeddingDimensions\n'
      'first_five=$firstFive\n'
      'l2_norm=$l2Norm';
}

/// Decode -> RGB -> resize short side -> center crop -> float32 NCHW.
/// This is still-image Step 1 preprocessing, not the Step 2 camera pipeline.
Float32List clipPixels(Uint8List encodedImage) {
  final decoded = img.decodeImage(encodedImage);
  if (decoded == null) {
    throw const FormatException('테스트 이미지를 읽을 수 없어요');
  }
  return clipImagePixels(decoded);
}

/// Shared still/camera normalization; preserves the Step 1 crop and RGB math.
Float32List clipImagePixels(img.Image image) {
  final crop = clipImageCrop(image);
  const mean = [0.48145466, 0.4578275, 0.40821073];
  const std = [0.26862954, 0.26130258, 0.27577711];
  const plane = 224 * 224;
  final values = Float32List(3 * plane);
  for (final pixel in crop) {
    final index = pixel.y * 224 + pixel.x;
    final channels = [pixel.r, pixel.g, pixel.b];
    for (var c = 0; c < 3; c++) {
      values[c * plane + index] = (channels[c] / 255 - mean[c]) / std[c];
    }
  }
  return values;
}

img.Image clipImageCrop(img.Image image) {
  final rgb = img
      .bakeOrientation(image)
      .convert(numChannels: 3, format: img.Format.uint8);
  final scale = 224 / math.min(rgb.width, rgb.height);
  final resized = img.copyResize(
    rgb,
    width: rgb.width <= rgb.height ? 224 : (rgb.width * scale).floor(),
    height: rgb.height <= rgb.width ? 224 : (rgb.height * scale).floor(),
    interpolation: img.Interpolation.cubic,
  );
  return img.copyCrop(
    resized,
    x: (resized.width - 224) ~/ 2,
    y: (resized.height - 224) ~/ 2,
    width: 224,
    height: 224,
  );
}

double vectorNorm(List<double> vector) =>
    math.sqrt(vector.fold<double>(0, (sum, value) => sum + value * value));

List<double> normalizeClipEmbedding(List<double> vector) {
  if (vector.length != clipEmbeddingDimensions ||
      vector.any((v) => !v.isFinite)) {
    throw const FormatException('Expected 512 finite embedding values');
  }
  final norm = vectorNorm(vector);
  if (!norm.isFinite || norm <= 0) {
    throw const FormatException('Invalid embedding norm');
  }
  return vector.map((value) => value / norm).toList(growable: false);
}

/// One runner owns one session. Concurrent calls are rejected, and disposal
/// waits for any native Run to complete before releasing its session.
class ClipRunner {
  ClipRunner({
    AssetBundle? bundle,
    Future<Directory> Function()? directory,
    this.modelManager,
  }) : _bundle = bundle ?? rootBundle,
       _directory = directory ?? getApplicationSupportDirectory;

  final AssetBundle _bundle;
  final Future<Directory> Function() _directory;
  final ModelManager? modelManager;
  OrtSession? _session;
  Future<void>? _warming;
  Future<ClipDebugResult>? _running;
  bool _disposed = false;
  String _activeVariant = 'q8';
  String get activeVariant => _activeVariant;

  Future<void> warmUp() {
    if (_disposed) throw StateError('Runner disposed');
    return _warming ??= _openBundledModel().catchError((Object error) {
      _warming = null;
      throw error;
    });
  }

  Future<void> _openBundledModel() async {
    if (modelManager != null) {
      final path = await modelManager!.ensureBest();
      final variant = modelManager!.activeVariant;
      if (variant != 'q8' && variant != 'fp16') {
        throw const FormatException('Unsupported CLIP variant');
      }
      if (_disposed) throw StateError('Runner disposed');
      final address = await compute(_openSceneSession, path);
      final session = OrtSession.fromAddress(address);
      if (_disposed) {
        session.release();
        throw StateError('Runner disposed');
      }
      _session = session;
      _activeVariant = variant;
      return;
    }
    final directory = await _directory();
    final model = File('${directory.path}/clip/vision_q8.onnx');
    if (!await model.exists()) {
      final asset = await _bundle.load('assets/clip/vision_q8.onnx');
      await model.parent.create(recursive: true);
      final temporary = File('${model.path}.part');
      await temporary.writeAsBytes(
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
        flush: true,
      );
      await temporary.rename(model.path);
    }
    if (_disposed) throw StateError('Runner disposed');
    final options = OrtSessionOptions()..setIntraOpNumThreads(2);
    try {
      // The plugin's fromFile uses UTF-8 even on Windows (ORT expects UTF-16).
      // Use its documented buffer API on the desktop test host.
      final session = Platform.isWindows
          ? OrtSession.fromBuffer(await model.readAsBytes(), options)
          : OrtSession.fromFile(model, options);
      if (_disposed) {
        session.release();
        throw StateError('Runner disposed');
      }
      if (!listEquals(session.inputNames, [clipInputName]) ||
          !listEquals(session.outputNames, [clipOutputName])) {
        session.release();
        throw const FormatException('Unexpected ONNX inputs/outputs');
      }
      _session = session;
    } finally {
      options.release();
    }
  }

  Future<ClipDebugResult> runAsset(String assetPath) async {
    final asset = await _bundle.load(assetPath);
    return runBytes(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    );
  }

  Future<ClipDebugResult> runBytes(Uint8List image) {
    if (_disposed) throw StateError('Runner disposed');
    if (_running != null) throw StateError('Inference already running');
    final future = _run(image);
    _running = future;
    return future.whenComplete(() => _running = null);
  }

  Future<ClipDebugResult> _run(Uint8List image) async {
    await warmUp();
    if (_disposed) throw StateError('Runner disposed');
    final result = await compute(_infer, (_session!.address, image));
    debugPrint('CLIP q8\n${result.summary}');
    return result;
  }

  /// Production camera path: already masked/normalized float32 NCHW pixels.
  /// Reuses the same native worker and tensor/output validation as still images.
  Future<ClipDebugResult> runPixels(Float32List pixels) {
    if (_disposed) throw StateError('Runner disposed');
    if (_running != null) throw StateError('Inference already running');
    final future = _runPixels(Float32List.fromList(pixels));
    _running = future;
    return future.whenComplete(() => _running = null);
  }

  Future<ClipDebugResult> _runPixels(Float32List pixels) async {
    await warmUp();
    if (_disposed) throw StateError('Runner disposed');
    return compute(_inferPixels, (_session!.address, pixels));
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      await _warming;
      await _running;
    } catch (_) {
      // Initialization/inference errors are delivered to the original caller.
    } finally {
      _session?.release();
      _session = null;
    }
  }
}

// A separate isolate keeps decode and native inference off the UI thread.
// Unlike the package's runAsync worker, compute forwards native exceptions.
ClipDebugResult _infer((int, Uint8List) request) {
  final (address, encodedImage) = request;
  return _inferPixels((address, clipPixels(encodedImage)));
}

int _openSceneSession(String path) {
  final options = OrtSessionOptions()..setIntraOpNumThreads(2);
  try {
    final model = File(path);
    final session = Platform.isWindows
        ? OrtSession.fromBuffer(model.readAsBytesSync(), options)
        : OrtSession.fromFile(model, options);
    if (!listEquals(session.inputNames, [clipInputName]) ||
        !listEquals(session.outputNames, [clipOutputName])) {
      session.release();
      throw const FormatException('Unexpected ONNX inputs/outputs');
    }
    // Ownership transfers to ClipRunner; worker wrappers never release it.
    return session.address;
  } finally {
    options.release();
  }
}

ClipDebugResult _inferPixels((int, Float32List) request) {
  final (address, pixels) = request;
  if (pixels.length != 150528 || pixels.any((v) => !v.isFinite)) {
    throw const FormatException('Expected finite float32 [1,3,224,224]');
  }
  final input = OrtValueTensor.createTensorWithDataList(pixels, clipInputShape);
  final options = OrtRunOptions();
  List<OrtValue?> outputs = [];
  try {
    final session = OrtSession.fromAddress(address);
    final stopwatch = Stopwatch()..start();
    outputs = session.run(options, {clipInputName: input}, [clipOutputName]);
    stopwatch.stop();
    final value = outputs.single?.value;
    if (value is! List || value.length != 1 || value.single is! List) {
      throw const FormatException('Expected image_embeds [1,512]');
    }
    final row = value.single as List;
    if (row.length != clipEmbeddingDimensions || row.any((v) => v is! double)) {
      throw const FormatException('Expected float32 image_embeds [1,512]');
    }
    return ClipDebugResult(
      inferenceDuration: stopwatch.elapsed,
      embedding: normalizeClipEmbedding(row.cast<double>()),
    );
  } finally {
    for (final output in outputs) {
      output?.release();
    }
    options.release();
    input.release();
  }
}
