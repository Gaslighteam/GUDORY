import '../../../core/contracts.dart';
import '../../../core/models.dart';

/// Stand-in until the coach module's analyzer lands. Accepts any photo.
class FakeReferenceAnalyzer implements ReferenceAnalyzer {
  @override
  Future<TargetComposition> analyze(String imagePath) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return const TargetComposition(
      framing: Framing.kneeUp,
      personHeightRatio: 0.72,
      personCenterX: 0.5,
      personCenterY: 0.28,
      source: 'reference',
    );
  }
}
