import 'dart:convert';
import 'dart:math' as math;

import '../twin/scenarios.dart';
import '../twin/twin_params.dart';

/// Iteration-based threshold campaign on top of the frozen engine + twin.
///
/// Runs the existing twin closed loop (public API only — engine and twin-core
/// learning rules untouched) one *iteration* at a time. "iteration" is an internal
/// learning step (one call = one iteration = [CampaignConfig.dayReps] reinforcement
/// rounds), decoupled from the calendar — the scheduler fires hourly, but the
/// experiment counts iterations, not days. Two phases:
///   - **build**: normal phototaxis reward (approach = reward) — crossed wiring forms.
///   - **reversal**: reward flipped (R7-style conflict) — netA must un-flip.
enum Phase { build, reversal, done }

Phase _phaseFrom(String s) => Phase.values.firstWhere((p) => p.name == s);

/// Pre-registered configuration (§4/§5). Locked before running; never tuned.
class CampaignConfig {
  /// Reinforcement rounds per iteration (each round = one left + one right encounter).
  final int dayReps;

  /// Saturation window: K consecutive iterations of small change.
  final int k;

  /// Saturation threshold on |Δ netA| per iteration.
  final double epsilon;

  /// Global iteration cap (terminate once iteration > maxIterations).
  final int maxIterations;

  /// Strength threshold for a "functional" connection (= engine thetaPrune).
  final double functionalW;

  const CampaignConfig({
    this.dayReps = 8,
    this.k = 3,
    this.epsilon = 0.02,
    this.maxIterations = 30,
    this.functionalW = 0.1,
  });

  Map<String, dynamic> toJson() => {
    'dayReps': dayReps,
    'k': k,
    'epsilon': epsilon,
    'maxIterations': maxIterations,
    'functionalW': functionalW,
  };
}

/// One iteration's recorded metrics.
class IterationMetrics {
  final int iteration;
  final String runAtUtc; // ISO8601 — real wall-clock audit
  final String runAtLocal;
  final Phase phase; // the phase this iteration was *run* in
  final double netA; // signed approach: + approach, - recede
  final double
  deltaDay; // |netA - netA(previous)|; NaN on the very first iteration
  final List<double> w; // [LL, LR, RL, RR]
  final int activeCount;
  final int functionalCount;
  final int formed;
  final int pruned;
  final double cMean;
  final bool saturated;
  final bool done;
  final String? doneReason; // 'saturation' | 'max-iterations'
  final String? transition; // e.g. "build->reversal"

  const IterationMetrics({
    required this.iteration,
    required this.runAtUtc,
    required this.runAtLocal,
    required this.phase,
    required this.netA,
    required this.deltaDay,
    required this.w,
    required this.activeCount,
    required this.functionalCount,
    required this.formed,
    required this.pruned,
    required this.cMean,
    required this.saturated,
    required this.done,
    required this.doneReason,
    required this.transition,
  });

  double get wCrossed => (w[1] + w[2]) / 2; // LR, RL
  double get wUncrossed => (w[0] + w[3]) / 2; // LL, RR

  Map<String, dynamic> toJson() => {
    'iteration': iteration,
    'runAtUtc': runAtUtc,
    'runAtLocal': runAtLocal,
    'phase': phase.name,
    'netA': netA,
    'deltaDay': deltaDay.isNaN ? null : deltaDay,
    'w': {'LL': w[0], 'LR': w[1], 'RL': w[2], 'RR': w[3]},
    'wCrossed': wCrossed,
    'wUncrossed': wUncrossed,
    'activeCount': activeCount,
    'functionalCount': functionalCount,
    'formed': formed,
    'pruned': pruned,
    'cMean': cMean,
    'saturated': saturated,
    'done': done,
    'doneReason': doneReason,
    'transition': transition,
  };

  static const csvHeader =
      'iteration,runAtUtc,phase,netA,deltaDay,wLL,wLR,wRL,wRR,wCrossed,wUncrossed,'
      'activeCount,functionalCount,formed,pruned,cMean,saturated,done,doneReason,transition';

