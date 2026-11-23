# ConferenceMaths — submission to the Journal of Mathematical Sciences (NMC Abuja)

**State file: `PLAN.md`.** Read it first — phases, status, checkpoints and the defect register live
there. This file holds the rules, verified facts and traps; `PLAN.md` holds where the work stands.

One manuscript, not a codebase. Target: **Journal of Mathematical Sciences**, National Mathematical
Centre Abuja, Vol. 8 Issue 1. Deadline **30 December 2026**, stated on the call-for-papers poster.
Open access, no publication fee. Submission is by email to the editor named on that poster; there is
no portal and no account to create.

## What is actually here

- `IMG-20261119-WA0007.jpg` — the call for papers. **This is the authoritative style guide**, and
  being an image nothing in it is greppable. Read it before formatting anything.
- `MathematicsApplied Paper.txt` — a critique of a proposed model, plus a revised plan and a
  six-stage agent workflow. **It is not the manuscript and contains no manuscript prose.**

There is no `.tex`, no data, no code, no bibliography, and **no git repository** — so there is no
undo. Copy a file before rewriting it. The original proposal that the critique attacks is also
absent; only the critique survived, so "revise the paper" has nothing to revise yet.

## Journal constraints (from the poster)

- LaTeX or Word, 12 pt, A4, English.
- Page 1 carries title, author names, affiliations, emails, abstract, subject classification and
  keywords. In a multi-author paper the corresponding author must be listed **first**.
- Abstract ≤ 250 words, single-spaced.
- Body order is fixed: Introduction, Methods, Results, Discussion, Conclusions, Declaration,
  References (APA 7th). Do not reorder, rename, or add sections at that level.
- Tables and figures numbered `Table 1`, `Figure 1`, and referenced in the text in that form.

## The finding that decides the model

Published Nigerian evidence puts global Moran's I for state food inflation at about 0.011 with
p ≈ 0.353: no national spatial synchrony, only isolated hotspots (Kebbi) and coldspots (Rivers).
A global CAR prior therefore smooths away exactly the heterogeneity this paper claims to find, and
a referee will say so in the first paragraph.

Any model built here is localised — BYM2 with a heavy-tailed outlier component, a mixture of CARs,
or spatially varying coefficients — and the paper must show a global CAR benchmark losing the Kebbi
shock while the localised model keeps it. Reverting to a global CAR prior is a regression, not a
simplification.

That Moran's I figure is secondhand, quoted in the `.txt` from a paper nobody here has opened.
Trace it to the real source and the real number before it enters the manuscript, and report the
number you found rather than the one you were handed.

## Working with `MathematicsApplied Paper.txt`

- Its mathematics is mangled by text extraction: symbols are duplicated and broken across lines
  (`u s u s`, `λ st λ st`). Never copy an equation out of it. Re-derive in LaTeX or from the cited
  source.
- Everything in it is one AI reviewer's assertion. Its novelty verdicts, its comparison table and
  its citations (Khan et al. 2026, Adam et al. 2025, the 2024 scale-mixture CAR paper, the 2025
  Springer chapter on heavy-tailed spatial effects) need independent confirmation, including that
  the claim attributed to each source is actually in it.
- Its six-stage workflow is the plan of record for the paper's structure. It is not an instruction
  to run those prompts verbatim.

## Non-negotiables for this paper

1. **Identifiability is a Methods subsection, not a caveat.** Sum-to-zero constraints on the spatial
   and time effects, plus an argument that the scale parameters are separable from the error
   variance. The standing objection is that the model may be reallocating variance between the
   scale parameters and the error rather than learning a heavy-tailed spatial shock.
2. **The policy quantity must be derived, not asserted.** Latent scale parameters are not a finding
   a central bank can act on. Ship a posterior tail probability and a conditional tail expectation
   at a stated inflation threshold, computed from the same MCMC draws without new likelihood
   evaluations.
3. **Say which novelty is claimed.** Novel application is not novel method; claim one and scope the
   other, because the prior itself is a recombination of existing scale-mixture and CAR work.
4. **Computational claims need evidence.** With 37 states over many months the latent scale
   parameters run into the thousands; mixing, convergence diagnostics and cost have to be shown,
   not assumed.
5. **No citation that has not been opened**, and no number without the script that produced it.

## Data source — settled, do not re-search

The only national state-level series is **Table 5, "Combined Urban And Rural State Consumer Price
Index"**, in NBS's monthly CPI workbook. It carries all 36 states plus Abuja, Food and All-Items
indices at t−12, t−1 and t, with month-on-month and year-on-year change — ten numbers per row.

- **Nov 2024 → Oct 2026**: Excel, one workbook per month, in the NBS microdata catalog (study
  `NGA-NBS-CPI`). Monthly ZIPs each contain both the xlsx and the PDF.
- **Before Nov 2024**: PDF only, but the text layer is clean and the state table is fully
  extractable. Verified on January 2024.
- **Rebasing break**: base changed from November 2009 to 2024 = 100 in January 2025. Pre-2025
  indices sit around 600–1100, post-2025 around 100–130. Levels never cross the break; growth
  rates only.

