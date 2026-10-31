// App shell: router + theme. Owned by the team lead.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/camera/camera_screen.dart';
import '../features/tutorial/tutorial_screen.dart';
import 'debug_pose_route.dart';
import 'theme.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const CameraScreen()),
    GoRoute(
      path: '/tutorial',
      builder: (context, state) => const TutorialScreen(),
    ),
    // Debug routes are added here by the lead as modules land.
    GoRoute(
      path: '/debug/pose',
      builder: (context, state) => const DebugPoseRoute(),
    ),
  ],
);

class GudoryApp extends StatelessWidget {
  const GudoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '구도리',
      theme: buildTheme(),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
