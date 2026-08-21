# TELEMETRY — event-driven observation of the twin

The twin used to run its thirty trials and print a summary. The process in between
was invisible, and that is how a campaign that stopped on its iteration cap on
2026-06-26 went unnoticed for two months. Observation is a precondition for running
experiments here, not a convenience feature.

This document specifies the telemetry stream: what is emitted, when, and what each
number means. It is the contract the observatory, the terminal UI and the trace
tools are written against.

---

## 1. Principles

### 1.1 Observation is passive

The engine computes every time decay **lazily**, at the moment a synapse is touched
by an event. Nothing is recomputed on a tick, so an idle synapse costs nothing —
this is the zero-idle principle, in the implementation rather than in the prose.

A periodic poll would have to touch the state in order to read it. The act of
observing would wake the engine, and the measurement would be of the instrument as
much as of the system. So:

- **push only, never pull.** Every emission happens at a moment the twin was
  already going to touch that state, and reports the value the engine produced
  there.
- **nothing is touched in order to emit.** No emission advances a clock, delivers a
  pulse, or forces a decay.
- **quiet intervals are quiet in the stream.** That silence is the visible evidence
  of zero-idle, not a hole in the instrumentation. A recorded run of the decay
  scenario contains a 3.0-unit stretch with no events at all; that is the dark
  interval, and it is supposed to look like that.

The model is the electrophysiology bench. An electrode does not wake the neuron; it
records, passively, a potential change that had already happened.

### 1.2 The twin knows nothing about transport

`lib/twin/telemetry.dart` writes NDJSON lines to a `StringSink`. There is no socket,
screen or file logic anywhere under `lib/twin/`. That is what lets the same code run
unchanged on a server, on a Raspberry Pi rover, or on a phone — carrying the lines
somewhere else is a separate program's job.

### 1.3 Observation does not change the result

Emission only reads. A run with `--telemetry` and a run without produce the same
score curve, the same final strengths and the same bench verdict.

### 1.4 The engine is never modified

`lib/engine/` is a read-only vendored mirror, verified by REG-2 against
`lib/engine/VENDOR_MANIFEST.json`. Telemetry reads only what the engine's public API
already exposes.

---

## 2. Running

```bash
dart run bin/twin_run.dart                        # unchanged: A, B and C summaries
dart run bin/twin_run.dart --telemetry            # NDJSON on stdout (scenario: learning)
dart run bin/twin_run.dart --telemetry --scenario=decay
dart run bin/twin_run.dart --telemetry --scenario=reversal
dart run bin/twin_run.dart --scenario=learning    # that scenario's summary, no stream
```

Telemetry is **off by default**, and each emission site is a single null check when
it is off.

With `--telemetry` the stream owns **stdout** and the human summary moves to
**stderr**, so a piped stream never interleaves with prose:

```bash
dart run bin/twin_run.dart --telemetry | some-observer      # pure NDJSON
dart run bin/twin_run.dart --telemetry 2>/dev/null > run.ndjson
```

A stream describes exactly one scenario, which `run.start` names:

| scenario   | what it runs                                                        |
|------------|---------------------------------------------------------------------|
| `learning` | 30 trials of probe-then-reinforce (`learnCurve`) — section A         |
| `decay`    | 30 reinforcement rounds, probe, dark interval + prune, re-probe — B  |
| `reversal` | build 30 rounds, then reversed reinforcement until the uncrossed pair overtakes (cap 200) — the strongly-consolidated case of section C |

`form` and `prune` events occur only in the `decay` scenario: in `learning` the
synapses start realized and pruning is never evaluated.

---

## 3. Format

NDJSON — one JSON object per line, LF-terminated. Every line carries, in this order:

| field | type   | meaning                                            |
|-------|--------|----------------------------------------------------|
| `seq` | int    | 0-based, strictly increasing by 1, no gaps          |
| `t`   | double | simulation (engine) time of the event               |
| `ev`  | string | event kind                                          |

Doubles are serialized with Dart's shortest round-trip representation and are
**never rounded**. A stream can therefore be compared bit-for-bit, which is the
point: the same comparison has to serve a future Dart-versus-Rust check and an
ARM64 port.

---

## 4. Events

### `run.start`

```json
{"seq":0,"t":0.0,"ev":"run.start","engineSha":"45ad1c0008af70ea8d901c93b7acf58a4979301f",
 "twinSha":"3ac84bc","seed":42,"scenario":"learning",
 "params":{"wMax":1.0,"thetaFire":0.5,"tauA":0.3,"tauE":0.3,"thetaE":0.05,"sMin":2,
           "etaBase":0.15,"tauC":15.0,"thetaForm":0.6,"tauForm":0.5,"thetaPrune":0.1,
           "firingWindow":0.8987196820661972},
 "twinParams":{"sensorAngle":0.5,"imax":1.0,"falloff":0.01,"sensorGain":0.7,
               "turnGain":0.3,"moveGain":1.0,"dtEngine":0.1,"teachDelta":0.02,
               "stepsPerTrial":60,"trials":30,"darkSteps":30,"seed":42},
 "nTrials":30}
```

