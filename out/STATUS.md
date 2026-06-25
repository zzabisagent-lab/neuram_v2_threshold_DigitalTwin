# Threshold campaign — STATUS

- Iteration: **14** (1 call = 1 iteration; hourly schedule, calendar-independent)
- Run at: 2026-06-25T12:49:03.934688 (local) / 2026-06-25T03:49:03.934688Z (UTC)
- Phase run: **build** → **build->reversal**
- Current phase (next run): **reversal**
- netA (signed approach): **+0.869** (+ approach, − avoid)
- Δ: **0.004** (saturate: < ε=0.02 for K=3 iters)
- Saturated this phase: **true**
- Done: **false**

## Strengths
- crossed (LR,RL): **0.776**, uncrossed (LL,RR): **0.000**
- active: 4/4, functional (w≥0.1): 2/4, formed: 0, pruned: 0, mean c: 34.62

## netA history

| iter | phase | netA |
|----:|:------|-----:|
| 1 | build | +0.880 |
| 2 | build | +0.909 |
| 3 | build | +0.924 |
| 4 | build | +0.901 |
| 5 | build | +0.898 |
| 6 | build | +0.892 |
| 7 | build | +0.925 |
| 8 | build | +0.891 |
| 9 | build | +0.928 |
| 10 | build | +0.923 |
| 11 | build | +0.877 |
| 12 | build | +0.892 |
| 13 | build | +0.872 |
| 14 | build | +0.869 |

_Pre-registered (§4/§5): dayReps=8, K=3, ε=0.02, maxIterations=30. Engine + twin core frozen; campaign code additive only. seed_verification/ holds the initial 3-iteration verification._
