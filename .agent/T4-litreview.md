# T4 — what is already published on spatial small-area estimation of food insecurity, and where is the gap

Scope: positioned at the paper described in `.agent/T4-brief.md` — unit-level binary small-area
estimation of household food insecurity (eight FIES items, NDHS 2024), BYM2 spatial field on
Nigeria's 37-jurisdiction graph, INLA, optional heavy-tailed area effect, state-level credible
intervals and threshold exceedance, benchmarked against gradient-boosted trees.

Method note. Search channels used: OpenAlex works API (search + DOI lookups, abstracts parsed from
the inverted index), Crossref (abstract fallback), and the local file `MathematicsApplied Paper.txt`
only to identify what the 0.011 Moran's I claim refers to. No paywalled full text was opened. Every
"read" entry below was read at abstract level; that is stated rather than glossed. 51 HTTP requests
used of the 60 allowed.

Markers: **read** = abstract opened and quoted. **seen** = title/metadata only, cannot support a
gap claim.

---

## Block A — core references

### A1. The closest competitor: spatial latent food insecurity, already published
**Chacón-Montalván EA, Parry L, Giorgi E, Torres PC (2025).** Mapping food insecurity in the
Brazilian Amazon using a spatial item factor analysis model. *The Annals of Applied Statistics*.
DOI `10.1214/25-aoas2072`. **read.**
> "we propose a spatial item factor analysis model that captures spatial dependence, allowing us to
> predict latent factors at unsampled locations and identify food insecurity hotspots"

What it did: item factor analysis (the latent-variable cousin of Rasch) with a spatial random field
on the latent factor, Bayesian inference, applied to household food-insecurity perceptions in one
Amazonian municipality (Ipixuna); predicts the latent factor at unsampled locations and maps
hotspots. Software: R package `spifa`.
Why it matters here: this is the paper that occupies the space "spatial statistical model of
FIES-type food insecurity with prediction where nobody was sampled". Any claim that a spatial latent
treatment of food insecurity is new is false.

### A2. The methods frame a referee will judge us by
**Wakefield JC, Gao PA, Fuglstad G-A, Li ZR (2026).** The Two Cultures of Prevalence Mapping: Small
Area Estimation and Model-Based Geostatistics. *Statistical Science*. DOI `10.1214/25-sts990`.
**read.**
> "Unit-level models for binary responses are relatively underdeveloped."

What it did: reviews area-level and unit-level SAE against model-based geostatistics for binary
indicators from complex household surveys in low- and middle-income countries; flags that
design-ignorability and aggregation of unit predictions to areas are the two delicate issues;
illustrates with Zambia 2018 DHS HIV prevalence.
Why it matters here: it is both the justification for our unit-level binary model (that class is
described as underdeveloped in the survey-statistics literature) and the source of the sharpest
criticism we will face (design ignorability, i.e. survey weights).

### A3. Heavy-tailed BYM2 is a published method, in 2024, exactly as described
**Michal V, Schmidt AM, Freitas LP, Cruz OG (2024).** A Bayesian hierarchical model for disease
mapping that accounts for scaling and heavy-tailed latent effects. *Statistical Methods in Medical
Research*. DOI `10.1177/09622802241293776`. **read.**
> "We build on the BYM2 model to allow for heavy-tailed latent effects and accommodate potentially
> outlying risks, after accounting for the fixed effects."

What it did: a scale-mixture extension of BYM2 in which the variance of the latent process varies by
area, giving outlier identification and two prior specifications for the scale-mixture parameter;
simulation comparison plus Zika cases in Rio de Janeiro, 2015–2016.
Why it matters here: this settles the question in the brief's item 4. Heavy-tailed BYM2 is not novel.
It is the thing we would be re-implementing, and it is citable as our method's ancestor.

### A4. Scale-mixture CAR for spatial heteroscedasticity and outliers, older
**Congdon P (2016).** Representing spatial dependence and spatial discontinuity in ecological
epidemiology: a scale mixture approach. *Stochastic Environmental Research and Risk Assessment*.
DOI `10.1007/s00477-016-1292-9`. **read.**
> "A spatial prior representing spatial heteroscedasticity within a model accommodating both spatial
> and non-spatial variation is therefore proposed."