- `engineSha` — read from `lib/engine/VENDOR_MANIFEST.json`; the pinned engine commit.
- `twinSha` — `git rev-parse --short HEAD` at run time, or `"unknown"` outside a checkout.
- `params` — the eleven frozen engine parameters. `firingWindow` is included as well:
  it is *derived* (`tauE·ln(1/thetaE)`), not a free parameter, but a reader needs it
  to interpret `fc`.
- `nTrials` — trials the scenario declares. For `reversal` this is the upper bound
  (30 build rounds + the 200 cap); the actual count is evident from the stream.
- `seed` — recorded for provenance. **The twin contains no RNG**: `seed` is never
  read by the dynamics, and changing it cannot change a run.

### `trial.start` / `trial.end`

```json
{"seq":1,"t":0.0,"ev":"trial.start","trial":0}
{"seq":99,"t":5.0,"ev":"trial.end","trial":0,"score":0.326,
 "w":{"LL":0.0,"LR":0.127,"RL":0.127,"RR":0.0}}
```

- `trial` — index, monotonic across the run.
- `score` — the trial's approach score, `clamp(1 - dFinal/dInitial, 0, 1)`, or
  **`null`** when the trial contains no scored probe. A reinforcement-only round
  (`train`) measures nothing, and reporting a number there would be an invention.
- `w` — stored strengths at the end of the trial.

A trial is a scenario-level round. A probe that runs *inside* one (as `probeScore`
does inside a learning trial) belongs to that trial and does not open a nested one;
a probe that runs on its own — the before/after readings around a pruning interval —
becomes a trial in its own right. That is what puts a score on the learning curve
next to the prune marker that explains it.

### `sense` — layer 1, stimulus

```json
{"seq":2,"t":0.1,"ev":"sense","sL":0.231,"sR":0.164,"light":{"x":0.0,"y":18.0}}
```

`sL` / `sR` are the left and right sensor intensities the twin just read. When the
light is off or out of range both are `0.0`, and no `syn` or `fire` event follows —
a dark sensor generates no input event at all.

### `syn` — layer 2, synapse state

```json
{"seq":3,"t":0.1,"ev":"syn","id":"LR","a":0.161,"e":0.0013,"w":0.0,"c":0.0,"fc":0}
```

Emitted **once per synapse per input event it actually received**, immediately after
that input. A synapse that received no input at this step emits nothing.

- `id` — `LL`, `LR`, `RL`, `RR`. Crossed (phototaxis-correct) are `LR` and `RL`.
- `a` — the activation accumulator the engine produced at `t`, i.e. the value the
  firing threshold was tested against. Directly comparable to `thetaFire`.
- `e` — the eligibility factor the engine applied **at this event**:
  `exp(-(t - tLast)/tauE)`, with the `tLast` that was in force when the event
  arrived (that is, before this input reset it). This is the quantity the staleness
  gate tests, so it is directly comparable to `thetaE`.
- `w` — stored strength (not decayed; `effective` is `w·exp(-(t-tLast)/tauE)`).
- `c` — consolidation state.
- `fc` — `firedCount`, recent consecutive firings, comparable to `sMin`. Two firings
  count as consecutive when they fall within `firingWindow`.

### `fire`

```json
{"seq":4,"t":0.1,"ev":"fire","id":"LR","a":0.640}
```

Emitted when an input crossed threshold ①. `a` is the accumulator at the crossing.

### `plast` — threshold ②

```json
{"seq":5,"t":0.12,"ev":"plast","id":"LR","w0":0.0,"w1":0.021,
 "eta":0.15,"e":0.936,"m":1.0}
```

Emitted for **every teacher signal the twin delivered**, including those the engine
gated out — in which case `w0 == w1`. Emitting only the effective ones would hide
the eligibility and persistence gates precisely when they are doing their work.

- `w0` / `w1` — strength before and after.
- `eta` — the effective learning rate `etaBase/(1+c)` with the `c` in force before
  the update; this is metaplasticity, visible.
- `e` — eligibility at the teaching moment, `exp(-(t - tLast)/tauE)` where `tLast`
  is the driving input. Below `thetaE` the signal is ignored.
- `m` — teacher magnitude. `+1.0` reinforces, `-1.0` depresses (reversal).

### `form` / `prune` — structural change

```json
{"seq":6,"t":0.3,"ev":"form","id":"LR","acc":0.624}
{"seq":7,"t":2.5,"ev":"prune","id":"LL","w":0.553}
```

- `form` — a silent synapse became realized; `acc` is `formAcc` at realization,
  which had reached `thetaForm`.
- `prune` — a synapse was structurally eliminated. `w` is the **stored** strength at
  that moment. Note that the rule tests the *effective* strength
  (`w·exp(-(t-tLast)/tauE) < thetaPrune` after stimulation ceased for `3·tauE`), so
  a prune with a large `w` is normal and is exactly the "latent strength retained"
  case: the connection is silent but has not forgotten.

### `act` — layer 3, output and behavior

```json
{"seq":8,"t":0.1,"ev":"act","mL":0.0,"mR":0.0,"x":0.0,"y":0.0,"th":1.271}
```

