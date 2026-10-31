// Hosts Eungyu's DebugPosePage: starts the shared camera and owns the
// PoseSource it feeds. Owned by the team lead.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/camera/camera_service.dart';
import '../features/coach/debug_pose_page.dart';
import '../features/coach/pose_source.dart';

class DebugPoseRoute extends ConsumerStatefulWidget {
  const DebugPoseRoute({super.key});

  @override
  ConsumerState<DebugPoseRoute> createState() => _DebugPoseRouteState();
}

class _DebugPoseRouteState extends ConsumerState<DebugPoseRoute> {
  // One stream per instance, so this page gets its own source.
  final _source = MlKitPoseSource();
  late final CameraService _camera = ref.read(cameraServiceProvider);

  @override
  void initState() {
    super.initState();
    _camera.start();
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _camera,
    builder: (context, _) {
      final controller = _camera.controller;
      if (controller == null || !_camera.isReady) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(title: const Text('자세 좌표 확인')),
          body: Center(
            child: Text(
              _camera.error == null
                  ? '카메라를 준비하고 있어요'
                  : '카메라 오류: ${_camera.error}',
            ),
          ),
        );
      }
      return DebugPosePage(
        controller: controller,
        frameBus: _camera,
        poseSource: _source,
      );
    },
  );
}
