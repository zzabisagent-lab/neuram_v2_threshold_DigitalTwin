# TWIN_RESULTS — embodied verification of the two thresholds

Benches (deterministic, seed 42, no external dependencies):

```
dart run bin/twin_run.dart    # scenario summary (A learning, B decay, C reversal)
dart run bin/twin_test.dart   # pre-registered REG/T pass/fail; exit != 0 on any FAIL
```

This run: **8/8 scored criteria PASS**, exit 0.

## Design summary

A learning **phototaxis / Braitenberg** closed loop drives the frozen engine
through its public API only (the engine is vendored read-only under `lib/engine/`;
REG-2 verifies it is byte-identical to the pin).

- **World** (`lib/twin/world.dart`): differential-drive agent + point light;
  left/right sensors read `Imax/(1+falloff·d²)·max(0,cosBearing)`. The
  left/right asymmetry is the steering signal.
- **Body** (`lib/twin/body.dart`): sensory pulse `x = sensorGain·I` (threshold ①);
  wheel speed = Σ `propagate` over a motor's synapses (threshold ②'s gated
  propagation becomes motion).
- **Brain** (`lib/twin/brain.dart`): 4 candidate sense→motor synapses start at
  `w=0` (not hardwired). The goal-directed teacher reinforces the
  bright-sensor→contralateral-motor synapse; the crossed (approach) pair is
  **carved out by reward, never wired**. Engine-time advances `dtEngine=0.1 <
  firingWindow (≈0.899)`, so sustained light accumulates `firedCount` past `sMin`
  — the embodied form of the engine's temporal-persistence gate.
- **Learning unit**: each trial reinforces once per side (an embodied B1-style
  presentation), so the across-trial strength follows the engine's verified
  gradual-formation curve. (Per-step online teaching saturates `w` within a single
  trial given the frozen `etaBase`; episodic consolidation is what exposes the
  multi-trial learning curve. This is a twin-side design choice; no §6/§7 parameter
  was changed.)

## REG — independence / vendoring / soundness

| ID | Result | Evidence |
|----|--------|----------|
| REG-1 | PASS | Independent history (1 root commit; no engine/companion SHA); README + ENGINE_SOURCE document separation and that the engine is frozen / not modified. |
| REG-2 | PASS | All 5 vendored engine files byte-identical to engine @ `45ad1c0` (FNV-1a body hashes match the manifest, header excluded). The twin does not modify the engine. |
| REG-3 | PASS | No external dependencies; SDK `^3.8.1`; deterministic (same seed ⇒ identical learning curve); build/test executed. |

## T — embodied verification of the two thresholds

| ID | Result | Measured |
|----|--------|----------|
| **T-①** (signal-pass) | PASS | far light (d=60) → motor **0**; light off → motor **0**; near light (d=4) → motor **1.106 > 0**. Only sufficient light fires and steers. |
| **T-②-form** (gradual learning) | PASS | trial-1 score **0.000** < 0.30·final (0.276); 95% of final needs **9 trials** (≥4); max single-trial gain **0.326** < 0.60·final (0.552); survivors are the **crossed** pair (LR,RL>0; LL,RR=0). final≈0.92. |
| **T-②-prune** (decay/reversion) | PASS | after 30 dark steps (silence ≥ 3·tauE) the learned paths are **pruned (active=false)**; immediate approach response **0.060 → 0.000** (< 0.5×). (On sustained re-exposure the agent re-forms/relearns — latent `w` is retained.) |
| **T-meta** (metaplasticity) | PASS | weakly consolidated (c≈2.4) reverses in **2** trials; strongly consolidated (c≈22.2) needs **19** trials — higher consolidation resists reversal. |
| **T-persist** | PASS | save → new Connectome → load restores `w/c/active/tLast` exactly; post-reload score **0.880 == 0.880** control (the twin clock `brain.t` is restored with the state). |

### T-②-form learning curve (per-trial approach score)

```
trial:  1     2     3     4     5     6     7     8     9    10    11    12    13   ...  30
score: 0.00  0.37  0.58  0.71  0.75  0.78  0.82  0.87  0.88  0.92  0.92  0.91  0.94 ... 0.92
```

Gradual, decelerating rise over many trials (not one-shot), with no single trial
dominating — the embodied image of the engine's threshold-② gradual formation.
Final synapse strengths: **LR=0.553, RL=0.553** (crossed, survived) vs **LL=0.000,
RR=0.000** (uncrossed, never reinforced).

### T-②-prune timing

After learning (crossed w≈0.553, retained latently), 30 dark steps drive the lazy
effective strength below `thetaPrune`; `pruneAll` sets `active=false` on the learned
paths. The **immediate** post-dark response is ~0 (a pruned synapse is silent until
it structurally re-forms). Over a full 60-step re-exposure the agent **relearns**
(score recovers to ≈0.90) because `w` is retained — a faithful, reported consequence
of the engine's re-formation on a silent synapse.

## OBS — observation only (not scored)

**OBS-1.** The surviving wiring is **crossed** — LR (left→right motor) and RL
(right→left motor) both ≈0.553, while the uncrossed LL/RR stay 0. This matches the
nature-first phototaxis prediction (contralateral steering turns the agent toward
the brighter side). The crossed map was carved out purely by the goal-directed
reward; it was never wired in code.

## Honesty notes

- No §6 engine parameter and no §7 twin parameter was changed. Geometry (teaching/
  probe poses) and the score formula are as specified; the per-trial (episodic)
  reinforcement cadence is a twin-side design choice documented above.
- **T-②-prune nuance (reported, not hidden):** with the frozen engine, a pruned
  synapse re-forms quickly on bright re-exposure (firing and structural re-formation
  are both gated by the same sensory drive), so the behavioral reversion is captured
  as the *immediate* post-dark response; the full-trial behavior recovers via
  relearning from the retained latent `w`. Both facts are surfaced by the bench.
