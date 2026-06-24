# Threshold daily campaign — design, pre-registration, preview

A daily auto-simulation that drives the **frozen** threshold engine + twin (public
API only — no engine/twin-core edits) through an R7-style **reward reversal**, one
*day* per run, and **auto-stops when the change saturates**. The question it
answers: is the model's reversal a **single step** (old single-variable model) or a
**multi-day gradual** transition (threshold/metaplasticity model)?

## What is the same / new vs the old campaign

| | old single-variable | this (threshold) |
|---|---|---|
| task | reward→punish reversal (R7) | **same** R7-style reversal |
| metric | netA (approach − avoid) sign flip | same + **per-day transition curve** |
| expectation | day-4 one-step ±0.713 then flat | **multi-day gradual** transition |
| stop | fixed number of weeks | **automatic saturation detection** |

## Pre-registered configuration (§4/§5) — locked, not tuned

- Individual: the twin's learning phototaxis closed loop, 1 agent (seed 42),
  lifetime learning (synaptic state persists across days).
- **netA** = signed net approach, mean over a left-light and right-light probe of
  `(dInitial − dFinal)/dInitial` (+ = approach, − = recede). Read-only probe.
- **Phase build**: normal phototaxis reward (approach = reward).
- **Phase reversal**: reward flipped (the bright-sensor→ipsilateral, i.e. away,
  is rewarded; the previously-correct crossed path is depressed).
- **Day** = `dayReps = 8` reinforcement rounds (each round = one left + one right
  encounter), then the day's metrics are recorded.
- **Saturation (locked):** `Δ_day = |netA(today) − netA(yesterday)|`; a phase is
  saturated when the last **K = 3** within-phase days all have `Δ_day < ε = 0.02`.
  build saturates → switch to reversal; reversal saturates → **campaign done**.
- **Safety cap:** `maxDaysPerPhase = 30`.
- These (K, ε, cap, dayReps) are fixed before running and are **not** changed to
  shape the result. Engine §6 and twin §7 parameters are untouched.

## Daily runner & automation

- `dart run bin/campaign_day.dart` — advance one day, judge saturation, write
  `out/daily/day_NNN.json`, append `out/campaign_log.csv`, update `out/state.json`
  (resumable: connectome + twin clock + phase/day), refresh `out/STATUS.md`, and
  on completion write `out/DONE`. Prints a one-line summary. Deterministic.
- `run_daily.ps1` + scheduled task **`NeuRAM_ThresholdCampaign`** (daily): runs the
  day, commits `out/` to `feature/threshold-campaign`, pushes if credentials allow
  (else local-only + a note in STATUS.md), and **deletes its own task once
  `out/DONE` appears** (saturation auto-stop).

## Deterministic preview (full dry-run)

The simulation is fully deterministic, so the live day-by-day run reproduces this
exactly. Observed full trajectory:

- **build (days 1–14):** netA stays high (~+0.88…+0.93) while crossed strength
  forms **gradually** (wCrossed 0.358 → 0.776). build's *behavioral* netA plateaus
  early (approach is near-max once wCrossed > ~0.3), so build saturates at day 14.
- **reversal (days 15–35):** the key result. netA declines **monotonically over
  ~18 days** from its onset peak **+0.844 (day 17) → +0.220 (day 35)** as uncrossed
  strength overtakes crossed (wUncrossed 0.358 → 0.858, wCrossed 0.776 → 0.574).
  reversal saturates (Δ_day < ε for 3 days) at **day 35 → DONE**.

netA over the reversal (per day):
```
d15 +0.774  d16 +0.820  d17 +0.844  d18 +0.804  d19 +0.749  d20 +0.710
d21 +0.696  d22 +0.629  d23 +0.592  d24 +0.508  d25 +0.458  d26 +0.410
d27 +0.375  d28 +0.339  d29 +0.310  d30 +0.298  d31 +0.280  d32 +0.256
d33 +0.245  d34 +0.236  d35 +0.220
```

## Pre-registered observation hypothesis (§9) — interpretation, not pass/fail

**H (threshold effect):** under the same R7 reversal, netA changes over **≥3 days
monotonically** and no single day exceeds 60% of the total |Δ|.

- **Supported.** After a brief 2-day onset transient, netA declines monotonically
  for ~18 days. Total decline (peak +0.844 → +0.220) = 0.624; the **largest single
  day** is ~0.084 (day 23→24) = **~13% of the total**, far under 60%. Contrast: the
  old single-variable model flipped ~100% in a single day.
- **Honest caveat (no tuning):** the reversal is **gradual but partial** — netA
  saturates at +0.220 (a 71% reduction) rather than flipping negative, because
  metaplasticity decelerates both the crossed depression and the uncrossed
  formation, so the system reaches a new equilibrium before a full sign flip. This
  decelerating, non-snapping reversal is itself the threshold/metaplasticity
  signature, and is reported as observed.
