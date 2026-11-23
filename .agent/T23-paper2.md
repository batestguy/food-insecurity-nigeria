# T23 — paper 2: could not be obtained by any free route

**Written by the secretary** from the analyst's report; the agent hit its step cap before writing files.

**Verdict: the full text could not be obtained by any free route on 2026-11-23.** This is a documented
failure, not an unfinished search. Twenty-nine routes were tried.

## The paper

*Moura, Pereira and Silva, "A Beta–Beta Prime Model for Rates and their Precision for Small Area Estimation:
An Application to Brazilian Food Insecurity Index"*, **Journal of Survey Statistics and Methodology** 14(2):
430–451, online 2025-02-28, print 2026-04-01. DOI `10.1093/jssam/smaf002`.

**Correction to my brief:** I told the analyst to search USP, UNICAMP and UFMG. The authors are not at those
institutions — Moura is UFRJ (retired), Pereira is CEAUL and the University of Minho, Silva is CEAUL and IST
Lisbon. Wrong repositories were named, so part of the search was aimed at the wrong places. The routes that
mattered were still tried.

## Routes tried, with outcomes

| route | result |
|---|---|
| Unpaywall | 200 — `is_oa: false`, `oa_status: closed`, `oa_locations: []`, no repository copy |
| OpenAlex (W4408140786) | 200 — `is_oa false`, no repository fulltext, `pdf_url` null |
| Semantic Scholar | 200 — `openAccessPdf.status: CLOSED` |
| Crossref | 200 — metadata confirmed: vol 14, issue 2, pp. 430–451 |
| OUP PDF and abstract page | **403**, Cloudflare interstitial |
| Wayback (article, PDF, DOI) | no snapshots of the article; only redirects of the DOI captured |
| CORE, OpenAIRE, BASE, RCAAP | 0 hits / IP denied / 403 |
| Lisbon research portal, IST author page, ORCID, CEAUL site | abstract or DOI link only, no file |
| RepositóriUM, repositorio.ul.pt, Pantheon UFRJ | 404 / TLS certificate error / unrelated theses |
| Google Scholar, scholar.archive.org, ResearchGate | CAPTCHA / bot protection / 403 |
| fatcat, arXiv API, SciELO Preprints, IASS newsletter, CiteDrive | connection refused / 429 / no result / timeout / metadata only |

## The abstract, verbatim

> "Statistics bureaus around the world have been faced with an increasing need to provide reliable estimates
> of economic and social indices, such as proportions or rates, from socioeconomic survey data at small area
> levels… Here, we propose to model the direct estimator of the rates or proportions in small area domains as
> being beta distributed. The novelty is that we also model the sampling precision estimator as a beta prime
> distribution. An evaluation study with real data shows that there is an additional gain in jointly modeling
> the direct estimator and its sampling precision estimator. An application is also provided to estimate the
> food insecurity index in small areas of a Brazilian state."

## What the abstract does and does not license

**Licensed:** the application estimates a food insecurity index at small-area level in one Brazilian state.
That is close enough to our contribution that it must be acknowledged rather than ignored.

**Not licensed:** the abstract says nothing about threshold-exceedance probabilities, hotspot counts,
out-of-sample validation, or any decision rule. **Absence from an abstract is not evidence of absence from the
paper**, and the manuscript may not use it either way. It cannot be cited as support for our novelty claim and
it cannot be dismissed.

## Consequence for the novelty claim

The claim must rest only on what was verified. In `AGENTS.md` and the Introduction it is now:

> We found no published estimates of household food insecurity at local-government level for Nigeria, and in
> the closest paper we were able to read in full, no administrative-area estimates and no out-of-sample
> validation.

Paper 2 is named as a related small-area food-insecurity application, **without a statement about what it
does or does not contain**. If a copy arrives later, the sentence can be strengthened; until then it is
written to survive being wrong about nothing.

## Open

To finish this properly, one of two things is needed:

1. **Interlibrary loan or a direct request to the authors.** Moura (UFRJ), Pereira (CEAUL / Minho) and Silva
   (CEAUL / IST). A three-line email asking for the accepted manuscript is a normal academic courtesy and
   normally works. This is a user action or an authorisation for me to draft the email.
2. **An institutional subscription.** OUP returns 403 to automated requests; a human with library access
   could download it in a minute.

Neither is a blocker for drafting: the Introduction is written to a claim that does not depend on it. It
remains a blocker for any sentence that characterises paper 2.
