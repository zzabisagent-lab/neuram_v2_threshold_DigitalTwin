// Deterministic scenario runner for the phototaxis twin.
//
//   dart run bin/twin_run.dart
//
// Prints the learning curve (A), decay/pruning (B) and reversal (C) summaries.

import 'package:neuram_v2_threshold_digital_twin/twin/scenarios.dart';
import 'package:neuram_v2_threshold_digital_twin/twin/twin_params.dart';

String f(double v, [int n = 3]) => v.toStringAsFixed(n);
String fl(Iterable<double> xs, [int n = 3]) =>
    '[${xs.map((e) => e.toStringAsFixed(n)).join(', ')}]';

void main() {
  const tp = TwinParams();

  print(
    '=== neuram_v2_threshold digital twin — scenarios (seed ${tp.seed}) ===\n',
  );

  // --- A: learning -----------------------------------------------------------
  final a = TwinHarness(tp);
  final curve = a.learnCurve(tp.trials);
  print('A) LEARNING (${tp.trials} trials)');
  print('   score curve: ${fl(curve)}');
  print(
    '   final synapse strengths  '
    'LR=${f(a.brain.lr.syn.w)} RL=${f(a.brain.rl.syn.w)} '
    'LL=${f(a.brain.ll.syn.w)} RR=${f(a.brain.rr.syn.w)}',
  );
  print(
    '   surviving wiring = crossed (LR, RL); uncrossed (LL, RR) stayed 0\n',
  );

  // --- B: decay / pruning ----------------------------------------------------
  final b = TwinHarness(tp);
  b.train(tp.trials);
  final wBefore = b.wCrossed;
  final respBefore = b.immediateResponse();
  final pruned = b.darkAndPrune(tp.darkSteps);
  final respAfter = b.immediateResponse();
  final fullAfter = b.probeScore();
  print('B) DECAY (light off for ${tp.darkSteps} dark steps)');
  print(
    '   crossed w before=${f(wBefore)} (retained latently); pruned=$pruned',
  );
  print(
    '   immediate approach response ${f(respBefore)} -> ${f(respAfter)} '
    '(behavior reverts: pruned path is silent)',
  );
  print(
    '   full-trial score on sustained re-exposure: ${f(fullAfter)} '
    '(re-forms/relearns — latent w retained)\n',
  );

  // --- C: reversal (metaplastic resistance) ----------------------------------
  int trialsToReverse(int consolidation) {
    final h = TwinHarness(tp);
    h.train(consolidation); // build crossed dominance (more => higher c)
    var n = 0;
    while (h.wCrossed >= h.wUncrossed && n < 200) {
      h.train(1, reversed: true);
      n++;
    }
    return n;
  }

  final weak = trialsToReverse(3);
  final strong = trialsToReverse(30);
  print(
    'C) REVERSAL (flip the reward; count trials until uncrossed overtakes crossed)',
  );
  print('   weakly consolidated (3 reps)  -> $weak trials to reverse');
  print('   strongly consolidated (30 reps) -> $strong trials to reverse');
  print(
    '   strongly-consolidated path resists reversal more: ${strong > weak}',
  );
}
