// App shell: router + theme. Owned by the team lead.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const _PlaceholderHome()),
    // Feature routes are wired here by the lead as modules land:
    // '/camera' (camera), '/result' (camera), '/debug/pose' (coach), '/debug/scene' (scene)
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

/// Temporary first screen until the camera screen lands. Shows the theme keyword.
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('사진 감각, 빌려드릴게요', style: TextStyle(fontSize: 20)),
      ),
    );
  }
}
