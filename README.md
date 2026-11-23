# Food insecurity in Nigeria — small-area estimation at LGA level

Bayesian small-area estimates of **severe household food insecurity** for Nigeria's 774 Local Government
Areas, from the 2024 Nigeria Demographic and Health Survey, fitted in R-INLA.

The question the project exists to answer is not "what is the national rate" but **how many LGAs are above
a crisis line, and how sure can we be of that count** — a question that needs the *joint* posterior and
that a method reporting only per-area estimates cannot answer.

## Headline results

At a threshold of 50% of households severely food insecure (`hfs_sev ≥ 0.5`, all eight food-insecurity
items affirmed):

| | |
|---|---|
| National weighted prevalence | 29.1% |
| State range | 4.6% (Niger) to 85.0% (Yobe) |
| **LGAs above the line** | **115 of 774** (14.9%) |
| 95% credible interval for that count | 101 to 130 |
| Posterior sd of the count | 7.38 |
| Variance if LGAs were treated as independent | 40.26 (sd 6.34) |
| **Pairwise (spatial) variance term** | **14.25** (ratio 0.354 to the independent term) |

**A method reporting only marginals would put the standard deviation at 6.34 instead of 7.38 — about 14%
too small.** The same model refitted with an exchangeable rather than spatial area effect gives a pairwise
ratio of 0.187, so roughly half of the pairwise term is shared uncertainty in the regression coefficients
and half is geography.

Of the 774 LGAs, 32 are above the line with probability above 0.95 and 509 below with the same confidence;
**40 lie between 0.40 and 0.60**, the places the survey does not decide.

## Method

Household-level binomial model,

```
logit Pr(severe food insecurity_i) = x_i'β + f(lga_i) + f(cluster_i)
```

with `f(lga)` a BYM2 field on a queen-contiguity graph over the 774 LGAs (774 nodes, 2,230 edges, one
connected component) and `f(cluster)` an IID effect for the 1,380 survey clusters. Ten design columns from
eight household covariates. Fitted with INLA; 20,000 posterior draws.

The count functional and its variance decomposition:

```
Var(C) = Σ_s P_s(1 − P_s)  +  Σ_{s≠t} (P_st − P_s P_t)
```

with all three matrices evaluated under the same draws, so the identity is exact (residual −2.7 × 10⁻³,
floating point). `.agent/T5-theory.md` states the four supporting propositions and their assumptions; all
four are classical and are attributed, not claimed.

## What is not in this repository

**The DHS microdata is not here and cannot be.** The data-use agreement permits neither redistribution nor
use outside the registered project. Access is free from [the DHS Program](https://dhsprogram.com/) after
registration; the files needed are the NDHS 2024 household and person recodes plus the geographic data and
geospatial covariates.

Household-level derived tables are excluded for the same reason. What is published is code and area-level
results.

## Reproducing

R 4.5.2 with R-INLA 25.10.19, `sf`, `spdep`; Python 3.14 with `pyreadstat`, `pandas`, `numpy`.

```
Rscript scripts/lga_assign.R       # clusters to LGAs
Rscript scripts/lga_dataset.R      # population denominators, household merge
Rscript scripts/lga_model.R        # the fit and the count functional (~30 min)
```

`scripts/lga_model.R` needs the licensed microdata in place; nothing else does.

## Data and licences

| Input | Source | Licence |
|---|---|---|
| NDHS 2024 microdata | DHS Program | DHS data-use agreement; not redistributed here |
| LGA and state boundaries | geoBoundaries | CC BY 4.0 |
| LGA population | COD-PS (NBS/UNFPA), 2020 projections | CC BY-IGO |

Population figures are 2020 projections from the 2006 census; no LGA-level 2024 figure exists on HDX.

## Status

Work in progress. No manuscript has been submitted. The estimates have not yet been calibrated by spatial
cross-validation, and the survey design is not in the likelihood — the unweighted national rate is 0.2774
against a weighted 0.2910.

`PLAN.md` carries the phase-by-phase state, the defect register and what remains unproven.
