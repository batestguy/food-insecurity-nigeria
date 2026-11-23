# T9 — report, written by the secretary

The builder hit its step cap after producing every deliverable but before writing this file or finishing
one script edit. I re-ran the script and verified the outputs myself; everything below is from that run.

## Changed

- `scripts/lga_dataset.R` — new; the whole build in one command
- `data/derived/cluster_lga_fixed.csv` — 1,380 rows, 15 clusters reassigned to their survey state's nearest LGA
- `data/derived/lga_population.csv` — 774 LGAs, 773 with a figure (Bakassi absent from the source)
- `data/derived/analysis_households_lga.csv` — 39,877 × 157, zero null `lga_id`, zero null `lga_population`
- `data/derived/lga_dataset_qc.json` — counts, both shares, covariate missingness, sources and hashes
- `data/derived/raw_pop/nga_admpop_2020.xlsx` — COD-PS (NBS/UNFPA), reference year 2020
- `.agent/T9-nametest.py` — scratch, deleted

## Verified

`Rscript scripts/lga_dataset.R` → "assertions: 15 of 15 passed", "QC passed".

- Population join 773 of 774 (743 exact, 28 fuzzy at Jaro–Winkler ≤ 0.19, 2 sole-remaining); unmatched
  Bakassi (NG-CR), which DHS's own boundary documentation describes as uninhabited.
- **LGA populations sum to 204,909,220, exactly the workbook's state-level total, difference 0.** This is
  the check that would catch a scrambled name join; it passes.
- Independent re-derivation from the written files (my own code, not the builder's): 774 LGAs, 773 with
  population, 120 zero-cluster LGAs, population share in those 0.1104, households 39,877 with no nulls,
  654 LGAs holding households, national weighted prevalence 0.2910.

| | before correction | after |
|---|---|---|
| LGAs with no cluster | 123 | **120 (15.5%)** |
| population in those LGAs | 11.58% | **11.04%** |
| count-based `p` | 0.8450 | **0.8450** |
| population-based `p` | — | **0.8896** |

## The finding that matters

**Unclustered LGAs are systematically smaller.** 15.5% of LGAs hold no cluster, but only 11.0% of people
live in them, so the identified-set width is about eleven percent of the population, not sixteen percent
of places. The paper must state the population version, because the width is a statement about people.

Four LGAs gained their first cluster under the correction (Ahoada West, Apa, Arochukwu, Dambatta) and one
lost its only one (Ihitte/Uboma), which is why 123 becomes 120 and not 122.

## Deviations

The builder's first run wrote a QC file without the Bakassi/national-total fields; the second run added
them. The numbers are identical between runs, so the build is deterministic on these inputs.

## Unproven

- Whether the nearest-LGA-within-state rule picks the LGA DHS itself would. Our polygons are
  geoBoundaries; DHS's are not published.
- The denominators are 2020 projections from the 2006 census — no LGA-level 2024 figure exists on HDX.
- Cluster geospatial covariates are attached but unselected; the modelling ticket must choose them by a
  declared rule, not by fit.
