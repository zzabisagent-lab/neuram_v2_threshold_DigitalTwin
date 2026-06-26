// One-shot iteration runner: advance one iteration (1 call = 1 iteration),
// judge termination, record, and emit commit-ready artifacts under out/.
//
//   dart run bin/campaign_iter.dart            # respects the 55-min hourly guard
//   dart run bin/campaign_iter.dart --force    # ignore the guard (manual demo)
//
// Deterministic sim (seed 42) + resumable state (out/state.json). On termination
// (saturation OR iteration > 30) it writes out/DONE and out/FINAL_REPORT.md.

import 'dart:convert';
import 'dart:io';

import 'package:neuram_v2_threshold_digital_twin/campaign/campaign.dart';

const outDir = 'out';
const stateFile = '$outDir/state.json';
const iterDir = '$outDir/iter';
const csvFile = '$outDir/campaign_log.csv';
const statusFile = '$outDir/STATUS.md';
const doneFile = '$outDir/DONE';
const finalReportFile = '$outDir/FINAL_REPORT.md';

const guardMinutes = 55.0;

void main(List<String> args) {
  final force = args.contains('--force');
  Directory(outDir).createSync(recursive: true);
  Directory(iterDir).createSync(recursive: true);

  final stateF = File(stateFile);
  final runner = stateF.existsSync()
      ? CampaignRunner.fromState(stateF.readAsStringSync())
      : CampaignRunner.fresh();

  // Idempotent: already finished -> ensure DONE, print, stop.
  if (runner.isDone) {
    if (!File(doneFile).existsSync()) {
      File(doneFile).writeAsStringSync(
        'campaign finished at iteration ${runner.iteration}\n',
      );
    }
    stdout.writeln(
      'iteration=${runner.iteration} phase=done (already finished) done=true',
    );
    return;
  }

  // Hourly guard: skip if < 55 min since the last iteration (unless --force).
  if (!force) {
    final mins = runner.minutesSinceLastRun(DateTime.now().toUtc());
    if (mins != null && mins < guardMinutes) {
      stdout.writeln(
        'skip: only ${mins.toStringAsFixed(1)} min since last iteration '
        '(< $guardMinutes min guard); no progress this run',
      );
      return;
    }
  }

  final m = runner.runOneIteration();

  File(
    '$iterDir/iter_${m.iteration.toString().padLeft(3, '0')}.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(m.toJson()));

  final csv = File(csvFile);
  if (!csv.existsSync())
    csv.writeAsStringSync('${IterationMetrics.csvHeader}\n');
  csv.writeAsStringSync('${m.csvRow()}\n', mode: FileMode.append);

  stateF.writeAsStringSync(runner.toStateJson());
  File(statusFile).writeAsStringSync(_status(runner, m, force));

  // §7: on termination, immediately persist DONE + FINAL_REPORT.
  if (m.done) {
    File(doneFile).writeAsStringSync(
      'reason=${m.doneReason} iteration=${m.iteration} '
      'netA=${m.netA.toStringAsFixed(4)}\n',
    );
    File(finalReportFile).writeAsStringSync(_finalReport(runner, m));
  }

  stdout.writeln('${m.oneLine()}${force ? ' [force]' : ''}');
}

String _sgn(double v) => (v >= 0 ? '+' : '') + v.toStringAsFixed(3);

String _status(CampaignRunner r, IterationMetrics m, bool force) {
  final b = StringBuffer()
    ..writeln('# Threshold campaign — STATUS')
    ..writeln()
    ..writeln(
      '- Iteration: **${m.iteration}** (1 call = 1 iteration; '
      'hourly schedule, calendar-independent)',
    )
    ..writeln(
      '- Run at: ${m.runAtLocal} (local) / ${m.runAtUtc} (UTC)'
      '${force ? ' [force]' : ''}',
    )
    ..writeln(
      '- Phase run: **${m.phase.name}**'
      '${m.transition == null ? '' : ' → **${m.transition}**'}',
    )
    ..writeln('- Current phase (next run): **${r.phase.name}**')
    ..writeln(
      '- netA (signed approach): **${_sgn(m.netA)}** (+ approach, − avoid)',
    )
    ..writeln(
      '- Δ: **${m.deltaDay.isNaN ? 'n/a' : m.deltaDay.toStringAsFixed(3)}**'
      ' (saturate: < ε=${r.cfg.epsilon} for K=${r.cfg.k} iters)',
    )
    ..writeln('- Saturated this phase: **${m.saturated}**')
    ..writeln(
      '- Done: **${m.done}**'
      '${m.doneReason == null ? '' : ' (${m.doneReason})'}',
    )
    ..writeln()
    ..writeln('## Strengths')
    ..writeln(
      '- crossed (LR,RL): **${m.wCrossed.toStringAsFixed(3)}**, '
      'uncrossed (LL,RR): **${m.wUncrossed.toStringAsFixed(3)}**',
    )
    ..writeln(
      '- active: ${m.activeCount}/4, functional (w≥${r.cfg.functionalW}): '
      '${m.functionalCount}/4, formed: ${m.formed}, pruned: ${m.pruned}, '
      'mean c: ${m.cMean.toStringAsFixed(2)}',
    )
    ..writeln()
    ..writeln('## netA history')
    ..writeln()
    ..writeln('| iter | phase | netA |')
    ..writeln('|----:|:------|-----:|');
  for (final e in r.history) {
    b.writeln(
      '| ${e['iteration']} | ${e['phase']} '
      '| ${_sgn((e['netA'] as num).toDouble())} |',
    );
  }
  b
    ..writeln()
    ..writeln(
      '_Pre-registered (§4/§5): dayReps=${r.cfg.dayReps}, K=${r.cfg.k}, '
      'ε=${r.cfg.epsilon}, maxIterations=${r.cfg.maxIterations}. '
      'Engine + twin core frozen; campaign code additive only. seed_verification/ '
      'holds the initial 3-iteration verification._',
    );
  return b.toString();
}

String _finalReport(CampaignRunner r, IterationMetrics m) {
  final b = StringBuffer()
    ..writeln('# Threshold campaign — FINAL REPORT')
    ..writeln()
    ..writeln(
      '- **Termination:** ${m.doneReason} '
      '(saturation = K=${r.cfg.k} iters with |Δ netA| < ε=${r.cfg.epsilon}; '
      'global cap = iteration > ${r.cfg.maxIterations})',
    )
    ..writeln('- **Total iterations:** ${m.iteration}')
    ..writeln(
      '- **Finished at:** ${m.runAtLocal} (local) / ${m.runAtUtc} (UTC)',
    )
    ..writeln('- **Final netA:** ${_sgn(m.netA)} (+ approach, − avoid)')
    ..writeln(
      '- **Final strengths:** crossed (LR,RL) ${m.wCrossed.toStringAsFixed(3)}, '
      'uncrossed (LL,RR) ${m.wUncrossed.toStringAsFixed(3)}, mean c ${m.cMean.toStringAsFixed(2)}',
    )
    ..writeln()
    ..writeln('## Phase transitions')
    ..writeln();
  if (r.transitions.isEmpty) {
    b.writeln('_none_');
  } else {
    for (final t in r.transitions) {
      b.writeln(
        '- iteration ${t['iteration']}: ${t['from']} → ${t['to']} '
        '(${t['reason']})',
      );
    }
  }
  b
    ..writeln()
    ..writeln('## netA per iteration')
    ..writeln()
    ..writeln('| iter | phase | netA | crossed | uncrossed |')
    ..writeln('|----:|:------|-----:|--------:|----------:|');
  // re-read per-iteration files for w columns where available
  for (final e in r.history) {
    final it = e['iteration'] as int;
    final f = File('$iterDir/iter_${it.toString().padLeft(3, '0')}.json');
    var wx = '', wu = '';
    if (f.existsSync()) {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      wx = (j['wCrossed'] as num).toStringAsFixed(3);
      wu = (j['wUncrossed'] as num).toStringAsFixed(3);
    }
    b.writeln(
      '| $it | ${e['phase']} | ${_sgn((e['netA'] as num).toDouble())} '
      '| $wx | $wu |',
    );
  }
  b
    ..writeln()
    ..writeln('## Notes')
    ..writeln()
    ..writeln(
      '- Engine (`lib/engine/`) and twin core (`lib/twin/`) are **frozen** '
      '(campaign code is additive: `lib/campaign/`, `bin/`). Deterministic sim '
      '(seed 42); timestamps are wall-clock audit only.',
    )
    ..writeln(
      '- The initial 3-iteration build-time verification is archived under '
      '`seed_verification/`.',
    )
    ..writeln(
      '- §10 hypothesis: a multi-iteration (≥3) monotone netA transition '
      'under the R7 reversal, with no single iteration exceeding 60% of the total '
      '|Δ| — vs the old single-variable ~100%-in-one-step. See the table above.',
    );
  return b.toString();
}