What it did: a CAR prior with area-varying scale intended to stop outliers distorting smoothing,
applied to TB incidence in 326 English local authorities plus a US-states simulation.
Why it matters here: the "global CAR smooths the one shock we care about" argument was made in the
spatial epidemiology literature a decade before the Nigerian inflation critique made it.

### A5. Structured smoothing versus heavy tails, decided by held-out prediction
**Bhadra D, Polson N (2026).** Horseshoe Priors for Spatial Small Area Estimation: Regular
Variation, Tail Robustness, and Deep Learning. arXiv preprint. DOI `10.48550/arxiv.2606.30659`.
**read — preprint, not peer reviewed.**
> "on strongly spatial data the smoother predicts held-out districts best, yet the horseshoe flags
> exceptional districts that smoothing suppresses"

What it did: area-level Fay–Herriot with a horseshoe (heavy-tailed global–local) prior on area
effects; tail-robustness and contraction theory; comparison against structured smoothing on Scottish
lip-cancer data and simulations.
Why it matters here: it is the paper that tells us the honest expected result. If the data are
strongly spatial, plain smoothing wins on held-out prediction and the heavy tail only wins on
flagging exceptions. Our claim has to be phrased in those terms or a referee will phrase it for us.

### A6. Fay–Herriot for food insecurity, area level
**Shiferaw YA (2020).** Model-based estimation of small area food insecurity measures in Ethiopia
using the Fay-Herriot EBLUP estimator. *Statistical Journal of the IAOS*. DOI `10.3233/sji-200673`.
**read.**
> "The results show the zonal level household food insecurity estimates generated by SAE were more
> efficient and precise compared to the survey-based estimates."

What it did: linked the 2015/16 welfare monitoring survey to the 2007 census, produced zone-level
household food insecurity estimates for Ethiopia by EBLUP; no spatial random effect.
Why it matters here: our own Fay–Herriot failure is not a novel finding about Fay–Herriot; it is a
known limitation of the area-level route when areas are few.

### A7. SAE of food insecurity at district level, unit-level covariates
**Pyne S, Guha S, Das S, Ray S (2023).** Food insecurity in the Eastern Indo-Gangetic plain: Taking
a closer look. *PLoS ONE*. DOI `10.1371/journal.pone.0279414`. **read.**
> "Our Small Area Estimation approach estimated food insecurity prevalence, gap, and severity of each
> rural district of the Eastern Indo-Gangetic Plain (EIGP) region by modeling the HCES data, guided
> by local covariates from the 2011 Indian Population Census."

What it did: district-level prevalence, gap and severity for three Indian states from the 2011–12
consumer expenditure survey with census covariates.
Why it matters here: food insecurity SAE with three distinct target parameters is already routine;
prevalence alone is the least ambitious of them.

### A8. The precision of the small-area estimate modelled too
**Moura FAS, Pereira S, Silva GL (2025).** A Beta–Beta Prime Model for Rates and their Precision for
Small Area Estimation: An Application to Brazilian Food Insecurity Index. *Journal of Survey
Statistics and Methodology*. DOI `10.1093/jssam/smaf002`. **read.**
> "Here, we propose to model the direct estimator of the rates or proportions in small area domains as
> being beta distributed."

What it did: area-level model in which both the rate and its estimated sampling variance are
modelled (beta and beta-prime), applied to a Brazilian food insecurity index.
Why it matters here: this is the current frontier of food-insecurity SAE — treating the design-based
uncertainty as data. We will be asked why we did not.

### A9. SAE of moderate and severe food insecurity, national statistics office route
**FAO (2024).** Estimation of the prevalence of moderate and severe food insecurity in Chilean
municipalities using small area estimation methods. *FAO eBooks*. DOI `10.4060/cd1350en`.
**seen** — no abstract available from OpenAlex or Crossref, so nothing may be claimed from it beyond
title, year and venue. It is listed because its existence shows FAO itself has commissioned
municipality-level SAE of the same indicator.

