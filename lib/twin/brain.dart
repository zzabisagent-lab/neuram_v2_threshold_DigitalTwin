import '../engine/connectome.dart';
import '../engine/sim.dart';
import '../engine/synapse.dart';
import 'body.dart';
import 'telemetry.dart';
import 'twin_params.dart';
import 'world.dart';

enum Motor { left, right }

enum SensorSide { left, right }

/// A candidate sense->motor connection. Which connections survive and grow is
/// *learned*, never wired in code.
class Edge {
  final String name;
  final SensorSide src;
  final Motor tgt;
  final Synapse syn;
  Edge(this.name, this.src, this.tgt, this.syn);

  /// Crossed = sensor and motor on opposite sides (the phototaxis-correct map).
  bool get crossed =>
      (src == SensorSide.left && tgt == Motor.right) ||
      (src == SensorSide.right && tgt == Motor.left);
}

/// The minimal connectome (2 sensors -> 2 motors) plus the goal-directed teacher.
///
/// Four candidate synapses start at w=0 (no functional connection — not
/// hardwired). The teacher is the embodied phototaxis reward: it knows only the
/// *goal* (turn toward the brighter sensor, i.e. approach the light) and
/// reinforces, per fired synapse, whether that synapse's motor serves the goal.
/// The crossed (approach) pair is carved out by reward, not pre-set.
class Brain {
  final TwinParams tp;
  final Connectome cx;
  final Stimulator sim;
  final Body body;
  double t = 0.0;

  static const double _eps = 1e-9;
  static const double mMag = 1.0;

  late final Edge ll; // left  sensor -> left  motor (uncrossed)
  late final Edge lr; // left  sensor -> right motor (crossed)
  late final Edge rl; // right sensor -> left  motor (crossed)
  late final Edge rr; // right sensor -> right motor (uncrossed)
  late final List<Edge> edges;

  Brain._(this.tp, this.cx, this.sim, this.body) {
    ll = Edge('LL', SensorSide.left, Motor.left, cx.addSynapse(0));
    lr = Edge('LR', SensorSide.left, Motor.right, cx.addSynapse(1));
    rl = Edge('RL', SensorSide.right, Motor.left, cx.addSynapse(2));
    rr = Edge('RR', SensorSide.right, Motor.right, cx.addSynapse(3));
    edges = [ll, lr, rl, rr];
  }

  factory Brain(TwinParams tp, {Connectome? connectome}) {
    final cx = connectome ?? Connectome();
    final sim = Stimulator(cx);
    final body = Body(sim, tp);
    return Brain._(tp, cx, sim, body);
  }

  List<Synapse> get leftMotorInputs => [ll.syn, rl.syn];
  List<Synapse> get rightMotorInputs => [lr.syn, rr.syn];

  /// Current strengths, keyed by edge name (for trial/run boundary telemetry).
  Map<String, double> get wMap => {for (final e in edges) e.name: e.syn.w};

  // --- telemetry wrappers ----------------------------------------------------
  //
  // These add emission around an engine call the twin was already making; the call
  // itself, its arguments and its result are unchanged. When telemetry is off the
  // wrapper is one null check and the original call.

  /// Deliver a sensory pulse and, if observed, record the input event.
  bool _pulse(Edge e, double intensity) {
    final tm = tlm;
    if (tm == null) return body.senseInto(e.syn, t, intensity);
    final s = e.syn;
    final tLast0 = s.tLast;
    final active0 = s.active;
    final fired = body.senseInto(s, t, intensity);
    tm.pulsed(e.name, t, s, tLast0, active0, fired, sim.params);
    return fired;
  }

  /// Deliver a teacher signal and, if observed, record the plasticity event.
  double _teach(Edge e, double tt, double m) {
    final tm = tlm;
    if (tm == null) return sim.teach(e.syn, tt, m);
    final s = e.syn;
    final w0 = s.w;
    final c0 = s.c;
    final tLast0 = s.tLast;
    final dw = sim.teach(s, tt, m);
    tm.plast(e.name, tt, s, w0, c0, tLast0, m, sim.params);
    return dw;
  }

