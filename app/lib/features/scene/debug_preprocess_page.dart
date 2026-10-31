import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts.dart';
import '../../core/models.dart';
import '../camera/camera_service.dart';
import 'nv21_frame.dart';
import 'person_mask.dart';
import 'preprocess.dart';

/// Diagnostic consumer only. Camera ownership stays in the existing service.
class DebugPreprocessPage extends ConsumerStatefulWidget {
  const DebugPreprocessPage({super.key});
  @override
  ConsumerState<DebugPreprocessPage> createState() =>
      _DebugPreprocessPageState();
}

class _DebugPreprocessPageState extends ConsumerState<DebugPreprocessPage>
    with WidgetsBindingObserver {
  late final CameraService _camera;
  StreamSubscription<CameraFrame>? _subscription;
  final _masker = PersonMasker();
  final _failingMasker = PersonMasker(
    process: (_) async => throw StateError('debug failure'),
  );
  PreparedSceneFrame? _result;
  bool _busy = false,
      _paused = false,
      _maskEnabled = true,
      _forceFailure = false;
  DateTime _next = DateTime.fromMillisecondsSinceEpoch(0);
  int _generation = 0, _dropped = 0;
  String _status = '카메라를 준비하고 있어요…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera = ref.read(cameraServiceProvider);
    final FrameBus bus = _camera;
    _subscription = bus.frames.listen(
      _onFrame,
      onError: (Object error) {
        if (mounted) setState(() => _status = 'FrameBus 오류: $error');
      },
    );
    unawaited(_start());
  }

  Future<void> _start() async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (!mounted) return;
    await _camera.start();
    if (mounted) {
      setState(() => _status = _camera.error?.toString() ?? '프레임을 기다리고 있어요');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _generation++;
      unawaited(_camera.stop());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_start());
    }
  }

  Future<void> _onFrame(CameraFrame frame) async {
    if (!mounted || _paused || _busy || DateTime.now().isBefore(_next)) {
      _dropped++;
      return;
    }
    final generation = _generation;
    setState(() => _busy = true);
    _next = DateTime.now().add(const Duration(seconds: 1));
    final stopwatch = Stopwatch()..start();
    try {
      // Snapshot once. Both the ML Kit input and RGB use these exact bytes.
      final data = Nv21FrameData.fromCameraFrame(frame);
      final masker = _forceFailure ? _failingMasker : _masker;
      final mask = _maskEnabled ? await masker.maskData(data) : null;
      final maskStatus = _maskEnabled ? masker.lastStatus : 'disabled';
      final result = await preprocessData(data, mask: mask);
      stopwatch.stop();
      if (!mounted || generation != _generation) return;
      final summary =
          '${result.frameSummary}\n'
          'preview=${result.width}x${result.height} mask=$maskStatus\n'
          'mask_applied=${result.maskApplied} filled=${result.maskedPixels} mean=${result.meanColor}\n'
          'tensor=float32 [1,3,224,224] count=${result.pixels.length} '
          'finite=${result.pixels.every((v) => v.isFinite)}\n'
          'preprocess_ms=${stopwatch.elapsedMicroseconds / 1000} dropped=$_dropped';
      debugPrint('SCENE STEP2\n$summary');
      setState(() {
        _result = result;
        _status = summary;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _status = '전처리 실패: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _flip() async {
    _generation++;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      await _camera.flip();
      if (mounted) {
        setState(() => _status = _camera.error?.toString() ?? '카메라를 전환했어요');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    unawaited(_subscription?.cancel());
    unawaited(_masker.close());
    unawaited(_failingMasker.close());
    // ProviderScope owns the shared service and invokes its shutdown callback.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('카메라 전처리 테스트')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_camera.isReady && _camera.controller != null)
            SizedBox(height: 160, child: CameraPreview(_camera.controller!)),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: () => setState(() => _paused = !_paused),
                child: Text(_paused ? '계속 보기' : '화면 고정'),
              ),
              if (_camera.canFlip)
                OutlinedButton(
                  onPressed: _busy ? null : _flip,
                  child: const Text('카메라 전환'),
                ),
              if (!_camera.isReady)
                OutlinedButton(
                  onPressed: _start,
                  child: const Text('카메라 다시 연결'),
                ),
            ],
          ),
          SwitchListTile(
            title: const Text('사람 영역 채우기'),
            value: _maskEnabled,
            onChanged: _busy
                ? null
                : (value) => setState(() => _maskEnabled = value),
          ),
          SwitchListTile(
            title: const Text('분할 실패 테스트'),
            value: _forceFailure,
            subtitle: const Text('실패 시 원본으로 계속 처리하는지 확인해요'),
            onChanged: _busy
                ? null
                : (value) => setState(() => _forceFailure = value),
          ),
          SelectableText(_status),
          if (_result case final result?) ...[
            const SizedBox(height: 12),
            const Text('회전·좌우 보정 원본 / 사람 영역을 평균색으로 채운 결과'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Image.memory(
                    result.originalPreviewPng,
                    gaplessPlayback: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Image.memory(
                    result.maskedPreviewPng,
                    gaplessPlayback: true,
                  ),
                ),
              ],
            ),
            const Text('CLIP 입력 영역: 224 × 224'),
            Center(
              child: Image.memory(
                result.clipPreviewPng,
                width: 224,
                height: 224,
                gaplessPlayback: true,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
