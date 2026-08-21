// Deterministic scenario runner for the phototaxis twin.
//
//   dart run bin/twin_run.dart
//
// Prints the learning curve (A), decay/pruning (B) and reversal (C) summaries.
//
// With --telemetry the run additionally emits an event-driven NDJSON stream (one
// JSON object per line) on stdout and moves the human summary to stderr, so the
// stream can be piped into an observer without interleaving. See docs/TELEMETRY.md.
//
//   dart run bin/twin_run.dart --telemetry [--scenario=learning|decay|reversal]
//
// Telemetry is off by default and the default output is unchanged.

import 'dart:convert';
import 'dart:io';

import 'package:neuram_v2_threshold_digital_twin/twin/scenarios.dart';
import 'package:neuram_v2_threshold_digital_twin/twin/telemetry.dart';
import 'package:neuram_v2_threshold_digital_twin/twin/twin_params.dart';

String f(double v, [int n = 3]) => v.toStringAsFixed(n);
String fl(Iterable<double> xs, [int n = 3]) =>
    '[${xs.map((e) => e.toStringAsFixed(n)).join(', ')}]';

const tp = TwinParams();

/// Upper bound on reversal rounds (mirrors the bench's cap; not a tunable).
const int reversalCap = 200;

// --- run identity -----------------------------------------------------------

String engineSha() {
  try {
    final m =
        jsonDecode(File('lib/engine/VENDOR_MANIFEST.json').readAsStringSync())
            as Map<String, dynamic>;
    return m['engineSha'] as String;
  } catch (_) {
    return 'unknown';
  }
}

String twinSha() {
  try {
    final r = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
    if (r.exitCode == 0) return (r.stdout as String).trim();
  } catch (_) {}
  return 'unknown';
}

Map<String, Object?> twinParamsJson(TwinParams p) => {
  'sensorAngle': p.sensorAngle,
  'imax': p.imax,
  'falloff': p.falloff,
  'sensorGain': p.sensorGain,
  'turnGain': p.turnGain,
  'moveGain': p.moveGain,
  'dtEngine': p.dtEngine,
  'teachDelta': p.teachDelta,
  'stepsPerTrial': p.stepsPerTrial,
  'trials': p.trials,
  'darkSteps': p.darkSteps,
  'seed': p.seed,
};

/// Install the emitter and write `run.start` for [h]. Returns the emitter.
Telemetry openStream(TwinHarness h, String scenario, int nTrials) {
  final t = Telemetry(stdout);
  tlm = t;
  t.runStart(
    engineSha: engineSha(),
    twinSha: twinSha(),
    seed: tp.seed,
    scenario: scenario,
    params: h.brain.cx.params,
    twinParams: twinParamsJson(tp),
    nTrials: nTrials,
  );
  return t;
}

void closeStream(Telemetry? t, TwinHarness h) {
  if (t == null) return;
  t.runEnd(h.brain.t, h.brain.wMap);
  tlm = null;
}

// --- scenarios --------------------------------------------------------------

void learning(StringSink out, {bool telemetry = false}) {
  final a = TwinHarness(tp);
  final t = telemetry ? openStream(a, 'learning', tp.trials) : null;
  final curve = a.learnCurve(tp.trials);
  closeStream(t, a);

  out.writeln('A) LEARNING (${tp.trials} trials)');
  out.writeln('   score curve: ${fl(curve)}');
  out.writeln(
    '   final synapse strengths  '
    'LR=${f(a.brain.lr.syn.w)} RL=${f(a.brain.rl.syn.w)} '
    'LL=${f(a.brain.ll.syn.w)} RR=${f(a.brain.rr.syn.w)}',
  );
  out.writeln(
    '   surviving wiring = crossed (LR, RL); uncrossed (LL, RR) stayed 0\n',
  );
}

void decay(StringSink out, {bool telemetry = false}) {
  final b = TwinHarness(tp);
  final t = telemetry ? openStream(b, 'decay', tp.trials) : null;
  b.train(tp.trials);
  final wBefore = b.wCrossed;
  final respBefore = b.immediateResponse();
  final pruned = b.darkAndPrune(tp.darkSteps);
  final respAfter = b.immediateResponse();
  final fullAfter = b.probeScore();
  closeStream(t, b);

  out.writeln('B) DECAY (light off for ${tp.darkSteps} dark steps)');
  out.writeln(
    '   crossed w before=${f(wBefore)} (retained latently); pruned=$pruned',
  );
  out.writeln(
    '   immediate approach response ${f(respBefore)} -> ${f(respAfter)} '
    '(behavior reverts: pruned path is silent)',
  );
  out.writeln(
    '   full-trial score on sustained re-exposure: ${f(fullAfter)} '
    '(re-forms/relearns — latent w retained)\n',
  );
}

