import 'package:flutter/material.dart';

import 'debug_scene_page.dart';

/// Standalone Step 1 entry point. No shared router or application imports.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const asset = String.fromEnvironment('CLIP_TEST_ASSET');
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const DebugScenePage(assetPath: asset == '' ? null : asset),
    ),
  );
}
