import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/models.dart';
import '../feedback/instruction_text.dart';
import '../feedback/sensory_feedback.dart';
import '../tutorial/tutorial_screen.dart';
import 'camera_service.dart';
import 'coaching.dart';
import 'framing.dart';
import 'shot_orientation.dart';
import 'shot_state.dart';
import 'widgets/controls.dart';
import 'widgets/language.dart';
import 'widgets/instruction_bubble.dart';
import 'widgets/mode_controls.dart';
import 'widgets/overlays.dart';
import 'widgets/reference_sheet.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  bool _capturing = false;

  /// Recommend mode: the 5-step composition panel is open.
  bool _panelOpen = false;

  /// Last saved photo, shown bottom-left outside custom mode.
  String? _lastShotPath;
  String? _toastText;

  Timer? _toastTimer;
  double _pinchBase = 1;

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
    _feedback.stop();
    await _camera.flip();
    final front = _camera.isFront;
    ref.read(frontCameraProvider.notifier).set(front);
    ref.read(coachingProvider.notifier).reset();
    _toast(front ? '전면 카메라: 구도 안내 없이 찍어요' : '구도 안내를 다시 시작해요');
  }

  Future<void> _pickLanguage() async {
    final lang = await pickLanguage(context, ref.read(languageProvider));
    if (lang == null || !mounted) return;
    ref.read(languageProvider.notifier).set(lang);
  }

  void _openTutorial() => context.push('/tutorial');

  void _openMenu() => showCameraMenu(
    context,
    languageLabel: instructionLanguages[ref.read(languageProvider)] ?? '한국어',
    onTutorial: _openTutorial,
    onLanguage: _pickLanguage,
  );

  void _setMode(ShootMode mode) {
    ref.read(modeProvider.notifier).setMode(mode);
    setState(() => _panelOpen = false);
    _toast(mode == ShootMode.recommend ? '추천 모드' : '맞춤 모드');
  }

  Future<void> _showTutorialOnFirstLaunch() async {
    if (!await TutorialGate.shouldShow() || !mounted) return;
    _openTutorial();
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
    ref.listen<CoachInstruction?>(coachingProvider, _onInstruction);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListenableBuilder(
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
              aspectRatio: _frameAspect(camera),
              child: LayoutBuilder(
                builder: (context, area) {
                  _publishVisibleCrop(area.biggest, camera);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        onScaleStart: (_) => _pinchBase = camera.zoom,
                        onScaleUpdate: (d) {
                          if (d.pointerCount < 2) return;
                          camera.setZoom(_pinchBase * d.scale);
                        },
                        child: _Preview(camera: camera, onRetry: camera.start),
                      ),
                      if (camera.isReady) ...[
                        const GridOverlay(),
                        const CenterCrosshair(),
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
                                  ? ref.read(coachingProvider.notifier).runDemo
                                  : null,
                              onDoubleTap: kDebugMode
                                  ? () => context.push('/debug/pose')
                                  : null,
                              child: _bubble(instruction, lang),
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
                      // composition button expands into the 5-step panel and
                      // the zoom and menu step aside until it closes.
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 14,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _panelOpen && showComposition
                              ? CompositionPanel(
                                  key: const ValueKey('panel'),
                                  level: mode.level,
                                  onChanged: ref
                                      .read(modeProvider.notifier)
                                      .setLevel,
                                  onClose: () {
                                    if (mounted) {
                                      setState(() => _panelOpen = false);
                                    }
                                  },
                                  quarterTurns: turns,
                                )
                              : Row(
                                  key: const ValueKey('row'),
                                  children: [
                                    SizedBox(
                                      width: 44,
                                      child: showComposition
                                          ? CompositionButton(
                                              level: mode.level,
                                              onPressed: () => setState(
                                                () => _panelOpen = true,
                                              ),
                                              quarterTurns: turns,
                                            )
                                          : null,
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: camera.isReady
                                            ? ZoomControl(
                                                min: camera.minZoom,
                                                max: camera.maxZoom,
                                                zoom: camera.zoom,
                                                presets: camera.zoomPresets,
                                                onChanged: camera.setZoom,
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                    ),
                                    MenuDotsButton(onPressed: _openMenu),
                                  ],
                                ),
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
