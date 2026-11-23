# PLAN.md — state of the food-insecurity small-area paper

This is the **state file**. `AGENTS.md` holds the rules, traps and settled decisions; this file holds
where the work actually stands, what each phase must produce, and what to do when one fails.

Update it whenever a ticket finishes. If a phase changes status, the change goes here first.

Last updated: 2026-11-23, after P6 (identification bounds) landed and was re-checked independently.

---

## Resume here — read this first next session

**One paragraph of orientation.** The project is a Bayesian small-area study of **severe household food
insecurity in Nigeria** from the 2024 DHS, fitted in R-INLA. Its contribution is not the estimator — that
is published work — but a **functional of the joint posterior**: the number of LGAs above a crisis line,
with the variance split into an independent and a pairwise term. That has now been computed. The repo is
public at **https://github.com/batestguy/food-insecurity-nigeria** (`main`, clean tree). No agents are
running; nothing is queued.

**The headline numbers, all verified and reproducible from `scripts/lga_model.R`:**

| | |
|---|---|
| National severe food insecurity (`hfs_sev ≥ 0.5`) | 29.10% weighted |
| States | 4.6% (Niger) to 85.0% (Yobe) |
| LGAs above 50% | **115 of 774** (14.9%), 95% interval 101–130, sd 7.38 — **but the interval is model-dependent: given the marginals alone, sd(C) could be anywhere from 0.16 to 74.11** |
| Variance, independent term | 40.26 (sd 6.34) |
| Variance, pairwise term | **14.25**, ratio 0.354 |
| Same ratio with an exchangeable area effect | **0.187** — so about half the pairwise term is geography |
| LGAs decided above / below / undecided | 32 / 509 / **40 in the 0.40–0.60 band** |
| LGAs with no cluster | 120 (15.5%), holding **11.04% of the population** |
| **Count the design cannot place** | **87 to 231** — the 101–130 sits inside it; 120 of the 144-wide interval is assumption |

**Do this first, in this order.**

1. ~~**P6 — the identification bounds.**~~ **Done 2026-11-23**, `.agent/T11-report.md`,
   `data/derived/identif_bounds.json`. Result below. Re-checked independently by the secretary.
2. **P7b — calibration.** ~~Run.~~ **The first test failed, badly** (see P7b below): leave-a-zone-out
   gives 77.5% coverage against a nominal 95%, and the model cannot place a removed region at all. The
   fair test — one LGA removed, neighbours kept — is the one that matches the paper's claim and is
   running now. **The paper cannot claim a calibrated map until it lands.**
3. **P8 — benchmarks.** Gradient boosting under the same spatial folds with conformal intervals
   (`scikit-learn` 1.9 is installed — `HistGradientBoostingClassifier`; LightGBM, XGBoost, PyTorch and
   `mapie` are **not**), plus the published spatial random forest as the external anchor.
4. **Then draft.** Methods and Results are writable from artefacts. The Introduction is not, until the two
   nearest competitor papers are read **in full** — the novelty claim still rests on abstracts.

**A debt to settle before drafting starts.** `lga_estimates.csv` carries a column named `n_clusters` that
is a duplicate of `n_households` (identical in all 774 rows, both summing to 39,877). The observed /
unobserved mask is unaffected, so P6 and P7 stand, but any sentence about "LGAs with one cluster" must
read cluster counts from `cluster_lga_fixed.csv` (654 LGAs with at least one, 120 with none) and **not**
from `lga_coverage.csv`, whose `n_clusters` is the pre-correction assignment (123 with none). Renaming
the column is a five-minute job; doing it before the manuscript means no draft can quote the wrong
number.

**Commands that build things** (all run from the repo root; all paths are now relative):

```
python scripts/build_analysis_households.py     # analysis dataset, prints retention and prevalence
python scripts/extract_fi_state.py              # direct state estimates, both estimands
Rscript scripts/lga_assign.R                    # clusters to LGAs (sf; python has no shapely)
Rscript scripts/lga_dataset.R                   # population denominators, household merge
Rscript scripts/lga_model.R                     # THE RESULT: fit + count functional (~35 min)
Rscript scripts/moran_fi.R                      # Moran's I on the state estimates
python scripts/qa_panel.py                      # legacy: CPI panel checks
```

`lga_model.R` takes about 35 minutes: a 60-second fit, then ~14 minutes of draws per model (two models).
Run it detached (`Start-Process`), because a shell background job dies with the session — that happened once.

