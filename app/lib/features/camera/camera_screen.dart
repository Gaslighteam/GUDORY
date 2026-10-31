import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/theme.dart';
import 'camera_service.dart';
import 'shot_state.dart';
import 'widgets/controls.dart';
import 'widgets/instruction_bubble.dart';
import 'widgets/overlays.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  bool _capturing = false;

  CameraService get _camera => ref.read(cameraServiceProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _camera.start();
  }

  @override
  void dispose() {
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

  Future<void> _capture() async {
    if (_capturing || !_camera.isReady) return;
    setState(() => _capturing = true);
    try {
      final file = await _camera.takePicture();
      final saved = await _saveToGallery(file.path);
      final reference = ref.read(referenceProvider);
      final category = ref.read(categoryProvider);
      final shot = ShotResult(
        path: file.path,
        referencePath: reference.status == ReferenceStatus.set
            ? reference.path
            : null,
        categoryId: category.selectedId,
        hashtagIds: category.guess?.hashtagIds ?? const [],
        savedToGallery: saved,
      );
      ref.read(lastShotProvider.notifier).set(shot);
      // A reference and a manual category apply to one shot only.
      ref.read(referenceProvider.notifier).clear();
      ref.read(categoryProvider.notifier).clearManual();
      if (mounted) context.push('/result', extra: shot);
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

  Future<void> _pickReference() async {
    final error = await ref.read(referenceProvider.notifier).pick();
    if (error != null) _toast(error);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    final camera = ref.watch(cameraServiceProvider);
    final reference = ref.watch(referenceProvider);
    final category = ref.watch(categoryProvider);
    final lastShot = ref.watch(lastShotProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListenableBuilder(
        listenable: camera,
        builder: (context, _) => Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Preview(camera: camera, onRetry: camera.start),
                  if (camera.isReady) ...[
                    const GridOverlay(),
                    const CenterCrosshair(),
                  ],
                  // TODO(lead): drive from CoachEngine at integration 1 (22:00).
                  const Align(
                    alignment: Alignment(0, -0.55),
                    child: InstructionBubble(text: '사진 감각, 빌려드릴게요'),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          const SizedBox(width: 48),
                          Expanded(
                            child: Center(
                              child: ReferencePill(
                                state: reference,
                                onAdd: _pickReference,
                                onClear: ref
                                    .read(referenceProvider.notifier)
                                    .clear,
                              ),
                            ),
                          ),
                          RoundIconButton(
                            icon: switch (camera.flashMode) {
                              FlashMode.auto => Icons.flash_auto,
                              FlashMode.always => Icons.flash_on,
                              _ => Icons.flash_off,
                            },
                            onPressed: camera.isReady
                                ? camera.cycleFlash
                                : null,
                            tooltip: '플래시',
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 16,
                    child: Center(
                      child: ZoomChips(
                        levels: camera.isReady ? camera.zoomPresets : const [],
                        selected: camera.zoom,
                        onSelect: camera.setZoom,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: Colors.black.withValues(alpha: 0.85),
              child: CategoryChips(
                categories: category.categories,
                selectedId: category.selectedId,
                suggestedIds: category.guess?.suggestedIds ?? const [],
                manualId: category.manualId,
                onTap: ref.read(categoryProvider.notifier).tap,
              ),
            ),
            SafeArea(
              top: false,
              child: BottomBar(
                thumbnailPath: lastShot?.path,
                onThumbnail: lastShot == null
                    ? null
                    : () => context.push('/result', extra: lastShot),
                onShutter: camera.isReady ? _capture : null,
                onFlip: camera.canFlip ? camera.flip : null,
                armed: false,
                busy: _capturing,
              ),
            ),
          ],
        ),
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