Motor speeds and the pose they produced. `x`, `y`, `th` are the pose **after** the
move, so the sequence of `act` events is exactly the trajectory.

### `run.end`

```json
{"seq":31583,"t":492.0,"ev":"run.end","nEvents":31584,"nFire":10838,"nPlast":60,
 "nForm":0,"nPrune":0,
 "finalW":{"LL":0.0,"LR":0.553,"RL":0.553,"RR":0.0},"wallMs":389}
```

`nEvents` counts every line including this one. `nFire`/`nPlast`/`nForm`/`nPrune`
count emitted events of those kinds; `neuram_trace summary` recomputes them and
reports any mismatch.

> **`wallMs` is not reproducible, and cannot be.** It is a measured wall-clock
> duration, which the schema mandates. Two identical runs therefore differ in
> exactly this one field and nowhere else. Tools treat `run.end.wallMs` as a
> declared volatile field; `neuram_trace verify` reports a `bytes` verdict and a
> `content` verdict separately for this reason. See §7.

### `campaign.iter` — layer 4

```json
{"seq":31,"t":31.0,"ev":"campaign.iter","iter":31,"phase":"reversal",
 "netA":0.27956113257820847,"wX":0.6048578606487003,"wU":0.8141813756227735,
 "dNetA":-0.01817818561768403,"sat":false,"done":true,"reason":"max-iterations"}
```

- `iter` — campaign iteration number.
- `phase` — `build` or `reversal`.
- `netA` — **signed net approach**: the mean over a left-light and a right-light
  probe. Positive means approach, negative means recede. It is a **behavioral
  measure, not a weight.**
- `wX` / `wU` — mean crossed (`LR`,`RL`) and uncrossed (`LL`,`RR`) strengths.
- `dNetA` — the **signed** change in `netA` since the previous iteration; `null` on
  the first. The campaign's own log records only the magnitude, and the sign is what
  separates convergence from reversal.
- `sat` / `done` / `reason` — saturation flag, termination flag, termination reason.

> **`netA` and `wX`/`wU` must be read on separate axes.** `wU > wX` together with
> `netA > 0` is not a contradiction — it is the state in which the wiring has
> already flipped while the behavior still approaches. The recorded campaign is in
> exactly that state at its final iteration: `wU` 0.814 > `wX` 0.605, and `netA`
> still +0.280. Putting them on one axis hides the only interesting thing about it.

`t` carries the **iteration index** for these events. A campaign iteration is a
separate twin run with its own engine clock, so there is no shared simulation time
to place it on, and the iteration is the axis the campaign advances along.

The twin runner does not emit `campaign.iter`: the campaign runner lives on the
`feature/threshold-campaign` branch and was deliberately not touched, since the
campaign must not be resumed and its iteration cap must not be changed. Recorded
campaigns are brought into this schema after the fact with
`neuram_trace campaign-import`, which reads files and writes NDJSON and runs
nothing.

---

## 5. What is deliberately not emitted

- **No event for a synapse that received no input.** A dark sensor produces no input
  event, so there is nothing to record. This is what makes silence meaningful.
- **No periodic snapshot.** There is no timer anywhere in the emission path.
- **No interpolated or back-filled values.** If the engine did not compute it, the
  stream does not contain it.

---

## 6. Reading the stream

The four layers share one time axis, which is what makes cause and effect legible:

| layer | events                       | source                     |
|-------|------------------------------|----------------------------|
| 1 stimulus | `sense`, `trial.*`      | `world.dart`, `scenarios.dart` |
| 2 engine internals | `syn`, `fire`, `plast`, `form`, `prune` | `brain.dart`, engine public API only |
| 3 output / behavior | `act`             | `body.dart`, `loop.dart`   |
| 4 campaign | `campaign.iter`         | imported from campaign records |

Tooling lives in the [`neuram_observatory`](https://github.com/zzabisagent-lab/neuram_observatory)
repository: a stream server, a single-file web dashboard, a terminal UI, and
`neuram_trace` for summary, diff and reproducibility checks.

---

## 7. Reproducibility

Two runs of the same scenario produce byte-identical NDJSON **except for
`run.end.wallMs`**, which is a wall-clock measurement the schema requires. Measured
on the `learning` scenario: 31 583 of 31 584 lines byte-identical, the difference
confined to that single field.

```bash
# is this the same run twice?
dart run bin/neuram_trace.dart verify \
  --run="dart run bin/twin_run.dart --telemetry --scenario=learning" \
  --cwd=/path/to/neuram_v2_threshold_DigitalTwin

# where did two streams first diverge?
dart run bin/neuram_trace.dart diff a.ndjson b.ndjson            # bitwise
dart run bin/neuram_trace.dart diff a.ndjson b.ndjson --tol=1e-9 # tolerant
```

`--tol=0` (the default) is bitwise. `--volatile` names fields allowed to differ and
defaults to `run.end.wallMs`. Both exist because this comparison has to serve the
later Dart-versus-Rust bit-identity check and the ARM64 port, where telling a real
divergence from floating-point noise is the whole question.

See [`docs/RESULTS.md`](RESULTS.md) for the pre-registered acceptance criteria and
their measured outcomes.
