// Cross-module wiring. Owned by the team lead.
// Each provider starts with a Fake and is switched to the real module when it lands.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/contracts.dart';
import '../features/camera/camera_service.dart';
import '../features/camera/fakes/fake_reference_analyzer.dart';

/// Live camera frames for pose (Eungyu) and scene (Seojun) analysis.
final frameBusProvider = Provider<FrameBus>(
  (ref) => ref.watch(cameraServiceProvider),
);

/// TODO(lead): switch to Eungyu's ReferenceAnalyzer when feat/coach lands.
final referenceAnalyzerProvider = Provider<ReferenceAnalyzer>(
  (ref) => FakeReferenceAnalyzer(),
);
