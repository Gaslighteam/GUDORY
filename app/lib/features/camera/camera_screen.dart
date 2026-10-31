import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/models.dart';
import '../feedback/instruction_text.dart';
import '../feedback/sensory_feedback.dart';
import '../settings/app_settings.dart';
import '../tutorial/camera_tour.dart';
import 'camera_service.dart';
import 'coaching.dart';
import 'framing.dart';
import 'shot_orientation.dart';
import 'shot_state.dart';
import 'widgets/controls.dart';
import 'widgets/instruction_bubble.dart';
import 'widgets/mode_controls.dart';
import 'widgets/overlays.dart';
import 'widgets/reference_sheet.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

/// The panels that expand out of the round buttons beside the zoom pill.
enum _Panel { none, composition, menu }

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _capturing = false;
  bool _flipping = false;

  /// The how-to tour is on screen (first launch, ⠿ → 사용법, settings).
  bool _touring = false;
  final _bubbleKey = GlobalKey();
  final _modeKey = GlobalKey();
  final _compositionKey = GlobalKey();
  final _midRowKey = GlobalKey();
  final _zoomKey = GlobalKey();
  final _previewKey = GlobalKey();
  final _menuKey = GlobalKey();
  final _bottomBarKey = GlobalKey();

  /// Open (or closing) panel; it stays set until the close animation ends.
  _Panel _panel = _Panel.none;
  late final AnimationController _panelAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _panelCurve = CurvedAnimation(
    parent: _panelAnim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Last saved photo, shown bottom-left outside custom mode.
  String? _lastShotPath;
  String? _toastText;

  Timer? _toastTimer;

  /// Mode-change popup at the top centre: shown, then faded out.
  ShootMode? _modeNotice;
  bool _modeNoticeOn = false;
  Timer? _modeNoticeTimer;
  double _pinchBase = 1;

  /// One-finger drag on the preview since the gesture began; a mostly
  /// vertical swipe flips the camera (Samsung-style).
  Offset _swipe = Offset.zero;
  bool _pinched = false;

  /// X / flash diameter (~10% of the screen width in the mock).
  static const _topButton = 44.0;

  CameraService get _camera => ref.read(cameraServiceProvider);
  SensoryFeedback get _feedback => ref.read(feedbackProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _camera.start();
    // Create the recommender now so CLIP loads while the user frames the shot.
    ref.read(recommenderProvider);
    _showTutorialOnFirstLaunch();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _modeNoticeTimer?.cancel();
    _panelAnim.dispose();
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _camera.stop();
    } else if (state == AppLifecycleState.resumed) {
      _camera.start();
    }
  }

  void _onInstruction(CoachInstruction? previous, CoachInstruction? next) {
    // "Add a reference" / "no person" are statuses: on screen only, no beeps.
    if (next == null ||
        next.key == InstructionKey.addReference ||
        next.key == InstructionKey.noPerson) {
      _feedback.stop();
      return;
    }
    // Aligned: ding + vibration + yellow shutter ring tell the photographer
    // to press. There is no auto shutter; the photo is always taken by hand.
    if (next.aligned) {
      if (previous?.aligned != true) _feedback.aligned();
      return;
    }
    _feedback.proximity(next.error);
  }

  Future<void> _capture() async {
    if (_capturing || !_camera.isReady) return;
    _feedback.stop();
    _feedback.shutter();
    setState(() => _capturing = true);
    try {
      final file = await _camera.takePicture();
      // Final photo = what the preview showed, rotated if held sideways.
      final previewSize = _camera.controller?.value.previewSize;
      var path = file.path;
      if (previewSize != null) {
        try {
          path = await finishShot(
            file.path,
            previewAspect: previewSize.height / previewSize.width,
            crop: ref.read(visibleCropProvider),
            quarterTurns: ref.read(heldOrientationProvider).quarterTurns,
          );
        } catch (_) {
          // Keep the unprocessed photo rather than losing the shot.
        }
      }
      final saved = await _saveToGallery(path);
      if (saved && mounted) setState(() => _lastShotPath = path);
      // References stay until the user resets them.
      ref.read(coachingProvider.notifier).reset();
      _toast(saved ? '앨범에 저장했어요' : '사진을 저장하지 못했어요');
    } catch (_) {
      _toast('사진을 찍지 못했어요. 다시 눌러 주세요');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<bool> _saveToGallery(String path) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        await Gal.requestAccess(toAlbum: true);
      }
      await Gal.putImage(path, album: 'GUDORY');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _addReferences() async {
    final message = await ref.read(referenceProvider.notifier).addFromGallery();
    if (message != null) _toast(message);
  }

  void _onReferenceTap() {
    if (ref.read(referenceProvider).isEmpty) {
      _addReferences();
    } else {
      showReferenceSheet(context, onAdd: _addReferences);
    }
  }

  void _resetReferences() {
    ref.read(referenceProvider.notifier).clear();
    ref.read(coachingProvider.notifier).reset();
    _toast('레퍼런스를 지웠어요');
  }

  /// Front camera = plain camera: coaching and recommendations stop.
  Future<void> _flip() async {
    if (_flipping || _capturing || !_camera.canFlip) return;
    _flipping = true;
    _closePanel();
    _feedback.stop();
    try {
      await _camera.flip();
    } finally {
      _flipping = false;
    }
    if (!mounted) return;
    final front = _camera.isFront;
    ref.read(frontCameraProvider.notifier).set(front);
    ref.read(coachingProvider.notifier).reset();
    _toast(front ? '전면 카메라: 구도 안내 없이 찍어요' : '구도 안내를 다시 시작해요');
  }

  /// Picked in the ⠿ panel: the highlight moves, then the panel closes.
  void _setLanguage(String lang) {
    ref.read(languageProvider.notifier).set(lang);
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted) _closePanel();
    });
  }

  /// Starts the tour from a known state: back camera, recommend mode, no
  /// open panel (so every step's control is on screen).
  Future<void> _startTour() async {
    _closePanel();
    if (_camera.isFront) await _flip();
    ref.read(modeProvider.notifier).setMode(ShootMode.recommend);
    if (mounted) setState(() => _touring = true);
  }

  void _endTour() {
    _closePanel();
    setState(() => _touring = false);
    TutorialGate.markSeen();
  }

  Future<void> _openSettings() async {
    final result = await context.push<String>('/settings');
    if (result == 'tour' && mounted) _startTour();
  }

  List<TourStep> get _tourSteps => [
    const TourStep(title: '구도리 사용법', body: '카메라 화면에서 직접 눌러 보며 익혀요.\n30초면 끝나요.'),
    TourStep(
      target: _bubbleKey,
      title: '한 줄 안내',
      body: '찍는 사람이 할 일을 한 문장으로 알려 줘요. 안내대로 움직이다 구도가 맞으면 \'띵\' 소리와 진동이 나요.',
    ),
    TourStep(
      target: _modeKey,
      title: '추천 · 맞춤',
      body: '추천: 지금 배경에 어울리는 구도를 골라 줘요.\n맞춤: 따라 하고 싶은 사진을 넣으면 그 구도로 안내해요.',
    ),
    TourStep(
      target: _compositionKey,
      title: '인물 ↔ 배경 비중',
      body: '추천 모드에서 사람을 얼마나 크게 담을지 정해요. 버튼을 눌러 보세요.',
      tryIt: true,
      advanceOnUse: true,
    ),
    TourStep(
      target: _midRowKey,
      title: '단계 고르기',
      body: '왼쪽(1)은 사람을 크게, 오른쪽(5)은 배경을 넓게 담아요. 하나 골라 보세요.',
      tryIt: true,
      advanceOnUse: true,
      onLeave: _closePanel,
    ),
    TourStep(
      target: _zoomKey,
      title: '확대 · 축소',
      body: '숫자를 누르거나 옆으로 밀어 보세요. 두 손가락으로 화면을 벌려도 돼요.',
      tryIt: true,
      advanceOnUse: true,
    ),
    TourStep(
      target: _previewKey,
      title: '앞 · 뒤 카메라',
      body: '화면을 위나 아래로 밀면 카메라가 바뀌어요. 셀카는 안내 없이 그냥 찍혀요.',
      tryIt: true,
    ),
    TourStep(
      target: _menuKey,
      title: '메뉴',
      body: '버튼을 눌러 보세요.',
      tryIt: true,
      advanceOnUse: true,
    ),
    TourStep(
      target: _midRowKey,
      title: '사용법 · 언어 · 설정',
      body: '사용법은 여기서 다시 볼 수 있어요. 안내 언어(한국어·English·日本語)와 설정도 여기 있어요.',
      onLeave: _closePanel,
    ),
    TourStep(
      target: _bottomBarKey,
      title: '셔터',
      body: '구도가 맞으면 셔터 테두리가 노랗게 바뀌어요. 그때 눌러 찍으세요. 사진은 앨범의 GUDORY 폴더에 저장돼요.',
    ),
  ];

  void _openPanel(_Panel panel) {
    setState(() => _panel = panel);
    _panelAnim.forward();
  }

  void _closePanel() {
    if (_panel == _Panel.none || _panelAnim.status == AnimationStatus.reverse) {
      return;
    }
    _panelAnim.reverse().then((_) {
      if (mounted && _panelAnim.isDismissed) {
        setState(() => _panel = _Panel.none);
      }
    });
  }

  void _onPreviewScaleStart(ScaleStartDetails d) {
    _pinchBase = _camera.zoom;
    _swipe = Offset.zero;
    _pinched = d.pointerCount > 1;
  }

  void _onPreviewScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount < 2) {
      _swipe += d.focalPointDelta;
      return;
    }
    _pinched = true;
    _camera.setZoom(_pinchBase * d.scale);
  }

  /// Swipe up/down (along the held "vertical", so sideways shots work too)
  /// flips between the front and back cameras.
  void _onPreviewScaleEnd(ScaleEndDetails d) {
    if (_pinched) return;
    final sideways = ref.read(heldOrientationProvider).quarterTurns.isOdd;
    final along = sideways ? _swipe.dx : _swipe.dy;
    final across = sideways ? _swipe.dy : _swipe.dx;
    if (along.abs() < 60 || along.abs() < across.abs() * 2) return;
    HapticFeedback.lightImpact();
    _flip();
  }

  void _setMode(ShootMode mode) {
    ref.read(modeProvider.notifier).setMode(mode);
    _closePanel();
    _announceMode(mode);
  }

  void _announceMode(ShootMode mode) {
    _modeNoticeTimer?.cancel();
    setState(() {
      _modeNotice = mode;
      _modeNoticeOn = true;
    });
    _modeNoticeTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _modeNoticeOn = false);
    });
  }

  Future<void> _showTutorialOnFirstLaunch() async {
    if (!await TutorialGate.shouldShow() || !mounted) return;
    // Wait for the camera (and its permission prompt) so the controls exist.
    for (var i = 0; i < 50 && !_camera.isReady; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (mounted && !_touring) _startTour();
  }

  void _toast(String message) {
    if (!mounted) return;
    _toastTimer?.cancel();
    setState(() => _toastText = message);
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toastText = null);
    });
  }

  /// Portrait aspect (w/h) of the camera frame; 3:4 until the camera is ready.
  double _frameAspect(CameraService camera) {
    final preview = camera.controller?.value.previewSize;
    return preview == null ? 3 / 4 : preview.height / preview.width;
  }

  /// Tracks which part of the camera frame the cover-fit preview shows.
  void _publishVisibleCrop(Size area, CameraService camera) {
    final preview = camera.controller?.value.previewSize;
    if (preview == null || area.isEmpty) return;
    // previewSize is landscape; the portrait frame is height x width.
    final frameAspect = preview.height / preview.width;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(visibleCropProvider.notifier).update(area, frameAspect);
      }
    });
  }

  Widget _midRow(
    CameraService camera,
    ModeState mode,
    bool showComposition,
    int turns,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: showComposition
              ? CompositionButton(
                  key: _compositionKey,
                  level: mode.level,
                  onPressed: () => _openPanel(_Panel.composition),
                  quarterTurns: turns,
                )
              : null,
        ),
        Expanded(
          child: Center(
            child: camera.isReady
                ? ZoomControl(
                    key: _zoomKey,
                    min: camera.minZoom,
                    max: camera.maxZoom,
                    zoom: camera.zoom,
                    presets: camera.zoomPresets,
                    onChanged: camera.setZoom,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        MenuDotsButton(key: _menuKey, onPressed: () => _openPanel(_Panel.menu)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final camera = ref.watch(cameraServiceProvider);
    final reference = ref.watch(referenceProvider);
    final instruction = ref.watch(coachingProvider);
    final mode = ref.watch(modeProvider);
    final held = ref.watch(heldOrientationProvider);
    final turns = held.quarterTurns;
    final custom = mode.mode == ShootMode.custom;
    final lang = ref.watch(languageProvider);
    // Front camera = plain camera: no coaching UI at all.
    final front = ref.watch(frontCameraProvider);
    final showComposition = !custom && !front;
    final settings = ref.watch(settingsProvider);
    ref.listen<CoachInstruction?>(coachingProvider, _onInstruction);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          ListenableBuilder(
            listenable: camera,
            builder: (context, _) => Column(
              children: [
                // Top bar sits above the 3:4 preview (Samsung-style).
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        if (!front)
                          ModeToggle(
                            key: _modeKey,
                            mode: mode.mode,
                            onChanged: _setMode,
                            quarterTurns: turns,
                          ),
                        if (!front && custom && !reference.isEmpty) ...[
                          const SizedBox(width: 10),
                          RoundIconButton(
                            icon: Icons.close,
                            onPressed: _resetReferences,
                            size: _topButton,
                            tooltip: '레퍼런스 초기화',
                            quarterTurns: turns,
                          ),
                        ],
                        const Spacer(),
                        RoundIconButton(
                          icon: switch (camera.flashMode) {
                            FlashMode.auto => Icons.flash_auto,
                            FlashMode.always => Icons.flash_on,
                            _ => Icons.flash_off,
                          },
                          onPressed: camera.isReady ? camera.cycleFlash : null,
                          size: _topButton,
                          tooltip: '플래시',
                          quarterTurns: turns,
                        ),
                      ],
                    ),
                  ),
                ),
                // The preview has the still's own aspect (3:4), so what you see is
                // the whole photo: nothing is cropped when saving.
                AspectRatio(
                  key: _previewKey,
                  aspectRatio: _frameAspect(camera),
                  child: LayoutBuilder(
                    builder: (context, area) {
                      _publishVisibleCrop(area.biggest, camera);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          GestureDetector(
                            onScaleStart: _onPreviewScaleStart,
                            onScaleUpdate: _onPreviewScaleUpdate,
                            onScaleEnd: _onPreviewScaleEnd,
                            child: _Preview(
                              camera: camera,
                              onRetry: camera.start,
                            ),
                          ),
                          if (camera.isReady) ...[
                            if (settings.grid) const GridOverlay(),
                            if (settings.crosshair) const CenterCrosshair(),
                          ],
                          if (!front)
                            Align(
                              alignment: const Alignment(0, -0.5),
                              child: AnimatedRotation(
                                turns: turns / 4,
                                duration: const Duration(milliseconds: 250),
                                child: GestureDetector(
                                  // Debug builds: long-press plays a scripted session,
                                  // double-tap opens the pose overlay.
                                  onLongPress: kDebugMode
                                      ? ref
                                            .read(coachingProvider.notifier)
                                            .runDemo
                                      : null,
                                  onDoubleTap: kDebugMode
                                      ? () => context.push('/debug/pose')
                                      : null,
                                  child: KeyedSubtree(
                                    key: _bubbleKey,
                                    child: _bubble(instruction, lang),
                                  ),
                                ),
                              ),
                            ),
                          if (_modeNotice != null)
                            SafeArea(
                              child: Align(
                                alignment: const Alignment(0, -0.9),
                                child: IgnorePointer(
                                  child: AnimatedOpacity(
                                    opacity: _modeNoticeOn ? 1 : 0,
                                    duration: _modeNoticeOn
                                        ? const Duration(milliseconds: 160)
                                        : const Duration(milliseconds: 500),
                                    curve: Curves.easeOut,
                                    child: AnimatedSlide(
                                      offset: _modeNoticeOn
                                          ? Offset.zero
                                          : const Offset(0, -0.25),
                                      duration: const Duration(
                                        milliseconds: 500,
                                      ),
                                      curve: Curves.easeOut,
                                      child: AnimatedRotation(
                                        turns: turns / 4,
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        child: ModeNotice(mode: _modeNotice!),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_toastText != null)
                            SafeArea(
                              child: Align(
                                alignment: const Alignment(0, -0.82),
                                child: _Toast(text: _toastText!),
                              ),
                            ),
                          // Composition (recommend only) · zoom · ⠿ menu. The
                          // round buttons expand in place into their panels; the
                          // rest of the row fades out, and a tap anywhere else
                          // closes the panel.
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 14,
                            child: Stack(
                              key: _midRowKey,
                              alignment: Alignment.center,
                              children: [
                                FadeTransition(
                                  opacity: ReverseAnimation(_panelCurve),
                                  child: IgnorePointer(
                                    ignoring: _panel != _Panel.none,
                                    child: _midRow(
                                      camera,
                                      mode,
                                      showComposition,
                                      turns,
                                    ),
                                  ),
                                ),
                                if (_panel == _Panel.composition &&
                                    showComposition)
                                  TapRegion(
                                    onTapOutside: (_) => _closePanel(),
                                    child: ExpandFromButton(
                                      animation: _panelCurve,
                                      alignment: Alignment.centerLeft,
                                      child: CompositionPanel(
                                        level: mode.level,
                                        onChanged: ref
                                            .read(modeProvider.notifier)
                                            .setLevel,
                                        onClose: () {
                                          if (mounted) _closePanel();
                                        },
                                        quarterTurns: turns,
                                      ),
                                    ),
                                  ),
                                if (_panel == _Panel.menu)
                                  TapRegion(
                                    onTapOutside: (_) => _closePanel(),
                                    child: ExpandFromButton(
                                      animation: _panelCurve,
                                      alignment: Alignment.centerRight,
                                      child: CameraMenuPanel(
                                        language: lang,
                                        onTutorial: _startTour,
                                        onSettings: () {
                                          _closePanel();
                                          _openSettings();
                                        },
                                        onLanguage: _setLanguage,
                                        onClose: _closePanel,
                                        quarterTurns: turns,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Expanded(
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: BottomBar(
                        key: _bottomBarKey,
                        reference: custom && !front
                            ? ReferenceThumb(
                                state: reference,
                                onTap: _onReferenceTap,
                              )
                            : LastShotThumb(path: _lastShotPath),
                        quarterTurns: turns,
                        onShutter: camera.isReady ? _capture : null,
                        onFlip: camera.canFlip ? _flip : null,
                        armed: instruction?.aligned ?? false,
                        busy: _capturing,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_touring)
            Positioned.fill(
              child: CameraTour(steps: _tourSteps, onDone: _endTour),
            ),
        ],
      ),
    );
  }

  Widget _bubble(CoachInstruction? instruction, String lang) {
    if (instruction == null) {
      return const InstructionBubble(text: '사진 감각, 빌려드릴게요');
    }
    return InstructionBubble(
      text: InstructionText.of(instruction.key, instruction.amount, lang),
      direction: InstructionText.arrowOf(instruction.key),
      highlight: instruction.aligned,
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }
}

/// Full-bleed preview (cover). Shows an error with retry when the camera fails.
class _Preview extends StatelessWidget {
  const _Preview({required this.camera, required this.onRetry});

  final CameraService camera;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final controller = camera.controller;
    if (camera.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white54,
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              '카메라를 열 수 없어요.\n카메라 권한을 허용해 주세요',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final size = controller.value.previewSize;
    if (size == null) return CameraPreview(controller);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // previewSize is landscape; the UI is portrait.
          width: size.height,
          height: size.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
