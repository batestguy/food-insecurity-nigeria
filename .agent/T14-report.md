# T14 — LGA covariate surface: build and validation

**Written by the secretary.** The analyst hit its step cap after the artefacts were written and verified but
before the report file. Numbers below are read from the artefacts; the cross-validation table and the
selection set were recomputed by me from the output files.

## The answer

**Yes, but only for the environmental covariates.** Four of the eight candidates interpolate well enough to
carry information; the three that describe economy and access do not, and are dropped by the rule that was
fixed before the run.

| covariate | interpolation r | RMSE / sd | verdict |
|---|---|---|---|
| `Aridity_2020` | 0.999 | 0.04 | keep |
| `Precipitation_2020` | 0.999 | 0.04 | dropped — \|r\| = 0.985 with aridity, which comes first |
| `Elevation` | 0.977 | 0.21 | keep |
| `Malaria_Incidence_2020` | 0.923 | 0.39 | keep |
| `Enhanced_Vegetation_Index_2020` | 0.920 | 0.40 | keep |
| `Travel_Times` | 0.614 | 0.80 | **dropped — cannot be interpolated** |
| `Livestock_Cattle` | 0.535 | 0.85 | **dropped — cannot be interpolated** |
| `Nightlights_Composite` | 0.522 | 0.92 | **dropped — cannot be interpolated** |

Final set (five): **population density, aridity, vegetation index, elevation, malaria incidence**.

**That result is itself a finding and belongs in the paper.** Nightlights, travel time and livestock are the
covariates that most plausibly drive food insecurity — economic activity, market access, pastoral
livelihoods — and they vary too sharply at this scale to be recovered from 1,380 sample points by
inverse-distance weighting. What survives is agro-ecology and terrain. A model extolling "geospatial
covariates" while silently using only climate and elevation would be overclaiming; the manuscript must say
which four dimensions it actually has and which it lacks.

## Verified by the secretary

- **Table structure**: 774 rows; ids unique; `n_clusters_in_lga` sums to 1,380; every LGA has five
  covariate values and a population density except Bakassi, which is `NA` and not zero.
- **Selection set reproduced from the flags**: aridity, EVI, elevation, malaria, density = 774 each;
  nightlights, travel time, livestock, precipitation = 0 each. Consistent with the pre-declared rule.
- **Geometry**: total area 912,516 km², 98.86% of the 923,000 km² reference — the 1.1% gap is coastline
  simplification in the ADM2 file, not a projection error. All 774 polygons, centroid inside own polygon
  for every one.
- **Interpolation distances**: nearest cluster median 9.1 km, p95 27.4 km, max 67.6 km; 51 LGAs are more
  than 25 km from any cluster and 6 more than 50 km. For the 123 records with no cluster of their own the
  median is 15.3 km. Coarse but usable; the far tail is where the covariate is a guess.
- **The hold-out test works**: excluding the North East's 213 clusters changed 118 of 774 LGAs and left 656
  untouched, with zero cases of "nearest set unchanged but values differ". Deterministic and correct, which
  is what makes T15's per-fold rebuild meaningful.

## Deviations

1. **A fact in my brief was wrong again.** I wrote that the ADM2 file holds 1,299 polygons; it holds **774**
   — one per LGA, the same file `lga_assign.R` asserts on. The agent reported the discrepancy rather than
   quietly working around it. That is the third incorrect file fact in three briefs, and the pattern is
   mine: I have been quoting counts from memory. From here, counts in a brief get a command attached.
2. `n_clusters_in_lga` in the covariate table was built from `cluster_lga.csv`, the **pre-correction**
   assignment: 123 LGAs with zero clusters. The corrected file gives 120, and four LGAs listed as empty
   (Ahoada West, Dambatta, Apa, Arochukwu) actually hold one cluster each. **Rebuilt by the secretary before
   the commit** from `cluster_lga_fixed.csv`: now 120 zeros, 1,380 clusters in total, all other columns
   byte-identical. This is the third file to carry a stale or mislabelled cluster count; the underlying
   `cluster_lga.csv` remains on disk as a trap, and `AGENTS.md` now says so.
3. No report file written; progress lines exist.

## Open risks

1. `Aridity_2020` correlates **−0.46** with severe food insecurity at LGA level. If the variable is an
   index where higher means wetter, that is expected. If higher means drier, the sign is backwards and the
   name has been misread. T15 is required to settle this from the DHS data-description PDF before any
   coefficient is interpreted.
2. The covariates are drawn from displaced cluster coordinates, so interpolation error here includes
   displacement error. The `rmse/sd` column already carries that.
3. Five covariates over 774 areas is comfortable statistically, but four of them are one agro-ecological
   gradient. The effective number of independent covariates is nearer two.

## Unproven

Whether any of this improves out-of-sample calibration — that is T15, and the honest expectation is a
modest improvement, not a rescue. Nothing here says the 120 unclustered LGAs are now well estimated; it says
they now have predictors at all.
