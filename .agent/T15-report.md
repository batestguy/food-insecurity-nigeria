# T15 — the area-level covariates improve every check and pass none of them

**The answer, in one line:** adding the five area-level covariates moves all three checks toward their pass
bands and still fails all three by a wide margin. This is an improvement, not a fix.

| check | pass band | T12 | **T15** | change | verdict |
|---|---|---|---|---|---|
| mean of z | −0.15 to +0.15 | −0.6539 | **−0.4854** | +0.169 | FAIL |
| sd of z | 0.85 to 1.15 | 1.6481 | **1.5649** | −0.083 | FAIL |
| share \|z\| ≤ 1.96 | 0.90 to 0.98 | 0.7752 | **0.7966** | +0.021 | FAIL |

n = 654 LGAs, each predicted once by a model that never saw its zone. 133 of them (20.3%) are outside the
model's 95% interval and 72 (11.0%) are beyond 2.58. States whose direct estimate falls inside: **11 of 37**
(T12: 8), or 29 of 37 under the perfectly-correlated bound. Zones: **1 of 6**, South West.

The rule was not touched. "Improved but still fails" is the whole finding.

## Why the improvement is small, stated as a number

Adding the five covariates lifted **every** zone by a similar amount — this is the mechanism, and it is not
the one the test needed:

| zone | n | direct | T12 model | **T15 model** | lift | z T12 | z T15 | coverage T15 |
|---|---|---|---|---|---|---|---|---|
| North West | 154 | 0.416 | 0.212 | **0.229** | +0.017 | −1.470 | −1.283 | 0.695 |
| North East | 98 | 0.548 | 0.247 | **0.279** | +0.032 | −1.942 | −1.672 | 0.622 |
| North Central | 108 | 0.169 | 0.280 | **0.296** | +0.016 | +0.717 | +0.822 | 0.769 |
| South West | 112 | 0.185 | 0.167 | **0.186** | +0.019 | −0.127 | +0.006 | 0.946 |
| South East | 83 | 0.193 | 0.130 | **0.150** | +0.020 | −0.580 | −0.364 | 0.831 |
| South South | 99 | 0.176 | 0.145 | **0.159** | +0.014 | −0.263 | −0.153 | 0.960 |

A covariate set that separated north from south would lift the southern zones by little and the northern
zones by a lot. Every zone moves up by 1.4 to 3.2 percentage points: the five columns behave like a change
in the intercept, not like a spatial predictor. North East is 0.27 below its truth and gained 0.03.

What did change is the *shape* of the failure. The southern zones are now essentially calibrated on their
own (South West mean z +0.006, coverage 0.946; South South coverage 0.960) while the northern zones remain
1.3 to 1.7 standard deviations too low and too narrow. T12 was uniformly bad; T15 is bad in the north only.

Out of sample, over the 654 LGAs with a direct estimate:

| | T12 | T15 |
|---|---|---|
| correlation with direct | 0.195 | **0.215** |
| slope of model on direct | 0.101 | **0.117** |
| compression ratio (sd model / sd direct) | 0.520 | **0.543** |
| mean model / mean direct | 0.200 / 0.291 | **0.220 / 0.291** |

The slope is still an eighth of what it should be. Averaged over the 111 LGAs whose direct estimate exceeds
0.50 the model says 0.250; over the 126 below 0.10 it says 0.184. The map still has one value for the
country.

## Diagnostics

- **Convergence.** Six folds, INLA `mode.status` 0 in all six, 58–74 s each, 367 s total, all fits well
  inside the 360 s per-fold limit.
- **BYM2.** Mixing parameter φ = 0.962 to 0.972 and precision 0.844 to 1.032 across the six folds. T12
  recorded neither on disk — `calibration_folds.csv` carries only `fold_sd_cluster` — so there is no
  before/after for the mixing parameter and T12 was not refitted to manufacture one. The cluster-effect sd
  is 0.415–0.473 (T12: 0.416–0.475), i.e. unchanged.