### A10. Machine learning inside SAE, with a proper comparison protocol
**Krennmair P, Würz N, Schmid T, Tzavidis N (2026).** Random forests and mixed effects random forests
for small area estimation of general parameters: A poverty mapping case study in Mozambique. *The
Annals of Applied Statistics*. DOI `10.1214/25-aoas2126`. **read.**
> "Estimates are further contrasted to 2023 World Bank estimates and to design-unbiased direct
> estimates."

What it did: mixed-effects random forests with area random effects, smearing estimator for the
area-specific distribution function, nonparametric block bootstrap for MSE; district head-count ratio
and poverty gap for Mozambique; compared against the linear mixed-model EBP and a synthetic random
forest, and against World Bank and direct estimates.
Why it matters here: this is the template for the benchmark section, including the evaluation
protocol we would otherwise have to invent.

### A11. The same comparison for a binary outcome
**Frink N, Schmid T, Würz N (2026).** Small area estimation with generalized random forests:
estimating poverty rates in Mexico. *Journal of the Royal Statistical Society Series A*.
DOI `10.1093/jrsssa/qnag092`. **read.**
> "We present the generalized mixed effects random forest, a robust and flexible framework for
> estimating area-level indicators under generalized modelling assumptions within the small area
> estimation context."

What it did: generalised mixed-effects random forest for exponential-family responses, binary poverty
indicators in Mexico, parametric-bootstrap MSE, and an examination of information loss from
dichotomising a continuous variable.
Why it matters here: somebody has already done "ML versus model-based SAE for a binary poverty
indicator". Our benchmark is a replication in a new domain, not a contribution.

### A12. Random forest fused with a CAR/SAR prior
**MacBride C, Davies V, Lee D (2025).** A spatial autoregressive random forest algorithm for
small-area spatial prediction. *The Annals of Applied Statistics*. DOI `10.1214/24-aoas1969`.
**read.**
> "In this paper we propose SPAR-Forest, a novel spatial prediction algorithm that fuses random
> forests with spatial smoothing models."

What it did: iteratively refits a random forest and a Bayesian CAR/SAR model so that nonlinear
feature–target structure and residual spatial autocorrelation are both represented; Scottish property
prices plus simulations.
Why it matters here: "the ML competitor ignores spatial autocorrelation" is no longer a safe straw
man. A referee who knows this paper will ask why our comparator is plain gradient boosting.

### A13. What "validation" means in official SAE
**Tzavidis N, Zhang L-C, Luna Hernandez A, Schmid T (2018).** From Start to Finish: A Framework for
the Production of Small Area Official Statistics. *Journal of the Royal Statistical Society Series A*.
DOI `10.1111/rssa.12364`. **read.**
> "We propose a general framework for the production of small area statistics that is governed by the
> principle of parsimony and is based on three broadly defined stages, namely specification, analysis
> and adaptation, and evaluation."

What it did: set out the specification–analysis–evaluation cycle, with emphasis on uncertainty
measures and model- and design-based simulation for method evaluation.
Why it matters here: it is the check-list a statistical referee will apply, and it asks for
evaluation by simulation, not only by comparison to direct estimates.

### A14. FIES measurement validity in sub-Saharan Africa, including the item we lean on
**Wambogo EA, Ghattas H, Leonard KL, Sahyoun NR (2018).** Validity of the Food Insecurity Experience
Scale for Use in Sub-Saharan Africa and Characteristics of Food-Insecure Individuals. *Current
Developments in Nutrition*. DOI `10.1093/cdn/nzy062`. **read.**
> "However, 34.3% of countries had high outfits (≥2.0) for the item 'went without eating for a whole
> day.'"

