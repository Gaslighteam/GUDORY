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
import 'camera_service.dart';
import 'coaching.dart';
import 'framing.dart';
import 'shot_orientation.dart';
import 'shot_state.dart';
import 'widgets/controls.dart';
import 'widgets/handover.dart';
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
  Timer? _autoShutter;
  String? _toastText;

  /// Hand-over guide / "done" message shown in the bubble for a moment.
  String? _note;
  Timer? _noteTimer;
  Timer? _toastTimer;
  double _pinchBase = 1;

  /// "Aligned" must hold this long before the auto shutter fires.
  static const _holdBeforeShot = Duration(seconds: 1);

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
  }

  @override
  void dispose() {
    _autoShutter?.cancel();
    _toastTimer?.cancel();
    _noteTimer?.cancel();
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
    // "Add a reference" is shown in the bubble only: no beeps or shot.
    if (next == null || next.key == InstructionKey.addReference) {
      _autoShutter?.cancel();
      _feedback.stop();
      return;
    }
    // "No person" is a status, not a move: on screen only, no beeps.
    if (next.key == InstructionKey.noPerson) {
      _autoShutter?.cancel();
      _feedback.stop();
      return;
    }
    if (next.aligned) {
      if (previous?.aligned != true) {
        _feedback.aligned();
        _autoShutter?.cancel();
        _autoShutter = Timer(_holdBeforeShot, _capture);
      }
      return;
    }
    _autoShutter?.cancel();
    _feedback.proximity(next.error);
  }

  Future<void> _capture() async {
    if (_capturing || !_camera.isReady) return;
    _autoShutter?.cancel();
    _feedback.stop();
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
      // References stay until the user resets them.
      ref.read(coachingProvider.notifier).reset();
      final handover = ref.read(handoverProvider);
      if (handover.active && saved) {
        final done = InstructionText.handoverDone(handover.lang);
        _showNote(done, const Duration(seconds: 4));
      } else {
        _toast(saved ? '앨범에 저장했어요' : '사진을 저장하지 못했어요');
      }
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

  /// Language for instructions: the photographer's while handed over.
  String get _lang {
    final handover = ref.read(handoverProvider);
    return handover.active ? handover.lang : 'ko';
  }

  /// Custom mode coaches toward a reference, so handing the phone over
  /// without one would leave the photographer on an empty prompt.
  bool get _handoverBlocked =>
      ref.read(modeProvider).mode == ShootMode.custom &&
      ref.read(referenceProvider).isEmpty;

  Future<void> _startHandover() async {
    if (_handoverBlocked) {
      _toast('레퍼런스 사진을 먼저 추가해 주세요');
      return;
    }
    final lang = await pickPhotographerLanguage(
      context,
      ref.read(handoverProvider).lang,
    );
    if (lang == null || !mounted) return;
    ref.read(handoverProvider.notifier).start(lang);
    final guide = InstructionText.handoverGuide(lang);
    _showNote(guide, const Duration(seconds: 3));
  }

  void _endHandover() {
    ref.read(handoverProvider.notifier).stop();
    _noteTimer?.cancel();
    setState(() => _note = null);
    _toast('주인 화면으로 돌아왔어요');
  }

  void _showNote(String text, Duration duration) {
    _noteTimer?.cancel();
    setState(() => _note = text);
    _noteTimer = Timer(duration, () {
      if (mounted) setState(() => _note = null);
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    _toastTimer?.cancel();
    setState(() => _toastText = message);
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toastText = null);
    });
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
    final handover = ref.watch(handoverProvider);
    final handedOver = handover.active;
    ref.listen<CoachInstruction?>(coachingProvider, _onInstruction);

    return PopScope(
      // While handed over, the system back gesture must not leave the app.
      canPop: !handedOver,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: ListenableBuilder(
          listenable: camera,
          builder: (context, _) => Column(
            children: [
              Expanded(
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
                          child: _Preview(
                            camera: camera,
                            onRetry: camera.start,
                          ),
                        ),
                        if (camera.isReady) ...[
                          const GridOverlay(),
                          const CenterCrosshair(),
                        ],
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
                              child: _bubble(instruction, handover),
                            ),
                          ),
                        ),
                        // Pinned to the top: inside an expanded Stack an unpositioned
                        // Row would stretch and center its buttons vertically.
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: handedOver
                                  ? Row(
                                      children: [
                                        HandoverLockPill(
                                          onUnlock: _endHandover,
                                        ),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        ModeToggle(
                                          mode: mode.mode,
                                          onChanged: ref
                                              .read(modeProvider.notifier)
                                              .setMode,
                                        ),
                                        if (custom && !reference.isEmpty) ...[
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
                                        Opacity(
                                          opacity: custom && reference.isEmpty
                                              ? 0.4
                                              : 1,
                                          child: RoundIconButton(
                                            icon: Icons.front_hand_outlined,
                                            onPressed: _startHandover,
                                            size: _topButton,
                                            tooltip: '폰 건네기',
                                            quarterTurns: turns,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        RoundIconButton(
                                          icon: switch (camera.flashMode) {
                                            FlashMode.auto => Icons.flash_auto,
                                            FlashMode.always => Icons.flash_on,
                                            _ => Icons.flash_off,
                                          },
                                          onPressed: camera.isReady
                                              ? camera.cycleFlash
                                              : null,
                                          size: _topButton,
                                          tooltip: '플래시',
                                          quarterTurns: turns,
                                        ),
                                      ],
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
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 14,
                          child: Center(
                            child: camera.isReady && !handedOver
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
                      ],
                    );
                  },
                ),
              ),
              if (!custom && !handedOver)
                LevelBar(
                  level: mode.level,
                  onChanged: ref.read(modeProvider.notifier).setLevel,
                ),
              SafeArea(
                top: false,
                child: BottomBar(
                  reference: custom && !handedOver
                      ? ReferenceThumb(state: reference, onTap: _onReferenceTap)
                      : const SizedBox(width: 60),
                  quarterTurns: turns,
                  onShutter: camera.isReady ? _capture : null,
                  // Front camera is hidden for the submission: coaching runs in mirrored
                  // preview space while the saved selfie is unmirrored, and
                  // photographer-relative wording reads oddly for a selfie.
                  onFlip: null,
                  armed: instruction?.aligned ?? false,
                  busy: _capturing,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(CoachInstruction? instruction, HandoverState handover) {
    final note = _note;
    if (note != null) {
      return InstructionBubble(text: note, large: handover.active);
    }
    if (instruction == null) {
      return InstructionBubble(
        text: handover.active
            ? InstructionText.handoverGuide(handover.lang)
            : '사진 감각, 빌려드릴게요',
        large: handover.active,
      );
    }
    return InstructionBubble(
      text: InstructionText.of(instruction.key, instruction.amount, _lang),
      direction: InstructionText.arrowOf(instruction.key),
      highlight: instruction.aligned,
      large: handover.active,
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
