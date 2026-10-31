// Module interfaces. Only the team lead edits this file. Implementations live in features/. See AGENTS.md §4.
import 'models.dart';

/// Taeho. Frames arriving while busy are dropped (backpressure is the consumer's job).
abstract class FrameBus {
  Stream<CameraFrame> get frames;
}

/// Eungyu. ML Kit + sensors, at most 15 per second.
abstract class PoseSource {
  Stream<PoseFrame> poses(FrameBus bus);
}

/// Eungyu.
abstract class CoachEngine {
  CoachInstruction update(PoseFrame frame, TargetComposition target);
  void reset();
}

/// Eungyu. Throws [NoPersonException] when no person is found.
abstract class ReferenceAnalyzer {
  Future<TargetComposition> analyze(String imagePath);
}

/// Eungyu, Should.
abstract class WhoMoves {
  Who decide(CameraFrame live, String referencePath, double subjectXError);
}

/// Seojun. The UI calls this every ~3 seconds.
abstract class SceneClassifier {
  Future<void> warmUp();
  Future<CategoryGuess> classify(CameraFrame frame);
}

/// Seojun.
abstract class CompositionLibrary {
  Future<void> load();
  List<CategoryInfo> get categories;
  TargetComposition targetFor(String categoryId);
}

/// Seojun, Should.
abstract class ModelManager {
  /// Returns the path of the model file to use.
  Future<String> ensureBest();
  String get activeVariant;
  Stream<double> get downloadProgress;
}

/// Taeho.
abstract class FeedbackService {
  void announce(CoachInstruction instruction, String lang);
  void proximity(double error);
  void aligned();
  void stop();
}
