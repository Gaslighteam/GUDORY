import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../../../core/models.dart';
import 'diagnostic_camera.dart';
import '../../../coach/pose_geometry.dart';
import 'actions.dart';
import 'background_features.dart';
import 'background_overlay.dart';
import 'director.dart';
import 'director_models.dart';
import 'live_analysis.dart';

const _diagnosticIntervalSeconds = 1.0;

class CompositionDiagnosticPage extends StatefulWidget {
  const CompositionDiagnosticPage({super.key});
  @override
  State<CompositionDiagnosticPage> createState() =>
      _CompositionDiagnosticState();
}

class _CompositionDiagnosticState extends State<CompositionDiagnosticPage>
    with WidgetsBindingObserver {
  final _camera = DiagnosticCamera();
  final _analyzer = LiveDirectorAnalyzer();
  final _director = CompositionDirector();
  final _clock = Stopwatch()..start();
  StreamSubscription<CameraFrame>? _frames;
  StreamSubscription<AccelerometerEvent>? _sensor;
  Future<void>? _inflight;
  Future<void> _lifecycle = Future.value();
  ShotAttitude _attitude = const ShotAttitude.initial();
  LiveSample? _sample, _calibrationStart;
  DirectorDecision? _decision;
  MeasuredMotion? _motion;
  BackgroundOverlayOptions _backgroundOptions =
      const BackgroundOverlayOptions();
  BackgroundOverlaySnapshot? _background;
  double _lastPaintMs = 0;
  final _recent = <DirectorPerson>[];
  final _coreTimes = <double>[], _pipelineTimes = <double>[];
  bool _busy = false, _paused = false, _overlay = true, _active = true;
  int _level = 3, _epoch = 0, _count = 0, _dropped = 0;
  double _next = 0, _safetyAt = -10, _firstAt = 0;
  String _status = '카메라 연결 중', _actor = 'subject', _axis = 'horizontal';
  double get _now => _clock.elapsedMicroseconds / 1e6;
  String get _geometry => 'rear/$_epoch/q${_attitude.quarterTurns}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera.addListener(_cameraChanged);
    _frames = _camera.frames.listen(_onFrame);
    _sensor =
        accelerometerEventStream(
          samplingPeriod: SensorInterval.gameInterval,
        ).listen((e) {
          final old = _attitude;
          _attitude = updateShotAttitude(old, ax: e.x, ay: e.y, az: e.z);
          if (old.quarterTurns != _attitude.quarterTurns) {
            _director.reset();
            _motion = null;
            _calibrationStart = null;
            _recent.clear();
          }
        });
    unawaited(_start());
  }

  void _cameraChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    await _camera.start();
    if (mounted) {
      setState(
        () => _status = _camera.error == null
            ? '실시간 분석 대기'
            : '카메라 연결 실패 · 다시 연결해 주세요',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _active = false;
      _epoch++;
      _director.reset();
      _motion = null;
      _calibrationStart = null;
      _lifecycle = _lifecycle.then((_) => _camera.stop());
    } else if (state == AppLifecycleState.resumed) {
      _active = true;
      _lifecycle = _lifecycle.then((_) => _start());
    }
  }

  void _onFrame(CameraFrame frame) {
    if (!_active || !mounted || _paused || _busy || _now < _next) {
      _dropped++;
      return;
    }
    _busy = true;
    _next = _now + _diagnosticIntervalSeconds;
    _inflight = _process(frame);
    unawaited(_inflight);
  }

  MovementContext _context(DirectorFrame frame) {
    final directions = {
      'horizontal': ['left', 'right'],
      'distance': ['forward', 'backward'],
      'height': ['up', 'down'],
    }[_axis]!;
    return MovementContext(
      motions: _motion == null ? const [] : [_motion!],
      safe: directions.map((d) => '$_actor/$d').toSet(),
      safetyAt: _safetyAt,
      geometry: frame.geometry,
    );
  }

  Future<void> _process(CameraFrame frame) async {
    final epoch = _epoch,
        at = _now,
        q = _attitude.quarterTurns,
        reliable = _attitude.rollReliable;
    final timer = Stopwatch()..start();
    try {
      final sample = await _analyzer.process(
        frame,
        quarterTurns: q,
        level: _level,
        at: at,
        geometry: _geometry,
      );
      if (!mounted ||
          !_active ||
          epoch != _epoch ||
          q != _attitude.quarterTurns) {
        return;
      }
      final core = Stopwatch()..start();
      var decision = _director.update(sample.frame, _context(sample.frame));
      if (!reliable) {
        _director.reset();
        decision = DirectorDecision(
          decision.features,
          null,
          holdAction('phone-flat-or-attitude-unreliable'),
          decision.generation,
          'unavailable',
        );
      }
      final coreMs = core.elapsedMicroseconds / 1000,
          pipelineMs = timer.elapsedMicroseconds / 1000;
      final overlayTimer = Stopwatch()..start();
      final background = BackgroundOverlaySnapshot(
        sample.frame,
        decision.features,
        sample.quarterTurns,
      );
      final overlayPrepareMs = overlayTimer.elapsedMicroseconds / 1000;
      _count++;
      if (_count == 1) _firstAt = at;
      _coreTimes.add(coreMs);
      _pipelineTimes.add(pipelineMs);
      if (_coreTimes.length > 240) {
        _coreTimes.removeAt(0);
        _pipelineTimes.removeAt(0);
      }
      if (sample.frame.person case final p?) {
        _recent.add(p);
        if (_recent.length > 3) _recent.removeAt(0);
      } else {
        _recent.clear();
        _motion = null;
        _calibrationStart = null;
      }
      debugPrint(
        'DIRECTOR_LIVE ${jsonEncode({'sample': _count, 'person': sample.frame.person != null, 'maskValid': decision.features.valid, 'q': q, 'width': sample.frame.width, 'height': sample.frame.height, 'lines': decision.features.lines.length, 'confidence': decision.features.confidence, 'actor': decision.action.actor, 'direction': decision.action.direction, 'instruction': decision.action.text, 'reason': decision.action.reason, 'progress': decision.progress, 'targetGeneration': decision.generation, 'coreMs': coreMs, 'poseMs': sample.poseMs, 'maskMs': sample.maskMs, 'prepareMs': sample.prepMs, 'pipelineMs': pipelineMs, 'hz': _count < 2 ? 0 : (_count - 1) / (at - _firstAt), 'dropped': _dropped, 'showLines': _backgroundOptions.lines, 'showHeatmap': _backgroundOptions.heatmap, 'drawnLines': background.lineCount(_backgroundOptions), 'heatValues': background.cells.map((c) => c.value).toList(), 'heatCoverage': background.cells.map((c) => c.cell.coverage).toList(), 'analysisIntervalMs': (_diagnosticIntervalSeconds * 1000).round(), 'overlayPrepareMs': overlayPrepareMs, 'overlayPaintMs': _lastPaintMs})}',
      );
      setState(() {
        _sample = sample;
        _background = background;
        _decision = decision;
        _status = sample.frame.person == null
            ? '한 사람의 머리와 양쪽 어깨를 보여 주세요'
            : '실제 카메라 입력 · ${reliable ? '분석 중' : '폰을 세워 주세요'}';
      });
    } catch (e) {
      _director.reset();
      _motion = null;
      _calibrationStart = null;
      debugPrint('DIRECTOR_ERROR ${e.runtimeType}');
      if (mounted && epoch == _epoch) {
        setState(() {
          _decision = null;
          _sample = null;
          _background = null;
          _status = '분석을 잠시 멈췄어요 · ${e.runtimeType}';
        });
      }
    } finally {
      _busy = false;
    }
  }

  void _calibrate() {
    final sample = _sample, decision = _decision;
    if (sample?.frame.person == null || decision == null) return;
    if (_calibrationStart == null) {
      setState(() {
        _calibrationStart = sample;
        _status = '공간이 안전할 때 선택한 +방향으로 반 단위 이동 후 완료를 누르세요';
      });
      return;
    }
    final start = _calibrationStart!,
        before = start.frame.person!,
        after = sample!.frame.person!;
    _calibrationStart = null;
    final duration = sample.frame.at - start.frame.at;
    final stable =
        _recent.length == 3 &&
        _recent.every(
          (p) =>
              (p.x - after.x).abs() < .025 &&
              (p.eyeY - after.eyeY).abs() < .025 &&
              (p.scale - after.scale).abs() < .015,
        );
    final dx = (after.x - before.x) / .5,
        dy = (after.eyeY - before.eyeY) / .5,
        ds = (after.scale - before.scale) / .5;
    final preservation =
        (1 - sceneChange(analyzeScene(start.frame), decision.features)).clamp(
          0.0,
          1.0,
        );
    final significant = _axis == 'horizontal'
        ? dx.abs() >= .025
        : _axis == 'height'
        ? dy.abs() >= .025
        : ds.abs() >= .008;
    if (!stable ||
        !significant ||
        duration < .5 ||
        duration > 12 ||
        start.frame.geometry != sample.frame.geometry ||
        [dx.abs(), dy.abs(), ds.abs()].reduce(math.max) > .4 ||
        _actor == 'photographer' && preservation < .8) {
      setState(() {
        _motion = null;
        _status = '측정 근거가 부족해요 · 고정한 뒤 다시 측정해 주세요';
      });
      return;
    }
    _director.reset();
    setState(() {
      _motion = MeasuredMotion(
        _actor,
        _axis,
        dx,
        dy,
        ds,
        .8,
        sample.frame.at,
        sample.frame.geometry,
        preservation: preservation,
      );
      _safetyAt = -10;
      _status = '실제 이동 측정 완료 · 5초 안에 이동 공간 확인을 누르세요';
    });
    debugPrint(
      'DIRECTOR_CALIBRATION actor=$_actor axis=$_axis source=observed-live-half-unit accepted=true',
    );
  }

  void _reset() {
    _epoch++;
    _director.reset();
    _motion = null;
    _calibrationStart = null;
    _safetyAt = -10;
    setState(() {
      _decision = null;
    });
  }

  double _percentile(List<double> values, double p) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    return sorted[((sorted.length - 1) * p).floor()];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _active = false;
    _epoch++;
    _camera.removeListener(_cameraChanged);
    unawaited(_close());
    super.dispose();
  }

  Future<void> _close() async {
    await _frames?.cancel();
    await _sensor?.cancel();
    await _inflight;
    await _lifecycle;
    await _camera.shutdown();
    await _analyzer.close();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _camera.controller;
    final instruction = _decision?.action.text ?? '촬영자님, 잠시 그대로 유지해 주세요.';
    final direction = _axis == 'horizontal'
        ? '오른쪽 반 걸음'
        : _axis == 'distance'
        ? '앞으로 반 걸음'
        : '폰을 위로 반 주먹';
    return Scaffold(
      appBar: AppBar(
        title: const Text('구도 디렉터 · 실험 V1'),
        actions: [
          IconButton(
            tooltip: '인물·목표 표시 켜기/끄기',
            onPressed: () => setState(() => _overlay = !_overlay),
            icon: Icon(_overlay ? Icons.layers : Icons.layers_clear),
          ),
          IconButton(
            tooltip: '다시 분석',
            onPressed: _reset,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: controller != null && _camera.isReady
                    ? AspectRatio(
                        aspectRatio: 1 / controller.value.aspectRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(controller),
                            if (_background case final background?)
                              RepaintBoundary(
                                child: CustomPaint(
                                  painter: BackgroundOverlayPainter(
                                    background,
                                    _backgroundOptions,
                                    onPaint: (ms) => _lastPaintMs = ms,
                                  ),
                                ),
                              ),
                            if (_overlay)
                              CustomPaint(
                                painter: _DiagnosticPainter(
                                  _sample,
                                  _decision,
                                  _sample?.quarterTurns ??
                                      _attitude.quarterTurns,
                                ),
                              ),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: ColoredBox(
                                color: Colors.black54,
                                child: Text(
                                  'LIVE · $_count · ${_sample?.frame.orientation ?? 'portrait'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Center(child: Text(_status)),
              ),
            ),
            Container(
              width: double.infinity,
              color: const Color(0xFF333336),
              padding: const EdgeInsets.all(12),
              child: Text(
                instruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              height: 270,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BackgroundOverlayControls(
                      options: _backgroundOptions,
                      detectedLines: _background?.detectedLineCount ?? 0,
                      onChanged: (value) {
                        setState(() => _backgroundOptions = value);
                        debugPrint(
                          'DIRECTOR_OVERLAY_OPTIONS ${jsonEncode({'lines': value.lines, 'heatmap': value.heatmap, 'sample': _count, 'generation': _decision?.generation})}',
                        );
                      },
                    ),
                    if (_backgroundOptions.heatmap)
                      Text(
                        '${_background?.summary ?? '배경 분석 대기'} · ${_background?.heatValuesLabel ?? ''}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    Text(
                      '1초 갱신 · 배경 ${_background?.supportedCellCount ?? 0}/9 · $_status',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '분석 ${_percentile(_coreTimes, .5).toStringAsFixed(1)}ms · 전체 ${_percentile(_pipelineTimes, .5).toStringAsFixed(0)}ms · p95 ${_percentile(_pipelineTimes, .95).toStringAsFixed(0)}ms · 신뢰 ${((_decision?.features.confidence ?? 0) * 100).round()}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                    Text(
                      '근거: ${_decision?.action.reason ?? 'waiting'} · 목표 ${_decision?.generation ?? 0} · ${_decision?.progress ?? ''}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    Row(
                      children: [
                        const Text('인물 중심', style: TextStyle(fontSize: 12)),
                        Expanded(
                          child: Slider(
                            min: 1,
                            max: 5,
                            divisions: 4,
                            value: _level.toDouble(),
                            label: '$_level',
                            onChanged: (v) {
                              _level = v.round();
                              _reset();
                            },
                          ),
                        ),
                        Text(
                          '배경 중심 · $_level',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        DropdownButton<String>(
                          value: _actor,
                          items: const [
                            DropdownMenuItem(
                              value: 'subject',
                              child: Text('모델 이동'),
                            ),
                            DropdownMenuItem(
                              value: 'photographer',
                              child: Text('촬영자 이동'),
                            ),
                          ],
                          onChanged: (v) {
                            _actor = v!;
                            if (_actor == 'subject') _axis = 'horizontal';
                            _reset();
                          },
                        ),
                        DropdownButton<String>(
                          value: _axis,
                          items: [
                            const DropdownMenuItem(
                              value: 'horizontal',
                              child: Text('좌우'),
                            ),
                            if (_actor == 'photographer') ...const [
                              DropdownMenuItem(
                                value: 'distance',
                                child: Text('앞뒤'),
                              ),
                              DropdownMenuItem(
                                value: 'height',
                                child: Text('폰 높이'),
                              ),
                            ],
                          ],
                          onChanged: (v) {
                            _axis = v!;
                            _reset();
                          },
                        ),
                      ],
                    ),
                    Text(
                      '실제 응답 측정: +방향 = $direction',
                      style: const TextStyle(fontSize: 11),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _sample?.frame.person == null
                              ? null
                              : _calibrate,
                          child: Text(
                            _calibrationStart == null
                                ? '공간 확인 후 측정 시작'
                                : '반 단위 이동 후 완료',
                          ),
                        ),
                        FilledButton(
                          onPressed: _motion == null
                              ? null
                              : () => setState(() {
                                  _safetyAt = _now;
                                  _status = '선택한 축의 양방향 공간 확인 · 2초간 유효';
                                }),
                          child: const Text('이동 공간 확인 · 2초'),
                        ),
                        TextButton(
                          onPressed: () {
                            _paused = !_paused;
                            _reset();
                          },
                          child: Text(_paused ? '분석 재개' : '분석 일시정지'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticPainter extends CustomPainter {
  _DiagnosticPainter(this.sample, this.decision, this.q);
  final LiveSample? sample;
  final DirectorDecision? decision;
  final int q;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    Offset point(double x, double y) {
      final p = shotToPortrait(Offset(x, y), quarterTurns: q);
      return Offset(p.dx * size.width, p.dy * size.height);
    }

    final grid = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(size.width * i / 3, 0),
        Offset(size.width * i / 3, size.height),
        grid,
      );
      canvas.drawLine(
        Offset(0, size.height * i / 3),
        Offset(size.width, size.height * i / 3),
        grid,
      );
    }
    void box(double x, double head, double width, double bottom, Color color) {
      final path = Path()
        ..moveTo(point(x - width / 2, head).dx, point(x - width / 2, head).dy);
      for (final p in [
        (x + width / 2, head),
        (x + width / 2, bottom),
        (x - width / 2, bottom),
      ]) {
        final offset = point(p.$1, p.$2);
        path.lineTo(offset.dx, offset.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    if (sample?.frame.person case final p?) {
      box(
        p.x,
        p.headY,
        p.width,
        p.headY + p.span(p.framing),
        Colors.cyanAccent,
      );
    }
    if (decision?.target case final t?) {
      box(
        t.x,
        t.headY,
        t.width,
        t.headY + t.scale * spans[t.framing]! / .28,
        Colors.yellowAccent,
      );
      canvas.drawCircle(
        point(t.x, t.eyeY),
        5,
        Paint()..color = Colors.yellowAccent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DiagnosticPainter old) =>
      sample != old.sample || decision != old.decision || q != old.q;
}