  String csvRow() {
    String n(double v, [int p = 4]) => v.isNaN ? '' : v.toStringAsFixed(p);
    return [
      iteration,
      runAtUtc,
      phase.name,
      n(netA),
      n(deltaDay),
      n(w[0]),
      n(w[1]),
      n(w[2]),
      n(w[3]),
      n(wCrossed),
      n(wUncrossed),
      activeCount,
      functionalCount,
      formed,
      pruned,
      n(cMean),
      saturated,
      done,
      doneReason ?? '',
      transition ?? '',
    ].join(',');
  }

  String oneLine() {
    String s(double v) => (v >= 0 ? '+' : '') + v.toStringAsFixed(3);
    final d = deltaDay.isNaN ? 'n/a' : deltaDay.toStringAsFixed(3);
    return 'iteration=$iteration phase=${phase.name} netA=${s(netA)} Δ=$d '
        'wX=${wCrossed.toStringAsFixed(3)} wU=${wUncrossed.toStringAsFixed(3)} '
        'sat=$saturated done=$done'
        '${doneReason == null ? '' : '($doneReason)'}'
        '${transition == null ? '' : ' [$transition]'}';
  }
}

/// The resumable iteration runner. Owns a [TwinHarness] (one individual, lifetime
/// learning) plus campaign bookkeeping; serializes to/from a single JSON state.
class CampaignRunner {
  final CampaignConfig cfg;
  final TwinParams tp;
  late final TwinHarness h;

  int iteration;
  Phase phase;
  int phaseStartIter;
  String? lastRunAtUtc;
  final List<Map<String, dynamic>>
  history; // {iteration, phase, netA, runAtUtc}
  final List<Map<String, dynamic>> transitions;

  CampaignRunner._(
    this.cfg,
    this.tp,
    this.iteration,
    this.phase,
    this.phaseStartIter,
    this.lastRunAtUtc,
    this.history,
    this.transitions,
  );

  factory CampaignRunner.fresh({CampaignConfig cfg = const CampaignConfig()}) {
    const tp = TwinParams();
    final r = CampaignRunner._(cfg, tp, 0, Phase.build, 1, null, [], []);
    r.h = TwinHarness(tp);
    return r;
  }

  factory CampaignRunner.fromState(
    String stateJson, {
    CampaignConfig cfg = const CampaignConfig(),
  }) {
    final m = jsonDecode(stateJson) as Map<String, dynamic>;
    const tp = TwinParams();
    final r = CampaignRunner._(
      cfg,
      tp,
      m['iteration'] as int,
      _phaseFrom(m['phase'] as String),
      m['phaseStartIter'] as int,
      m['lastRunAtUtc'] as String?,
      (m['history'] as List).cast<Map<String, dynamic>>(),
      (m['transitions'] as List).cast<Map<String, dynamic>>(),
    );
    r.h = TwinHarness(tp);
    r.h.brain.cx.loadFromString(m['connectome'] as String);
    r.h.brain.t = (m['brainT'] as num).toDouble(); // resume the twin clock
    return r;
  }

  List<double> _ws() => [
    h.brain.ll.syn.w,
    h.brain.lr.syn.w,
    h.brain.rl.syn.w,
    h.brain.rr.syn.w,
  ];

  /// Signed net approach: mean over a left-light and right-light probe of
  /// (dInitial - dFinal)/dInitial. Positive = net approach, negative = net
  /// avoidance. Read-only (no learning), so it does not perturb w/c.
  double _netA() {
    double signed(bool leftSide) {
      h.brain.t += TwinHarness.settleTime;
      h.world.setLight(0, TwinHarness.probeDist, on: true);
      h.world.setPose(
        0,
        0,
        math.pi / 2 - (leftSide ? TwinHarness.probeOff : -TwinHarness.probeOff),
      );
      final r = h.loop.runTrial(learn: false);
      return (r.dInitial - r.dFinal) / r.dInitial;
    }

    return (signed(true) + signed(false)) / 2;
  }

  bool _saturated(Phase runPhase) {
    final ser = history
        .where((e) => e['phase'] == runPhase.name)
        .map((e) => (e['netA'] as num).toDouble())
        .toList();
    if (ser.length < cfg.k + 1) return false;
    for (var i = ser.length - cfg.k; i < ser.length; i++) {
      if ((ser[i] - ser[i - 1]).abs() >= cfg.epsilon) return false;
    }
    return true;
  }