**Environment.** R 4.5.2 at `C:\Program Files\R\R-4.5.2\bin\Rscript.exe`; INLA 25.10.19 as a Windows
binary (the source build is 26.08.07 and compiles for an hour); `sf`, `spdep`; Python 3.14 with
`pyreadstat`, `pandas`, `numpy`, `sympy`, `pyproj`. Playwright is installed for Python but the MCP browser
is `--headless --browser chrome`, so it cannot show anything to the user.

**Do not repeat these.** Do not use `fies_score >= 6` as the outcome (uncitable). Do not treat `hv225`
blanks as missing — they mean "no toilet", and reading them as missing deleted the poorest quarter of the
sample. Do not reconstruct the BYM2 field from `inla.posterior.sample` — use prediction rows. Do not claim
a new estimator: all four propositions are classical. **Do not use any disability variable anywhere.**

**Waiting on the user.**
- Amend the DHS project description to cover a food-insecurity outcome (an edit to the existing
  registration), and send a PDF of the paper to references@dhsprogram.com.
- Decide whether to rewrite history to remove the account email that survives in commit `9dce997`
  (redacted from the working tree in `103dd3a`; force-push was gated, so it needs explicit authorisation).
- The local folder is still `ConferenceMaths`; the repo is `food-insecurity-nigeria`. The scripts are
  path-portable, so the rename is safe whenever.

**Unproven, stated plainly.** The literature review read abstracts only. The survey design is not in the
likelihood (unweighted national 0.2774 against weighted 0.2910). No geospatial covariate has entered a fit.
Calibration has never been checked. The pairwise term is 14.2 ± ~1.7 (split-half 13.37 vs 15.12 at 20,000
draws). LGA assignment relies on geoBoundaries polygons, not DHS's, and population denominators are 2020
projections from the 2006 census.

---

## Status at a glance

| Phase | What it settles | Status | Artefact |
|---|---|---|---|
| P0 | Documentation, decisions, traps | **done** | `AGENTS.md`, this file, `data/derived/covariate_spec.md` |
| P1 | Data access: cluster coordinates + geospatial covariates | **done** | `data/restricted/dhs-2024/ge/` |
| P2 | Analysis dataset | **done — 39,877 households, 100% retention** | `data/derived/analysis_households.csv` |
| P3 | Direct estimates and spatial diagnostics at state level | **done** | `data/derived/fi_state_direct.csv` |
| P4 | Design-aware state-level model (baseline) | **superseded** — measured analytically instead (γ 0.9866) | `AGENTS.md` |
| P5 | Clusters → LGAs, population denominators, LGA model | **done** | `lga_estimates.csv`, `lga_fit_summary.json` |
| P6 | Identification bounds at LGA level (Imbens–Manski) | **done 2026-11-23** — count ∈ [87, 231] | `data/derived/identif_bounds.json` |
| P7 | Count functional | **done** — E[C] = 115, ratio 0.354 | `count_functional.json` |
| P7b | Calibration by spatial cross-validation | **failed 2026-11-23** — see P7b; fair test running | `data/derived/calibration_summary.json` |
| P8 | Benchmarks: gradient boosting, spatial random forest | pending | — |
| P9 | Manuscript | pending | — |
| P10 | Submission compliance: DHS amendment, PDF to DHS | pending — **waiting on user** | — |
| P10 | Submission compliance | pending | — |

---

## Decisions locked

Do not reopen these without a recorded reason.

1. **Outcome.** Severe food insecurity = `hfs_sev >= 0.5`, which in this file is exactly the households
   affirming all eight FIES items. National 29.1%; states 4.6% (Niger) to 85.0% (Yobe).
   *Reason:* the Rasch/probability route is the only citable construct. "Six or more of eight" has no
   source and gives 56.5%, a different quantity.
2. **No disability variable, anywhere.** Not outcome, not covariate, not discussion.
   *Reason:* user decision, 2026-11-22.
3. **Centre of the paper is LGA level, not state.** *Reason:* at ~1,000 households per state the direct
   estimates are already more precise than the between-state spread (γ median 0.9866), so state-level
   small-area estimation is nearly a no-op. See `AGENTS.md`.
4. **The method is not novel.** Four published papers own the components (Brazilian Amazon AOAS 2025;
   heavy-tailed SMMR 2024; Beta–Beta Prime JSSAM 2025; spatial random forest AOAS 2025). The claim is
   Nigeria, LGA level, and a decision layer — novelty by absence, worded as "we found none".
