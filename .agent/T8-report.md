# T8 report — clusters → LGAs

**Vintage note:** this ticket writes no `registry/` vintage. It writes derived files only.

## 1. Changed

| Path | What |
|---|---|
| `scripts/lga_assign.R:1` | New. The whole build: LGA→state by representative point (`:80`), cluster→LGA by points-in-polygon (`:140`), border distance (`:175`), near-border rule (`:200`), sensitivity (`:220`), the three outputs (`:252`, `:310`, `:449`). |
| `data/derived/cluster_lga.csv` | 1,380 rows × 13 columns. |
| `data/derived/lga_coverage.csv` | 774 rows × 6 columns. |
| `data/derived/lga_assignment_qc.json` | 15 assertions, all counts, displacement figure with its source line, sensitivity comparison, limitations. |
| `.agent/T8-progress.md`, `.agent/T8-report.md` | This ticket. |

One command reproduces all three: `Rscript scripts/lga_assign.R` from the repo root.

## 2. Verified

**Assignment chain.** Real output of the final run:

```
ADM1 features: 37   ADM2 features: 774   clusters: 1380   households: 39877
LGA->state: 774 LGAs, 37 states, counts sum to 774 (assert TRUE)
assignment rules used: representative_point=774
clusters in exactly one LGA: 1380 | on a shared border (>1 LGA): 0 | outside all LGAs: 0
containment cross-check lon/lat(s2) vs EPSG:32632: disagreements 0
UTM32N vs geodesic on 200 clusters: median |diff| 4.5 m, max 77.6 m, near-border flags differing 0
assertions: 15 of 15 passed
QC passed
```

Every LGA was assigned by its representative point — the area-overlap and nearest-state fallbacks
in the code were never needed. Per-state LGA counts sum to 774 and all 37 states receive LGAs
(so no state's LGAs were silently captured by a neighbour).

**Independent re-derivation in Python** (`pandas`, 20 checks, all PASS), not the R script's own
assertions: rows 1380/774; `DHSCLUST == hv001`; every cluster present in the microdata; no missing
`lga_id` or `state_iso`; `near_border == (border_distance_m <= border_radius_m)` for all rows;
`n_clusters` recomputed from `cluster_lga.csv` matches `lga_coverage.csv` exactly (0 mismatches);
`n_clusters_sensitivity` recomputed from the stated rule matches exactly (0 mismatches);
`n_households` recomputed from the microdata through the cluster join matches exactly (0
mismatches); sums 1380, 1380, 39877; each assigned LGA carries exactly one state.

**Determinism.** Script re-run; both CSVs byte-identical (`Get-FileHash` comparison, `True` for both).

**Geometry is not the explanation for the near-border count.** Median LGA area 713 km², and
representative points sit a median 6.2 km from their own boundary, so 5 km against ~27 km-wide
LGAs genuinely puts most clusters near an edge. Checked before trusting the headline.

## 3. Counts the paper needs

| | primary | sensitivity |
|---|---|---|
| LGAs with 0 clusters | **123** (15.9%) | **145** (18.7%) |
| LGAs with data | 651 (p = 0.8411) | 629 (p = 0.8127) |
| 1 cluster | 260 | 262 |
| 2–4 clusters | 357 | 328 |
| 5+ clusters | 34 | 39 |

- 807 of 1,380 clusters (58.5%) are within the displacement radius of their LGA boundary:
  340 urban (≤2 km), 467 rural (≤5 km). Rural clusters within 10 km: 617.
- 517 LGAs change cluster count under the sensitivity; 84 fall to zero, 62 rise from zero.
- Clusters outside every LGA polygon: **0**. Clusters on a shared border: **0**.

## 4. Deviations

1. **One extra column**, `border_radius_m`, in `cluster_lga.csv` (all 12 required columns present and
   in the requested order). Without it `near_border` cannot be interpreted per row; the radius differs
   by urban/rural.
2. **`tabulate(..., weights=)` does not exist in this R** — first run failed on it. Replaced with
   `tapply`. No behaviour change.
3. **Added an s2 containment cross-check** (lon/lat vs projected) and a **projection accuracy check**
   (UTM 32N vs geodesic on 200 clusters). Both were needed to make the border distances defensible;
   both are recorded in the QC file.
4. **Added a state-rollup conflict table** to the QC file, because the 15-cluster defect below is
   found by this build and is not in the defect register.

## 5. Two findings that change how the paper should state the rule

**(a) DHS displacement preserves the LGA.** `GPS_Displacement_README.txt` lines 5–7: "the displaced
cluster's coordinates are located within the same admin0, admin1, and admin2 areas as the undisplaced
cluster." So the published point is guaranteed inside the *true* LGA of DHS's own admin2 layer, and
points-in-polygon against that layer would be exact by construction. The 58.5% ambiguity is therefore
**not** displacement sending clusters across borders — it is that geoBoundaries ADM2 is not DHS's
admin2 layer. The paper must say this; the naive "coordinates are displaced up to 5 km so LGA
assignment is uncertain" sentence would misdescribe the mechanism.

**(b) The two boundary sets disagree at state level for 15 clusters (1.1%).** For example cluster 155
is recorded as Yobe by DHS but falls in Gombe's Nafada LGA here; cluster 119 Jigawa → Katsina's Baure.
Consequence: LGA counts roll up to state counts that differ from the microdata's `geography` column by
at most 2 clusters in 19 states. **State-level aggregates must use the microdata state variable, not
the LGA rollup.** Flagged in the QC file, not silently repaired.

## 6. Left alone (found, deliberately not fixed)

- The 15 state-level disagreements above. Fixing them would mean overriding geometry with a state
  field, which changes the assignment rule this ticket was asked to state. It is a decision for the
  user, not a silent patch.
- `data/restricted/dhs-2024/ge/NGGE8AFL.shp` carries `ADM1FIPS`/`ADM1SALB*` columns that are all
  `NULL` — unused, harmless.
- 5 duplicate LGA names in the ADM2 file. Uniqueness is carried by `lga_id`, which is why the join
  uses geometry and never names.

## 7. Unproven

- **That geoBoundaries ADM2 matches DHS's admin2 layer anywhere.** No DHS polygon file is on disk, so
  the boundary mismatch is measured (15 clusters, ≤2 per state) but not explained area by area. The
  sensitivity is a plausible-alternative bound, not a worst case: a cluster could in principle belong
  to a third LGA under DHS's layer.
- **The 1% rural 10 km tail is treated as out of scope.** Radii used are 2 km / 5 km; 617 rural
  clusters would additionally qualify at 10 km. Recorded as a count, not folded into the sensitivity.
- **`n_households` is a count of surveyed households, not population.** The DHS weights are
  normalised, so absolute population per LGA is not recoverable — this does not change here.
- LGAs are working boundaries for reporting, not a legal or electoral record.
