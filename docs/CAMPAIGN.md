# Threshold campaign — design, pre-registration, preview

A self-stopping auto-simulation that drives the **frozen** threshold engine + twin
(public API only — no engine/twin-core edits) through an R7-style **reward
reversal**, **one iteration per run**, and stops when the change saturates or a
global iteration cap is hit. Question: is the model's reversal a **single step**
(old single-variable model) or a **multi-iteration gradual** transition
(threshold/metaplasticity model)?

## Calendar-free iteration model

"day" was an internal counter, not a calendar day — so it is renamed **iteration**.
One run = one iteration = `dayReps` reinforcement rounds. The scheduler fires
**hourly** (with a 55-min guard against double-runs), but the experiment counts
iterations, not days. Each iteration records `runAtUtc`/`runAtLocal` (wall-clock
audit).

## Pre-registered configuration (§4/§5) — locked, not tuned

- Individual: the twin learning-phototaxis closed loop, 1 agent (seed 42), lifetime
  learning (synaptic state persists across iterations).
- **netA** = signed net approach, mean over a left-light and right-light probe of
  `(dInitial − dFinal)/dInitial` (+ = approach, − = recede). Read-only probe.
- **build**: normal phototaxis reward. **reversal**: reward flipped (R7 conflict).
- **iteration** = `dayReps = 8` reinforcement rounds (each = one left + one right).
- **Termination (locked) — either ends it:**
  1. **Saturation:** last **K = 3** within-phase iterations all have
     `|Δ netA| < ε = 0.02` (build→reversal; reversal→done).
  2. **Global cap:** `iteration > 30` ⇒ done immediately (phase-independent).
- K, ε, cap, dayReps fixed before running and not changed to shape results. Engine
  §6 and twin §7 parameters untouched.

## Runner & automation

- `dart run bin/campaign_iter.dart` — advance one iteration (respects the 55-min
  guard; `--force` bypasses for demos). Writes `out/iter/iter_NNN.json`, appends
  `out/campaign_log.csv` (incl. `iteration`, `runAtUtc`), updates `out/state.json`
  (resumable: connectome + twin clock + phase/iteration), refreshes
  `out/STATUS.md`. On termination writes **`out/DONE` + `out/FINAL_REPORT.md`**.
- `run_hourly.ps1` + scheduled task **`NeuRAM_ThresholdCampaign_Hourly`** (every
  1 h): runs an iteration, commits `out/` to `feature/threshold-campaign`, pushes
  if credentials allow (else records the failure in `out/last_run.txt` +
  `STATUS.md`), and **deletes its own task once `out/DONE` appears**. The old daily
  task / `run_daily.ps1` are removed; the initial 3-day batch is archived under
  `seed_verification/`.

## Repo-resident completion signal

An unattended scheduler can't message a chat session, so completion is recorded
**in the repo**: `out/DONE` (reason + final iteration/netA), `out/FINAL_REPORT.md`
(full result), and a `done:` commit. Reopening the repo shows immediately whether
it finished, why, and the outcome.

## Deterministic preview (full force dry-run)

The sim is deterministic (seed 42; only timestamps vary), so the live hourly run
reproduces these values:

- **build (iter 1–14):** netA stays high (~+0.88…+0.93) while crossed strength
  forms **gradually** (wCrossed 0.358 → 0.776). build's behavioral netA plateaus
  early, so build **saturates at iteration 14 → reversal**.
- **reversal (iter 15–31):** netA declines **monotonically** from its onset peak
  **+0.844 (iter 17) → +0.280 (iter 31)** as uncrossed strength overtakes crossed
  (wUncrossed 0.358 → 0.814, wCrossed 0.776 → 0.605). The **global cap (iteration >
  30)** terminates at **iteration 31** (reversal still gradually progressing, not
  yet at its own saturation), writing DONE + FINAL_REPORT.

## §10 observation hypothesis — interpretation, not pass/fail

**H:** under the same R7 reversal, netA changes over **≥3 iterations monotonically**
and no single iteration exceeds 60% of the total |Δ|.

- **Supported.** After a brief 2-iteration onset transient, netA declines
  monotonically for ~14 iterations. Total decline (peak +0.844 → +0.280) ≈ 0.564;
  the **largest single iteration** is ~0.084 ≈ **15%** of the total — far under 60%.
  Contrast: the old single-variable model flipped ~100% in one step.
- **Honest caveat (no tuning):** the reversal is **gradual but partial** — netA is
  +0.280 at the cap (a ~68% reduction from peak) and has not flipped negative,
  because metaplasticity decelerates both the crossed depression and uncrossed
  formation. This decelerating, non-snapping reversal is itself the
  threshold/metaplasticity signature, reported as observed.