5. **Survey design is modelled and disclosed.** Weights are not silently ignored.
6. **Novelty is carried by functionals of the joint posterior, not by the prior or the estimator** (decided
   2026-11-22). Three, in order:
   - **the count of areas above the crisis line**, `C = Σ_s 1{θ_s > c}`, whose variance is
     `Σ P_s(1−P_s) + Σ_{s≠t}(P_st − P_s P_t)` and therefore needs *pairwise* exceedance probabilities.
     No method that reports marginals only — direct estimates, or the published spatial random forest —
     can produce it. This is the paper's signature result.
   - **confidence sets for the partially identified tail** (Imbens–Manski): the Manski bounds are
     themselves estimated, so the honest object is an interval covering the identified set.
   - **the budget allocation index**: the Bayes-optimal choice of K areas is not the K highest posterior
     means, and the difference is a short results subsection.
   Claims about a "new estimator" are forbidden; all four propositions remain classical.

## Drafting gate

**No manuscript prose is drafted before the first LGA fit exists.** Every number in a draft must trace to
an artefact in this repo and the command that produced it. The count functional cannot be drafted ahead
of a joint posterior — that is exactly the error this project has made three times and caught three times.

---

## Phases

Each phase has an exit criterion and a rule for failure. A phase that fails is dropped and the paper
rescoped, never rescued by relaxing its own criterion.

### P1 — data access (done, 2026-11-22)

Both files downloaded through a visible Brave window driven by Playwright, then unpacked to
`data/restricted/dhs-2024/ge/`:

| File | Bytes | SHA-256 |
|---|---|---|
| `NGGE8AFL.ZIP` | 137509 | b02e1923b3360e7832de1d1f32ebca31044a4601b751995dc037a61276926741 |
| `NGGC8AFL.ZIP` | 1337762 | f813b71bb9d2ce8c181cc1e24ef777e906842aa66506425b813822a9555c7713 |

Contents: shapefile (`DHSCLUST`, `LATNUM`, `LONGNUM`, `URBAN_RURA`, `ADM1NAME`), the 135-column
covariates CSV, `GPS_Displacement_README.txt` and the covariates data description.

**Join verified:** 1,380 geocoded clusters against 1,380 microdata clusters, **1,380 matched, zero
either side**, and all 176,045 person records carry a cluster with coordinates. Coordinates span
4.33°–13.79° N, which is Nigeria. No missing coordinates.

**How the download actually works, for next time** — this cost an hour to learn:

1. Sign in, then **select a project** (`proj_id`; Curb Cut is 246118). Until a project is selected the
   dataset page serves *no* download links at all, only plain text, which reads like a permission
   refusal and is not one.
2. Open the dataset page **with `?flag=1`**. Without it the file list module can throw
   "Error in custom script module"; with it the list renders.
3. The geographic anchors are `/customcf/legacy/data/download_dataset.cfm?Filename=…&surv_id=609`.

Driver: `scripts/dhs_final.py`, reusing cookies saved at
`%LOCALAPPDATA%\Temp\opencode\dhs_cookies.json`. Both that file and the scratch Brave profile
`…\Temp\opencode\brave-dhs-profile` hold your DHS session and should be deleted once we are done.

### P2 — analysis dataset (done, rebuilt 2026-11-22)

`data/derived/analysis_households.csv` — 39,877 households, **100% retention**, zero missing covariates,
37 states, 1,380 clusters, 688–1,409 households per state.

- Outcome `severe_fi` = `hfs_sev >= 0.5`: weighted 0.2910. Secondary `modsev_ge4`: 0.6900.
- Aggregated to states, it reproduces `data/derived/fi_state_direct.csv` exactly
  (max |difference| 8.3e-17, correlation 1.000000).
- Built by `scripts/build_analysis_households.py`; decisions logged in `data/derived/covariate_mapping.json`.

**The defect it replaced, for the record.** The first build dropped 12,159 households (30%) because
`hv225` (shared toilet) was treated as missing. It is not missing: the question is only asked of
households *with* a facility, so its absence means "no toilet at all", which is unimproved sanitation by
definition. Complete-case deletion therefore removed the poorest quarter of the sample — the classic way
to manufacture a spatial pattern. Rule now: no facility → `improved_sanitation = 0`, never a dropped row.

**Wealth scaling confirmed:** the factor score runs −217,213 to 231,627, so it is stored ×1e5 and divided
back before standardising.

**If a future build reintroduces attrition:** stop. Any exclusion must be reported with the outcome
prevalence in the excluded group.

### P3 — direct estimates and spatial diagnostics (done)

- National 29.10%; state range 4.6%–85.0%, median 23.5%.
- Moran's I on the Rasch severe measure 0.204, permutation p = 0.018 (9,999 draws); on
  moderate-or-severe −0.012, p = 0.427. The structure is in the tail.
- Design effects 1.23–8.12, median 2.88; state standard errors 0.0104–0.0467.
- **Carry forward:** state standard errors feed `ψ_s` in every later model.

### P4 — design-aware state-level baseline