  bool get isDone => phase == Phase.done;

  /// Minutes since the last iteration's wall-clock run, or null if none yet.
  double? minutesSinceLastRun(DateTime nowUtc) {
    if (lastRunAtUtc == null) return null;
    final last = DateTime.tryParse(lastRunAtUtc!);
    if (last == null) return null;
    return nowUtc.difference(last).inSeconds / 60.0;
  }

  /// Run exactly one iteration in the current phase, stamp it with wall-clock
  /// time, apply the §5 termination rules, and return the metrics.
  IterationMetrics runOneIteration() {
    final runPhase = phase;
    iteration += 1;
    final nowUtc = DateTime.now().toUtc();
    final nowLocal = DateTime.now();
    final runAtUtc = nowUtc.toIso8601String();
    final runAtLocal = nowLocal.toIso8601String();
    lastRunAtUtc = runAtUtc;

    final wBefore = _ws();
    h.train(cfg.dayReps, reversed: runPhase == Phase.reversal);

    final netA = _netA();
    final wAfter = _ws();

    final edges = [h.brain.ll, h.brain.lr, h.brain.rl, h.brain.rr];
    final active = edges.where((e) => e.syn.active).length;
    final functional = wAfter.where((w) => w >= cfg.functionalW).length;
    var formed = 0, pruned = 0;
    for (var i = 0; i < 4; i++) {
      final b = wBefore[i] >= cfg.functionalW;
      final a = wAfter[i] >= cfg.functionalW;
      if (!b && a) formed++;
      if (b && !a) pruned++;
    }
    final cMean = edges.map((e) => e.syn.c).reduce((x, y) => x + y) / 4;

    final prevNetA = history.isEmpty
        ? double.nan
        : (history.last['netA'] as num).toDouble();
    final delta = prevNetA.isNaN ? double.nan : (netA - prevNetA).abs();
    history.add({
      'iteration': iteration,
      'phase': runPhase.name,
      'netA': netA,
      'runAtUtc': runAtUtc,
    });

    final sat = _saturated(runPhase);
    final overCap = iteration > cfg.maxIterations; // global ceiling (§5.2)

    String? transition;
    String? doneReason;
    var done = false;

    if (overCap) {
      // Global cap terminates regardless of phase.
      doneReason = 'max-iterations';
      done = true;
      transitions.add({
        'from': runPhase.name,
        'to': 'done',
        'iteration': iteration,
        'reason': 'max-iterations',
      });
      phase = Phase.done;
    } else if (runPhase == Phase.build && sat) {
      transition = 'build->reversal';
      transitions.add({
        'from': 'build',
        'to': 'reversal',
        'iteration': iteration,
        'reason': 'saturation',
      });
      phase = Phase.reversal;
      phaseStartIter = iteration + 1;
    } else if (runPhase == Phase.reversal && sat) {
      transition = 'reversal->done';
      doneReason = 'saturation';
      done = true;
      transitions.add({
        'from': 'reversal',
        'to': 'done',
        'iteration': iteration,
        'reason': 'saturation',
      });
      phase = Phase.done;
    }

    return IterationMetrics(
      iteration: iteration,
      runAtUtc: runAtUtc,
      runAtLocal: runAtLocal,
      phase: runPhase,
      netA: netA,
      deltaDay: delta,
      w: wAfter,
      activeCount: active,
      functionalCount: functional,
      formed: formed,
      pruned: pruned,
      cMean: cMean,
      saturated: sat,
      done: done,
      doneReason: doneReason,
      transition: transition,
    );
  }

  String toStateJson() => const JsonEncoder.withIndent('  ').convert({
    'version': 2,
    'iteration': iteration,
    'phase': phase.name,
    'phaseStartIter': phaseStartIter,
    'lastRunAtUtc': lastRunAtUtc,
    'history': history,
    'transitions': transitions,
    'brainT': h.brain.t,
    'connectome': h.brain.cx.toJsonString(),
    'config': cfg.toJson(),
  });
}
