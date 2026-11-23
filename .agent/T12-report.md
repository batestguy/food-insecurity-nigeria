# T12 — spatial calibration by leaving one geopolitical zone out

**Written by the secretary.** The analyst hit its step cap with the test complete and on disk, but before
writing this file. Everything below is either read from the artefacts or re-computed by me; nothing is
quoted from the agent's summary without a second check, and where I re-ran something I say so.

## The answer, in one line

The pre-declared test **failed, on all three criteria**, and the failure is specifically in spatial
extrapolation rather than in the model's ability to fit data it holds.

| check | pass band | value | verdict |
|---|---|---|---|
| mean of z | −0.15 to +0.15 | **−0.6539** | FAIL |
| sd of z | 0.85 to 1.15 | **1.6481** | FAIL |
| share \|z\| ≤ 1.96 | 0.90 to 0.98 | **0.7752** | FAIL |

States whose direct estimate fell inside the model's 95% interval: **8 of 37** (expected 35). Zones: 0 of 6.
The rule was not revised after the numbers appeared, and it must not be.

## Design as run

Six folds, one per geopolitical zone: drop every household in the zone, refit the identical model, predict
the zone's LGAs from prediction rows at each LGA's mean covariate profile with the cluster index `NA`.
Every LGA is predicted exactly once, out of sample, by a model that never saw its zone. Six fits,
48.8–57.5 s each, 316.7 s total, all `mode_status` 0. The graph keeps all 774 nodes in every fold, so no
fold can disconnect.

Truth: the direct unweighted proportion from the held-out households, matched to the model's unweighted
likelihood; variance by cluster-robust linearisation (PSU cluster, strata state). Scored on
`z = (model − direct) / sqrt(model_var + design_var)`, because the direct estimate carries its own
sampling error and a naive "inside the interval" count under-covers by construction.

## Verified by the secretary

- **z recomputed from `calibration_folds.csv` myself**: mean −0.6539, sd 1.6481, coverage 0.7752. Identical
  to the summary; max |my z − stored z| = 0.
- **Fold split is sound.** Pooling the direct estimates over the six folds reproduces the national
  unweighted rate: 0.277428 against 0.2774. Nobody was lost or double-counted.
- **Not an artefact of the imputed design variance.** 266 of the 654 LGAs hold a single cluster and had
  their design variance imputed from a median design effect; on the 388 multi-cluster LGAs only, the test
  fails slightly *worse* (mean −0.813, sd 1.718, coverage 0.768).
- **The script runs and reproduces itself.** `Rscript scripts/calibration_spatial.R` exits 0 in 9.8 s with
  all six folds already on disk (no refits) and prints the same three numbers.
- **It is extrapolation, not fit.** Compared against the same model fitted on everything, over the 654 LGAs
  with data: in sample, correlation with the direct estimates is **0.974** and the spread is 0.188 against
  0.212. Out of sample, correlation collapses to **0.195**, spread compresses to **0.110**, and the mean
  falls from 0.285 to 0.200. The model reproduces the level of the region it saw, not the region it did not.

By zone, direct estimate → fold prediction (full sample fit in brackets):

| zone | direct | out of sample | in sample |
|---|---|---|---|
| North East | 0.548 | 0.247 | 0.535 |
| North West | 0.416 | 0.212 | 0.406 |
| North Central | 0.169 | 0.280 | 0.176 |
| South East | 0.193 | 0.130 | 0.184 |
| South West | 0.185 | 0.167 | 0.183 |
| South South | 0.176 | 0.145 | 0.170 |

Every zone is predicted near 0.13–0.28 whatever the truth. Yobe: direct 0.844, predicted 0.266.

## Deviations

1. `n_clusters` in `calibration_folds.csv` was written as a duplicate of `n_households` — the same defect
   `PLAN.md` records for `lga_estimates.csv`. The agent fixed the script but the re-run skipped folds
   already on disk, so the column was never rewritten. **Repaired by the secretary** from
   `cluster_lga_fixed.csv` (1,380 clusters, 266 LGAs with exactly one). It affects no number in the test:
   the variance logic used the true counts, which is why exactly 266 LGAs carry an imputed design variance.
2. No report file was written by the agent; no progress line after 03:20.
3. `inla_version` is an empty array in the JSON, so the INLA version is not machine-recorded. It is 25.10.19
   per `AGENTS.md`.

## What this does and does not establish

**Establishes.** Removing a whole contiguous region destroys the model's ability to place that region's
areas, and the intervals are far too confident when it fails. A referee will read this as: the model's
LGA-level surface is a smoothing of the data it saw, not a map of Nigeria.

**Does not establish.** That the 120 unclustered LGAs are as badly estimated as this. In this test the
held-out areas lose their neighbours as well as their own data. The 120 unclustered LGAs keep their
neighbours, which is a materially easier problem — and it is the problem the paper actually makes a claim
about. **That test has not been run.** Until it is, this result scopes the extrapolation claim; it does not
measure the map the paper intends to publish.

## Open risks

1. The paper's headline count (101–130) is not tested here: that needs joint draws per fold. It remains
   unproven, and this result makes it less comfortable, not more.
2. Aggregating to state and zone assumed independent LGAs, which understates those intervals; the JSON
   reports the perfectly-correlated bound (26 of 37 rather than 8) so the state count is not over-read.
   Both are bad; the bound matters for how the sentence is written.
3. Covariates were held known for held-out areas, which flatters the model relative to a world where an
   area's covariates must also be borrowed. The failure happened anyway.

## Unproven

The fair test (an individual LGA removed, neighbours retained) does not exist yet. The count functional is
not calibrated. Whether widening the intervals by the measured inflation factor restores coverage is not
known — it is the next ticket.
