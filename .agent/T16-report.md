# T16 — calibration at the neighbour exposure the 120 unsampled LGAs face

**Verdict: FAILS the pre-declared rule, on one check, narrowly — and is far better than T12 on all
three. The transfer argument survives; the 95% claim for unsampled areas does not.**

| check | pass band | value | verdict |
|---|---|---|---|
| mean of z | −0.15 to +0.15 | **−0.0681** | PASS |
| sd of z | 0.85 to 1.15 | **1.1807** | **FAIL** |
| share \|z\| ≤ 1.96 | 0.90 to 0.98 | **0.9000** (180/200) | PASS, on the floor |

Command: `Rscript scripts/calibration_matched_exposure.R`. Exit 0, five of five groups on disk.
R 4.5.2, INLA 25.10.19, seed 20261124. Five fits, 46.4 / 39.5 / 38.4 / 40.8 / 40.0 s, all mode
status 0.

## The exposure, target versus achieved

`e120 = 0.4750` adjacent pairs per LGA — 57 queen-contiguity edges with both ends among the 120
unclustered LGAs, over 120. Target band on pairs per LGA: **[0.3800, 0.5700]**.

| group | LGAs | internal pairs | pairs/LGA | ratio to e120 | in band |
|---|---|---|---|---|---|
| 1 | 40 | 19 | 0.4750 | 1.000 | yes |
| 2 | 40 | 18 | 0.4500 | 0.947 | yes |
| 3 | 40 | 19 | 0.4750 | 1.000 | yes |
| 4 | 40 | 19 | 0.4750 | 1.000 | yes |
| 5 | 40 | 19 | 0.4750 | 1.000 | yes |
| 120 unsampled | 120 | 57 | 0.4750 | 1.000 | — |

Groups span 22, 24, 22, 25 and 22 states, so the held-out areas are not one region.

The graph and the exposure reproduce the secretary's figures exactly: median share of neighbours
observed **0.8333**, **2** of 120 below half observed, **36** fully observed, minimum **0.3333**.

## Three-experiment comparison

| design | what is removed | exposure, unobserved neighbours per LGA | n | mean z | sd z | coverage |
|---|---|---|---|---|---|---|
| T12, whole zone | the area **and every neighbour** | ≈5.4 (whole neighbourhood) | 654 | −0.654 | 1.648 | 0.775 |
| **T16, matched** | **40 LGAs with matched exposure** | **1.67** (measured, see below) | **200** | **−0.068** | **1.181** | **0.900** |
| T13, single LGA | one LGA, neighbours kept | 0.82 (adjacency to the 120 only) | 200 | −0.051 | 1.111 | 0.940 |
| **the 120 themselves** | **never sampled** | **0.95** | 120 | — | — | — |

**Does T16 lie between T12 and T13? Yes, on all three checks.** Coverage 0.775 → 0.900 → 0.940;
sd of z 1.648 → 1.181 → 1.111; mean z −0.654 → −0.068 → −0.051. T16 minus T12: mean z +0.586,
sd z −0.467, coverage +0.125. T16 minus T13: −0.017, +0.070, −0.040. Ordering is monotone in
neighbour exposure across four designs, which is the signature expected if exposure is the
mechanism.

**T16 is not no better than T12.** It is much better on every check. The paper's transfer argument
is not broken by this result.

## The finding that matters for how this is read

The brief's e120 counts only the neighbours held out *with* the area. A held-out clustered LGA also
has neighbours among the **permanent 120**, which no fit of any ticket ever sees. Measured after
the fits, from the same graph:

```
120 set: unobserved neighbours per LGA 0.9500 (distribution 0:36  1:58  2:22  3:4)
held-out: within-group 0.9400 + adjacent to the 120 0.7300 = 1.6700 total  (1.758 x the 120's)
T13's exposure by the same measure: 0.8226 (mean adjacency to the 120 over the 654)
```

