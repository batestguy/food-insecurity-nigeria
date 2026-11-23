# T20 — what the two closest papers actually do

Target claim under test: *first LGA-level small-area estimates of household food insecurity for
Nigeria, with threshold-exceedance probabilities.*

**HEADLINE (read first): paper 1 DOES produce threshold-exceedance probabilities.** It maps
`Pr(theta_k(s) > 0)`, labels regions above 0.7 as hotspots, and counts them. The clause "none of the
closest published models report threshold-exceedance probabilities" is false as written and must be
narrowed (see §Verdict at the end).

---

## Paper 1 — Chacón-Montalván, Parry, Giorgi, Torres, Orellana, Moraga & Taylor (2025),
## "Mapping food insecurity in the Brazilian Amazon using a spatial item factor analysis model",
## *Annals of Applied Statistics* 19(4): 3438–3463. DOI `10.1214/25-aoas2072`

`full_text_opened: true`
Route: DOI resolved to the citation only (no free HTML at Project Euclid without subscription).
Full text read from the **accepted version on arXiv**: `https://arxiv.org/html/1809.03905`
(arXiv:1809.03905v2 [stat.ME], 11 Jul 2025). This is the AoAS-accepted version: it cites its own
supplement as `AOAS2072SUPPA/B` (line 547 of the fetched HTML), and the reference list, tables and
figure numbering match the published article. A second open copy exists at Lancaster eprints
(`eprints.lancs.ac.uk/id/eprint/232929/1/00-aoas_accepted_version.pdf`), not fetched.

Locators below are to the arXiv HTML section/figure numbers, which are the published numbering.

### Q1. Spatial unit and granularity of published estimates

**Continuous point-referenced locations inside one municipality — not administrative areas.**
The model is a geostatistical model on `s in D subset R^2`: "We model the binary response variables as
discrete-state stochastic processes {Y_j(s): s in D} where D ⊂ R^2 and Y_j(s) denotes the response to item
j at spatial location s" (§2.3). Predictions are made "at a set of locations that we have not observed
data, s-tilde" (§S2.6).

Data: "100 randomly sampled households per season" — August 2015 and March 2016, 200 households total
(§3.1; §1.2). Sampling points geolocated, "restricted to the habitable area of Ipixuna, defined as a
20-meter radius from streets or river edges" (§3.1).

The administrative geography is explicitly too coarse for their purposes: "there are only eight urban
census sectors in the 2010 demographic census covering Ipixuna" (§3.3). So the finest administrative
unit is 8 census sectors, and **no area-level estimates are published at any administrative level** —
the output is a continuous surface plus qualitatively labelled neighbourhoods (Bairro da Várzea,
Turrufão, Bairro da Ressaca, Bairro do Cemetério/Multirão Velho, Bairro da Liberdade/Multirão Novo; §3.3.2).

Grid resolution of the prediction surface: **not found in text.** The main text says only "maps"
(Figures 7, 8, 19, 20); no cell size is stated in the arXiv HTML.

### Q2. Outcome

**A latent factor score per household, mapped as a continuous surface — not a rate per area.**
Three latent dimensions from an 18-item modified EBIA questionnaire. `theta(s) = eta(s) + w(s) + v(s)`
(§2.3, eq. 5). Labels: factor 1 "severe food insecurity including children"; factor 2 "anxiety and
reliance on social relations"; factor 3 "adults eating less and experiencing hunger" (§3.2). No
prevalence, no percentage of households, no count of food-insecure households per unit is reported
anywhere in the results.

### Q3. Exceedance probabilities / count above threshold / joint functional — **YES, all but the last**

Quoted verbatim (§3.3.2):

> "Spatial food insecure hotspots were identified as regions where the probability that the spatial
> effect is positive is greater than 0.7. Maps of these exceedance probabilities are provided in
> Chacón-Montalván et al. (2025, Section S4.4). Using all data, we identified four hotspots (A, B, C, D)
> ... in the dry season, only one hotspot (A) was identified, while in the rainy season, four hotspots
> (B, E, F, G) were identified."

And the supplement, Appendix S4.4 "Exceedance probabilities of food insecurity":

> "Figures 19 and 20 display the probabilities of food insecurity exceeding zero, using the full dataset
> and separated by season, respectively. Regions with exceedance probabilities above 0.7 are identified
> as high food insecurity zones."

Figure 19 caption: "Probability of positive food insecurity dimensions (>0). Only regions with
probabilities >0.5 are shown; labeled regions exceed 0.7."

So, concretely:
- pointwise exceedance probability at every mapped location: **yes** (`Pr(theta_k(s) > 0)`);
- a threshold decision rule (0.7) turning the probability map into a binary hotspot map: **yes**;
- a **count of hotspot regions** above the threshold (4 / 1 / 4): **yes**;
- a functional of the *joint* posterior across areas (e.g. `Pr(at least k areas exceed)`, `Pr(rank)`,
  `Pr(area is worst)`): **not found in text.** Grep of the full HTML for "joint" returns only likelihood
  factorisations and the joint posterior used for sampling; no joint exceedance functional.

Threshold caveat worth recording: the threshold is **zero on the latent-factor scale**, i.e. "is this
place above the study-area average", not a policy-relevant prevalence such as "more than 30% of
households severely food insecure". No exceedance probability for a prevalence is reported.

### Q4. Out-of-sample validation

**None found.** Grep of the full text for `validat`, `cross-valid`, `calibrat`, `coverage`, `hold-out`
returns no validation study of the spatial predictions. What exists is:
- DIC comparison of CIFA vs SPIFA I–III (Table 2) — in-sample model choice;
- MCMC diagnostics: R-hat < 1.05, bulk-ESS and tail-ESS ~5900 (Fig. 4; §3.3);
- a missing-data sensitivity check, not a predictive check: "compare the estimated easiness and
  discrimination parameters ... under the selected model (SPIFA III) with those from an equivalent model
  that excludes profiles with missing items. The results indicate no significant differences ... supporting
  the assumption that the missing data mechanism is missing at random (MAR)" (§S4.3).

No leave-one-household-out, no spatial hold-out, no comparison of predicted vs held-out item responses,
no interval coverage of the latent predictions. `not found in text` for all of these.

### Q5. Uncertainty usable for a decision

- Credible intervals on parameters throughout: e.g. `T_11 = 0.468 (95% CI 0.29–0.7)`,
  `phi_1 = 216 m (95% CI 127–365)`; and CI plots for easiness/discrimination (Figs 5, 6).
- Per-location exceedance probabilities and a stated decision rule (0.7) — this is the strongest
  decision-facing output in the paper.
- **Not found in text:** credible intervals on a *prevalence* or on any policy quantity; no cost, no
  targeting rule beyond the binary hotspot label.

### Q6. What it says is absent / future work

- Spatial covariates were left out: "Spatial predictors were not included in our model because these are
  insufficiently finely resolved in our study area ... In the future, we are planning a larger scale
  analysis in which spatial predictors *will* be included" (§3.3).
- Two-stage structure learning rather than joint: "in our application we adopted a two-stage modeling
  procedure ... the SPIFA model could be extended to stochastically infer the sparse structure" (§4.1).
- Extensions listed: spatio-temporal, mixed outcome types, non-linear predictor effects, heavier-tailed
  distributions, scalable Gaussian-process approximations (§4.1).
- Explicitly local, not national: the application is one town of ~12,000 urban residents (§1.2). No claim
  of national or sub-national coverage, and no threshold defined on a prevalence scale.