- **Question:** does modelling the design change the state estimates, and does the hierarchical model beat
  the direct estimate at state level?
- **Prediction, recorded in advance:** it will barely move them (γ ≈ 0.987). That is the point — this
  phase exists to *demonstrate* the no-op and justify going to LGA level, not to produce a headline.
- **Exit:** a fitted model with design variables or calibration, compared against direct estimates on the
  pre-declared rule (33 of 37 states inside the direct 95% interval; median credible width narrower). A
  fail verdict is written up as the motivating result.

### P5 — LGA mapping and covariate model (mapping done, model fitted 2026-11-22)

**Cluster→LGA assignment complete.** `scripts/lga_assign.R` → `data/derived/cluster_lga.csv`,
`lga_coverage.csv`, `lga_assignment_qc.json`.

- All 774 LGAs assigned to exactly one parent state by representative point; per-state counts sum to 774.
- All 1,380 clusters fall inside exactly one LGA; none outside all polygons.
- **123 LGAs (15.9%) hold no cluster** — the `1−p` in the identification proposition. 260 hold one,
  357 hold two to four, 34 hold five or more; median 2, max 22.
- 807 clusters (58.5%) lie within the displacement radius of an LGA edge. Nigerian LGAs are only ~27 km
  across, so this is geometry, not a measurement artefact.

**The displacement question is settled by DHS's own README, and it changes the wording.** The file states
displacement is *"restricted so that the points stay within … the admin2 area"*. So DHS guarantees a
cluster stays inside its own LGA. **The uncertainty is therefore not that DHS moved points across
borders — it is that our LGA polygons are not DHS's** (geoBoundaries simplified). Say it that way in the
paper; the naive "displaced coordinates may cross boundaries" sentence would be wrong.

**Two things still to fix before the LGA model is final:**
1. **15 clusters (1.1%) sit in a different state from the one the survey records.** Given the DHS
   guarantee, the survey state is authoritative and our polygon is at fault. Rule to adopt: keep the
   survey's state and reassign the cluster to the nearest LGA *within* that state. Quantify the effect.
2. **`p` must be a population share, not a count share.** 123/774 is an area share; the identified-set
   width `1−p` is about people. Needs LGA population denominators (WorldPop or GRID3 zonal totals), which
   are not yet on disk.

**Both refinements are now done** (`scripts/lga_dataset.R`, `.agent/T9-report.md`): 120 LGAs hold no
cluster (15.5%) but only **11.04% of the population** lives in them, so `p_population = 0.8896` against
`p_count = 0.8450`. **Unclustered LGAs are systematically smaller** — the paper must quote the population
version, because the width is a statement about people. Population source: COD-PS (NBS/UNFPA) 2020
projections; LGA populations sum to 204,909,220, exactly the workbook's state totals.

**LGA model fitted** (`scripts/lga_model.R`, 2026-11-22): household binomial, BYM2 on a queen-contiguity
graph over 774 LGAs (774 nodes, 2,230 edges, one component), IID cluster effect, the ten design columns of
the eight household covariates, no geospatial covariates yet.

- 39,877 households; **fit 40–55 s**, mode status 0, **WAIC 37942.17 identical across runs**.
- Hyperparameters: precision for LGA 0.904, **φ = 0.971** (0.903–0.997), precision for cluster 4.784.
  **At LGA level the between-area variation is almost entirely structured** — the opposite of the
  state-level result, and the first real evidence that going below state was right.
- Unweighted national rate 0.2774 against weighted 0.2910; the 1.4-point gap is a stated limitation.
- INLA labels coefficients `"<name>:1"` in `inla.posterior.sample()$latent`, unlike `summary.fixed`.
  That cost one debugging cycle; `inla.posterior.sample` also requires `control.compute=list(config=TRUE)`.
- **BYM2 stores two latent blocks per area** (`lga:1..774` and `lga:775..1548`), and their combination is
  not a plain sum. Do not reconstruct the field from the draws. The working approach: append 774
  prediction rows (one per LGA at its mean covariate profile, response `NA`, cluster index `NA`) and read
  the linear predictor from `Predictor:<row>` — INLA returns joint draws of it directly. The cluster effect
  is then marginalised by Gauss–Hermite (its sd is ≈ 0.46 on the logit scale, too large to ignore).
- `tcrossprod(Z)` is `Z Zᵀ` (draws × draws); the joint exceedance matrix needs `crossprod(Z)` = `Zᵀ Z`
  (areas × areas). This crashed loudly, but the same slip in a faster path would have produced a
  plausible wrong number.