/// Reversal rounds needed for the uncrossed pair to overtake the crossed pair,
/// after [consolidation] forward reinforcement rounds.
int trialsToReverse(int consolidation) {
  final h = TwinHarness(tp);
  h.train(consolidation); // build crossed dominance (more => higher c)
  var n = 0;
  while (h.wCrossed >= h.wUncrossed && n < reversalCap) {
    h.train(1, reversed: true);
    n++;
  }
  return n;
}

void reversal(StringSink out) {
  final weak = trialsToReverse(3);
  final strong = trialsToReverse(tp.trials);
  out.writeln(
    'C) REVERSAL (flip the reward; count trials until uncrossed overtakes crossed)',
  );
  out.writeln('   weakly consolidated (3 reps)  -> $weak trials to reverse');
  out.writeln(
    '   strongly consolidated (${tp.trials} reps) -> $strong trials to reverse',
  );
  out.writeln(
    '   strongly-consolidated path resists reversal more: ${strong > weak}',
  );
}

/// Scenario C as a single observable run: the strongly-consolidated case on one
/// harness. Section C's default output also runs a weakly-consolidated control on a
/// second, independent harness, and one stream describes one run — so `--scenario=
/// reversal` is this case alone.
///
/// It runs identically whether or not telemetry is on. Selecting a scenario and
/// observing it are separate choices: if `--telemetry` changed which computation
/// ran, the observation would be altering its own subject.
void reversalScenario(StringSink out, {bool telemetry = false}) {
  final h = TwinHarness(tp);
  final t = telemetry
      ? openStream(h, 'reversal', tp.trials + reversalCap)
      : null;
  h.train(tp.trials);
  var n = 0;
  while (h.wCrossed >= h.wUncrossed && n < reversalCap) {
    h.train(1, reversed: true);
    n++;
  }
  closeStream(t, h);

  out.writeln(
    'C) REVERSAL (flip the reward; count trials until uncrossed overtakes crossed)',
  );
  out.writeln(
    '   strongly consolidated (${tp.trials} reps) -> $n trials to reverse',
  );
  out.writeln(
    '   final synapse strengths  '
    'LR=${f(h.brain.lr.syn.w)} RL=${f(h.brain.rl.syn.w)} '
    'LL=${f(h.brain.ll.syn.w)} RR=${f(h.brain.rr.syn.w)}',
  );
}

// ---------------------------------------------------------------------------

const usage =
    'usage: dart run bin/twin_run.dart '
    '[--telemetry] [--scenario=learning|decay|reversal]';

void main(List<String> args) {
  var telemetry = false;
  String? scenario;
  for (final a in args) {
    if (a == '--telemetry') {
      telemetry = true;
    } else if (a.startsWith('--scenario=')) {
      scenario = a.substring('--scenario='.length);
    } else {
      stderr.writeln('unknown argument: $a\n$usage');
      exit(2);
    }
  }
  if (scenario != null &&
      !const ['learning', 'decay', 'reversal'].contains(scenario)) {
    stderr.writeln('unknown scenario: $scenario\n$usage');
    exit(2);
  }
  // The stream owns stdout when telemetry is on, so the summary moves to stderr.
  final StringSink out = telemetry ? stderr : stdout;

  out.write(
    '=== neuram_v2_threshold digital twin — scenarios (seed ${tp.seed}) ===\n\n',
  );

  switch (scenario) {
    case 'learning':
      learning(out, telemetry: telemetry);
    case 'decay':
      decay(out, telemetry: telemetry);
    case 'reversal':
      reversalScenario(out, telemetry: telemetry);
    case null:
      // Default: all three scenarios, exactly as before. A telemetry stream is
      // scoped to one scenario (`run.start` names it), so --telemetry selects
      // `learning` unless another scenario is given.
      if (telemetry) {
        learning(out, telemetry: true);
      } else {
        learning(out);
        decay(out);
        reversal(out);
      }
  }
}
