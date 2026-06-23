# Phase 0 — engine public-API surface used by the twin

Confirmed by reading the vendored sources under `lib/engine/` (frozen @
`45ad1c0008af70ea8d901c93b7acf58a4979301f`). The twin calls only these.

## `Stimulator` (lib/engine/sim.dart)

Constructed from a `Connectome`; `params` exposes the frozen `Params`.

| Method | Signature | Meaning |
|--------|-----------|---------|
| `pulse` | `bool pulse(Synapse s, double t, double x)` | Threshold ① input event of magnitude `x` at time `t`; returns whether it fired (passed). |
| `teach` | `double teach(Synapse s, double t, double m)` | Threshold ② teacher signal `m`; returns Δw actually applied (gated by fired + eligibility + sMin). |
| `propagate` | `double propagate(Synapse s, double t)` | Forwarded magnitude, > 0 only if fired AND active AND `effective ≥ thetaPrune`; else 0. |
| `prune` | `bool prune(Synapse s, double t)` | Lazy structural elimination; true if pruned (set `active=false`). |
| `observe` | `Observation observe(Synapse s, double t)` | Read-only snapshot (`a, w, c, fired, active, firedCount, effective`) at `t`. |

## `Synapse` (lib/engine/synapse.dart)

Fields used: `w`, `a`, `c`, `active`, `lastFired`, `firedCount`, `tLast`.
Methods (used indirectly via `Stimulator`): `input`, `teach`, `effective`,
`propagate`, `maybePrune`.

- Threshold ①: `input` leaky-integrates `a = a·exp(-(t-tLast)/tauA) + x`, passes iff
  `a ≥ thetaFire`; consecutive firings within `firingWindow` raise `firedCount`.
- Threshold ②: `teach` requires `lastFired`, eligibility `e=exp(-(t-tLast)/tauE) ≥
  thetaE`, and `firedCount ≥ sMin`; then `w ← clamp(w + etaBase/(1+c)·e·m, 0, wMax)`.
- `effective(t) = w·exp(-(t-tLast)/tauE)`; pruning when silent ≥ `3·tauE` and
  `effective < thetaPrune`.

## `Connectome` (lib/engine/connectome.dart)

| Member | Signature |
|--------|-----------|
| ctor | `Connectome({Params? params})` |
| add | `Synapse addSynapse(int id, {double w = 0.0, bool active = true})` |
| save | `String toJsonString()` / `void save(String)` |
| load | `void load(String)` / `void loadFromString(String)` (schema v1) |

`synapses` is `Map<int, Synapse>`.

## `Params` (lib/engine/params.dart) — frozen §6, not touched by the twin

`wMax=1.0, thetaFire=0.5, tauA=0.3, tauE=0.3, thetaE=0.05, sMin=2, etaBase=0.15,
tauC=15.0, thetaForm=0.6, tauForm=0.5, thetaPrune=0.1`.
`firingWindow = tauE·ln(1/thetaE) ≈ 0.8987`.

## Consequence for the twin's loop timing

The twin advances engine-time by `dtEngine = 0.1` per loop step, which is **<
firingWindow (≈0.899)**. Therefore a *sustained* light (firing on consecutive steps)
accumulates `firedCount` past `sMin`, so persistent illumination — not a single
flash — is what unlocks threshold-② plasticity. This is the embodied form of the
engine's "temporal persistence" gate.
