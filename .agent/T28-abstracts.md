# T28 — the two abstracts, verbatim

Fetched 2026-11-23. Both DOIs resolved. Both Crossref `abstract` fields were populated, so the
OpenAlex and Semantic Scholar fallback routes were not needed. OpenAlex was used only as a
completeness check, not as the source of the text.

No full text was fetched. The text below is the publisher's deposited abstract, with the JATS
`<jats:p>` wrapper removed and nothing else changed — no rewording, no shortening, no punctuation
tidying. Curly apostrophes and the hyphen in `(2015-2016)` are as they appear in the API.

---

## Paper 1

- **DOI**: `10.1177/09622802241293776`
- **title**: A Bayesian hierarchical model for disease mapping that accounts for scaling and heavy-tailed latent effects
- **venue**: Statistical Methods in Medical Research, vol. 34, pp. 307–321
- **year**: 2024 (Crossref `issued` 2024-12-10)
- **route**: Crossref `https://api.crossref.org/works/<DOI>` → `message.abstract`, HTTP 200. JATS markup stripped.
- **abstract_complete**: true

Completeness check: OpenAlex `abstract_inverted_index` reconstructs to 260 words with an identical
opening clause ("In disease mapping, the relative risk of a disease is commonly estimated across
different areas…") and an identical closing clause ("…identify potential issues in the recording of
cases."). Same terminal sentence in both routes, so the Crossref field is not truncated.

### abstract_verbatim

> In disease mapping, the relative risk of a disease is commonly estimated across different areas within a region of interest. The number of cases in an area is often assumed to follow a Poisson distribution whose mean is decomposed as the product between an offset and the logarithm of the disease’s relative risk. The log risk may be written as the sum of fixed effects and latent random effects. A modified Besag-York-Mollié (BYM2) model decomposes each latent effect into a weighted sum of independent and spatial effects. We build on the BYM2 model to allow for heavy-tailed latent effects and accommodate potentially outlying risks, after accounting for the fixed effects. We assume a scale mixture structure wherein the variance of the latent process changes across areas and allows for outlier identification. We propose two prior specifications for this scale mixture parameter. These are compared through various simulation studies and in the analysis of Zika cases from the first (2015-2016) epidemic in Rio de Janeiro city, Brazil. The simulation studies show that the proposed model always performs at least as well as an alternative available in the literature, and often better, both in terms of widely applicable information criterion, mean squared error and of outlier identification. In particular, the proposed parametrisations are more efficient, in terms of outlier detection, when outliers are neighbours. Our analysis of Zika cases finds 23 out of 160 districts of Rio as potential outliers, after accounting for the socio-development index. Our proposed model may help prioritise interventions and identify potential issues in the recording of cases.

### What this abstract supports

**Narrowest supported claim.** They build on the BYM2 model by giving the latent effects a scale-mixture
structure whose variance changes across areas, propose two prior specifications for that scale-mixture
parameter, compare them in simulation studies and in an analysis of Zika cases in Rio de Janeiro, and
report 23 of 160 districts as potential outliers after accounting for a socio-development index.

**Also supported, if needed.** The comparison is against "an alternative available in the literature"
and is scored on WAIC, mean squared error and outlier identification; the proposed parametrisations are
reported as more efficient at outlier detection when outliers are neighbours.

**NOT supported.** It does not support any statement that this model was applied to food insecurity,
poverty, or any non-health outcome; the only application named is Zika. It does not support a claim that
the method reports exceedance or threshold probabilities, or interval coverage — the abstract names only
WAIC, MSE and outlier identification, and says nothing about calibration or credible-interval performance.
It also does not support the phrase "scaling" as a claim about survey design or rate precision; "scaling"
here refers to the scale-mixture variance, not to small-area rate scaling.

---

## Paper 2

- **DOI**: `10.1214/24-aoas1969`
- **title**: A spatial autoregressive random forest algorithm for small-area spatial prediction
- **venue**: The Annals of Applied Statistics, vol. 19, pp. 485–504
- **year**: 2025 (Crossref `issued` 2025-03-01)
- **route**: Crossref `https://api.crossref.org/works/<DOI>` → `message.abstract`, HTTP 200. JATS markup stripped.
- **abstract_complete**: true

Completeness check: OpenAlex `abstract_inverted_index` reconstructs to 184 words with an identical
opening clause ("In spatial areal unit data with missing or suppressed values…") and an identical
closing clause ("…a state-of-the-art framework for small-area spatial prediction."). Not truncated.

### abstract_verbatim

> In spatial areal unit data with missing or suppressed values, it is desirable to create models that are able to predict observations that are not available. Typically, statistical spatial smoothing models fitted in a Bayesian hierarchical framework are used for this purpose, which capture any unexplained residual spatial autocorrelation in the data through conditional autoregressive (CAR) or spatial autoregressive (SAR) priors applied to a set of random effects. In contrast, typical machine learning approaches, such as random forests or neural networks, ignore this residual autocorrelation and instead base predictions on complex nonlinear feature-target relationships. In this paper we propose SPAR-Forest, a novel spatial prediction algorithm that fuses random forests with spatial smoothing models. By iteratively refitting a random forest combined with a Bayesian CAR or SAR model in one algorithm, SPAR-Forest can incorporate flexible feature-target relationships while still accounting for the residual spatial autocorrelation. Our results, based on a Scottish property price data set and multiple simulated data sets, show that SPAR-Forest outperforms Bayesian CAR/SAR models, random forests, and state-of-the-art hybrid approaches, including geographical random forests, providing a state-of-the-art framework for small-area spatial prediction.

### What this abstract supports

**Narrowest supported claim.** They propose SPAR-Forest, which iteratively refits a random forest
together with a Bayesian CAR or SAR model inside one algorithm, and report on a Scottish property-price
data set plus simulated data sets that it outperforms Bayesian CAR/SAR models, random forests, and
hybrid approaches including geographical random forests.

**Also supported, if needed.** The motivation is areal data with missing or suppressed values, i.e.
prediction of observations that are absent, and the stated contrast is that plain ML ignores residual
spatial autocorrelation while plain CAR/SAR smoothing cannot use nonlinear feature-target relationships.

**NOT supported.** It does not support any statement that SPAR-Forest reports uncertainty for its
predictions — the abstract claims outperformance, not intervals, coverage, or calibrated posterior
predictive statements, and no uncertainty measure is named. It also does not support any application to
health, food insecurity or survey outcomes: the only real data set named is Scottish property prices. And
"outperforms" here is a predictive-accuracy comparison; the abstract gives no metric, so no specific
metric may be attributed to it.

---

## Cross-cutting note for the Introduction

Neither abstract mentions food insecurity, Nigeria, prevalence thresholds, or local-government areas.
Both are citable as *method* precedents only. Neither can be cited as evidence that an estimator
performs well on the kind of outcome this paper models.

Routes tried, for the record: Crossref (succeeded for both, so no fallback was exercised). No DOI
failed to resolve. No paper was substituted.
