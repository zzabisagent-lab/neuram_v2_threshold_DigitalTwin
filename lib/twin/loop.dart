import 'brain.dart';
import 'telemetry.dart';
import 'twin_params.dart';
import 'world.dart';

/// Outcome of one trial.
class TrialResult {
  final double score; // clamp(1 - dFinal/dInitial, 0, 1)
  final double dInitial;
  final double dFinal;
  final double maxMotor; // max |vL|+|vR| over the trial (0 => never moved)
  const TrialResult(this.score, this.dInitial, this.dFinal, this.maxMotor);
}

/// One closed loop: sense -> brain (pulse/propagate) -> move -> (teach) -> tick.
class ClosedLoop {
  final TwinParams tp;
  final World world;
  final Brain brain;

  ClosedLoop(this.tp, this.world, this.brain);

  /// Single step. Returns (vL, vR). When [learn] is set, the goal-directed teacher
  /// reinforces the synapses that fired on this step's sensing.
  (double, double) stepOnce({required bool learn, double rewardScale = 1.0}) {
    final sn = world.sense();
    if (tlm != null) tlm!.sense(brain.t, sn, world);
    final (vL, vR) = brain.drive(sn);
    world.step(vL, vR);
    if (tlm != null) tlm!.act(brain.t, vL, vR, world);
    if (learn) brain.reward(sn, scale: rewardScale);
    brain.tick();
    return (vL, vR);
  }

  /// Run a trial of [steps] (default stepsPerTrial). Pose must be set on [world]
  /// beforehand. Returns the approach score and the max motor magnitude seen.
  TrialResult runTrial({
    required bool learn,
    int? steps,
    double rewardScale = 1.0,
  }) {
    final n = steps ?? tp.stepsPerTrial;
    final d0 = world.distance;
    var maxMotor = 0.0;
    for (var i = 0; i < n; i++) {
      final (vL, vR) = stepOnce(learn: learn, rewardScale: rewardScale);
      final mag = vL.abs() + vR.abs();
      if (mag > maxMotor) maxMotor = mag;
    }
    final d1 = world.distance;
    final score = (1.0 - d1 / d0).clamp(0.0, 1.0);
    return TrialResult(score, d0, d1, maxMotor);
  }

  /// Advance engine time with no sensing/learning (e.g. a dark, unstimulated
  /// interval). Pruning is evaluated lazily at the end of the interval.
  void darkInterval(int steps) {
    for (var i = 0; i < steps; i++) {
      brain.tick();
    }
  }
}