- **Fold integrity.** The direct estimates and design variances were recomputed, not copied, and agree with
  T12's file to **6.9e-17** and **7.6e-17**; `n_households` and `n_clusters` agree exactly. The fold split,
  the truth and the scoring are therefore identical and the comparison is controlled.
- **Pooled prevalence** from the direct estimates: 0.2774, reproducing the national unweighted rate — nobody
  lost or double-counted.
- **Multi-cluster LGAs only** (n = 388, where the design variance is estimable): mean −0.6248, sd 1.6123,
  coverage 0.7784 (T12: −0.813 / 1.718 / 0.768). The failure is not an artefact of the deff imputation.
- **Variance accounting.** Median model sd 0.125 against a median design se of 0.060; the design contributes
  23% of the variance of z. The model is the confident party and it is wrong: rms z = 1.637, so the real
  out-of-sample error is 1.64 times the uncertainty claimed.
- **Covariate rebuild.** The surface was rebuilt inside every fold: 259, 211, 262, 246, 181, 221 clusters
  excluded for North West, North East, North Central, South West, South East and South South. The script
  asserts that no rebuilt nearest-3 set contains an excluded cluster and that 1,121–1,199 clusters remain.
  LGAs whose five values changed: 198, 115, 136, 141, 105, 129.
- **The builder is T14's.** Copied because sourcing `lga_covariates.R` would rewrite its outputs; it
  reproduces the shipped table to 4.8e-12 on the eight interpolated candidates and 4.7e-11 on density. That
  check caught a real discrepancy first — T14 rounds area to three decimals before dividing population by
  it — which is why the copy is exact rather than approximate.

## Aridity_2020: higher is wetter, read not assumed

Page 10 of 42 of `DHS Covariates Extract Data Description_3.pdf` (printed page 9), entry "Column Name:
Aridity YEAR":

> "Units: Index between 0 (most arid) and 300 (most wet)."

and

> "The dataset represents the average monthly precipitation divided by average monthly potential
> evapotranspiration, an aridity index defined by the United Nations Environmental Programme (UNEP)."

A higher `Aridity_2020` therefore means **wetter**. One sentence on the same page says that if the index
"becomes higher than normal" the climate tends to suffer drought; that refers to a deviation above normal,
not to the level, and is contradicted by the units line and by the P/PET definition. The units line governs.
Two independent checks on the 774 LGA values agree: r(Aridity, Precipitation) = +0.985 and r(Aridity,
Elevation) = −0.623, both only possible if a higher index is wetter. The reported descriptive r = −0.46 with
severe food insecurity is therefore "wetter LGA, less severe food insecurity" — the expected direction, not
a misread sign.

## Coefficients of the five covariates

Raw scale, so a coefficient is per unit of the covariate as shipped. Five of six folds report them (see
Deviations 4).

| term | North Central | South West | South East | South South | sign |
|---|---|---|---|---|---|
| pop_density (per person/km²) | +5.49e−06 | +6.76e−06 | +7.36e−06 | +5.86e−06 | + 4/4, none significant |
| Aridity_2020 (0 arid → 300 wet) | −0.0132 | −0.0016 | +0.0010 | −0.0137 | − 3/4, none significant |
| Enhanced_Vegetation_Index_2020 | −0.394 | **−3.255** | −2.024 | −0.639 | − 4/4, one significant |
| Elevation (m) | −6.36e−04 | +2.41e−04 | −4.23e−05 | +2.03e−04 | mixed |
| Malaria_Incidence_2020 (cases/person) | −0.749 | +1.225 | +0.899 | +0.862 | + 3/4, none significant |

The one coefficient that is stable, sizeable and significant is EVI, negative: greener LGAs have less severe
food insecurity. Its 95% interval excludes zero in South West only (−6.11 to −0.40), where the covariate
varies most within the zone. Aridity's negative sign agrees with the descriptive correlation but its
magnitude is small: −0.013 per index point, so even the full national range of 65.6 points buys 0.86 logits,
and the fitted value in three folds is a third of that. **Nothing here identifies a between-zone gradient:
these coefficients are estimated from within-zone variation, because the intercept and the BYM2 field absorb
the level.**

