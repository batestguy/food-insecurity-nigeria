# T17 — calibration at the exposure the 120 unsampled LGAs actually face

**Verdict: FAILS the pre-declared rule** — on the spread and, by two areas, on coverage. Written by the
secretary; the analyst hit its step cap after the fits and before the report.

| check | pass band | value | verdict |
|---|---|---|---|
| mean of z | −0.15 to +0.15 | −0.0582 | PASS |
| sd of z | 0.85 to 1.15 | **1.1776** | FAIL |
| share \|z\| ≤ 1.96 | 0.90 to 0.98 | **0.8900** (178/200) | FAIL, two areas below the floor |

200 LGAs, five groups of 40, **exposure achieved exactly 0.95 in every group** (internal edges 3/6/6/2/5).
Five fits, 192 s, all `mode_status` 0.

## Why this is the number the paper needs

T16 matched only the edges *inside* a held-out group and ignored that a held-out LGA also sits next to the
permanent 120, so it ran at 1.670 unobserved neighbours. The 120 themselves face 0.950. T17 reused T16's
exact 200 areas and regrouped them to 0.950, so exposure is the only difference between the two.

**The result refutes the bracket.** T16 and T17 are indistinguishable on spread (1.181 against 1.178) while
sitting at 1.670 and 0.950 exposure. **The failure is already present at 0.95, not introduced between 0.95
and 1.67.** The bracket [0.900, 0.940] that T16 proposed for the 120 is too optimistic; a measurement at
their own exposure gives **0.890**.

## The four designs, re-measured by the secretary on one definition

Exposure = mean number of a held-out LGA's neighbours that no fit ever sees.

| design | exposure | mean z | sd z | coverage |
|---|---|---|---|---|
| T13 single LGA | 0.88 | −0.051 | 1.111 | 0.940 |
| **T17 exact exposure** | **0.95** | **−0.058** | **1.178** | **0.890** |
| T16 matched | 1.67 | −0.068 | 1.181 | 0.900 |
| T12 whole zone | 5.4 | −0.654 | 1.648 | 0.775 |

**Read this honestly: it is not a clean curve.** Three designs between 0.88 and 1.67 exposure give 0.940,
0.890 and 0.900 — a spread comparable to the binomial noise at n = 200 (SE ≈ 0.021) plus group composition
effects. There is **no evidence of a monotone exposure effect** in that range, and the earlier framing of a
"curve" should not be used. What the data support is narrower and still useful: **coverage for a single
unsampled area among sampled neighbours is about 0.89–0.94 across three independent designs; remove a whole
region and it collapses to 0.775.**

## Verified by the secretary

- z recomputed from `calibration_exact.csv`: mean −0.0582, sd 1.1776, coverage 0.8900 (178/200); max
  difference from the stored z = 1.6e−14.
- Exposure 0.95 achieved in all five groups.
- **Leave-one-group-out, recomputed**: dropping group 1 gives sd 1.1365 and coverage 0.900 and *would pass*;
  dropping any other group still fails. The verdict sits on a single group of 40 — the same weakness as T16,
  now seen twice. Coverage is 0.890 with a group-level range of 0.878–0.900.
- Out-of-fold k coverages recomputed: 0.875, 1.000, 0.925, 0.975, 0.950 (mean 0.945).

## Deviations

1. **Construction.** T16 was built up to 19 internal pairs per group; T17 had to cut 178 of the 200 edges
   among the 200 areas to reach 22 internal edges in total — a deliberately anti-clustered partition.
   Declared in the script header before fitting; no outcome entered that choice.
2. An indexing bug (positions 1–200 used against 774-long vectors) was caught before any fit; the first
   launch failed in under a second. Five fits used of five permitted.
3. **A small unresolved discrepancy:** the agent reports T13's exposure as 0.823, my recomputation gives
   0.880. The difference is a definitional detail (links versus distinct neighbours) and does not change any
   conclusion, but the figure should not be quoted until one definition is fixed.

## Open risks

1. One group of 40 carries the pass/fail boundary, and coverage is two areas below the floor. Reporting
   "about 89%" is right; reporting "fails" without the group range would overstate the precision.
2. Exposure is matched on the mean, not the distribution: the 120 range from 0 to 3 unobserved neighbours.
3. Covariates held known for held-out areas, which flatters the model in every one of these four designs.
4. The survey design is not in the likelihood.

## Consequence for the manuscript

Quote coverage **≈ 0.89** at the exposure the 120 actually face, with the range 0.878–0.900, and note that
the same three designs span 0.89–0.94. Widen unsampled-area intervals by **k ≈ 1.18**, validated out of fold.
Do not describe the calibration as a function of exposure; describe it as a level with a floor and a
collapse. **The calibration section is closed.**