- **Draw count:** at 6,000 draws the split-half comparison of the pairwise variance gave 14.90 vs 11.09 —
  29% relative difference, i.e. Monte Carlo noise. Raised to 20,000. The pairwise term must be reported
  with its Monte Carlo uncertainty, not as a bare number.

### P6 — identification and missingness (done 2026-11-23)

`.agent/T11-report.md`, `scripts/identif_bounds.R`, `data/derived/identif_bounds.json`,
`data/derived/identif_bounds_lga.csv`. Reads the saved 20,000 × 774 joint prevalence draws, so the spatial
dependence is preserved and the model was not refitted.

- Partition: 654 LGAs hold at least one cluster, **120 hold none**, and the unclustered ones hold 11.04% of
  the population (`p = 0.88963`, re-checked independently).
- **Count of LGAs above 50%.** With the 120 treated as completely unknown, each counts 0 or 1, so the
  identified set is `[C_O, C_O + 120]`. Endpoint-wise across draws: **87 to 231**. The model's 101–130 sits
  inside it; the model's upper end is 101 LGAs below what the design can rule out.
- **Share of people living in a crisis LGA.** Observed-only 13.72%; identified interval **10.63% to 24.90%**.
- **120 of the 144-wide interval is the assumption**, not the data. That sentence is the paper's honest
  statement and belongs in the Discussion.
- The monotonicity variant (`π_U ≥ π_O`) buys only 1.3 points of width and rests on an assumption these
  data cannot test. Recorded in its own key, deliberately not the headline.
- **The name matters.** It is a 95% posterior interval for the sample-analogue identified set, and the JSON
  records `is_imbens_manski_confidence_set: false`. It must never be called an Imbens–Manski confidence
  set: that object buys frequentist coverage under moment inequalities and this construction does not.
- **Conceded before a referee finds it:** `C_O` is computed from BYM2-smoothed prevalences, so the *lower*
  end of the bound is model-based at the end where it is supposed to discipline the model. A direct-estimate
  count is possible as a glance — 97 of 654 observed LGAs above 0.5 on the raw proportions, giving [97, 217],
  which brackets the model answer too — but thresholding a noisy direct estimate is not a valid bound. Say
  the limitation, do not paper over it.

### P7 — decision layer and calibration

- Exceedance probabilities per LGA; the Bayes threshold from P4 of the theory annex with explicit costs;
  expected counts expressed as **shares**, because the household weights in the extract are normalised
  and absolute population is not recoverable from the repo.
- Calibration: spatial cross-validation (leave-states-out), interval coverage, comparison against direct
  estimates.

**Count functional done (2026-11-22)** — `.agent/T10-report.md`, `data/derived/count_functional.json`:

At c = 0.50: **E[C] = 115.0 of 774 LGAs**, 95% interval 101–130, posterior sd **7.38**. Independent term
40.26 (sd 6.34), **pairwise term 14.25 (ratio 0.354)**. A marginal-only method would report sd 6.34 — **14%
too small**. The IID-LGA comparator gives ratio **0.187**, so about half the pairwise term is shared
coefficient uncertainty and half is geography: that attribution is what makes it a result.

Determination: 32 LGAs above 0.50 with probability > 0.95, 509 below, **40 undecided in the 0.40–0.60
band**.

**Caveat to state in the paper:** the pairwise term is 14.2 ± ~1.7. Split-half gave 13.37 vs 15.12, a 12%
relative difference at 20,000 draws. Report the interval, never the point estimate alone.

### P7b — calibration (first test FAILED, 2026-11-23)

`.agent/T12-report.md`, `scripts/calibration_spatial.R`, `data/derived/calibration_summary.json`,
`data/derived/calibration_folds.csv`. Pass rule fixed before any fold was fitted; not revised.

**Leave-one-geopolitical-zone-out, six folds, every LGA predicted once by a model that never saw its zone.**

| check | pass band | value |
|---|---|---|
| mean of z | −0.15 to +0.15 | **−0.654** FAIL |
| sd of z | 0.85 to 1.15 | **1.648** FAIL |
| coverage of \|z\| ≤ 1.96 | 0.90 to 0.98 | **0.775** FAIL |

8 of 37 states inside their interval (expected 35); 0 of 6 zones. Re-checked by the secretary from the
fold file (identical), and the script re-runs and reproduces itself. Not an artefact of the imputed
design variance: the 388 multi-cluster LGAs alone fail worse. The fold split is sound — pooling the direct
estimates reproduces the national unweighted 0.2774.

**The diagnosis matters more than the verdict.** Against the same model fitted on everything, over the 654
LGAs with data: **in sample the correlation with the direct estimates is 0.974** (spread 0.188 vs 0.212);
**out of sample it is 0.195** (spread compressed to 0.110). Every zone is predicted near 0.13–0.28 whatever
the truth: North East direct 0.548 → predicted 0.247; Yobe 0.844 → 0.266. The model smooths the data it
saw; it does not carry an area-level surface into a region it did not.

