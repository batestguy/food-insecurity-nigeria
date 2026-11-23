# T11 — identification bounds for the crisis-LGA count

**Question.** The model reports E[C] = 115 of 774 LGAs above 50%, 95% interval 101–130. 120 LGAs hold
no survey cluster. What set of counts can the **survey design** not rule out?

**Answer, in one line.** The design cannot place the national count anywhere inside **87 to 231**
LGAs (95% posterior interval for the identified set). The model's 101–130 sits wholly inside it. Of
the 144-LGA width, **120 (83.3%) is pure assumption** about the unclustered areas; the remaining 24 is
estimating uncertainty in the 654 observed areas.

---

## 1. Estimand and design

Two estimands, reported separately and never pooled, as the brief requires.

**(a) Count of LGAs above the line.** `C = #{s = 1..774 : θ_s > 0.50}`, where `θ_s` is LGA prevalence
for a household at the LGA's mean covariate profile, cluster effect marginalised — the same quantity
`count_functional.json` reports. Partition LGAs into `O` (654 with at least one cluster) and `U` (120
with none). With `C_O = #{s∈O : θ_s > 0.50}` the identified set given one realisation of the observed
statuses is `[C_O, C_O + 120]`, width 120. The identifying assumption is one sentence a
non-statistician can argue with: **nothing is assumed about the 120 unclustered LGAs, so each of them
counts 0 or 1.**

**(b) Population share living in a crisis LGA.** `π_O` = population-weighted share of the observed
population in LGAs above the line; `p` = population share held by `O`. Manski bounds
`[p·π_O, p·π_O + (1−p)]`, width `1−p` = 0.110373. Identifying assumption: **the population in
unclustered LGAs is between 0% and 100% above the line.**

Both use `theta`, a 20,000 × 774 matrix of per-LGA prevalence draws saved by `scripts/lga_model.R`.
That is the intended path: the draws are joint across areas, so spatial dependence is preserved and no
independence approximation is needed. Nothing was refitted.

---

## 2. Estimate

`p_population = 0.8896274555` (88.9627%), over the 773 LGAs that have a denominator. `p_area =
0.8449612403` (654/774), reported and used in no bound. `n_observed = 654`, `n_unobserved = 120`.
National denominator 204,909,220 people; the 120 unclustered LGAs hold 22,616,352 of them (11.0373%).

### (a) Count of LGAs above 50%

| | LGAs |
|---|---|
| Observed-only count `C_O`, posterior mean | **99.13** (sd 6.08) |
| `C_O` 95% interval across draws | 87 to 111 (median 99, range 76–123) |
| Identified set, at the posterior mean | [99.13, 219.13] |
| **Draws interval on the identified set** | **[87, 231]**, width 144 |
| Bound width contributed by assumption | **120** (83.3% of 144) |
| Model answer (T10, unchanged) | E[C] = 114.975, [101, 130], width 29 |

The model's interval lies entirely inside the identified interval; the identified interval is 5.0× as
wide. The model's upper end (130) is **101 LGAs below** what the design can rule out (231). That 101 is
the work the model's spatial smoothing and covariate extrapolation are doing that the survey did not.

### (b) Population share living in a crisis LGA

| | share |
|---|---|
| Observed-only estimate `π_O` | **0.137214** (13.72%), sd 0.009237 |
| `π_O` 95% interval across draws | 0.119474 to 0.155785 |
| Identified set, at the posterior mean | [0.122104, 0.232477] |
| **Draws interval on the identified set** | **[0.106287, 0.248963]** = 10.63% to 24.90% |
| Bound width `1−p` | 0.110373 (11.04 percentage points) |

Note the scale: the point estimate is 13.7% of the observed population; the design cannot rule out
24.9%. The model's own national figure (29.10% weighted household prevalence) is not the same object —
it is a household-weighted prevalence, not a population share of areas in crisis, and the two must not
be quoted against each other.

### Monotonicity variant — labelled, not the headline

Under `π_U ≥ π_O` (unclustered LGAs are no better than observed ones — an assumption about Nigeria
that these data cannot test), the identified set is `[π_O, p·π_O + (1−p)]`:

- at the posterior mean: **[0.137214, 0.232442]**, mean width 0.095228
- draws interval: [0.119474, 0.248963], width 0.129490

The assumption costs a lot to make and buys **1.3 percentage points** of interval width (0.142676 →
0.129490). It is not worth defending in the paper. Recorded in its own JSON key with
`status: "variant, NOT the headline"`.

---

## 3. Diagnostics (printed by the script, all pass)