So **the groups were over-exposed by 1.76×**. T16 is a harsher test than the paper's problem. The
120's true coverage is therefore **bracketed** between T16's 0.900 (exposure 1.67) and T13's 0.940
(exposure 0.82), because the 120 sit at 0.95 between them. That bracket assumes coverage is monotone
in exposure; three points cannot prove it.

The design and the pass rule were not touched when this was found. It was added to the script as a
descriptive block after the five fits, and it changes no number in the verdict.

## Changed

- `scripts/calibration_matched_exposure.R` — new. Builds the 774-node queen graph, measures e120,
  constructs the five matched groups, fits the T13 model five times, scores, writes both artefacts.
  Supports `--design-only`; resumable per group.
- `data/derived/calibration_matched.csv` — 200 rows, T13's 23 columns plus `internal_pairs`.
- `data/derived/calibration_matched.json` — 21.5 KB: e120, per-group achieved, the three checks with
  bands and bootstrap intervals, the three-experiment comparison, the exposure audit, the post-hoc
  leave-one-group-out block, limitations.
- `.agent/T16-progress.md`, `.agent/T16-report.md`.

Nothing else written. No T12–T15 artefact or script read for writing, only for the comparison table.
No git, no network.

## Verified

1. **Graph rebuilt independently** (separate script, separate R session): 774 nodes, 2,230 edges,
   0 isolates; every held-out `lga_id` matched; recomputed internal pairs **19, 18, 19, 19, 19** —
   identical to what the CSV records.
2. **Checks recomputed from the CSV**, not from the fitting objects: mean z −0.068074, sd 1.180651,
   coverage 0.900000 (180 of 200), rms 1.1797. Identical to the script's printed values.
3. **Cluster counts**: `cluster_lga_fixed.csv` gives 1,380 clusters in 654 LGAs and 120 with none;
   per-LGA counts are **identical** to the household file's for all 774; the recorded `n_clusters`
   column in the output equals the fixed file for every row. The output contains no cluster count
   taken from `lga_estimates.csv` or `lga_coverage.csv`.
4. **Design checks**: 200 rows, no duplicate LGA, every group exactly 40, groups disjoint, all 200
   drawn from the 654 clustered LGAs, held-out household totals match the full file.
5. **Convergence**: mode status 0 in all five fits; WAIC reported per group (not comparable across
   groups — different training sets).
6. **Resumability**: second run took **8.7 s**, skipped all five groups, reproduced every number.
7. **Fit cap respected**: 5 fits, exactly the allowance.

## Deviations

1. **Constructed groups, not a plain draw-then-split.** A uniform 40 of 654 has expected internal
   pairs `C(40,2)·2·2230/(774·773) = 5.81`; the target is 19.00, so no plain split could be within
   ±20% except by chance. Groups were built by random start plus a deterministic swap search to
   `round(40·e120)`. Declared in the script header before any fit, and the band was checked in a
   `--design-only` run before a single model was fitted. Achieved: 19, 18, 19, 19, 19.
2. **The exposure audit above** — a measurement added after the fits, reported because it changes
   what the number means, not because it changes the verdict.
3. **Two descriptive blocks added to the script after the first run** (exposure audit, leave-one-
   group-out). Neither alters the design, the model, the scoring or the pass rule.

## Open risks

1. **One group of 40 carries the failure.** Group 1 has 8 of the 20 misses, sd 1.448, coverage 0.800.
   Without it: n 160, mean −0.082, sd **1.1087**, coverage **0.9250** — would pass all three. Without
   any *other* group the design still fails. So the pooled sd verdict rests on 40 of the 200 LGAs.
   With five groups we cannot separate one unlucky draw from genuine excess dispersion, and the honest
   statement is that the design's sd of z lies somewhere in **1.11–1.22** depending on which 40 LGAs
   you look at. **The calibration constant is not stable at 40-LGA resolution**, and a paper that
   quotes one number must say so.
