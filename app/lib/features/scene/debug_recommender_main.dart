import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts.dart';
import '../../core/models.dart';
import '../camera/camera_service.dart';
import '../camera/shot_orientation.dart';
import 'recommender.dart';
import 'scene_embedding.dart';
import 'clip_parity_check.dart';

/// Standalone QA entry point. No shared router/provider is replaced.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      child: MaterialApp(theme: ThemeData.dark(), home: const _Page()),
    ),
  );
}

class _Page extends ConsumerStatefulWidget {
  const _Page();
  @override
  ConsumerState<_Page> createState() => _PageState();
}

class _PageState extends ConsumerState<_Page> with WidgetsBindingObserver {
  late final CameraService _camera;
  late final _DebugEmbedder _embedder;
  late final SceneRecommender _recommender;
  StreamSubscription<CameraFrame>? _frames;
  CameraFrame? _latest;
  bool _busy = false, _missingAsset = false;
  int _level = 3, _epoch = 0;
  String _status = '카메라를 준비하고 있어요';
  final _age = Stopwatch()..start();
  Duration _next = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera = ref.read(cameraServiceProvider);
    _embedder = _DebugEmbedder(
      NativeSceneEmbedder(
        modelManager: const bool.fromEnvironment('SCENE_MISSING_MODEL')
            ? _MissingModel()
            : null,
      ),
    );
    _recommender = SceneRecommender(
      embedder: _embedder,
      loadAsset: () {
        if (_missingAsset) throw StateError('QA missing asset');
        return rootBundle.loadString('assets/recommend.json');
      },
      viewForFrame: (_, _) => SceneView(
        quarterTurns: ref.read(heldOrientationProvider).quarterTurns,
      ),
    );
    _frames = _camera.frames.listen(
      (frame) {
        _latest = frame;
        if (!_busy && _age.elapsed >= _next) unawaited(_measure());
      },
      onError: (Object _) {
        if (mounted) setState(() => _status = '카메라 프레임 오류');
      },
    );
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      debugPrint(
        'SCENE PREPROCESS PARITY ${await compute(checkClipRgbParity, null)}',
      );
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      _recommender.invalidateEmbedding();
      await _camera.start();
      if (mounted) {
        setState(
          () => _status = _camera.error == null ? '프레임을 기다리고 있어요' : '카메라 연결 실패',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _status = '카메라 연결 실패');
    }
  }

  Future<void> _measure({bool compare = false}) async {
    final frame = _latest;
    if (_busy || frame == null || !mounted) return;
    final epoch = _epoch;
    setState(() => _busy = true);
    _next = _age.elapsed + const Duration(seconds: 3);
    try {
      final orientation = ref.read(heldOrientationProvider).orientation;
      final lines = <String>[];
      for (final level in compare ? [1, 3, 5] : [_level]) {
        final result = await _recommender.recommend(frame, level, orientation);
        final target = result.target, d = _recommender.lastDiagnostics!;
        lines.add(
          'o=${orientation.name} level=$level selected=${d.selectedLevel} '
          'f=${target.framing.name} h=${target.personHeightRatio.toStringAsFixed(6)} '
          'cx=${target.personCenterX.toStringAsFixed(6)} cy=${target.personCenterY.toStringAsFixed(6)} '
          'hy=${target.horizonY} neighbors=${result.neighbors} model=${result.modelVariant}\n'
          'cos=${d.cosine} total_ms=${d.duration.inMicroseconds / 1000} '
          'cached=${d.cacheHit} embedding_calls=${d.inferences} status=${d.status} '
          'clusters=${d.clusterCount} ${d.trace?.summary ?? ''}',
        );
      }
      final text = lines.join('\n\n');
      debugPrint('SCENE RECOMMENDER\n$text');
      if (mounted && epoch == _epoch) setState(() => _status = text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _epoch++;
      _latest = null;
      _recommender.invalidateEmbedding();
      unawaited(_camera.stop());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_frames?.cancel());
    unawaited(_recommender.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final held = ref.watch(heldOrientationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('추천 검증')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _camera,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('전체 프레임 검증 · 미리보기 크롭 없음'),
              if (_camera.isReady && _camera.controller != null)
                Center(
                  child: SizedBox(
                    width: 160,
                    child: CameraPreview(_camera.controller!),
                  ),
                ),
              Text('방향: ${held.orientation.name} / ${held.quarterTurns}'),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 1; i <= 5; i++)
                    ChoiceChip(
                      label: Text('$i'),
                      selected: _level == i,
                      onSelected: _busy
                          ? null
                          : (_) {
                              setState(() => _level = i);
                              unawaited(_measure());
                            },
                    ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : () => _measure(compare: true),
                    child: const Text('1·3·5 비교'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () {
                            _recommender.invalidateEmbedding();
                            unawaited(_measure());
                          },
                    child: const Text('새 배경 분석'),
                  ),
                  OutlinedButton(
                    onPressed: _busy || !_camera.canFlip
                        ? null
                        : () async {
                            _epoch++;
                            _latest = null;
                            _recommender.invalidateEmbedding();
                            await _camera.flip();
                            if (mounted) setState(() {});
                          },
                    child: const Text('카메라 전환'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _start,
                    child: const Text('카메라 연결'),
                  ),
                ],
              ),
              SwitchListTile(
                title: const Text('추론 실패 주입'),
                value: _embedder.fail,
                onChanged: _busy
                    ? null
                    : (value) {
                        setState(() => _embedder.fail = value);
                        _recommender.invalidateEmbedding();
                        unawaited(_measure());
                      },
              ),
              SwitchListTile(
                title: const Text('에셋 누락 주입'),
                value: _missingAsset,
                onChanged: _busy
                    ? null
                    : (value) async {
                        setState(() => _missingAsset = value);
                        await _recommender.reloadAssets();
                        unawaited(_measure());
                      },
              ),
              SelectableText(_status),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebugEmbedder implements SceneEmbedder {
  _DebugEmbedder(this.native);
  final SceneEmbedder native;
  bool fail = false;
  @override
  Future<void> warmUp() => native.warmUp();
  @override
  Future<SceneEmbedding> embed(CameraFrame frame, SceneView view) {
    if (fail) throw StateError('Injected inference failure');
    return native.embed(frame, view);
  }

  @override
  Future<void> dispose() => native.dispose();
}

class _MissingModel implements ModelManager {
  @override
  String get activeVariant => 'q8';
  @override
  Stream<double> get downloadProgress => const Stream.empty();
  @override
  Future<String> ensureBest() async => '/gudory-deliberately-absent.onnx';
}
