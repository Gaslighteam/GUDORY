// Contract data types. Only the team lead edits this file. See AGENTS.md §4.
import 'package:camera/camera.dart';

enum CoachAxis { level, distance, horizontal, height }

enum Who { camera, subject }

enum InstructionKey {
  holdPhoneUpright, // level: hold the phone upright
  stepBack, // distance (photographer)
  stepForward,
  stepLeft, // horizontal (photographer, body-relative)
  stepRight,
  subjectLeft, // horizontal (subject) — Should
  subjectRight,
  phoneUp, // height
  phoneDown,
  oppositeWay, // error growing: "the other way"
  fitWholeBody, // fit the whole body in frame
  noPerson, // no person visible
  aligned, // aligned: hold still
  turnLandscape, // target orientation differs from how the phone is held
  turnPortrait,
  addReference, // custom mode with no reference
}

/// 추천 (recommend) or 맞춤 (custom, reference-driven).
enum ShootMode { recommend, custom }

/// How the phone is held for the shot (the UI itself stays portrait).
enum ShotOrientation { portrait, landscape }

/// Normalized 0~1 coordinates in shot space (the frame as the saved photo
/// will look: portrait, or landscape when the phone is held sideways).
class Landmark {
  const Landmark({required this.x, required this.y, required this.visibility});
  final double x;
  final double y;
  final double visibility;
}

class PoseFrame {
  const PoseFrame({
    required this.landmarks,
    required this.imageWidth,
    required this.imageHeight,
    this.orientation = ShotOrientation.portrait,
    required this.rollDeg,
    required this.pitchDeg,
    required this.at,
  });

  /// 33 points in ML Kit PoseLandmarkType order. null when no person.
  final List<Landmark>? landmarks;

  /// In shot space (landscape: width > height).
  final int imageWidth;
  final int imageHeight;

  /// From the accelerometer, hysteresis 45°/60°.
  final ShotOrientation orientation;

  /// Sensors, relative to the shot orientation; level = 0, 0.
  final double rollDeg;
  final double pitchDeg;
  final DateTime at;
}

class TargetComposition {
  const TargetComposition({
    required this.personHeightRatio,
    required this.personCenterX,
    required this.personCenterY,
    this.horizonY,
    this.orientation = ShotOrientation.portrait,
    this.tolHeight = 0.10,
    this.tolX = 0.08,
    this.tolY = 0.08,
    this.tolRollDeg = 3,
    required this.source,
  });

  /// (top of head ~ ankles) / frame height, 0~1.
  final double personHeightRatio;

  /// Center x of shoulders+hips, 0~1.
  final double personCenterX;

  /// Hip center y, 0~1.
  final double personCenterY;
  final double? horizonY;
  final ShotOrientation orientation;
  final double tolHeight;
  final double tolX;
  final double tolY;
  final double tolRollDeg;

  /// `'reference'`, `'recommend:<1-5>'` or `'fallback'`.
  final String source;

  static const fallback = TargetComposition(
    personHeightRatio: 0.6,
    personCenterX: 0.5,
    personCenterY: 0.58,
    source: 'fallback',
  );
}

class Recommendation {
  const Recommendation({
    required this.target,
    required this.neighbors,
    required this.modelVariant,
  });

  final TargetComposition target;

  /// Photos behind the target (0 = fallback median only, no CLIP).
  final int neighbors;

  /// 'q8' | 'fp16' | 'none'
  final String modelVariant;
}

class CoachInstruction {
  const CoachInstruction({
    required this.key,
    required this.axis,
    required this.who,
    required this.amount,
    required this.error,
    required this.aligned,
    required this.errors,
  });

  final InstructionKey key;
  final CoachAxis? axis;
  final Who who;

  /// Steps or fists, in 0.5 units, minimum 0.5.
  final double amount;

  /// Normalized error of the active axis (<= 1.0 means aligned).
  final double error;

  /// All four axes aligned.
  final bool aligned;

  /// For debug overlay.
  final Map<CoachAxis, double> errors;
}

class CameraFrame {
  const CameraFrame({
    required this.image,
    required this.sensorOrientation,
    required this.isFrontCamera,
  });

  final CameraImage image;
  final int sensorOrientation;
  final bool isFrontCamera;
}

class NoPersonException implements Exception {
  const NoPersonException([this.message = '사진에서 사람을 찾지 못했어요']);
  final String message;
  @override
  String toString() => message;
}