2. **Coverage 0.9000 is exactly the lower boundary.** Any smaller sample fails that check too. The
   bootstrap interval is 0.855–0.940 and the Wilson interval 0.851–0.934; the point estimate passes
   the letter of the rule and nothing more.
3. **Excess dispersion is not the design-variance imputation.** 77 of 200 LGAs are single-cluster and
   imputed; the 123 multi-cluster LGAs alone give mean −0.136, sd 1.197, coverage 0.894 — if anything
   worse.
4. **The misses are diffusely spread** — 20 LGAs across 15 states, 13 cluster-robust and 7 imputed, 12
   below the direct and 8 above. The most extreme are small LGAs whose direct estimate sits at the
   ceiling (Albasu 0.967 on 30 households, Fika 0.967 on 60, Sagbama 0.610 on 59). That is the known
   weakness of a direct proportion with 30 households, and it is scored identically in T13.
5. **Inflation**: `k = 1.1807` gives coverage 0.940 on these 200. T13's `k = 1.111` applied here gives
   **0.935**, so the existing constant is close but not sufficient. Out-of-fold (k from four groups
   applied to the fifth): 0.850, 0.975, 0.950, 0.975, 0.950 — mean **0.940**, so the correction
   generalises with group 1 still the weak fold.
6. **What the paper should use.** For unsampled-area intervals, widen by **k ≈ 1.18**, not 1.11; and
   the 120's coverage should be quoted as a bracket **[0.900, 0.940]**, not as 0.95. The count
   interval (101–130) remains untested by this ticket.
7. **A cleaner test exists and is cheap.** Match *total* unobserved neighbours to 0.95 instead of
   internal pairs to 0.475: that means about 0.22 within-group unobserved neighbours per LGA, i.e.
   ~4.4 internal edges per group of 40 — at or just below the random-split expectation of 5.81, so it
   needs an anti-clustered sample. Same code, different target, one run. Not run here: the brief allows
   one design and five fits.

## Unproven

- **The 120 LGAs themselves are never fitted.** This tests clustered LGAs matched on exposure, not the
   unsampled areas. Their outcome is unobserved in every design here.
- **Covariates held known.** Each held-out LGA's prediction row uses its own household-mean profile,
  which a genuinely unsampled LGA would not have. T16 therefore *overstates* the information available
  for the 120 and its coverage is, on that dimension, an optimistic bound. The real number could be
  worse than this bracket, not better.
- **Matching on an edge count matches the mean exposure, not its distribution.** The 120 range from 0
  to 3 unobserved neighbours (36 have none); the groups' totals range 0 to 7.
- **Monotonicity of coverage in exposure is assumed** for the bracket. It is consistent with all four
  designs and proved by none of them.
- **The survey design is not in the likelihood** (unweighted fit), as in every other ticket.
- **Count-functional calibration is untested** — it needs joint draws per fold.
- The linear predictor's marginal is assumed Gaussian on the logit scale, as in T12 and T13.

---

## In plain words (under 200 words)

The question was whether the model's 95% ranges still hold where a tenth of the neighbours are
missing — the situation the 120 unsampled areas are actually in. I made that situation exactly: five
sets of 40 areas, each with the same amount of missing neighbourhood as the 120 have.

The answer is a near miss, not a clean pass. The average error is fine. But the spread of errors is
a little too wide: 1.18 against a limit of 1.15. And 90 in every 100 true values fall inside the
range, where 95 should. So the ranges are **slightly too narrow** for unsampled areas. Widening
them by about a fifth fixes it.

That is much better than removing a whole region, which gave 77 in 100. So missing neighbours do
explain the earlier failure — the ordering is clean across all four tests, and the paper's argument
survives.

Two cautions. The test was harder than the real problem, because I also left each held-out area
next to the 120 that are never sampled. And one set of 40 out of five carries most of the failure.