## Changed

- `scripts/calibration_covariates.R` (new) — T12's design plus five area-level fixed effects, surface
  rebuilt per fold, same pass rule, same scoring, resumable per zone.
- `data/derived/calibration_cov_zone.csv` (new) — 774 rows, one per LGA: T12's columns, the five covariate
  values used in its fold, the fold's BYM2 φ and precision, the fold's cluster count and the number of LGAs
  whose covariates changed, and the fold's five coefficients. Column `pop_density_imputed` flags Bakassi.
- `data/derived/calibration_cov_summary.json` (new) — checks with bands and booleans, the side-by-side
  against T12 read from `calibration_summary.json`, per-zone comparators, hyperparameters, coefficients,
  the Aridity sentence, the construction string.
- `.agent/T15-progress.md`, `.agent/T15-report.md` (this file).

Nothing else was written. T12's files, T14's files, `PLAN.md`, `AGENTS.md` and everything under
`data/restricted/` were read only.

## Verified

- `Rscript scripts/calibration_covariates.R` **exits 0**; the second run skipped all six zones in 15.5 s of
  script time (24.1 s wall) and printed identical numbers, so the artefacts are reproducible from disk
  without refitting.
- 774 rows, 654 with a direct estimate, six zones, every LGA once, no duplicate key (asserted in the script).
- Direct estimates and design variances equal T12's to 1e-16; `n_clusters` equals T12's repaired column
  exactly (max diff 0), so the counts come from `cluster_lga_fixed.csv` and not from the wrong column.
- 654 LGAs with at least one cluster, 120 with none, 1,380 clusters, 266 singletons — asserted, not assumed.
- Household `state_iso` equals `cluster_lga_fixed.csv$state_iso` for all 1,380 clusters; the 15 clusters the
  two cluster files disagree on use the survey state, which is what defines the folds.
- Every rebuilt fold surface excludes exactly its zone's clusters and draws from none of them.

## Deviations

1. **`pop_density` for Bakassi.** No COD-PS population, so density is NA for that one LGA. It holds no
   cluster and no household, so the value enters no likelihood; it is filled with the parent-state
   (Cross River) median and flagged. Declared before the fit, one cell.
2. **Two failed runs before the reported one, both from script defects, both fixed.**
   (a) Density computed from unrounded area differed from T14's shipped value by up to 3.05 per km²; my own
   reproduction check caught it and the run stopped before any fit.
   (b) `data.frame(A = matrix)` names the columns `A.pop_density`, `A.Aridity_2020`, …, so the five covariate
   columns were missing and the first fold's block write failed after a completed 68 s fit.
3. **The T12-JSON cross-check tolerance was 1e-9 and the stored values are rounded to about 2.2e-9.** Left
   alone, the run would have discarded a complete six-fold result at its final step. Found by dry-running
   the post-fit code against T12's file before the folds finished; relaxed to 1e-6, and the actual
   discrepancy is printed (2.20e-09).
4. **Seven fold-fits against a cap of six.** Two were thrown away by the defects above (North West fitted
   twice, North East once in the process that was killed at the moment it wrote its block). North West and
   North East therefore carry **no coefficient row** — their fits predate the change that persists the
   coefficient table, and a fold already on disk is not refitted. Their predictions, z values and
   contribution to every calibration number are unaffected; the coefficient table covers four folds.
5. **Household covariates are still held known** from the full file, as in T12, so the test still flatters
   the model. It failed anyway.

## Open risks

1. **The covariates are interpolated from the clusters that remain**, so for the held-out zone they are
   extrapolations inward from the boundary — worst exactly where they are needed. This is inherent to the
   design: any area-level covariate built from survey clusters degrades in a region with no clusters. If the
   real surfaces (CRU, SRTM) were used directly instead of IDW over cluster points, the covariate values in
   the held-out zone would be better, and this test would be measuring a different quantity. It is the
   declared design of T14, not a defect of this run.
