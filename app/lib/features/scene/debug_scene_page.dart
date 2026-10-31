import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clip_runner.dart';
import 'debug_test_image.dart';
import 'debug_preprocess_page.dart';

class DebugScenePage extends StatefulWidget {
  const DebugScenePage({super.key, this.assetPath});

  /// Optional lead-provided image in an already declared asset directory.
  /// Without it, use the deterministic scene-local PNG fixture.
  final String? assetPath;

  @override
  State<DebugScenePage> createState() => _DebugScenePageState();
}

class _DebugScenePageState extends State<DebugScenePage> {
  final _runner = ClipRunner();
  bool _busy = false;
  String _result = '버튼을 눌러 CLIP을 테스트하세요';

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _result = '모델을 준비하고 있어요…';
    });
    try {
      final asset = widget.assetPath;
      final result = asset == null
          ? await _runner.runBytes(debugTestImage())
          : await _runner.runAsset(asset);
      if (mounted) setState(() => _result = result.summary);
    } catch (error) {
      if (mounted) {
        setState(
          () => _result = 'CLIP 테스트 실패\n$error\n모델과 테스트 이미지를 확인한 뒤 다시 눌러주세요',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_runner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('CLIP 기기 테스트')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('입력: ${widget.assetPath ?? '고정 색상 테스트 이미지'}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _run,
              child: Text(_busy ? '측정 중…' : 'CLIP 실행'),
            ),
            const SizedBox(height: 24),
            SelectableText(_result),
            const SizedBox(height: 16),
            const Text('inference_ms는 모델 실행 시간만 표시해요.\n첫 실행과 반복 실행을 각각 기록하세요.'),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const ProviderScope(child: DebugPreprocessPage()),
                      ),
                    ),
              child: const Text('Step 2 카메라 전처리 테스트'),
            ),
          ],
        ),
      ),
    ),
  );
}