**What this scopes and what it does not.** The zone test also removes each held-out area's neighbours, which
is not the paper's problem — the 120 unclustered LGAs sit among observed LGAs. The test that matches the
claim (one LGA removed, neighbours retained) had not been run when this was written. Until it is: the paper
may not present 774 LGA estimates as a calibrated map, and the count interval (101–130) is unvalidated.

**Consequence for the manuscript, if the fair test also fails.** The contribution moves decisively to what
is identified (P6) and what the count is worth (P7), with the LGA surface presented as a smoothing whose
per-area precision is demonstrated only where data exist. That is a narrower paper than planned and a
defensible one.

**The fair test PASSED (T13, 2026-11-23).** One LGA removed, neighbours kept, 200 LGAs in five groups of
40, zero within-group adjacency verified by the secretary against a queen graph he rebuilt himself
(2,230 edges; 136 edges among the drawn set; 0 contaminated). Mean z **−0.052**, sd **1.111**, coverage
**0.940** — all three inside the pre-declared bands. Widening every interval by `k = 1.111` gives 0.95, and
the out-of-fold check (k fitted on four groups, coverage measured on the fifth) gives 1.000, 1.000, 0.950,
0.900, 0.925 — mean 0.955, so the correction is not fitted to the data it is judged on.

**The pair is the paper's position:**

| design | asks | mean z | sd z | coverage |
|---|---|---|---|---|
| T12, whole zone removed | map a region never sampled? | −0.654 | 1.648 | 0.775 |
| T13, one LGA removed | place one area among observed neighbours? | −0.052 | 1.111 | 0.940 |

In sample the model correlates 0.975 with the direct estimates; out of sample here 0.768; when a whole zone
was removed 0.195. **Interpolation is calibrated. Extrapolation is not.** Neither number may be quoted
without the other, and the count interval is still unvalidated by either test.

**A brief error of mine, for the record.** T13's brief asserted that `data/derived/neighbours.csv` was the
774-node LGA graph; it is the 37-node **state** graph. The agent noticed and built the LGA graph from the
polygons, which is why the design is clean. A file called `neighbours.csv` is not evidence of which graph
it holds.

### P7c — give the model information that exists where nobody was interviewed

**Diagnosis, stated plainly.** Every predictor in the present fit is measured only in households. An LGA
with no households therefore has *no predictors at all*, and the model falls back to the national average.
That is not a tuning defect; it is the reason the zone-out test collapsed. The DHS geographic file carries
~130 environmental covariates sampled at the 1,380 cluster coordinates — aridity, nightlights, travel time,
rainfall, vegetation, elevation, livestock, malaria. Those are surfaces, not survey responses, so they can
be interpolated to a place with no survey. **None has ever entered a fit.** It is the only information
available offline that exists everywhere.

**Three tickets, in this order, nothing fitted twice.**

1. **T14 (done 2026-11-23) — the covariate surface.** LGA centroids and areas from the ADM2 polygons
   (774, not 1,299 — my brief was wrong); inverse-distance interpolation (k = 3) of eight
   mechanism-chosen covariates plus population density; **5-fold cross-validation over the 1,380
   clusters**. Pre-declared rule applied mechanically. **Result: only the environmental covariates
   survive.** Aridity 0.999, precipitation 0.999 (dropped to aridity at |r| = 0.985), elevation 0.977,
   malaria 0.923, vegetation 0.920. **Nightlights 0.522, travel time 0.614, livestock 0.535 — all dropped
   as un-interpolatable.** Final five: density, aridity, vegetation, elevation, malaria.
   **That is a finding, not a footnote:** the covariates that most plausibly drive food insecurity —
   economic activity, market access, pastoral livelihoods — cannot be recovered at this scale from 1,380
   sample points. What survives is agro-ecology and terrain. The paper says which four dimensions it has
   and which it lacks. The surface is a function with `exclude_cluster_ids`, proved by excluding the North
   East (213 clusters, 118 of 774 LGAs changed, zero inconsistencies), so the next ticket can hold a zone
   out honestly. `n_clusters_in_lga` in that table is stale (123 zeros, pre-correction) and must not be
   used — **third** file with a bad cluster count.