2. **No before/after for the BYM2 mixing parameter.** T12 stored only the cluster-effect sd.
3. **The northern failure is not explained.** The five coefficients are estimated within zone; nothing in
   this design can tell whether the region's level is missing from the covariates, or from the likelihood,
   or from the spatial prior.
4. **State and zone coverage assume independent LGAs.** The perfectly-correlated bound (29 of 37 states) is
   reported so 11 of 37 is not over-read. Both are bad.

## Unproven

- Whether a covariate that varies sharply *between* zones, or an explicit zone-level effect, would pass the
  rule. This ticket tested the five covariates that exist; it did not test the hypothesis space.
- The count functional (101–130 LGAs above 50%). Still needs joint draws per fold.
- The 120 unclustered LGAs, which keep their neighbours and are a materially easier problem than this one.
- Whether widening the intervals by the measured inflation factor (rms z = 1.64) restores coverage.

**The sentence for the paper:** removing a whole zone, the five area-level covariates raise out-of-sample
coverage from 0.775 to 0.797 against a nominal 0.95, and the northern zones remain 1.3 to 1.7 standard
deviations below their direct estimates. The covariates do not rescue spatial extrapolation.

---

## Secretary addendum — independent re-check and one further finding (2026-11-23)

**Everything reproduces.** Recomputing z from `calibration_cov_zone.csv`: 654 areas with a direct estimate,
mean **−0.4854**, sd **1.5649**, coverage **0.7966**; maximum difference from the stored z = 1.6e−14. The
direct estimates are byte-identical to T12's, so the truth did not move between runs and the comparison is
controlled.

Per zone, T12 → T15 (mean z, coverage):

| zone | direct | T12 | T15 | T15 predicted |
|---|---|---|---|---|
| North Central | 0.169 | +0.717, 0.806 | +0.822, 0.769 | 0.296 |
| North East | 0.548 | −1.942, 0.571 | −1.672, 0.622 | 0.279 |
| North West | 0.416 | −1.470, 0.630 | −1.283, 0.695 | 0.229 |
| South East | 0.193 | −0.580, 0.819 | −0.364, 0.831 | 0.150 |
| South South | 0.176 | −0.263, 0.949 | −0.153, 0.960 | 0.159 |
| South West | 0.185 | −0.127, 0.938 | +0.006, 0.946 | 0.186 |

The south is calibrated. The north is not, in either direction: North Central is over-predicted, North East
and North West are under-predicted by 0.27 and 0.19. The model lands every zone between 0.15 and 0.30
whatever the truth.

**The finding the agent did not draw out, which matters more than the pass/fail.** Across the four folds
that recorded coefficients, **19 of 20 coefficient intervals contain zero** — aridity, elevation,
vegetation, malaria and density are all inert. Their point estimates are tiny; vegetation is consistently
negative but not distinguishable from zero in three of four folds. The covariates do not fail because they
are mis-signed. **They fail because, once household composition is accounted for, these environmental
variables carry no measurable signal about severe food insecurity at LGA level.** The north-east's 0.548 is
not an agro-ecological phenomenon, and no reparameterisation of climate and terrain will produce it. That
belongs in the paper as a result, not a footnote.

**One correction of my own.** My first recomputation reported coverage 0.673 because pandas counts a missing
value as *outside* the interval; the 120 areas without a direct estimate were being scored as failures. The
agent's 0.797 was right and my check was wrong. The mean and sd matched, which is why the error survived a
glance — a reminder that a summary statistic agreeing does not validate the code that produced its
neighbours.

**Deviation to record.** The agent used **7 model fits against a cap of 6**, one wasted on its own bug, and
only four of six folds carry coefficient rows. No conclusion depends on the missing two, but the cap was
exceeded and should not become a habit.