```
CHECK 2  p_population = 0.8896274555 ; target 0.88963 ; |diff| = 2.544e-06 ; tol 1e-5 ; PASS
CHECK 1  sum_{s in O} P_050(rds) = 99.1270500000 ; mean over draws of C_O = 99.1270500000 ; |diff| = 0.000e+00 ; PASS
CHECK 1b same sum from lga_estimates.csv (rounded to 5 dp) = 99.12705 ; |diff| = 0.000e+00  [rounding only]
CHECK 1c mean C_O = 99.127050 ; target 99.127 ; |diff| = 5.000e-05 ; PASS
max |exceed_050 - 1{theta > 0.50}| = 0.000e+00  [exact]
max |colMeans(theta) - posterior_mean(csv)| = 4.996e-16
max |colMeans(exceed_050) - P_050(rds)|   = 0.000e+00
mean C over all 774 areas (model headline) = 114.975000  [count_functional: 114.975]
```

Structural checks: 774 areas in the `.rds` in the same order as `lga_estimates.csv`; 654 observed /
120 unobserved; 1 LGA without a population denominator (Bakassi). Column order verified identical.

---

## 4. Sensitivity and what moves the estimate

- **The bound width does not depend on the threshold.** `[C_O(c), C_O(c)+120]` has width 120 for any
  `c`; only the location moves. So the identification statement is threshold-free even though the
  point estimate is not (E[C] is 196 at c = 0.40 and 61 at c = 0.60).
- **The location is sensitive to the unclustered LGAs' model-implied risk.** The model predicts 15.85
  of the 120 above the line (sum of `P_exceed_050`), and only 8 have P > 0.5; the highest is Magumeri
  (Borno) at 0.744. If those 15.85 are right, the national count is 115. If the truth is 0, it is 99;
  if all 120 are above, it is 219.
- **p is stable.** 120/774 by count, but 11.04% by population, and the two differ because unclustered
  LGAs are systematically smaller — the paper must quote the population version, and does.

---

## 5. Changed

- `scripts/identif_bounds.R` — new, 447 lines. Sections: 0 draws (37), 1 population share (62, p at
  93–94), 2 consistency (111), 3 estimand (a) (131, `C_O` at 135, bounds at 171), 4 estimand (b)
  (182, `pi_O` at 193, bounds at 197), 5 monotonicity variant (210), 6 comparison (223), 7 outputs
  (243, CSV at 256, JSON at 443).
- `data/derived/identif_bounds.json` — new, 18 top-level keys.
- `data/derived/identif_bounds_lga.csv` — new, 120 rows × 6 columns.
- `.agent/T11-progress.md`, `.agent/T11-report.md` — new.

Nothing else was touched. No git command was run (the directory is not a repository).

## 6. Deviations

1. **`lga_id` added as the first column** of `identif_bounds_lga.csv`. The five required columns are
   all present and in the stated order after it; without the id the file cannot be joined back.
2. **`exceed_050` recomputed** from `theta > 0.50` after verifying the saved matrix is identical
   (max abs difference exactly 0). No numeric consequence.
3. **Extra JSON content**: a `checks` block, a `console_log` array (77 lines), `quantities`,
   `comparison_to_model`, `interval_interpretation`. All additive.
4. **No seed is set because no random number is drawn.** The script is a deterministic function of the
   saved 20,000 draws; the file's own seed (20261122) is copied into the JSON.

### Disagreements with the pre-declared construction (implemented as written)

- **The lower end of (a) is not a design-based number.** `C_O` is computed from the model's `θ_s` for
  observed LGAs, and those are BYM2-smoothed, so they already borrow strength from neighbouring
  unobserved LGAs. The identified set therefore inherits the model at the end where it is supposed to
  discipline it. A genuinely design-based `C_O` would need direct estimates in 654 LGAs with a median
  of 2 clusters each; that is not viable, so the flaw cannot be removed here — only disclosed.
- **`π_O` mixes two weighting schemes.** `θ_s` comes from an *unweighted* binomial likelihood
  (unweighted national 0.2774 against weighted 0.2910), and `π_O` then weights those prevalences by
  external 2020 projected LGA populations. It is a population-weighted average of model prevalences,
  not a design-consistent population share. A design-weighted version needs a weighted refit, which is
  out of scope for this ticket.
- **"How much of the model's interval is assumption" is not a decomposition.** The model's interval
  and the identified interval are different objects; comparing widths is informative but does not
  partition the model interval into assumption and data. The JSON reports the comparison under
  `comparison_to_model` and does not call it a decomposition.
- **The percentile interval is a posterior interval, not a confidence set.** It is not an
  Imbens–Manski (2004) confidence set and the paper must not borrow that name; the JSON carries
  `is_imbens_manski_confidence_set: false` with the reason. One thing the construction does earn: in
  all three reported cases both bounds are non-decreasing functions of a single draw-level quantity
  (`C_O` or `π_O`), so the identified set lies inside the reported interval exactly when that quantity
  lies in its own central 95% interval. Containment therefore carries 95% posterior mass — derived
  algebraically, not simulated. It carries no frequentist coverage and it conditions on the model for
  the observed LGAs being right.