2. **T15 (done 2026-11-23) — refit with the covariates. Improved; does not pass; not a fix.** Same six
   folds, same scoring, same pass rule. Coverage **0.775 → 0.797**, mean z **−0.654 → −0.485**, sd z
   **1.648 → 1.565**. All three still fail. The south is now calibrated (South West mean z +0.006,
   coverage 0.946); the north stays 1.3–1.7 sd low, with North Central over-predicted and North East
   0.27 below truth. The model lands every zone between 0.15 and 0.30 whatever the truth.
   **The deeper finding: 19 of 20 coefficient intervals contain zero.** Once household composition is
   accounted for, aridity, elevation, vegetation, malaria and density carry no measurable signal about
   severe food insecurity at LGA level. The covariates do not fail for being mis-signed — they fail for
   being inert. The north-east's 0.548 is not an agro-ecological phenomenon. That is a result for the
   paper, not a footnote.
   Verified by the secretary: mean z −0.4854, sd 1.5649, coverage 0.7966 recomputed; direct estimates
   identical to T12's, so the comparison is controlled (`Aridity_2020` confirmed from the DHS description,
   p10: index 0 = most arid, 300 = most wet, so higher is wetter and the −0.46 LGA correlation is the
   expected direction).
3. **T16 — calibrated intervals for what survives.** Apply the measured inflation factors and report
   coverage again: `k = 1.111` for interpolation (already validated out of fold, T13) and `k ≈ 1.57` for
   regional extrapolation (from T15's sd of z). The point estimates stay blurry; the intervals must stop
   lying. **Do not — under any framing — add a zone-level random effect and re-run the zone test.** A
   held-out zone's level is unidentified; fitting one would be fitting the answer, and it would produce a
   pass that means nothing.
4. **T16 and T17 — put the calibration on an exposure axis.** The three tests differ in one thing that can be
   measured: **the mean number of a held-out LGA's neighbours that no fit ever sees.** T13 = 0.00,
   the 120 unsampled LGAs = **0.950**, T12 ≈ 5.4. T16 matched only edges *inside* the held-out set and so
   ran at **1.670** — over-exposed by 1.76×, and it failed narrowly (sd z 1.181 against a 1.15 ceiling,
   coverage exactly 0.900), with one group of 40 carrying 8 of the 20 misses. Verified by the secretary,
   including the 0.730 of that exposure that comes from sitting next to the permanent 120. **T17 (running)**
   reuses T16's exact 200 LGAs and regroups them to the 0.950 exposure, so exposure is the only difference.
   Then the paper reports one curve, all four points, and no fifth experiment. If T17 also lands near 0.90,
   that is the answer and the k is ~1.18; the bracket [0.900, 0.940] is not needed and the monotonicity
   assumption disappears.

**Calibration is CLOSED (T17, 2026-11-23).** Measured at the exposure the 120 actually face (0.95 unobserved
neighbours, achieved exactly in all five groups): **coverage 0.890** (178/200), sd z 1.178, mean z −0.058 —
**fails the rule**, by two areas on coverage. T16 and T17 are indistinguishable on spread (1.181 vs 1.178)
at exposures 1.67 and 0.95, so **the failure is already present at 0.95** and T16's bracket [0.900, 0.940]
was too optimistic.

**What the four designs actually say — and it is not a curve.** Recomputed by the secretary on one
definition: T13 at 0.88 exposure gives 0.940, T17 at 0.95 gives 0.890, T16 at 1.67 gives 0.900, T12 at 5.4
gives 0.775. The middle three span 0.89–0.94, which is within binomial noise at n = 200 plus group effects.
**So: coverage for a single unsampled area among sampled neighbours is about 0.89–0.94; remove a whole region
and it collapses to 0.775.** Do not write "coverage declines with exposure" — the evidence does not support
it. Both T16 and T17 have one group of 40 carrying the verdict; that fragility must be in the paper.

**Practical consequences for the manuscript:** quote ≈0.89 (range 0.878–0.900) for the 120; widen unsampled
intervals by **k ≈ 1.18**, validated out of fold (0.875, 1.000, 0.925, 0.975, 0.950); never quote a nominal
95%. The count interval 101–130 remains untested and must be labelled so.

### P7d — the mathematics of the count (done 2026-11-23)

`.agent/T18-theory.md`, `docs/theory.tex` (compiles), `scripts/theory_counts.R` (exit 0, 24 checks).

**Three errors in the secretary's brief were caught by the analyst, all of which would have reached a
referee.**

1. **The pairwise Fréchet route to the lower bound is invalid** for `n ≥ 3` and returns a variance of
   **−4436.63** on our marginals. The sharp lower bound is `f(1−f) = 0.024375` with `f = frac(Σp) = 0.975`,
   attained by the cyclic coupling (verified by 400,000-draw simulation).
2. **P1's if-and-only-if is false.** Signed covariances cancel: a dependent joint with covariances
   `(+0.1, 0, −0.1)` has `Var(C)` exactly equal to the independence value. The statement is one-directional.
3. **P3 needs no monotonicity** — it is the union bound. Monotonicity buys the interpretable sentence that the
   identified set is inside whenever the statistic is central; both estimands satisfy it (slopes exactly 1
   and exactly `p`).

**The result that changes the headline.** Given the 774 marginals and nothing else,
`Var(C) ∈ [0.0244, 5492.63]`, i.e. `sd(C) ∈ [0.156, 74.11]`. The model's 54.509 sits **0.99% of the way up
its own feasible range**. So the marginals do not identify the count's variance, and the reported interval
101–130 is a statement about the model's dependence structure. State that in Results, not Limitations.

**Blocking before submission:** the attribution table cites Fréchet, Hoeffding, Meilijson–Nádas, Dhaene,
Popoviciu, Bhatia–Davis, Manski and Imbens–Manski, and **none was opened**. The project rule applies; each must
be confirmed or the attribution rebuilt.

**The paper this becomes, if the covariates help.** Not "a map of 774 LGAs" but: an area-level surface
whose precision is demonstrated by spatial cross-validation, an identification bound on what the design
cannot settle, and a count with intervals a decision can rest on. If the covariates do **not** help, that
is publishable too — as the negative result plus the calibration protocol the field does not currently
run — and the map is demoted, not defended.

**Do not let this become scope creep.** The deadline is 30 December 2026. If T15 shows no improvement, the
paper proceeds on the P6/P7 spine and drops the covariate chapter to a sentence in Limitations.

### P8 — benchmarks

- Gradient boosting with spatial cross-validation and conformal intervals (scikit-learn 1.9 is installed;
  LightGBM, XGBoost and PyTorch are not).
- The published spatial random forest (AOAS 2025) as the external anchor.
- Any published modelled surface for Nigeria, if one exists for this outcome.
- **Rule:** score at area level, not household level, or the comparison is meaningless.

### P9 — manuscript

- Journal constraints from the poster are in `AGENTS.md`: 12 pt, A4, abstract ≤ 250 words, fixed section
  order, APA 7th.
- No citation enters a draft until its DOI is verified and its abstract opened.

### P10 — submission compliance

- Amend the DHS project description to cover a food-insecurity outcome (edit, not new registration).
- Send a PDF of the publication to references@dhsprogram.com.

---

## Defect register

| Defect | Where it is recorded |
|---|---|
| CPI panel: April 2025 corrupt, Dec 2024 duplicated, base break | `AGENTS.md`, `data/panel/qc_flags.csv` |
| DHS: `hfs_sev` scaled by 1e8; state codes zone-ordered; two estimands | `AGENTS.md` |
| Dataset: wrong outcome, 30% silent attrition | this file, P2 |
| Theory: wrong MSE formula (mine), Kish does not match this design | `AGENTS.md`, `.agent/T5-theory.md` |
| Literature: abstracts only, no full texts read | `.agent/T4-litreview.md` |
| **LGA files: `lga_estimates.csv` `n_clusters` is a duplicate of `n_households`; `lga_coverage.csv` `n_clusters` is the pre-correction assignment (123 zeros, not 120)** | this file, "A debt to settle" above |

## Evidence index

| Finding | Lives in |
|---|---|
| Literature and novelty position | `.agent/T4-litreview.md`, `.agent/T4-report.md` |
| Four propositions, proofs, numeric checks | `.agent/T5-theory.md`, `.agent/T5-verification/` |
| Direct state estimates | `data/derived/fi_state_direct.csv` |
| Covariate definitions | `data/derived/covariate_spec.md` |
| CPI panel build and defects | `.agent/T1-report.md`, `data/panel/qc_flags.csv` |
| Dispatch history | `~/.config/opencode/runtime/ledger.jsonl` |
| Identification bounds, p, count and share | `data/derived/identif_bounds.json`, `.agent/T11-report.md` |

## Unproven

- The "nothing exists for Nigeria" claim rests on abstract-level screening only. The two nearest papers
  must be read in full before the introduction is written.
- **Calibration has still never been checked.** No spatial cross-validation exists, so the 95% intervals
  are a claim about the model, not a demonstrated property. This is now the first thing a referee asks.
- The lower end of the identification bound is model-based (smoothed prevalences), and `π_O` is not
  design-weighted because the fit is unweighted. Both are disclosed, neither is fixed.
- Whether the 120 unclustered LGAs are better or worse off is untestable here — and the whole
  identification exercise rests on assuming nothing about them.
- LGA assignment of displaced coordinates is untested against DHS's own boundaries.
- The covariate reduction in between-area variance has not been measured on our data.
