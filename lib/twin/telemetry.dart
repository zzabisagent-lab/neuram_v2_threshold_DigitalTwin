import 'dart:convert';
import 'dart:math' as math;

import '../engine/params.dart';
import '../engine/synapse.dart';
import 'world.dart';

/// Event-driven telemetry emission for the twin (NDJSON, one JSON object per line).
///
/// **Passive observation.** The engine computes every time decay lazily, at the
/// moment a synapse is *touched* by an event; an idle synapse costs nothing. A
/// periodic poll would have to touch the state to read it, so the act of observing
/// would wake the engine. This emitter therefore never initiates a read: every
/// emission happens at a moment the twin was already going to touch that state, and
/// reports the value the engine itself produced there. Quiet intervals are silent in
/// the stream — that silence is the visible evidence of the zero-idle principle, not
/// a gap in the instrumentation.
///
/// **No transport knowledge.** This writes NDJSON lines to a [StringSink] (stdout in
/// the runner) and nothing else. There is no socket, screen or file logic anywhere in
/// `lib/twin/`, so the same code runs unchanged on a server, on a robot, or on a
/// phone; carrying the lines elsewhere is somebody else's job.
///
/// **Off by default.** [tlm] is null unless the runner installs a sink, and every
/// call site is guarded by a single null check, so an uninstrumented run pays one
/// branch per event site and nothing more.
Telemetry? tlm;

/// The four candidate synapses, in a stable order for `w` maps.
const List<String> synIds = ['LL', 'LR', 'RL', 'RR'];

class Telemetry {
  final StringSink _out;

  int _seq = 0;
  int _nFire = 0;
  int _nPlast = 0;
  int _nForm = 0;
  int _nPrune = 0;

  final Stopwatch _wall = Stopwatch();

  Telemetry(this._out);

  int get seq => _seq;

  /// Emit one NDJSON line. `seq`, `t` and `ev` always lead the object, in that
  /// order; doubles are serialized by Dart's shortest round-trip representation and
  /// are never rounded, so a stream can be replayed bit-for-bit.
  void _line(double t, String ev, Map<String, Object?> fields) {
    final m = <String, Object?>{'seq': _seq++, 't': t, 'ev': ev};
    m.addAll(fields);
    _out.writeln(jsonEncode(m));
  }

  // --- run / trial boundaries ------------------------------------------------

  void runStart({
    required String engineSha,
    required String twinSha,
    required int seed,
    required String scenario,
    required Params params,
    required Map<String, Object?> twinParams,
    required int nTrials,
  }) {
    _wall.start();
    _line(0.0, 'run.start', {
      'engineSha': engineSha,
      'twinSha': twinSha,
      'seed': seed,
      'scenario': scenario,
      'params': {
        'wMax': params.wMax,
        'thetaFire': params.thetaFire,
        'tauA': params.tauA,
        'tauE': params.tauE,
        'thetaE': params.thetaE,
        'sMin': params.sMin,
        'etaBase': params.etaBase,
        'tauC': params.tauC,
        'thetaForm': params.thetaForm,
        'tauForm': params.tauForm,
        'thetaPrune': params.thetaPrune,
        'firingWindow': params.firingWindow,
      },
      'twinParams': twinParams,
      'nTrials': nTrials,
    });
  }

  void trialStart(double t, int trial) =>
      _line(t, 'trial.start', {'trial': trial});

  /// [score] is null for a reinforcement-only round, which runs no scored probe.
  void trialEnd(double t, int trial, double? score, Map<String, double> w) =>
      _line(t, 'trial.end', {'trial': trial, 'score': score, 'w': w});

  void runEnd(double t, Map<String, double> finalW) => _line(t, 'run.end', {
    'nEvents': _seq + 1, // this line included
    'nFire': _nFire,
    'nPlast': _nPlast,
    'nForm': _nForm,
    'nPrune': _nPrune,
    'finalW': finalW,
    'wallMs': _wall.elapsedMilliseconds,
  });

  // --- layer 1: stimulus -----------------------------------------------------

  /// The sensing the twin just performed. Emitted where the twin already called
  /// [World.sense]; it does not sense again.
  void sense(double t, Sensors sn, World world) => _line(t, 'sense', {
    'sL': sn.left,
    'sR': sn.right,
    'light': {'x': world.lightX, 'y': world.lightY},
  });

  // --- layer 2: engine internals --------------------------------------------

  /// Record an input event that the twin just delivered to [s] at time [t].
  ///
  /// [tLast0] and [active0] are the synapse's timestamps *before* the input, read
  /// as plain fields (a field read is not a touch). `e` is the eligibility of the
  /// synapse's prior activity as the engine evaluated it at [t] —
  /// `exp(-(t - tLast)/tauE)` with the `tLast` that was in force when the event
  /// arrived. `a` is the accumulator the engine produced at [t], i.e. the value the
  /// firing threshold was tested against, so it is directly comparable to
  /// `thetaFire`.
  void pulsed(
    String id,
    double t,
    Synapse s,
    double tLast0,
    bool active0,
    bool fired,
    Params p,
  ) {
    if (!active0 && s.active) {
      _nForm++;
      _line(t, 'form', {'id': id, 'acc': s.formAcc});
    }
    _line(t, 'syn', {
      'id': id,
      'a': s.a,
      'e': math.exp(-(t - tLast0) / p.tauE),
      'w': s.w,
      'c': s.c,
      'fc': s.firedCount,
    });
    if (fired) {
      _nFire++;
      _line(t, 'fire', {'id': id, 'a': s.a});
    }
  }

  /// Record a teacher signal the twin just delivered. Emitted for every delivered
  /// signal, including those the engine gated out (`w0 == w1`), so the eligibility
  /// and persistence gates are visible rather than invisible.
  void plast(
    String id,
    double t,
    Synapse s,
    double w0,
    double c0,
    double tLast0,
    double m,
    Params p,
  ) {
    _nPlast++;
    _line(t, 'plast', {
      'id': id,
      'w0': w0,
      'w1': s.w,
      'eta': p.etaBase / (1.0 + c0),
      'e': math.exp(-(t - tLast0) / p.tauE),
      'm': m,
    });
  }

  /// Record a structural elimination the twin's lazy prune evaluation just made.
  void pruned(String id, double t, Synapse s) {
    _nPrune++;
    _line(t, 'prune', {'id': id, 'w': s.w});
  }

  // --- layer 3: output / behavior -------------------------------------------

  /// The motor command and the pose it produced. Emitted after the move the twin
  /// already made.
  void act(double t, double mL, double mR, World world) => _line(t, 'act', {
    'mL': mL,
    'mR': mR,
    'x': world.x,
    'y': world.y,
    'th': world.heading,
  });

  // --- layer 4: campaign -----------------------------------------------------

  /// One campaign iteration's metrics.
  ///
  /// `netA` is a *behavioral* measure — signed net approach, the mean over a
  /// left-light and a right-light probe (+ = approach, - = recede) — not a weight.
  /// `wX`/`wU` are the crossed / uncrossed mean strengths. `wU > wX` together with
  /// `netA > 0` is not a contradiction: it means the wiring has already flipped
  /// while the behavior still approaches.
  void campaignIter(
    double t, {
    required int iter,
    required String phase,
    required double netA,
    required double wX,
    required double wU,
    required double? dNetA,
    required bool sat,
    required bool done,
    required String? reason,
  }) => _line(t, 'campaign.iter', {
    'iter': iter,
    'phase': phase,
    'netA': netA,
    'wX': wX,
    'wU': wU,
    'dNetA': dNetA,
    'sat': sat,
    'done': done,
    'reason': reason,
  });
}
