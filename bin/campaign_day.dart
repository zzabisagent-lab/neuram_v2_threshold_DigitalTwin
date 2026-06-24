// One-shot daily campaign runner: advance one day, judge saturation, record,
// and emit commit-ready artifacts under out/.
//
//   dart run bin/campaign_day.dart
//
// Deterministic and resumable: state lives in out/state.json. When the campaign
// finishes it writes out/DONE (the scheduler wrapper sees this and self-removes).

import 'dart:convert';
import 'dart:io';

import 'package:neuram_v2_threshold_digital_twin/campaign/campaign.dart';

const outDir = 'out';
const stateFile = '$outDir/state.json';
const dailyDir = '$outDir/daily';
const csvFile = '$outDir/campaign_log.csv';
const statusFile = '$outDir/STATUS.md';
const doneFile = '$outDir/DONE';

void main() {
  Directory(outDir).createSync(recursive: true);
  Directory(dailyDir).createSync(recursive: true);

  final stateF = File(stateFile);
  final runner = stateF.existsSync()
      ? CampaignRunner.fromState(stateF.readAsStringSync())
      : CampaignRunner.fresh();

  // Idempotent: if already finished, don't advance — just ensure DONE exists.
  if (runner.isDone) {
    File(
      doneFile,
    ).writeAsStringSync('campaign finished at day ${runner.day}\n');
    stdout.writeln('day=${runner.day} phase=done (already finished) done=true');
    return;
  }

  final m = runner.runOneDay();

  // per-day json
  File(
    '$dailyDir/day_${m.day.toString().padLeft(3, '0')}.json',
  ).writeAsStringSync(_pretty(m.toJson()));

  // append csv (header once)
  final csv = File(csvFile);
  if (!csv.existsSync()) csv.writeAsStringSync('${DailyMetrics.csvHeader}\n');
  csv.writeAsStringSync('${m.csvRow()}\n', mode: FileMode.append);

  // state
  stateF.writeAsStringSync(runner.toStateJson());

  // human-readable status
  File(statusFile).writeAsStringSync(_status(runner, m));

  if (m.done) {
    File(doneFile).writeAsStringSync('campaign finished at day ${m.day}\n');
  }

  stdout.writeln(m.oneLine());
}

String _pretty(Map<String, dynamic> j) =>
    const JsonEncoder.withIndent('  ').convert(j);

String _status(CampaignRunner r, DailyMetrics m) {
  final b = StringBuffer()
    ..writeln('# Threshold campaign — STATUS')
    ..writeln()
    ..writeln('- Day: **${m.day}**')
    ..writeln(
      '- Phase run today: **${m.phase.name}**'
      '${m.transition == null ? '' : ' → transitioned (**${m.transition}**)'}',
    )
    ..writeln('- Current phase (next run): **${r.phase.name}**')
    ..writeln(
      '- netA (signed approach): **${_sgn(m.netA)}**'
      '  (+ = approach, − = avoid)',
    )
    ..writeln(
      '- Δ_day: **${m.deltaDay.isNaN ? 'n/a' : m.deltaDay.toStringAsFixed(3)}**'
      '  (saturate when < ε=${r.cfg.epsilon} for K=${r.cfg.k} days)',
    )
    ..writeln('- Saturated this phase: **${m.saturated}**')
    ..writeln('- Campaign done: **${m.done}**')
    ..writeln()
    ..writeln('## Strengths')
    ..writeln(
      '- crossed (LR,RL): **${m.wCrossed.toStringAsFixed(3)}**, '
      'uncrossed (LL,RR): **${m.wUncrossed.toStringAsFixed(3)}**',
    )
    ..writeln(
      '- active synapses: ${m.activeCount}/4, '
      'functional (w≥${r.cfg.functionalW}): ${m.functionalCount}/4, '
      'formed today: ${m.formed}, pruned today: ${m.pruned}, '
      'mean c: ${m.cMean.toStringAsFixed(2)}',
    )
    ..writeln()
    ..writeln('## netA history (per day)')
    ..writeln()
    ..writeln('| day | phase | netA |')
    ..writeln('|----:|:------|-----:|');
  for (final e in r.history) {
    b.writeln(
      '| ${e['day']} | ${e['phase']} '
      '| ${_sgn((e['netA'] as num).toDouble())} |',
    );
  }
  b
    ..writeln()
    ..writeln('## Transitions')
    ..writeln();
  if (r.transitions.isEmpty) {
    b.writeln('_none yet_');
  } else {
    for (final t in r.transitions) {
      b.writeln(
        '- day ${t['day']}: ${t['from']} → ${t['to']} (${t['reason']})',
      );
    }
  }
  b
    ..writeln()
    ..writeln(
      '_Pre-registered (§4/§5): dayReps=${r.cfg.dayReps}, K=${r.cfg.k}, '
      'ε=${r.cfg.epsilon}, maxDaysPerPhase=${r.cfg.maxDaysPerPhase}. '
      'Engine + twin core frozen; campaign code is additive only._',
    );
  return b.toString();
}

String _sgn(double v) => (v >= 0 ? '+' : '') + v.toStringAsFixed(3);
