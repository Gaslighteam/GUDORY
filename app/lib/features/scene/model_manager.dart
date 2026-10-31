import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/contracts.dart';

/// Offline q8 only. A lead-supplied ModelManager may provide the optional fp16.
class BundledSceneModelManager implements ModelManager {
  BundledSceneModelManager({
    AssetBundle? bundle,
    Future<Directory> Function()? directory,
  }) : _bundle = bundle ?? rootBundle,
       _directory = directory ?? getApplicationSupportDirectory;
  final AssetBundle _bundle;
  final Future<Directory> Function() _directory;
  Future<String>? _pending;

  @override
  String get activeVariant => 'q8';
  @override
  Stream<double> get downloadProgress => const Stream.empty();
  @override
  Future<String> ensureBest() =>
      _pending ??= _copy().catchError((Object error) {
        _pending = null;
        throw error;
      });

  Future<String> _copy() async {
    final directory = await _directory();
    final file = File('${directory.path}/clip/vision_q8.onnx');
    if (await file.exists() && await file.length() > 0) return file.path;
    final bytes = await _bundle.load('assets/clip/vision_q8.onnx');
    if (bytes.lengthInBytes == 0) {
      throw const FormatException('Empty CLIP model');
    }
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    await part.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    await part.rename(file.path);
    return file.path;
  }
}