What it did: Rasch analysis of 2014–2015 Gallup World Poll data for 57,792 adults in sub-Saharan
Africa; severe-food-insecurity prevalence by country; item-fit diagnostics.
Why it matters here: the most severe item — the one that drives the difference between the Rasch
measure and the raw-score cut-off — is the item that misfits in a third of African countries. A
referee who knows FIES psychometrics will ask about exactly this.

### A15. The Rasch reference-scale machinery behind "comparable" prevalence
**Nord M, Cafiero C, Viviani S (2016).** Methods for estimating comparable prevalence rates of food
insecurity experienced by adults in 147 countries and areas. *Journal of Physics: Conference Series*.
DOI `10.1088/1742-6596/772/1/012060`. **read.**
> "A Rasch-model-based scale was estimated for each country, and data were assessed for consistency
> with model assumptions."

What it did: the FAO Voices of the Hungry method — country Rasch scales adjusted to a global
reference standard so that "moderate or severe" means the same severity everywhere.
Why it matters here: it is the citation for why the outcome is a Rasch probability rather than a raw
count, and it makes the raw-score cut-off a deliberate deviation that must be defended.

---

## Also read, used in Block B and D

- **Mikailu F, Dakyen YJ, Enebeli UU, Cherima YJ, Hassan R (2026).** Spatial Dynamics, Convergence,
  and Persistence of Inflation in Post-Rebasing Nigeria: Evidence from State-Level CPI Indices
  (2024–2025). *Hensard Journal of Policy Economics and Development*. DOI `10.65757/hjpedv1n15`.
  **read (abstract only).** > "Results reveal weak global spatial autocorrelation but the presence of
  localized inflation hot-spots and cold-spots, particularly in northern states (e.g., Kebbi, Sokoto,
  Zamfara) and Rivers State."
  This is, by content, the source of the "global Moran's I ≈ 0.011, p ≈ 0.353, Kebbi hotspot, Rivers
  coldspot" claim quoted at line 59 of `MathematicsApplied Paper.txt`. **The number itself does not
  appear in the abstract and I could not verify it.** The journal is not indexed in the usual places
  and is not a statistics outlet; treat the number as unverified until the full text is read.
- **Ibrahim A, Raji M, Adaji I, Sule B (2026).** Bivariate Spatial Modeling of Malnutrition among
  Under Five Children in Nigeria. *FUDMA Journal of Sciences*. DOI `10.33003/fjs-2026-1014-5679`.
  **read.** > "All models were estimated within the Integrated Nested Laplace Approximation (INLA)
  techniques." Uses the **2024 NDHS** with cluster random effects and spatial dependence. So
  "first INLA spatial analysis of NDHS 2024 for Nigeria" is already taken, for malnutrition.
- **Otekunrin OA, Mukaila R, Otekunrin OA (2023).** Investigating and Quantifying Food Insecurity in
  Nigeria: A Systematic Review. *Agriculture*. DOI `10.3390/agriculture13101873`. **read.** Of 79
  Nigerian studies reviewed, 18 used HFIAS, 13 calorie requirement, 12 HFSSM, 10 expenditure-based
  index, 7 FIES (quoted in Block D). Prevalence ranged 12%–100% by instrument.
- **Adeyemi KD, Adeyemi B, Ibiyemi T, Park O-H, Korir JK (2026).** Urban Food Insecurity in Nigeria: A
  Multilevel Analysis of Nationally Representative Data. *Research Square preprint*.
  DOI `10.21203/rs.3.rs-8041739/v1`. **read, preprint.** > "Food insecurity was assessed via the Food
  Insecurity Experience Scale (FIES), with item responses analyzed using the Rasch model to ensure
  valid measurement of the latent food insecurity construct." Nigeria, FIES, Rasch, multilevel
  logistic — but no spatial random effect and no SAE. Nearest Nigerian competitor.
- **Egenti S, Dinbabo MF (2025).** Gendered Spatial Vulnerability to Food Insecurity in Nigeria.
  *African Journal of Governance and Development* 14(1). DOI `10.36369/2616-9045/2025/v14i1.2a8`.
  **read — grey-adjacent, low-visibility journal.** > "The analysis covered 4,401 households, with
  descriptive statistics complemented by Moran's I to test for spatial autocorrelation." A
  PCA-built vulnerability index from the 2018/19 GHS with a Moran's I test: a composite index, not a
  prevalence estimate, and not model-based SAE.
