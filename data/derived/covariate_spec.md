# Analysis dataset and covariate specification (fixed 2026-11-22)

Pinned before any model is fitted. The builder must not add, drop or redefine a variable without
recording the change and its reason in `.agent/T3-report.md`.

Source: `data/restricted/dhs-2024/pr/NGPR8BFL.dta` (person recode). Collapse to one row per household
with `drop_duplicates("hhid")` after sorting, so the first person row of each household supplies the
household-level fields. Households: 40,047 rows collapse to 40,047 households; 39,877 have a
non-missing food-insecurity score and a positive weight.

## Outcome — severe food insecurity

Eight items `hfs1`–`hfs8` ("household worried about food…", through "…did not eat for a whole day").

1. Read the value labels from the file (`meta.variable_value_labels`) and confirm the coding. Do not
   assume 1 = yes.
2. Recode each item to `1` for "yes", `0` for "no". **Don't know and missing count as 0** (the standard
   FIES practice: an unaffirmed item is not an experience), and report how many cells that affects.
3. `fies_score` = sum of the eight recoded items, 0–8.
4. `severe_fi` = 1 if `fies_score >= 6`, else 0. This is the FAO classification: 0–3 food secure or
   mild, 4–5 moderate, 6–8 severe.
5. **Validation gate.** Correlate `fies_score` with the survey office's `hfs_sev / 1e8` across
   households. Expect r > 0.9. If it is lower, stop and report the item coding rather than proceeding.

Also carry `modsev_fi` = 1 if `fies_score >= 4` as a secondary outcome for sensitivity only. It is not
the primary.

## Covariates — eight, fixed

Standardise continuous variables over the analytic sample and report the raw range of each.

| Name | Source | Rule |
|---|---|---|
| `wealth_z` | `hv271` | Wealth factor score. If its range exceeds ±20 it is stored ×1e5 — divide by 1e5, then standardise to mean 0, sd 1. Report the raw range before and after. |
| `hh_size` | `hv009` | Number of household members, continuous. |
| `urban` | `hv025` | 1 if the household is urban, else 0. |
| `head_male` | `hv219` | 1 if the household head is male, else 0. |
| `head_age` | `hv220` | Years. Include `head_age` and `head_age²` (centred at 40) — a quadratic, not an interaction. |
| `head_edu` | member `hv106` where `hvidx == hv218` | Head's highest level attained: none (0), primary (1), secondary (2), higher (3). Enter as two dummies: `head_edu_secondary`, `head_edu_higher`, with none/primary as reference. If the head's line cannot be matched, use the head's `hv106` from the household row if present, else missing — and report the count. |
| `improved_water` | `hv201` | **Classify from the value labels, not from hard-coded codes.** Improved per JMP: piped into dwelling, piped to yard or plot, public tap or standpipe, tube well or borehole, protected well, protected spring, rainwater. Everything else, including surface water, unprotected well or spring, tanker, cart, bottled and "other", is 0. Print the full label → class table in the report so it can be audited. |
| `improved_sanitation` | `hv205` + `hv225` | Improved **and not shared**. Improved per JMP: flush to sewer, septic tank or pit; ventilated improved pit; pit with slab; composting toilet. Unimproved: flush to elsewhere, pit without slab or open pit, bucket, hanging toilet, no facility or open defecation. Then set to 0 if `hv225` says the facility is shared with other households. Print the label → class table. |

`head_edu` and the two WASH binaries are the only constructed variables; say in the report how many
households each construction could not resolve.

## Analytic sample

Complete cases on `severe_fi` and all eight covariates. Report:

- households in, households dropped, and the severe-FI prevalence in each group — so selective
  deletion is visible rather than assumed harmless.

## Outputs

`data/derived/analysis_households.csv`, one row per household, columns at minimum:
`hhid, hv001, geography (ISO), hv005, fies_score, severe_fi, modsev_fi, wealth_z, hh_size, urban,
head_male, head_age, head_age_c, head_edu_secondary, head_edu_higher, improved_water, improved_sanitation`

`data/derived/covariate_mapping.json`, holding:
the item coding check, the wealth rescaling, both WASH label → class tables, the head-education match
count, the missing-data counts, and the correlation between `fies_score` and `hfs_sev`.

## Prohibitions

- No disability variable, anywhere. Not as covariate, not as a sensitivity analysis.
- No covariate added after seeing a model result.
- No imputation, no winsorising, no dropping clusters.
- No survey weights in the dataset build beyond carrying `hv005` through for reporting; weighting is
  a modelling decision that the report must state plainly.
