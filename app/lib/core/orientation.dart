// Shot orientation rule (AGENTS.md §4), shared by PoseSource (coach) and the
// portrait-locked UI (camera) so the two never drift. Pure Dart: feed it the
// accelerometer's x / y (m/s²). Only the team lead edits this file.
import 'dart:math' as math;

import 'models.dart';

/// |roll| above this → landscape.
const double landscapeEnterDeg = 60;

/// |roll| below this → back to portrait.
const double portraitEnterDeg = 45;

/// Below this in-plane gravity (m/s²) the phone is lying flat and roll is
/// meaningless; the previous decision is kept.
const double flatGuard = 4;

/// How the phone is held.
class HeldOrientation {
  const HeldOrientation(this.orientation, this.quarterTurns);

  static const portrait = HeldOrientation(ShotOrientation.portrait, 0);

  final ShotOrientation orientation;

  /// Clockwise quarter turns that bring the scene upright:
  /// 1 = phone turned counter-clockwise (top to the left),
  /// -1 = clockwise (top to the right), 0 = portrait.
  final int quarterTurns;

  bool get isLandscape => orientation == ShotOrientation.landscape;

  @override
  bool operator ==(Object other) =>
      other is HeldOrientation &&
      other.orientation == orientation &&
      other.quarterTurns == quarterTurns;

  @override
  int get hashCode => Object.hash(orientation, quarterTurns);
}

/// Device roll in degrees from upright portrait. **+ = top tilted to the
/// left** (counter-clockwise), − = to the right. ±90 = held sideways.
double accelRollDeg(double ax, double ay) => math.atan2(ax, ay) * 180 / math.pi;

/// False while the phone lies flat: roll is meaningless then.
/// Use for `PoseFrame.rollReliable`.
bool isRollReliable(double ax, double ay) =>
    math.sqrt(ax * ax + ay * ay) >= flatGuard;

/// True when the phone is too flat for a reliable roll.
bool isFlat(double ax, double ay) => !isRollReliable(ax, ay);

/// Next orientation with 60° / 45° hysteresis. Returns [current] unchanged
/// while the phone is flat or inside the hysteresis band.
HeldOrientation nextHeldOrientation(
  HeldOrientation current,
  double ax,
  double ay,
) {
  if (isFlat(ax, ay)) return current;
  final roll = accelRollDeg(ax, ay);
  final magnitude = roll.abs();
  if (!current.isLandscape && magnitude > landscapeEnterDeg) {
    return HeldOrientation(ShotOrientation.landscape, roll > 0 ? 1 : -1);
  }
  if (current.isLandscape && magnitude < portraitEnterDeg) {
    return HeldOrientation.portrait;
  }
  // Flipped straight from one landscape side to the other.
  if (current.isLandscape &&
      magnitude > landscapeEnterDeg &&
      (roll > 0 ? 1 : -1) != current.quarterTurns) {
    return HeldOrientation(ShotOrientation.landscape, roll > 0 ? 1 : -1);
  }
  return current;
}

/// Roll relative to the shot orientation (`PoseFrame.rollDeg`): 0 = level.
/// Portrait: the device roll. Landscape: measured from ±90°.
double levelRollDeg(double deviceRollDeg, HeldOrientation held) =>
    switch (held.quarterTurns) {
      1 => deviceRollDeg - 90,
      -1 => deviceRollDeg + 90,
      _ => deviceRollDeg,
    };
