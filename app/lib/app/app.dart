// App shell: router + theme. Owned by the team lead.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/camera/camera_screen.dart';
import '../features/camera/result_screen.dart';
import '../features/camera/shot_state.dart';
import 'theme.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const CameraScreen()),
    GoRoute(
      path: '/result',
      builder: (context, state) =>
          ResultScreen(shot: state.extra! as ShotResult),
    ),
    // Debug routes are added here by the lead as modules land:
    // '/debug/pose' (coach), '/debug/scene' (scene)
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
