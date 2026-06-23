/// Twin parameters (§7), frozen before execution and not tuned. The engine's §6
/// parameters are never touched (the engine is vendored read-only).
class TwinParams {
  /// Left/right sensor splay from heading (radians).
  final double sensorAngle;

  /// Peak light intensity and inverse-square-ish distance falloff.
  final double imax;
  final double falloff;

  /// Sensor intensity -> input-pulse magnitude. With imax=1, a bright sensor
  /// yields x = sensorGain = 0.7 >= thetaFire (0.5), so near light can fire.
  final double sensorGain;

  /// Differential-drive gains.
  final double turnGain;
  final double moveGain;

  /// Engine-time advanced per loop step. Must be < firingWindow (~0.899) so that
  /// sustained illumination accumulates firedCount past sMin.
  final double dtEngine;

  /// Teacher offset within a step (< firingWindow) so eligibility is still fresh.
  final double teachDelta;

  final int stepsPerTrial;
  final int trials;

  /// Dark steps for the decay scenario: guarantees silence >= 3*tauE.
  final int darkSteps;

  final int seed;

  const TwinParams({
    this.sensorAngle = 0.5,
    this.imax = 1.0,
    this.falloff = 0.01,
    this.sensorGain = 0.7,
    this.turnGain = 0.3,
    this.moveGain = 1.0,
    this.dtEngine = 0.1,
    this.teachDelta = 0.02,
    this.stepsPerTrial = 60,
    this.trials = 30,
    this.darkSteps = 30,
    this.seed = 42,
  });
}