### Bug found and fixed during the work

`stringsASFactors` was miscapitalised in the `data.frame()` call that builds the 120-row CSV, so R
treated it as a data column and wrote a stray `stringsASFactors` column. Caught by reading the output
back with pandas; fixed; the files on disk are from the corrected script (run 3).

## 7. Open risks — what a statistical referee should attack first

1. **The lower bound is model-based, not design-based** (above). This is the first thing to attack and
   the paper should say so before a referee does.
2. **`p` is treated as known and the observed/unobserved split as exact.** Cluster→LGA assignment uses
   geoBoundaries polygons, not DHS's; 15 clusters (1.1%) fell in a different state from the survey
   record, and the state-authoritative reassignment is what produced 120 rather than 123 unclustered
   LGAs. Any further reclassification moves `p` in the fourth decimal — immaterial to a width of 120,
   but it should be sensitivity-checked rather than asserted.
3. **Bakassi has no population denominator and is itself unclustered.** The 11.04% is therefore a share
   of 204,909,220 people in 773 LGAs, not of all 774. If Bakassi holds population, the unobserved share
   is slightly above 11.0373%; the brief's instruction to exclude it from both numerator and
   denominator was followed.
4. **The interval is conditional on the model.** Everything above the word "posterior" is a statement
   about this BYM2 fit, not about Nigeria.

## 8. Unproven

- No design-weighted refit, so `π_O` is not design-consistent.
- No sensitivity to the choice of LGA boundary source or to the 15 state-discordant clusters.
- Bakassi's population is unknown, so the unobserved population share is a lower bound in that one
  respect.
- The 95% containment claim is derived from the monotonicity of the bounds in `C_O` / `π_O`, not
  checked by simulation.
- Whether the 120 unclustered LGAs are systematically better or worse off is untestable here. That is
  the assumption the whole exercise rests on, and it stays untested.
- Only the c = 0.50 threshold was run, as the brief fixed. The width is threshold-invariant by
  construction; the locations at other thresholds were not computed.

---

## 9. Secretary addendum — independent re-check (2026-11-23)

Written by the secretary after the agent hit its step cap. The agent did not run this.

A fresh R script (kept outside the repo, at `%LOCALAPPDATA%\Temp\opencode\t11_check.R`; it reads only
`lga_posterior_draws.rds` and `lga_estimates.csv` and never calls `scripts/identif_bounds.R`) reproduces
every headline number:

```
rds names: theta exceed_050 P_050 Pst_050 C_050 lga_id seed n_draws theta_iid method
theta dim: 20000 774
max|colMeans(theta) - posterior_mean| = 4.996004e-16
lga_id identical: TRUE
observed: 654   unobserved: 120
missing pop: 1   p_population (mine): 0.8896274555   1-p = 0.1103725445
mean C_O: 99.12705   sum CSV P_050 over obs: 99.12705
C_O q025/q50/q975: 87 99 111   range: 76 123
IDENTIFIED INTERVAL (a): [ 87 , 231 ]
mean pi_O: 0.137214   sd: 0.009237
IDENTIFIED INTERVAL (b): [ 0.106287 , 0.248963 ]
model [101,130] inside [ 87 , 231 ] : TRUE
unobserved csv rows: 120  cols: lga_id,lga_name,state_iso,lga_population,posterior_mean,P_exceed_050
matches lga_estimates unobserved set: TRUE
sum P_exceed_050 in csv: 15.847950
max P: Magumeri 0.7439
```

**Robustness glance at the conceded flaw** (referee attack #1). Replacing the smoothed count with the raw
direct proportions in the 654 observed LGAs gives **97** above 0.5 rather than 99.13, so the identified
interval becomes **[97, 217]** — the model's 101–130 is still inside it. 624 of the 654 LGAs agree on
above/below between the two routes. This is a glance, **not** a bound: thresholding a noisy direct
estimate at 0.5 is not a valid identification argument, only reassurance that the lower end is not an
artefact of smoothing.

**Two input defects found while checking; neither changes any number above.**

1. `lga_estimates.csv`: the column `n_clusters` is a duplicate of `n_households` — identical in all 774
   rows, both summing to 39,877. The observed/unobserved mask is unaffected (an LGA has clusters iff it
   has households), so both estimands stand, but **no manuscript sentence may quote a cluster count from
   this file.**
2. `lga_coverage.csv`: its `n_clusters` is the **pre-correction** assignment — 123 LGAs with none and 260
   with one. The 120 used downstream comes from `cluster_lga_fixed.csv` (654 LGAs with at least one
   cluster, 1,380 clusters in total). Anything quoting coverage must use the fixed file.

Both are recorded in `PLAN.md`, in "A debt to settle before drafting starts" and in the defect register.