Four defects that will silently corrupt any panel built from this, all confirmed by reading the
files:

1. **NBS's own warning, printed under the table**: "Indices may not be used for inter-state price
   comparison because market baskets differ state to state." A cross-state model of index *levels*
   contradicts the source. Model growth rates and say why.
2. **Bauchi's Food at t−12 is Anambra's All-Items at t−12**, identical to every decimal, in the
   November 2024, June 2025 and October 2025 workbooks and in the January 2024 PDF. The error
   predates the rebasing and survives it. One of those two cells is wrong; do not use either
   without checking against the published report text.
3. **State spellings drift between months**: `Nassarawa` (June 2025) versus `Nasarawa` (October
   2025); the FCT is `Abuja`, never `FCT`. Eleven of the 37 rows are multi-word names.
4. **Workbooks carry leftover old-base tables** alongside the new ones, so the base year has to be
   read from the table heading, not assumed from the file date.

Five more, learned the hard way while building the panel (`data/panel/qc_flags.csv` carries these as
data):

5. **April 2025's workbook is corrupt at row level.** The chain test — file(t)'s previous-month column
   against file(t−1)'s current-month column — agrees 72–74 of 74 for every consecutive pair except
   2025-04→2025-05, which scores 13 of 72. The Benue and Borno rows carry each other's numbers. Trust
   the May file's lookback, not the April file.
6. **December 2024 gets duplicated** if you parse both the PDF and the xlsx, which is tempting because
   both exist. Key duplicates on (jurisdiction, month, series) only — a key that includes the source
   file passes while the table is double-weighted.
7. **PDFs print month-on-month before year-on-year; the workbooks print annual first.** A parser that
   assumes one order silently swaps the two change columns.
8. **The PDF parser is calibrated**: on December 2024 the PDF and xlsx agree to within 0.05, which is
   the PDF's one-decimal rounding. Use that as the standard when extending backwards.
9. **Pre-Nov-2024 months are one request each**, not a crawl: the e-library exposes
   `nigerianstat.gov.ng/download/<id>` for every report, and the saved listing
   (`data/raw/nbs/_elibrary_search_cpi.html`) already holds 1,695 ids including 152 CPI reports back
   past 2020. One month is legacy `.xls` — do not assume an `.xlsx` extension.

Rejected alternatives, so nobody spends a day on them again: the WFP food-price dataset on HDX has
91,216 rows but only Borno, Yobe and Adamawa since 2024 — 3 of 37 states; Kaggle copies are
national aggregates. Neither supports a spatial model.

**Panel status, 2026-11-22 — built, do not rebuild.** 5,992 rows, 81 of 82 months (2020-01 to
2026-10), 37 jurisdictions, no duplicate keys. Verified by the annual-change identity (index against
the same month a year earlier) on 3,918 cells: the only 72 failures are all in 2026-02, whose published
year-ago column is lagged. January 2025 was recovered from a lookback column. April 2025 is
quarantined in `data/panel/quarantined.csv`. 2022-08 is missing Cross River because the PDF breaks the
name across lines. `qa_panel.py` is still the old version — it does not apply the quarantine or print
the annual test.

## Direction from 2026-11-22 — NDHS 2024, food insecurity

The paper is a small-area estimation of **severe household food insecurity** from the NDHS 2024,
not the CPI panel. The CPI panel is retained only as a possible area-level covariate. Measured on
the microdata:

