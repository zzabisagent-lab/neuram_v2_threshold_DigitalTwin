import 'dart:convert';
import 'dart:math' as math;

import '../twin/scenarios.dart';
import '../twin/twin_params.dart';

/// Daily threshold-campaign on top of the frozen engine + twin.
///
/// It drives the existing twin closed loop (via its public API only — the engine
/// and the twin core learning rules are untouched) one *day* at a time, through
/// two phases:
///   - **build**: normal phototaxis reward (approach = reward) — the crossed
///     (contralateral) wiring forms gradually.
///   - **reversal**: the reward is flipped (the previously-rewarded approach
///     direction is punished) — an R7-style conflict; netA must un-flip.
/// The point is to expose, day by day, whether the threshold model's transition
/// is a single step (old single-variable model) or **multi-day gradual**.
enum Phase { build, reversal, done }

Phase _phaseFrom(String s) => Phase.values.firstWhere((p) => p.name == s);

/// Pre-registered configuration (§4/§5). Locked before running; never tuned.
class CampaignConfig {
  /// Reinforcement rounds per day (each round = one left + one right encounter).
  final int dayReps;

  /// Saturation window: K consecutive days of small change.
  final int k;

  /// Saturation threshold on |Δ netA| per day.
  final double epsilon;

  /// Safety cap per phase (prevents an unbounded loop).
  final int maxDaysPerPhase;

  /// Strength threshold for a "functional" connection (= engine thetaPrune).
  final double functionalW;

  const CampaignConfig({
    this.dayReps = 8,
    this.k = 3,
    this.epsilon = 0.02,
    this.maxDaysPerPhase = 30,
    this.functionalW = 0.1,
  });

  Map<String, dynamic> toJson() => {
    'dayReps': dayReps,
    'k': k,
    'epsilon': epsilon,
    'maxDaysPerPhase': maxDaysPerPhase,
    'functionalW': functionalW,
  };
}

/// One day's recorded metrics.
class DailyMetrics {
  final int day;
  final Phase phase; // the phase this day was *run* in
  final double netA; // signed approach: + approach, - recede
  final double deltaDay; // |netA - netA(yesterday)|; NaN on the very first day
  final List<double> w; // [LL, LR, RL, RR]
  final int activeCount; // engine active flags
  final int functionalCount; // w >= functionalW
  final int formed; // functional crossings up today
  final int pruned; // functional crossings down today
  final double cMean; // mean consolidation
  final bool saturated; // this phase reached equilibrium today
  final bool done; // campaign finished today
  final String? transition; // e.g. "build->reversal"

  const DailyMetrics({
    required this.day,
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
    required this.transition,
  });

  double get wCrossed => (w[1] + w[2]) / 2; // LR, RL
  double get wUncrossed => (w[0] + w[3]) / 2; // LL, RR

  Map<String, dynamic> toJson() => {
    'day': day,
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
    'transition': transition,
  };

  static const csvHeader =
      'day,phase,netA,deltaDay,wLL,wLR,wRL,wRR,wCrossed,wUncrossed,'
      'activeCount,functionalCount,formed,pruned,cMean,saturated,done,transition';

  String csvRow() {
    String n(double v, [int p = 4]) => v.isNaN ? '' : v.toStringAsFixed(p);
    return [
      day,
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
      transition ?? '',
    ].join(',');
  }

  String oneLine() {
    String s(double v) => (v >= 0 ? '+' : '') + v.toStringAsFixed(3);
    final d = deltaDay.isNaN ? 'n/a' : deltaDay.toStringAsFixed(3);
    return 'day=$day phase=${phase.name} netA=${s(netA)} Δ=$d '
        'wX=${wCrossed.toStringAsFixed(3)} wU=${wUncrossed.toStringAsFixed(3)} '
        'sat=$saturated done=$done${transition == null ? '' : ' [$transition]'}';
  }
}

/// The resumable daily runner. Owns a [TwinHarness] (one individual, lifetime
/// learning) plus campaign bookkeeping; serializes to/from a single JSON state.
class CampaignRunner {
  final CampaignConfig cfg;
  final TwinParams tp;
  late final TwinHarness h;

  int day;
  Phase phase;
  int phaseStartDay;
  final List<Map<String, dynamic>> history; // {day, phase, netA}
  final List<Map<String, dynamic>> transitions;

  CampaignRunner._(
    this.cfg,
    this.tp,
    this.day,
    this.phase,
    this.phaseStartDay,
    this.history,
    this.transitions,
  );

  factory CampaignRunner.fresh({CampaignConfig cfg = const CampaignConfig()}) {
    const tp = TwinParams();
    final r = CampaignRunner._(cfg, tp, 0, Phase.build, 1, [], []);
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
      m['day'] as int,
      _phaseFrom(m['phase'] as String),
      m['phaseStartDay'] as int,
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
  /// avoidance (recede). Read-only (no learning), so it does not perturb w/c.
  double _netA() {
    double signed(bool leftSide) {
      h.brain.t += TwinHarness.settleTime; // clear residual activation
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

  /// True once the campaign has already finished (idempotent guard for re-runs).
  bool get isDone => phase == Phase.done;

  /// Run exactly one day in the current phase, apply the §5 saturation rule, and
  /// return the day's metrics. Does nothing destructive if already done.
  DailyMetrics runOneDay() {
    final runPhase = phase;
    day += 1;
    final wBefore = _ws();

    // a day of learning in the current phase (reward flipped in reversal)
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
    history.add({'day': day, 'phase': runPhase.name, 'netA': netA});

    final sat = _saturated(runPhase);
    final daysInPhase = day - phaseStartDay + 1;
    final capped = daysInPhase >= cfg.maxDaysPerPhase;

    String? transition;
    var done = false;
    if (runPhase == Phase.build && (sat || capped)) {
      transition = 'build->reversal';
      transitions.add({
        'from': 'build',
        'to': 'reversal',
        'day': day,
        'reason': sat ? 'saturated' : 'maxDaysCap',
      });
      phase = Phase.reversal;
      phaseStartDay = day + 1; // reversal begins next day
    } else if (runPhase == Phase.reversal && (sat || capped)) {
      transition = 'reversal->done';
      transitions.add({
        'from': 'reversal',
        'to': 'done',
        'day': day,
        'reason': sat ? 'saturated' : 'maxDaysCap',
      });
      phase = Phase.done;
      done = true;
    }

    return DailyMetrics(
      day: day,
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
      transition: transition,
    );
  }

  String toStateJson() => const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'day': day,
    'phase': phase.name,
    'phaseStartDay': phaseStartDay,
    'history': history,
    'transitions': transitions,
    'brainT': h.brain.t,
    'connectome': h.brain.cx.toJsonString(),
    'config': cfg.toJson(),
  });
}
