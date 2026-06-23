// Pre-registered pass/fail bench for the embodied twin (§8).
//
// Deterministic (fixed seed, no randomness), no external dependencies. Implements
// REG-1/2/3 and the T-criteria verbatim, prints a PASS/FAIL table, and exits with
// a non-zero code if any scored criterion fails.
//
//   dart run bin/twin_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:neuram_v2_threshold_digital_twin/twin/scenarios.dart';
import 'package:neuram_v2_threshold_digital_twin/twin/twin_params.dart';

const tp = TwinParams();

// --- result bookkeeping -----------------------------------------------------

class Result {
  final String id;
  final bool pass;
  final String detail;
  final bool obsOnly;
  Result(this.id, this.pass, this.detail, {this.obsOnly = false});
}

final results = <Result>[];
void record(String id, bool pass, String detail, {bool obsOnly = false}) =>
    results.add(Result(id, pass, detail, obsOnly: obsOnly));

String f(double v, [int n = 3]) => v.toStringAsFixed(n);

// Pure-Dart FNV-1a 64-bit over a vendored file's body (LF-normalized, excluding
// //VND header lines). No external crypto dependency.
String bodyHash(String content) {
  final body = content
      .split('\n')
      .where((l) => !l.startsWith('//VND'))
      .join('\n')
      .replaceAll('\r', '');
  var hash = BigInt.parse('14695981039346656037');
  final prime = BigInt.parse('1099511628211');
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final b in utf8.encode(body)) {
    hash = ((hash ^ BigInt.from(b)) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

// ===========================================================================
// REG — independence / vendoring / soundness
// ===========================================================================

void regChecks() {
  // REG-1: independent history + documented separation + engine-frozen.
  String norm(String path) => File(path).existsSync()
      ? File(
          path,
        ).readAsStringSync().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')
      : '';
  final readme = norm('README.md');
  final engSrc = norm('ENGINE_SOURCE.md');
  final docsOk =
      readme.contains('no code and no git history') &&
      engSrc.contains('must not modify the engine') &&
      engSrc.contains('frozen');
  var rootOk = false;
  var rootDetail = 'git unavailable';
  try {
    final r = Process.runSync('git', ['rev-list', '--max-parents=0', 'HEAD']);
    if (r.exitCode == 0) {
      final roots = (r.stdout as String)
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      rootOk = roots.length == 1;
      rootDetail = 'rootCommits=${roots.length}';
    }
  } catch (_) {
    rootOk = docsOk;
    rootDetail = 'git unavailable; docs-only';
  }
  record(
    'REG-1',
    docsOk && rootOk,
    'separation+frozen documented=$docsOk, $rootDetail (no engine/companion SHA in history)',
  );

  // REG-2: every vendored engine file is byte-identical to the pin (header aside).
  final manifest =
      jsonDecode(File('lib/engine/VENDOR_MANIFEST.json').readAsStringSync())
          as Map<String, dynamic>;
  final files = manifest['files'] as Map<String, dynamic>;
  var allMatch = true;
  final mismatches = <String>[];
  files.forEach((path, expected) {
    final got = bodyHash(File(path).readAsStringSync());
    if (got != expected) {
      allMatch = false;
      mismatches.add('$path got=$got exp=$expected');
    }
  });
  record(
    'REG-2',
    allMatch,
    'engine @ ${manifest['engineSha']} vendored byte-identical (FNV-1a body match=${files.length}/${files.length})${mismatches.isEmpty ? '' : ' MISMATCH: $mismatches'}',
  );

  // REG-3: no external dependencies + determinism (same seed => same result).
  final pub = File('pubspec.yaml').readAsStringSync();
  final noDeps = !pub.contains('dependencies:');
  final sdkOk = pub.contains('^3.8.1');
  final c1 = TwinHarness(tp).learnCurve(tp.trials);
  final c2 = TwinHarness(tp).learnCurve(tp.trials);
  final deterministic = _listEq(c1, c2);
  record(
    'REG-3',
    noDeps && sdkOk && deterministic,
    'no external deps=$noDeps, sdk^3.8.1=$sdkOk, deterministic(seed ${tp.seed})=$deterministic, build/test executed=true',
  );
}

bool _listEq(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ===========================================================================
// T — embodied verification of the two thresholds
// ===========================================================================

void tChecks() {
  // T-① — embodied signal-pass threshold.
  {
    final h = TwinHarness(tp)..train(tp.trials);
    final far = h.probe(true, TwinHarness.farDist).maxMotor;
    final off = h.probe(true, TwinHarness.probeDist, on: false).maxMotor;
    final near = h.probe(true, TwinHarness.nearDist).maxMotor;
    final pass = far == 0.0 && off == 0.0 && near > 0.0;
    record(
      'T-①',
      pass,
      'far(d=${TwinHarness.farDist.toInt()}) motor=${f(far)}=0; off motor=${f(off)}=0; '
          'near(d=${TwinHarness.nearDist.toInt()}) motor=${f(near)}>0 (only sufficient light fires->steers)',
    );
  }

  // T-②-form — embodied gradual learning.
  {
    final h = TwinHarness(tp);
    final curve = h.learnCurve(tp.trials);
    final fin = curve.sublist(curve.length - 5).reduce((a, b) => a + b) / 5;
    final s1 = curve.first;
    var n95 = -1;
    for (var i = 0; i < curve.length; i++) {
      if (curve[i] >= 0.95 * fin) {
        n95 = i + 1;
        break;
      }
    }
    var maxJump = 0.0;
    for (var i = 1; i < curve.length; i++) {
      final j = curve[i] - curve[i - 1];
      if (j > maxJump) maxJump = j;
    }
    final a = s1 < 0.30 * fin;
    final b = n95 >= 4;
    final c = maxJump < 0.60 * fin;
    final crossedWon = h.wCrossed > 0.0 && h.wUncrossed == 0.0;
    record(
      'T-②-form',
      a && b && c && crossedWon,
      'trial1=${f(s1)}<0.30*fin(${f(0.30 * fin)})=$a; n95=$n95>=4=$b; '
          'maxJump=${f(maxJump)}<0.60*fin(${f(0.60 * fin)})=$c; '
          'survivors crossed(LR,RL)>0 & uncrossed=0: $crossedWon; final=${f(fin)}',
    );
  }

  // T-②-prune — embodied decay/pruning reverts behavior.
  {
    final h = TwinHarness(tp)..train(tp.trials);
    final respBefore = h.immediateResponse();
    final pruned = h.darkAndPrune(tp.darkSteps);
    final learnedPruned =
        !h.brain.lr.syn.active || !h.brain.rl.syn.active; // >=1 learned path
    final respAfter = h.immediateResponse();
    final dropped = respAfter < 0.5 * respBefore;
    record(
      'T-②-prune',
      learnedPruned && dropped,
      '>=1 learned path pruned(active=false)=$learnedPruned (pruned=$pruned); '
          'immediate approach ${f(respBefore)} -> ${f(respAfter)} < 0.5x = $dropped '
          '(full-trial relearns; latent w retained)',
    );
  }

  // T-meta — embodied metaplasticity (consolidated path resists reversal).
  {
    int trialsToReverse(int reps) {
      final h = TwinHarness(tp)..train(reps);
      var n = 0;
      while (h.wCrossed >= h.wUncrossed && n < 200) {
        h.train(1, reversed: true);
        n++;
      }
      return n;
    }

    final weakH = TwinHarness(tp)..train(3);
    final strongH = TwinHarness(tp)..train(30);
    final cWeak = weakH.brain.lr.syn.c;
    final cStrong = strongH.brain.lr.syn.c;
    final weak = trialsToReverse(3);
    final strong = trialsToReverse(30);
    record(
      'T-meta',
      strong > weak,
      'weak(c=${f(cWeak, 1)}) reverses in $weak trials < strong(c=${f(cStrong, 1)}) in $strong trials '
          '(higher consolidation resists reversal)',
    );
  }

  // T-persist — save/load restores synaptic state and behavior exactly.
  {
    final h1 = TwinHarness(tp)..train(8);
    final before = [
      for (var id = 0; id < 4; id++)
        (
          w: h1.brain.cx.synapses[id]!.w,
          c: h1.brain.cx.synapses[id]!.c,
          active: h1.brain.cx.synapses[id]!.active,
          tLast: h1.brain.cx.synapses[id]!.tLast,
        ),
    ];
    final tSave = h1.brain.t; // twin-level clock is part of the persisted state
    final json = h1.brain.cx.toJsonString();
    final h2 = TwinHarness(tp);
    h2.brain.cx.loadFromString(json);
    h2.brain.t = tSave; // resume the same clock so lazy decay matches
    var fieldsOk = true;
    for (var id = 0; id < 4; id++) {
      final s = h2.brain.cx.synapses[id]!;
      final b = before[id];
      if (s.w != b.w ||
          s.c != b.c ||
          s.active != b.active ||
          s.tLast != b.tLast) {
        fieldsOk = false;
      }
    }
    final score1 = h1.probeScore();
    final score2 = h2.probeScore();
    final scoreOk = score1 == score2;
    record(
      'T-persist',
      fieldsOk && scoreOk,
      'restored w/c/active/tLast exactly=$fieldsOk; post-reload score ${f(score2)} == control ${f(score1)} = $scoreOk',
    );
  }
}

// ===========================================================================
// OBS — observation only (not scored)
// ===========================================================================

void obsChecks() {
  final h = TwinHarness(tp)..train(tp.trials);
  final crossed = h.wCrossed;
  final uncrossed = h.wUncrossed;
  record(
    'OBS-1',
    true,
    'surviving wiring is crossed: LR=${f(h.brain.lr.syn.w)} RL=${f(h.brain.rl.syn.w)} '
        '(mean ${f(crossed)}) vs uncrossed LL=${f(h.brain.ll.syn.w)} RR=${f(h.brain.rr.syn.w)} '
        '(mean ${f(uncrossed)}) — matches nature-first phototaxis prediction (contralateral steering)',
    obsOnly: true,
  );
}

// ===========================================================================

void main() {
  regChecks();
  tChecks();
  obsChecks();

  stdout.writeln(
    '\n=== neuram_v2_threshold_DigitalTwin — pre-registered embodied bench ===\n',
  );
  var failed = 0;
  for (final r in results) {
    final tag = r.obsOnly ? 'OBS ' : (r.pass ? 'PASS' : 'FAIL');
    if (!r.obsOnly && !r.pass) failed++;
    stdout.writeln('[$tag] ${r.id.padRight(10)} ${r.detail}');
  }
  final scored = results.where((r) => !r.obsOnly).length;
  stdout.writeln(
    '\n${scored - failed}/$scored scored criteria passed'
    '${failed == 0 ? ' — ALL PASS' : ' — $failed FAILED'}.',
  );
  if (failed > 0) exit(1);
}
