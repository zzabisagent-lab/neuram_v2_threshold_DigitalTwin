import 'dart:math' as math;

import 'brain.dart';
import 'loop.dart';
import 'twin_params.dart';
import 'world.dart';

/// Shared, deterministic scenario harness used by both the runner and the bench.
/// It wires a [World], a [Brain] and a [ClosedLoop] together and exposes the
/// embodied experiments (learning / decay / reversal / persistence / threshold-①).
///
/// The poses below are *geometry* (not §7 parameters): a close teaching encounter
/// where firing is reliable, and a probe at a distance where the approach amount
/// in stepsPerTrial scales with steering strength (so the score is graded, not
/// all-or-nothing).
class TwinHarness {
  final TwinParams tp;
  late final World world;
  late final Brain brain;
  late final ClosedLoop loop;

  static const double teachDist = 3.0;
  static const double teachOff = 0.3;
  static const double probeDist = 18.0;
  static const double probeOff = 0.3;
  static const double farDist = 60.0; // T-①: too far to fire
  static const double nearDist = 4.0; // T-①: near, fires

  TwinHarness(this.tp, {Brain? brain}) {
    this.brain = brain ?? Brain(tp);
    world = World(tp);
    loop = ClosedLoop(tp, this.world, this.brain);
  }

  void _teachPose(bool leftSide) {
    world.setLight(0, teachDist, on: true);
    world.setPose(0, 0, math.pi / 2 - (leftSide ? teachOff : -teachOff));
  }

  void _probePose(bool leftSide, double dist, {bool on = true}) {
    world.setLight(0, dist, on: on);
    world.setPose(0, 0, math.pi / 2 - (leftSide ? probeOff : -probeOff));
  }

  /// One reinforcement presentation on the given side (forward or reversed goal).
  void encounter(bool leftSide, {bool reversed = false}) {
    _teachPose(leftSide);
    brain.presentOnce(world.sense(), reversed: reversed);
  }

  /// Average approach score over a left-light and a right-light probe (no learning),
  /// so the measurement is symmetric in the two crossed synapses.
  double probeScore({double dist = probeDist}) =>
      (_probe(true, dist).score + _probe(false, dist).score) / 2;

  /// Let the neural state rest before a fresh probe so leftover activation `a`
  /// from prior stimulation decays (>> tauA). Without this, residual activation
  /// would spuriously fire on the first probe step regardless of light level.
  static const double settleTime = 2.0; // >> tauA (0.3)
  void _settle() => brain.t += settleTime;

  TrialResult _probe(bool leftSide, double dist, {bool on = true}) {
    _settle();
    _probePose(leftSide, dist, on: on);
    return loop.runTrial(learn: false);
  }

  /// Immediate behavioral response over a short window (~1 engine-time unit),
  /// before a pruned path can structurally re-form and rescue behavior. Averaged
  /// over both sides. This is the faithful read-out of the pruned (reverted) state.
  static const int responseSteps = 10;
  double immediateResponse({double dist = probeDist}) {
    _settle();
    _probePose(true, dist);
    final l = loop.runTrial(learn: false, steps: responseSteps).score;
    _settle();
    _probePose(false, dist);
    final r = loop.runTrial(learn: false, steps: responseSteps).score;
    return (l + r) / 2;
  }

  /// Probe once and report (score, maxMotor) — used by T-①.
  ({double score, double maxMotor}) probe(
    bool leftSide,
    double dist, {
    bool on = true,
  }) => (() {
    final r = _probe(leftSide, dist, on: on);
    return (score: r.score, maxMotor: r.maxMotor);
  })();

  /// Scenario A: probe (no learning) then reinforce both sides, [trials] times.
  /// Returns the per-trial approach-score curve.
  List<double> learnCurve(int trials) {
    final curve = <double>[];
    for (var k = 0; k < trials; k++) {
      curve.add(probeScore());
      encounter(true);
      encounter(false);
    }
    return curve;
  }

  /// Reinforce both sides [n] times with no probing (just build strength).
  void train(int n, {bool reversed = false}) {
    for (var k = 0; k < n; k++) {
      encounter(true, reversed: reversed);
      encounter(false, reversed: reversed);
    }
  }

  /// Advance a dark, unstimulated interval then lazily prune. Returns pruned names.
  List<String> darkAndPrune(int steps) {
    loop.darkInterval(steps);
    return brain.pruneAll();
  }

  /// Convenience accessors for the crossed/uncrossed strengths.
  double get wCrossed => (brain.lr.syn.w + brain.rl.syn.w) / 2;
  double get wUncrossed => (brain.ll.syn.w + brain.rr.syn.w) / 2;
}
