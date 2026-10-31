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

/// Seojun. The UI calls this every ~3 s in recommend mode.
abstract class Recommender {
  /// Loads recommend.json + CLIP.
  Future<void> warmUp();

  /// [level] 1~5 (1 = person largest, 5 = background largest).
  /// Never throws: falls back to the level median.
  Future<Recommendation> recommend(
    CameraFrame frame,
    int level,
    ShotOrientation orientation,
  );
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
  void proximity(double error);
  void aligned();
  void stop();
}
