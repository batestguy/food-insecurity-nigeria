# T4 report

## Changed
- `.agent/T4-litreview.md` — Blocks A–E. 15 core references each with DOI, year, venue, one verbatim
  abstract sentence and what it did; 6 further read entries; gap table of 8 candidate contributions;
  the two-sentence answer; 7 referee demands; 3 positioning papers; a recorded list of failed and
  empty searches.
- `.agent/T4-progress.md` — appended per unit.

## Verified
- Every "read" entry was opened at abstract level; quotes are verbatim substrings of the retrieved
  abstract text (OpenAlex `abstract_inverted_index`, reconstructed). 51 HTTP requests, 60 allowed.
- The headline negative results are positive finds, not guesses:
  - `10.1214/25-aoas2072` (AoAS 2025) — spatial item factor analysis of food insecurity already
    published.
  - `10.1177/09622802241293776` (SMMR 2024) — heavy-tailed BYM2 already published as a method.
- Two references had **no abstract** in OpenAlex or Crossref (`10.4060/cd1350en`,
  `10.1016/j.measurement.2017.10.065`) plus `10.1007/s12571-019-00936-9`; all three are marked
  **seen** and support no claim.

## Deviations
- Shell was denied (`permission.rejected`), so no directory listing or `git status`; all file access
  via read/grep/write.
- The brief's item 6 (FIES cut-offs and the debate about them) could not be answered from quotable
  abstracts. The query returned 7 hits, none relevant. I report the Rasch-reference route (Nord 2016,
  Wambogo 2018) as verifiable and the numeric raw-score rule as unsourced. I did not invent a
  citation for it.
- The Moran's I 0.011 figure used at `MathematicsApplied Paper.txt:59` traces by content to Mikailu
  et al. 2026 (`10.65757/hjpedv1n15`) — post-rebasing state CPI, global Moran's I, LISA, Kebbi
  hotspot, Rivers coldspot all match. **The number 0.011 and p = 0.353 are not in the abstract and I
  could not verify them.** The venue is a low-visibility policy/economics journal. The paper's
  premise therefore rests on an unverified number from an unindexed source.

## Unproven
- Exceedance probability for food-insecurity SAE is recorded as **not found**, not as non-existent;
  four query formulations is not a systematic search, and I did not query Europe PMC, Scopus or
  Google Scholar.
- Nothing was read at full-text level, so no claim about a paper's internal method (e.g. whether
  Michal 2024's scale mixture is fitted in INLA or Stan) is supported.
- The FAO Chile study is **seen** only; its methods are unknown and it may narrow the application gap
  further.
