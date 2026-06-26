# Threshold campaign — FINAL REPORT

- **Termination:** max-iterations (saturation = K=3 iters with |Δ netA| < ε=0.02; global cap = iteration > 30)
- **Total iterations:** 31
- **Finished at:** 2026-06-26T12:49:03.396074 (local) / 2026-06-26T03:49:03.396074Z (UTC)
- **Final netA:** +0.280 (+ approach, − avoid)
- **Final strengths:** crossed (LR,RL) 0.605, uncrossed (LL,RR) 0.814, mean c 98.27

## Phase transitions

- iteration 14: build → reversal (saturation)
- iteration 31: reversal → done (max-iterations)

## netA per iteration

| iter | phase | netA | crossed | uncrossed |
|----:|:------|-----:|--------:|----------:|
| 1 | build | +0.880 | 0.358 | 0.000 |
| 2 | build | +0.909 | 0.458 | 0.000 |
| 3 | build | +0.924 | 0.519 | 0.000 |
| 4 | build | +0.901 | 0.563 | 0.000 |
| 5 | build | +0.898 | 0.598 | 0.000 |
| 6 | build | +0.892 | 0.628 | 0.000 |
| 7 | build | +0.925 | 0.653 | 0.000 |
| 8 | build | +0.891 | 0.676 | 0.000 |
| 9 | build | +0.928 | 0.696 | 0.000 |
| 10 | build | +0.923 | 0.715 | 0.000 |
| 11 | build | +0.877 | 0.732 | 0.000 |
| 12 | build | +0.892 | 0.748 | 0.000 |
| 13 | build | +0.872 | 0.762 | 0.000 |
| 14 | build | +0.869 | 0.776 | 0.000 |
| 15 | reversal | +0.774 | 0.763 | 0.358 |
| 16 | reversal | +0.820 | 0.751 | 0.458 |
| 17 | reversal | +0.844 | 0.738 | 0.519 |
| 18 | reversal | +0.804 | 0.727 | 0.563 |
| 19 | reversal | +0.749 | 0.716 | 0.598 |
| 20 | reversal | +0.710 | 0.705 | 0.628 |
| 21 | reversal | +0.696 | 0.695 | 0.653 |
| 22 | reversal | +0.629 | 0.685 | 0.676 |
| 23 | reversal | +0.592 | 0.675 | 0.696 |
| 24 | reversal | +0.508 | 0.666 | 0.715 |
| 25 | reversal | +0.458 | 0.656 | 0.732 |
| 26 | reversal | +0.410 | 0.647 | 0.748 |
| 27 | reversal | +0.375 | 0.638 | 0.762 |
| 28 | reversal | +0.339 | 0.630 | 0.776 |
| 29 | reversal | +0.310 | 0.621 | 0.790 |
| 30 | reversal | +0.298 | 0.613 | 0.802 |
| 31 | reversal | +0.280 | 0.605 | 0.814 |

## Notes

- Engine (`lib/engine/`) and twin core (`lib/twin/`) are **frozen** (campaign code is additive: `lib/campaign/`, `bin/`). Deterministic sim (seed 42); timestamps are wall-clock audit only.
- The initial 3-iteration build-time verification is archived under `seed_verification/`.
- §10 hypothesis: a multi-iteration (≥3) monotone netA transition under the R7 reversal, with no single iteration exceeding 60% of the total |Δ| — vs the old single-variable ~100%-in-one-step. See the table above.