| | |
|---|---|
| national severe food insecurity | 31.3% (Rasch probability, the survey office's construct) |
| national, raw score 4 or more of 8 | 68.9% |
| national, raw score 6 or more of 8 | 56.5% |
| national, all 8 items affirmed | 29.0% |
| across the 37 states, all 8 affirmed | 4.6% (Niger) to 85.0% (Yobe), median 23.5% |
| across the 37 states, Rasch severe | 7.7% (Niger) to 65.6% (Yobe) |
| Moran's I, Rasch severe | 0.204, permutation p = 0.018 (9,999 draws, seed 20261028) |
| Moran's I, moderate-or-severe | −0.012, p = 0.427 |

**Two different constructs, and the difference matters.** `hfs_sev` is a Rasch probability that takes only
six distinct values, one per raw score; its mean (31.3%) is the survey office's severe prevalence, while
thresholding it at 0.5 selects only households affirming all eight items (29.0%). The FAO raw-score
cut-off of six or more gives 56.5%, which is not the same quantity. Item coding is verified correct: the
affirmation rate falls monotonically from 71% (worried about food) to 33.5% (did not eat for a whole day),
with no inversions.

The spatial structure sits in the severe tail, not in the broad measure, which is near its ceiling.
That is the empirical case for a heavy-tailed spatial model, and it is the paper's opening. The
Fay–Herriot attempt in the Curb Cut project failed all 26 candidate models on a pre-declared
normality diagnostic at 37 areas — do not repeat it at state level.

## Environment (pinned)

- R 4.5.2 at `C:\Program Files\R\R-4.5.2\bin\Rscript.exe`
- INLA 25.10.19, installed as a Windows binary (the source build is 26.08.07 and compiles for an hour)
- available: fmesher, inlabru, INLAspacetime, spdep, sf, igraph, renv
- packages warn they were built under R 4.5.3 — benign, they load and fit
- verified by fitting BYM2 on the real 37-state graph: 86 adjacencies, one component, 20 seconds

## Two traps in the DHS files

1. **`hfs_sev` and `hfs_mod` are probabilities scaled by 1e8.** Raw values reach 73,982,261. Divide by
   1e8. Read naively the national mean is 31 million percent.
2. **State codes are geopolitical-zone ordered, not alphabetical.** Read the labels from the file
   (`meta.variable_value_labels["shstate1"]`) rather than asserting a map: an alphabetical guess
   correlates −0.11 with the true estimates, while the resolved map reproduces the project's own
   disability aggregates at 0.9996.

## Novelty — settled by the literature, do not overclaim

Verified by DOI (OpenAlex, 2026-11-22). The method is **not** novel and the paper must not say it is:

- *Mapping food insecurity in the Brazilian Amazon using a spatial item factor analysis model*,
  Annals of Applied Statistics 2025, `10.1214/25-aoas2072` — already models food insecurity from
  household experience items spatially, and predicts where nobody was surveyed.
- *A Bayesian hierarchical model for disease mapping that accounts for scaling and heavy-tailed latent
  effects*, Statistical Methods in Medical Research 2024, `10.1177/09622802241293776` — already the
  heavy-tailed scale-mixture spatial model with outlier detection.
- *A Beta–Beta Prime Model for Rates and their Precision for Small Area Estimation: An Application to
  Brazilian Food Insecurity Index*, JSSAM 2025, `10.1093/jssam/smaf002` — food-insecurity small-area
  estimation is an active niche, and Brazil has two papers in it.
- *A spatial autoregressive random forest algorithm for small-area spatial prediction*, Annals of
  Applied Statistics 2025, `10.1214/24-aoas1969` — spatial ML for small-area prediction already exists,
  so it is the natural anchor for any ML comparison.

**The defensible claim is narrow: first state- and LGA-level small-area estimates of household food
insecurity for Nigeria, with threshold-exceedance probabilities a policymaker can act on.** That is
novelty by absence, and absence claims must be worded as such ("we found none"), never as "no one has".

The Moran's I of 0.011 in `MathematicsApplied Paper.txt` traces by content to a 2026 policy-journal
paper whose abstract does not contain the number. It is unverified and irrelevant now: we computed our
own from the microdata.

**Outcome definition resolved by evidence.** The "six or more of eight items means severe" rule has no
citable source. The Rasch/probability route is the sourced one. So severe food insecurity is
`hfs_sev >= 0.5`, which in this file is exactly the households affirming all eight items (29.0%). Both
descriptions are true; use whichever reads more clearly, and cite the survey office's construct.

## Theory annex — verified, and it constrains the paper

`.agent/T5-theory.md` holds four propositions with proofs and numeric checks. All four are **classical**,
correctly attributed (Manski–Lerman; Prentice–Pyke; Kish; Fay–Herriot; Rao–Molina; Prasad–Rao; Manski;
Manski–Pepper; Berger). Our contribution is the application, never the estimator.

Two results change how the paper must be framed:

1. **At state level, small-area estimation is very nearly a no-op.** Fay–Herriot on the 37 states gives
   σ̂²_u = 0.0313 and a shrinkage weight γ with median **0.9866**: the model moves the direct estimate by
   0.0026 on average, maximum 0.020. With ~1,000 households per state the direct estimates are already
   more precise than the between-state spread. **The value is at LGA level, where ψ is large.** A
   state-level-only paper invites exactly this objection, so do not write one.
2. **Nothing about any LGA is identified yet.** The person file has no LGA, ward or enumeration-area
   variable — geography stops at state, with `hv001` the cluster and `hv023` the 74 design strata. Every
   state is sampled, so the Manski identified set for a state's tail has zero width; every LGA is
   unobserved, so its set is the whole interval `[0,1]`. The bounds proposition becomes a theorem only
   once the coordinates arrive and clusters can be mapped into LGAs.

Also: the earlier `MSE = γψ + (1−γ)²σ²_u` was wrong — it equals `γψ(2−γ)` and overstates by up to 2×.
The correct result is `γψ` (plus `g₂` when `β` is estimated). And the Kish design-effect formula brackets
the truth here rather than matching it (6.63 unstratified, 2.73 within stratum, 4.935 actual): report it
as a benchmark, not an identity.

## Open

- Needs the user: `NGGE8AFL.ZIP` (cluster coordinates, 134 KB) — behind a DHS login, so it cannot be
  fetched from here. Blocks LGA-level work only; state-level modelling proceeds without it.
- **Data-use scope, decided 2026-11-22: the outcome is food insecurity.** The DHS registration is
  titled "Curb Cut: disability prevalence and poverty in Nigeria", so the project description must be
  amended on the DHS site (an edit to the existing project, not a new registration) before submission,
  and a PDF of the paper sent to references@dhsprogram.com. **No disability variable enters this paper
  at all** — not as outcome, not as covariate, not in the discussion. Do not re-litigate this framing.