- **Das S, Chambers R (2024).** Small Area Poverty Estimation Under Heteroskedasticity. *JSSAM*.
  DOI `10.1093/jssam/smad045`. **read.** Unit-level heteroskedasticity, bootstrap MSE, benchmarked
  against World Bank poverty mapping on Bangladesh data.

---

## Block B — gap table

| Candidate contribution | Does it already exist? | Nearest paper | Verdict |
|---|---|---|---|
| Small-area estimation of food insecurity at subnational level | Yes, repeatedly: Ethiopia (zones), India (districts), Brazil (municipalities/Amazon), Chile (municipalities) | A6 Shiferaw 2020; A7 Pyne 2023; A9 FAO 2024 (seen); A8 Moura 2025 | **already done** as a genre |
| Spatial (CAR/BYM2) latent model of FIES-type food insecurity with prediction where unsampled | Yes | A1 Chacón-Montalván 2025 | **already done**, at municipality scale, continuous spatial field |
| Unit-level binary model with BYM2 on a national state adjacency graph from DHS microdata, INLA | Yes as a Nigerian workhorse — for malnutrition, vaccination, mortality | A2 Wakefield 2026 for the class; Ibrahim 2026 (NDHS 2024, INLA) | **already done** as method; **not found** for food insecurity in Nigeria → application gap only |
| Heavy-tailed / scale-mixture area effect inside BYM2 | Yes, published as a method in 2024 | A3 Michal 2024; A4 Congdon 2016; A5 Bhadra & Polson 2026 (preprint) | **already done** — claiming this as the method novelty would be a factual error |
| Bayesian tail probability / exceedance probability against a policy threshold at state level for food insecurity | **Not found** | nearest in kind: disease-mapping exceedance practice (not opened here); A5's "flags exceptional districts" | **candidate novelty** — but "not found" ≠ "does not exist"; my queries were food-insecurity-specific |
| ML vs model-based SAE benchmark under spatial cross-validation | Comparison exists, including for binary poverty outcomes; **spatial** CV specifically: not found in what I read | A10 Krennmair 2026; A11 Frink 2026; A12 MacBride 2025 | **incremental**; a diagnostic, not a headline |
| Linking the food-insecurity surface to state food-price dynamics | Spatial CPI work exists but no joint model found | Mikailu 2026 (Moran/LISA, spatial regression on CPI) | **unclear / weak** — descriptive if attempted; and rests on an unverified Moran's I |
| Nigeria-specific application with a policy-facing threshold | Not found | Adeyemi 2026 (national/regional only, no SAE) | **novel application**, which is the weakest defensible kind |

---

## Block C — does this paper's idea already exist?

Partly, and the part that exists is the part we were most likely to call novel. A spatial latent
model of FIES-type food insecurity that predicts into unsampled places is published (A1), and a
heavy-tailed BYM2 latent effect is published as a method (A3); what is not published, in anything I
could open, is a unit-level binary FIES model for Nigeria at state level that reports calibrated
threshold-exceedance probabilities — and the honest support for that gap is the absence of the
paper, from four different query formulations, not a positive finding. The defensible claim is
therefore "first for Nigeria, with a policy-decision layer", not "new method".

---

## Block D — what a referee will demand that we have not yet done

1. **Head-to-head against plain BYM2 on held-out prediction.** A5 says the smoothing model wins on
   strongly spatial data while the heavy tail only flags exceptions. We must show, on a held-out
   split or by LOO/WAIC, what the heavy tail buys — otherwise "it detects Kebbi" is a picture, not a
   result.
2. **Survey design.** A2 makes design ignorability an explicit criticism of unit-level Bayesian
   prevalence mapping. Fitting unweighted with a disclosed limitation may not survive; a
   post-stratified or weighted variant, or a demonstration that the ranking is unchanged, will be
   asked for.