  /// Deliver sensory pulses (threshold ①) and decode motor wheel speeds from the
  /// gated propagation (threshold ②). A dark sensor (intensity 0) generates no
  /// event (event-driven). Returns (vL, vR).
  (double, double) drive(Sensors sn) {
    if (sn.left > _eps) {
      _pulse(ll, sn.left);
      _pulse(lr, sn.left);
    }
    if (sn.right > _eps) {
      _pulse(rl, sn.right);
      _pulse(rr, sn.right);
    }
    final vL = body.motor(leftMotorInputs, t);
    final vR = body.motor(rightMotorInputs, t);
    return (vL, vR);
  }

  /// The motor to promote in order to turn toward the brighter sensor: brighter
  /// left -> turn left -> promote the right motor (and vice versa).
  Motor? _promoteMotor(Sensors sn) {
    final xL = body.encode(sn.left);
    final xR = body.encode(sn.right);
    if ((xL - xR).abs() < _eps) return null; // no steering signal
    return xL > xR ? Motor.right : Motor.left;
  }

  /// The sensor side currently receiving the most light (the side to approach).
  SensorSide? _brighterSensor(Sensors sn) {
    final xL = body.encode(sn.left);
    final xR = body.encode(sn.right);
    if ((xL - xR).abs() < _eps) return null;
    return xL > xR ? SensorSide.left : SensorSide.right;
  }

  /// Goal-directed teacher (threshold ②). The phototaxis goal — approach the
  /// brighter sensor — defines the single sensorimotor association that serves it:
  /// the brighter sensor driving the *contralateral* motor (turn toward the
  /// light). The teacher positively reinforces exactly that fired synapse and
  /// leaves the others untouched, so the wrong/uncrossed synapses stay at w=0 and
  /// are later pruned. The crossed pair is carved out by reward, never wired.
  ///
  /// When [reversed] is set, the reward direction is flipped (the goal becomes
  /// "turn away"): the bright sensor's *ipsilateral* (uncrossed) synapse is
  /// reinforced and its previously-correct crossed synapse is depressed. This is
  /// used to test how strongly a consolidated path resists reversal.
  void reward(Sensors sn, {double scale = 1.0, bool reversed = false}) {
    final bright = _brighterSensor(sn);
    final promote = _promoteMotor(sn);
    if (bright == null || promote == null) return;
    for (final e in edges) {
      if (!e.syn.lastFired) continue;
      if (e.src != bright) continue;
      final isCrossed = e.tgt == promote; // serves the (forward) goal
      if (!reversed) {
        if (isCrossed) _teach(e, t + tp.teachDelta, mMag * scale);
      } else {
        // reversed goal: reward ipsilateral (uncrossed), depress crossed
        final m = (isCrossed ? -mMag : mMag) * scale;
        _teach(e, t + tp.teachDelta, m);
      }
    }
  }

  /// One embodied reinforcement presentation given a fixed sensing [sn]: two input
  /// pulses (so firedCount reaches sMin) followed by one goal-directed reward —
  /// the closed-loop analogue of the engine's B1 "presentation". Advances t.
  void presentOnce(Sensors sn, {bool reversed = false}) {
    for (var rep = 0; rep < 2; rep++) {
      if (sn.left > _eps) {
        _pulse(ll, sn.left);
        _pulse(lr, sn.left);
      }
      if (sn.right > _eps) {
        _pulse(rl, sn.right);
        _pulse(rr, sn.right);
      }
      t += tp.teachDelta + 0.03;
    }
    reward(sn, reversed: reversed);
    t += tp.dtEngine;
  }

  /// Lazily evaluate pruning of all candidate synapses at the current time.
  /// Returns the names of synapses pruned on this call.
  List<String> pruneAll() {
    final pruned = <String>[];
    for (final e in edges) {
      if (sim.prune(e.syn, t)) {
        pruned.add(e.name);
        if (tlm != null) tlm!.pruned(e.name, t, e.syn);
      }
    }
    return pruned;
  }

  /// Advance engine time one loop step.
  void tick() => t += tp.dtEngine;
}
