# neuram_v2_threshold_DigitalTwin

A minimal **digital twin** for the frozen [`neuram_v2_threshold`](https://github.com/zzabisagent-lab/neuram_v2_threshold)
engine. It puts the engine's two synaptic thresholds to work inside a **closed
embodied loop** — *sense → brain → motor → move → re-sense* — and verifies them
behaviorally.

This repository **shares no code and no git history** with the engine repo or with
`neuram_companion`. The engine is **vendored read-only** under [`lib/engine/`](lib/engine/)
(see [ENGINE_SOURCE.md](ENGINE_SOURCE.md)); **the twin does not modify the engine**,
it only calls the engine's public API.

## What the twin shows (the whole goal)

The engine's two thresholds become visible in behavior:

- **Threshold ① (signal-pass)** — a weak (far/dim) light cannot make a sensory
  synapse fire, so motor output is 0 and the agent does not move; only a strong
  (near) light fires and produces steering.
- **Threshold ② (connection strength)** — when successful approach *persists and
  repeats*, the sense→motor connection **forms gradually** (a learning curve) and
  behavior improves; when the light disappears and stimulation ceases, the
  connection **decays and is pruned** and behavior reverts; a strongly consolidated
  path resists reversal more (metaplasticity).

The task is **learning phototaxis / Braitenberg differential steering** — a
nature-first minimal closed loop. There is no other goal.

## Layout

```
lib/engine/        VENDORED read-only mirror of neuram_v2_threshold @ pinned SHA
  *.dart           engine sources (unmodified except a //VND header)
  VENDOR_MANIFEST.json   per-file body SHA-256 for REG-2
lib/twin/
  world.dart       self-contained 2D world (knows nothing about the engine)
  body.dart        sensory encoding / motor decoding via the engine's public API
  brain.dart       4 candidate sense->motor synapses; wiring is learned, not wired
  loop.dart        one closed-loop step + trial/score logic
bin/
  twin_run.dart    deterministic scenarios -> learning/decay/reversal summary
  twin_test.dart   pre-registered REG/T pass/fail bench (exit != 0 on any fail)
  telemetry.dart   event-driven NDJSON emission (off by default)
docs/
  PHASE0_api.md    the engine public-API surface the twin relies on
  TWIN_RESULTS.md  measured results
  TELEMETRY.md     telemetry stream schema
  RESULTS.md       pre-registered telemetry criteria, measured
```

## Run

```bash
dart analyze
dart run bin/twin_run.dart    # scenarios + docs/TWIN_RESULTS.md style summary
dart run bin/twin_test.dart   # PASS/FAIL table; exit code != 0 on any FAIL
```

## Watch a run happen

The summary tells you where a run ended up, not how it got there. `--telemetry`
emits an event stream — stimulus, synapse state, plasticity, motor output — as
NDJSON on stdout, one JSON object per line:

```bash
dart run bin/twin_run.dart --telemetry                    # scenario: learning
dart run bin/twin_run.dart --telemetry --scenario=decay   # also form/prune events
```

Emission is **passive**. The engine computes every time decay lazily, on touch, so
polling it would wake the very state it wanted to read. Every emission happens at a
moment the twin was already touching that state, and nothing is touched in order to
emit — which is why quiet intervals are quiet in the stream. That silence is the
visible form of the zero-idle principle, not a gap in the instrumentation.

Telemetry is off by default, costs one null check per site when off, and does not
change any result. With it on, the stream owns stdout and the human summary moves to
stderr. See [docs/TELEMETRY.md](docs/TELEMETRY.md) for the schema and
[docs/RESULTS.md](docs/RESULTS.md) for the verification.

Live views — a stream server, a dependency-free web dashboard, a terminal UI and
reproducibility tools — live in
[`neuram_observatory`](https://github.com/zzabisagent-lab/neuram_observatory),
which reads these lines and links nothing.

Pure Dart 3.8.1, offline, deterministic (fixed seed), no external dependencies
(the engine is used via vendored path imports).
