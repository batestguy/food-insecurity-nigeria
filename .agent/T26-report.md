# T26 - report (secretary)

The analyst produced the four PDFs and hit its step cap before wiring them into Results; it returned no
message. The secretary wired them in and ran the compile.

## State

`scripts/make_figures.R`, four PDFs in `docs/manuscript/figures/`, and four `\includegraphics` blocks in
`results.tex` replacing the placeholder boxes. No `\todo` remains in Results.

## Verified

- `main.tex` compiles twice with the figures embedded: **23 pages, exit 0, no undefined references, no
  missing-file errors.**
- All four PDFs are single page, vector, with embedded fonts (checked by parsing the PDF objects), valid
  PDF-1.4 headers. `fig_estimates.pdf` is 50 KB against 4.6 KB for the others, consistent with 774 intervals
  against four points.
- Captions rewritten: each now names the artefact it was drawn from, and the feasible-range caption says the
  axis is logarithmic so the fitted value is not visually flattered.
- The calibration figure's caption states that points are not joined, matching the text's refusal of a
  coverage curve.

## NOT verified

**I have not looked at the figures.** No image viewer is available to me, and a PDF that compiles is not a
figure that reads correctly. Axis ranges, label collisions, and whether the 120 unclustered areas are
distinguishable in practice all need a human eye before submission. That is the single largest unverified
item in the manuscript.
