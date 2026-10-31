import '../../../core/contracts.dart';
import '../../../core/models.dart';

/// Stand-in until the coach module's analyzer lands. Accepts any photo.
class FakeReferenceAnalyzer implements ReferenceAnalyzer {
  @override
  Future<TargetComposition> analyze(String imagePath) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return const TargetComposition(
      personHeightRatio: 0.6,
      personCenterX: 0.5,
      personCenterY: 0.6,
      source: 'reference',
    );
  }
}
