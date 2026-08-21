# RESULTS — pre-registered acceptance criteria, telemetry (P1)

Criteria T1–T7 were fixed before the work began and are reported here as measured.
Nothing was retuned to make a criterion pass. Where a criterion is not met it is
recorded as not met, with the reason.

Measured on branch `feature/telemetry`, Dart 3.13.1, linux_x64, against `main` at
`3ac84bc` as the baseline.

| id | criterion | result |
|----|-----------|--------|
| T1 | `dart run bin/twin_test.dart` → 8/8 PASS, exit 0 | **PASS** |
| T2 | REG-2 — vendored engine FNV-1a body match 5/5 *(non-negotiable)* | **PASS** |
| T3 | `--telemetry` on/off give identical results *(non-negotiable)* | **PASS** |
| T4 | same seed twice → byte-identical NDJSON | **FAIL as written** — see below |
| T5 | zero `syn` events in unstimulated intervals *(non-negotiable)* | **PASS** |
| T6 | every line valid JSON, `seq` monotonic with no gaps | **PASS** |
| T7 | `twin_run.dart` summary output unchanged | **PASS** |

---

### T1 — bench

```
8/8 scored criteria passed — ALL PASS.       exit 0
```

Output is byte-identical to the same bench run at `main` (`3ac84bc`).

### T2 — vendored engine untouched

```
[PASS] REG-2  engine @ 45ad1c0008af70ea8d901c93b7acf58a4979301f
              vendored byte-identical (FNV-1a body match=5/5)
```

Nothing under `lib/engine/` was modified. Telemetry reads only what the engine's
public API already exposes (`Stimulator`, `Synapse`, `Params`).

### T3 — observation does not change the result

Summary output with and without `--telemetry` is byte-identical for every scenario:

| scenario | on vs off |
|----------|-----------|
| `learning` | identical (score curve, final `LR`/`RL`/`LL`/`RR`) |
| `decay` | identical (crossed `w`, prune list, immediate response, re-exposure score) |
| `reversal` | identical (rounds to reverse, final strengths) |

The bench also still reports 8/8 with the telemetry code present and off.

> This criterion **initially failed for `reversal`**, and the failure was real:
> `--telemetry --scenario=reversal` ran a single strongly-consolidated harness while
> the same scenario without telemetry ran both the weak and strong cases. Turning
> observation on changed which computation ran, which is precisely what T3 exists to
> forbid. Fixed by making `--scenario=reversal` mean one thing — the
> strongly-consolidated case on one harness — in both modes. Selecting a scenario
> and observing it are separate choices.

### T4 — byte-identical NDJSON across two runs

**Not met as literally written**, because the pre-registration contradicts itself,
and the contradiction cannot be resolved without changing one of its two halves.

§4 of the specification mandates that `run.end` carry `"wallMs": <실측 ms>` — a
*measured* wall-clock duration. A measured duration is not reproducible. T4 then
requires the whole stream to be byte-identical between two runs. Both cannot hold.

Measured, `learning` scenario, two consecutive runs:

```
31 584 lines total
31 583 lines byte-identical
     1 line differs — the final run.end, in exactly one field:
       run.end.wallMs: 437 vs 382
```

`neuram_trace diff` with no volatile fields declared:

```
DIVERGES at event index 31583
  seq      A=31583  B=31583
  ev       run.end
  cause    field "wallMs": 437 vs 382 (exact comparison)
```

and with `run.end.wallMs` declared volatile:

```
IDENTICAL — 31584 events compared, no divergence
```

Neither half was altered to force a pass: `wallMs` is still emitted as the schema
requires, and the criterion is still reported as unmet. What was built instead is a
tool that states both facts separately — `neuram_trace verify` reports a `bytes`
verdict and a `content` verdict, so a bit-identity claim and a same-run claim are
never conflated. Every other field of every other event, including all 10 838
firings and all 60 plasticity events, is reproduced bit for bit.

Related fact, recorded because it bears on any future reading of "same seed": **the
twin contains no RNG.** `grep -rn "Random\|nextDouble\|nextInt" lib/ bin/` returns
nothing, and `TwinParams.seed` is only ever written into `run.start` for provenance —
never read by the dynamics. Changing the seed cannot change a run.

### T5 — silence in unstimulated intervals

Zero `syn` (and zero `fire`) events while both sensors read 0, in every scenario:

| scenario | `syn`/`fire` while dark | longest interval with no event of any kind |
|----------|------------------------|--------------------------------------------|
| `learning` | 0 | 2.100 units, from t=270.300 |
| `decay` | 0 | **3.000 units**, from t=18.000 |
| `reversal` | 0 | 0.080 units, from t=15.920 |

The 3.000-unit stretch in `decay` is the dark interval (30 steps × `dtEngine` 0.1).
The engine is touched by nothing during it, so the stream contains nothing. That
silence is the observable form of the zero-idle principle.

### T6 — well-formed stream

| scenario | lines | JSON | `seq` |
|----------|-------|------|-------|
| `learning` | 31 584 | all valid | monotonic 0…31583, no gaps |
| `decay` | 2 250 | all valid | monotonic 0…2249, no gaps |
| `reversal` | 1 900 | all valid | monotonic 0…1899, no gaps |

### T7 — existing behaviour unchanged

`dart run bin/twin_run.dart` with no arguments produces output byte-identical to the
same command at `main` (`3ac84bc`), verified by `diff` against a clean checkout.
Telemetry is off unless asked for, and when it is on the stream takes stdout while
the human summary moves to stderr, so neither can corrupt the other.

---

## Scope note

`campaign.iter` (layer 4) is specified and implemented in the schema and in every
consumer, but the twin runner does not emit it. The campaign runner lives on the
`feature/threshold-campaign` branch and was deliberately not touched: the campaign
must not be resumed and its iteration cap must not be changed. Recorded campaigns
are converted into the schema after the fact by `neuram_trace campaign-import`,
which reads files and writes NDJSON and runs nothing. The 2026-06-26 campaign
imports to 31 `campaign.iter` events ending in
`"done":true,"reason":"max-iterations"`.

## The rest of the criteria

S1–S5 (stream server), W1–W6 (web dashboard), C1–C4 (terminal UI) and V1–V3
(reproducibility tools) belong to the observation environment and are reported in
[`neuram_observatory/docs/RESULTS.md`](https://github.com/zzabisagent-lab/neuram_observatory/blob/main/docs/RESULTS.md).

Schema: [`TELEMETRY.md`](TELEMETRY.md).