3. **Benchmark against something official, not only against direct estimates.** A10 contrasts to
   World Bank estimates *and* direct estimates; A13 wants model- and design-based simulation. Our
   comparison rule (interval containment + interval width) is weaker than either.
4. **A proper uncertainty evaluation.** A10 and A11 both bootstrap the MSE. Coverage of the interval,
   not width alone, is the conventional criterion.
5. **Measurement diagnostics before modelling.** A14: the "whole day" item misfits in a third of
   African countries; A15: comparability is defined through a Rasch reference scale. Any raw-score
   cut-off must be justified, and Otekunrin et al.'s (2023) range of 12%–100% across instruments
   shows how much the choice moves the answer. Quote from Otekunrin 2023: > "The prevalence of FI varied from 12% to
   100%, based on the instrument and demography being studied."
6. **A calibrated exceedance probability.** If we sell threshold probabilities, someone will check
   their frequentist calibration or ask for a decision-theoretic loss; A5's language ("flags
   exceptional districts") is the standard we will be measured against.
7. **The comparator must be a strong one.** A12 fuses random forests with a CAR prior, so plain
   gradient boosting under spatial CV invites the comment that we chose a straw man.

---

## Block E — the three papers to position against

1. **A1 Chacón-Montalván et al. 2025 (AoAS, `10.1214/25-aoas2072`).** The nearest neighbour and the
   one that can sink a novelty claim. We must state in the introduction what it did (one municipality,
   latent-factor, continuous spatial field, hotspot prediction) and exactly what ours adds
   (national state graph, unit-level binomial with design-aware framing, policy exceedance, ML
   benchmark). Differentiating on scale alone is thin; differentiating on the decision layer is not.
2. **A2 Wakefield et al. 2026 (Statistical Science, `10.1214/25-sts990`).** It supplies both our
   justification ("unit-level models for binary responses are relatively underdeveloped") and the
   referee's objections (design, aggregation). Positioning against it means adopting its vocabulary:
   we are doing unit-level binary SAE with a spatial prior from a complex survey, and we say so.
3. **A3 Michal et al. 2024 (SMMR, `10.1177/09622802241293776`).** The method's owner. Citing it and
   modelling our scale-mixture component on it converts a possible "you reinvented this" into "we
   apply a published heavy-tailed BYM2 to a new outcome, and here is what changes". Ignoring it is the
   single most likely way for this submission to be rejected by a statistical referee.

---

## What I searched for and did not find (recorded as absence, with the query)

All via the OpenAlex works endpoint, `search=` parameter, 2026-11-22.

- `food insecurity experience scale small area estimation prevalence mapping` — 4,443 hits, no paper
  combining FIES with SAE in Nigeria.
- `food insecurity experience scale Nigeria prevalence spatial analysis` — 5,837 hits, no spatial SAE;
  nearest are a World Bank working paper on whether FIES should displace other measures, a Research
  Square preprint on urban Nigeria (Adeyemi 2026), and multi-country forecastability work.
- `exceedance probability policy threshold Bayesian small area estimates decision` — 33,601 hits, none
  on food insecurity; the returns were generic Bayesian decision theory.
- `spatial small area estimation food insecurity Bayesian` — 2,564 hits; the food-insecurity subset is
  A1, A3-adjacent, A6, A7, A9, A8.
- `moderate severe food insecurity threshold FIES cutoff debate comparability` — **7 hits, none
  relevant.** This is the query that failed. The specific numeric rule ("six or more of eight items
  = severe") could not be sourced to a quotable abstract; Cafiero et al. 2017
  (`10.1016/j.measurement.2017.10.065`) and Saint Ville et al. 2019 (`10.1007/s12571-019-00936-9`)
  both return **no abstract** from OpenAlex and Crossref, so both remain **seen**, not read, and
  neither may support a claim.
- FAO's Chilean municipality study (`10.4060/cd1350en`) has no abstract anywhere I could reach:
  **seen** only.
