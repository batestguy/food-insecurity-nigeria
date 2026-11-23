# T10 — report, written by the secretary

The analysis agent hit its step cap without running its own script; the secretary debugged and ran it. The
run was killed once by a server restart and relaunched detached. Everything below is from the completed
run's own outputs.

## Changed

- `scripts/lga_model.R` — fixed and made to run (see Deviations)
- `data/derived/lga_estimates.csv` — 774 rows × 16 columns
- `data/derived/count_functional.json` — the decomposition, headline, sensitivity, Monte Carlo block
- `data/derived/lga_fit_summary.json` — 5.0 MB, hyperparameters, checks, model comparison
- `data/derived/lga_posterior_draws.rds` — 223 MB, the draws themselves

## Verified

Independently re-read from the outputs, not taken from the log:

- **Σ P_exceed_050 = 114.97 against E[C] = 114.975** — the count from the draws and the sum of the
  marginals agree.
- **Variance identity:** independent 40.258 + pairwise 14.248 = 54.506, and the variance of the counts
  taken directly from the draws is 54.51. Residual −2.7 × 10⁻³, i.e. floating-point.
- 774 rows written; posterior means span 0.017 to 0.918.

## The result

At c = 0.50 (a majority of households severely food insecure):

| | |
|---|---|
| E[C] | **115.0** of 774 LGAs (14.9%) |
| 95% interval | **101 to 130** |
| posterior sd | **7.38** |
| variance, independent term | 40.26 (sd 6.34) |
| variance, pairwise term | **14.25** |
| ratio pairwise / independent | **0.354** |
| **sd a marginal-only method would report** | **6.34 — 14% too small** |
| IID-LGA comparator, same ratio | **0.187** |

**What this establishes.** A method that reports only per-LGA exceedance probabilities — direct
estimates, or the published spatial random forest — would put the standard deviation of the count at
6.34 when the joint posterior gives 7.38. The 95% interval would be roughly 101–129 instead of 101–130,
and any decision keyed to the upper end of that range moves.

**And the attribution works.** The IID comparator — the same model with no spatial structure — gives a
pairwise ratio of 0.187. So roughly half the pairwise term is shared uncertainty in the regression
coefficients, and the other half is geography. That is exactly what the comparator was added to separate,
and it is the sentence that makes the claim a result rather than a decomposition.

**How decided the classifications are:** 32 LGAs are above the line with probability > 0.95, 509 below
with probability < 0.95 in the other direction, and **40 sit in the 0.40–0.60 band** — the areas where the
data does not decide. The 120 LGAs with no cluster get model estimates from the field (posterior means
0.046–0.584, mean exceedance probability 0.132), which is the point of the exercise.

## Deviations

Three bugs, all found by running rather than by reading:

1. `inla.posterior.sample()` requires `control.compute=list(config=TRUE)`, and labels coefficients
   `"<name>:1"` unlike `summary.fixed`.
2. **BYM2 exposes two latent blocks per area** (`lga:1..774`, `lga:775..1548`) whose combination is not a
   plain sum. The fix was architectural: append 774 prediction rows (one per LGA at its mean covariate
   profile, response and cluster index `NA`) and read joint draws of the linear predictor from
   `Predictor:<row>`. This also gives the 120 empty LGAs a proper model estimate.
3. `tcrossprod(Z)` is `Z Zᵀ` (draws × draws); the joint matrix needs `crossprod(Z)`.

Two deliberate changes, both recorded rather than hidden: a Jensen-gap diagnostic comparing two
definitions of LGA prevalence was **removed**, because it needed per-household field draws the new
construction does not produce; and the draw count was raised from 6,000 to 20,000 after the split-half
check showed a 29% discrepancy.

## Unproven

- **Monte Carlo noise on the headline.** The split-half pairwise variances were 13.37 and 15.12 — a 12%
  relative difference. The pairwise term is 14.2 with roughly ±1.7 of Monte Carlo uncertainty. The paper
  must report it as such, not as 14.25.
- Survey weights are not in the likelihood; the unweighted national rate is 0.2774 against a weighted
  0.2910.
- No geospatial covariates entered this fit; they are attached and deferred to a declared selection rule.
- Whether the count is stable to the LGA boundary file, since our polygons are not DHS's.
