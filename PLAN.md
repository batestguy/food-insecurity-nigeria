# PLAN.md — state of the food-insecurity small-area paper

This is the **state file**. `AGENTS.md` holds the rules, traps and settled decisions; this file holds
where the work actually stands, what each phase must produce, and what to do when one fails.

Update it whenever a ticket finishes. If a phase changes status, the change goes here first.

Last updated: 2026-11-22, end of session.

---

## Resume here — read this first next session

**Where we stopped.** P2 (analysis dataset) was rebuilt and verified by the secretary. No agents are
running; nothing is queued. The last agent delivered proofs but hit its step cap before writing them up,
so `.agent/T5-theory.md` was transcribed by the secretary from saved outputs.

**Do this first, in this order.**

1. **Check for the downloads.** `data/restricted/dhs-2024/ge/` should hold `NGGE8AFL` (cluster
   coordinates) and `NGGC8AFL` (geospatial covariates). If present: unpack, record SHA-256 in the
   manifest, and confirm coordinates join to `hv001` for all 1,380 clusters. If absent, everything below
   state level stays blocked.
2. **Run P4, the design-aware state baseline.** It needs no downloads and produces the first real model
   output, validating the chain (INLA → adjacency graph → new dataset) end to end. Write a ticket from
   the P4 section below; expected verdict is "barely moves the estimates", and that is the result.
3. **If the coordinates arrived, open P5.** Map clusters to LGAs, with the displacement sensitivity
   check from the P5 section.

**Commands that build things** (all run from the repo root):

```
python scripts/build_analysis_households.py     # rebuilds the dataset; prints retention and prevalence
python scripts/extract_fi_state.py              # direct state estimates, both estimands
Rscript scripts/moran_fi.R                      # Moran's I on the state estimates
Rscript scripts/probe_inla.R                    # toolchain smoke test, BYM2 on the real graph
python scripts/qa_panel.py                      # legacy: CPI panel checks
```

**Environment.** R 4.5.2 at `C:\Program Files\R\R-4.5.2\bin\Rscript.exe`; INLA 25.10.19 (Windows
binary, installed from a local zip because the source build takes an hour); scikit-learn 1.9.
LightGBM, XGBoost, PyTorch and mapie are **not** installed.

**Do not repeat these.** Do not use `fies_score >= 6` as the outcome (uncitable, and it is what the first
dataset build wrongly used). Do not treat `hv225` blanks as missing — they mean "no toilet". Do not
re-run the old `scripts/build_analysis_households.R`. Do not claim a new estimator: all four propositions
are classical. Do not use any disability variable.

**Unproven, stated plainly.** The literature review read abstracts only, so the "nothing exists for
Nigeria" claim needs full texts. No Bayesian posterior has been fitted, so the decision layer has never
been computed. LGA assignment of displaced coordinates is untested. The covariate reduction in
between-area variance has not been measured on our data.

**Waiting on the user.** The two downloads above, and the amendment to the DHS project description before
any submission.

---

## Status at a glance

| Phase | What it settles | Status | Artefact |
|---|---|---|---|
| P0 | Documentation, decisions, traps | **done** | `AGENTS.md`, this file, `data/derived/covariate_spec.md` |
| P1 | Data access: cluster coordinates + geospatial covariates | **done** | `data/restricted/dhs-2024/ge/` |
| P2 | Analysis dataset | **done — rebuilt 2026-11-22** | `data/derived/analysis_households.csv` |
| P3 | Direct estimates and spatial diagnostics at state level | **done** | `data/derived/fi_state_direct.csv` |
| P4 | Design-aware state-level model (baseline) | pending | — |
| P5 | Clusters → LGAs, covariate-informed model | blocked by P1 | — |
| P6 | Identification and missingness at LGA level | blocked by P5 | — |
| P7 | Decision layer and calibration | blocked by P5 | — |
| P8 | Benchmarks: spatial random forest, published surfaces | pending | — |
| P9 | Manuscript | pending | — |
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

### P6 — identification and missingness

- Apply the Manski bounds from `AGENTS.md` / `.agent/T5-theory.md` at LGA level: which LGAs have no
  cluster, what the identified set is for each, and how wide the national tail interval becomes.
- **This is the paper's distinctive contribution.** It answers "is Yobe really at 85%" with a statement
  about what the data can and cannot identify, rather than a point estimate.

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

## Evidence index

| Finding | Lives in |
|---|---|
| Literature and novelty position | `.agent/T4-litreview.md`, `.agent/T4-report.md` |
| Four propositions, proofs, numeric checks | `.agent/T5-theory.md`, `.agent/T5-verification/` |
| Direct state estimates | `data/derived/fi_state_direct.csv` |
| Covariate definitions | `data/derived/covariate_spec.md` |
| CPI panel build and defects | `.agent/T1-report.md`, `data/panel/qc_flags.csv` |
| Dispatch history | `~/.config/opencode/runtime/ledger.jsonl` |

## Unproven

- The "nothing exists for Nigeria" claim rests on abstract-level screening only. The two nearest papers
  must be read in full before the introduction is written.
- No Bayesian posterior exists yet, so the decision layer has never been computed.
- LGA assignment of displaced coordinates is untested.
- The covariate reduction in between-area variance has not been measured on our data.
