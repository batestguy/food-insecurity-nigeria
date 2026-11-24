# T31 report — abstract

- **Written:** Abstract, `docs/manuscript/abstract.tex:1-5`; three plain paragraphs.
- **Word count:** 235 whitespace-separated tokens, with hyphenated forms counted as one.
- **Forbidden-word check:** Passed; none of the listed terms or phrases appears in the abstract. The requested closing says “not a new estimator.”
- **Load-bearing sentence:** “An independence calculation would understate the count’s standard deviation by 14%; the marginals alone permit a standard deviation from 0.156 to 74.11, so the interval reflects the model’s dependence structure rather than the marginals alone.”
- **Sources:** The supplied verified values are listed in `.agent/T31-brief.md:24-37` and `PLAN.md`. The project points to `scripts/lga_model.R` and `scripts/extract_fi_state.py` for the prevalence; `data/derived/count_functional.json` for the count and dependence result; `scripts/theory_counts.R` for the marginal bounds; `data/derived/identif_bounds.json` for the identified count; and `data/derived/calibration_exact.json` and `data/derived/calibration_summary.json` for coverage.
- **Removed:** None; this was a new abstract.
- **Open:** No source TODOs. The progress file was not written.
- **Uncertainty:** None about the requested wording; the abstract explicitly says the count interval was not validated by the calibration tests.
