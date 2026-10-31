import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/theme.dart';
import '../../core/models.dart';
import '../feedback/instruction_text.dart';
import '../feedback/sensory_feedback.dart';
import 'camera_service.dart';
import 'coaching.dart';
import 'framing.dart';
import 'shot_state.dart';
import 'widgets/controls.dart';
import 'widgets/instruction_bubble.dart';
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
  }

  @override
  void dispose() {
    _autoShutter?.cancel();
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
    if (next == null) {
      _autoShutter?.cancel();
      _feedback.stop();
      return;
    }
    if (next.aligned) {
      if (previous?.aligned != true) {
        _feedback.announce(next, 'ko');
        _feedback.aligned();
        _autoShutter?.cancel();
        _autoShutter = Timer(_holdBeforeShot, _capture);
      }
      return;
    }
    _autoShutter?.cancel();
    _feedback.announce(next, 'ko');
    _feedback.proximity(next.error);
  }

  Future<void> _capture() async {
    if (_capturing || !_camera.isReady) return;
    _autoShutter?.cancel();
    _feedback.stop();
    setState(() => _capturing = true);
    try {
      final file = await _camera.takePicture();
      // Save exactly what the preview showed (it is cover-cropped on screen).
      final previewSize = _camera.controller?.value.previewSize;
      var path = file.path;
      if (previewSize != null) {
        try {
          path = await cropToVisible(
            file.path,
            previewAspect: previewSize.height / previewSize.width,
            crop: ref.read(visibleCropProvider),
          );
        } catch (_) {
          // Keep the uncropped photo rather than losing the shot.
        }
      }
      final saved = await _saveToGallery(path);
      final category = ref.read(categoryProvider);
      final tags = [
        if (category.selectedId != null) category.labelOf(category.selectedId!),
        for (final id in category.guess?.hashtagIds ?? const <String>[])
          category.hashtagLabels[id] ?? '#$id',
      ];
      // References stay until the user resets them; a manual category pin
      // applies to one shot only.
      ref.read(categoryProvider.notifier).clearManual();
      ref.read(coachingProvider.notifier).reset();
      _toast(
        saved
            ? '갤러리에 저장했어요${tags.isEmpty ? '' : '  ·  ${tags.join(' ')}'}'
            : '사진을 저장하지 못했어요',
      );
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

  void _toast(String message) {
    if (!mounted) return;
    _toastTimer?.cancel();
    setState(() => _toastText = message);
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toastText = null);
    });
  }

  /// Only valid once the camera reports its preview size.
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

  Widget _previewStack(
    CameraService camera,
    ReferenceState reference,
    CoachInstruction? instruction,
  ) {
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
        if (camera.isReady) ...[const GridOverlay(), const CenterCrosshair()],
        Align(
          alignment: const Alignment(0, -0.5),
          child: GestureDetector(
            // Debug builds: long-press plays a scripted session.
            onLongPress: kDebugMode
                ? ref.read(coachingProvider.notifier).runDemo
                : null,
            child: instruction == null
                ? const InstructionBubble(text: '사진 감각, 빌려드릴게요')
                : InstructionBubble(
                    text: InstructionText.of(
                      instruction.key,
                      instruction.amount,
                    ),
                    direction: InstructionText.arrowOf(instruction.key),
                    highlight: instruction.aligned,
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
              child: Row(
                children: [
                  if (reference.isEmpty)
                    const SizedBox(width: _topButton)
                  else
                    RoundIconButton(
                      icon: Icons.close,
                      onPressed: _resetReferences,
                      size: _topButton,
                      tooltip: '레퍼런스 초기화',
                    ),
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final camera = ref.watch(cameraServiceProvider);
    final reference = ref.watch(referenceProvider);
    final category = ref.watch(categoryProvider);
    final instruction = ref.watch(coachingProvider);
    ref.listen<CoachInstruction?>(coachingProvider, _onInstruction);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListenableBuilder(
        listenable: camera,
        builder: (context, _) => Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, area) {
                  _publishVisibleCrop(area.biggest, camera);
                  return _previewStack(camera, reference, instruction);
                },
              ),
            ),
            Container(
              color: const Color(0xFF1C1C1E),
              child: CategoryWheel(
                categories: category.categories,
                selectedId: category.selectedId,
                suggestedIds: category.guess?.suggestedIds ?? const [],
                manualId: category.manualId,
                onPin: ref.read(categoryProvider.notifier).pin,
              ),
            ),
            SafeArea(
              top: false,
              child: BottomBar(
                reference: ReferenceThumb(
                  state: reference,
                  onTap: _onReferenceTap,
                ),
                onShutter: camera.isReady ? _capture : null,
                onFlip: camera.canFlip ? camera.flip : null,
                armed: instruction?.aligned ?? false,
                busy: _capturing,
              ),
            ),
          ],
        ),
      ),
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
