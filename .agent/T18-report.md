# T18 — report

**The full audit record is `.agent/T18-theory.md`; this file is the short form.** The analyst hit its step cap
after producing the two load-bearing artefacts and before writing documentation; the secretary wrote both.

## Changed

- `docs/theory.tex` — the manuscript's theory section, self-contained, compiles under a bare `article` wrapper.
- `scripts/theory_counts.R` — numeric verification; exit 0, 24 checks, 0 failures, 0.3 s.
- `.agent/T18-theory.md` — propositions, proofs, verification, attribution, and what the paper must say.

## Verified

Everything in `.agent/T18-theory.md` was recomputed by the secretary, including the comonotone variance by
exact integral (5492.630075), the naive pairwise bound (−4436.6336), `f(1−f)` (0.024375), the cyclic coupling
by 400,000-draw simulation (mean 114.97508, variance 0.024297, support {114,115}), the P1 counterexample, and
`pdflatex` on the section.

## Deviations

Three of the brief's own instructions were wrong and were corrected by the analyst: the pairwise Fréchet
route to the lower bound (invalid, returns a negative variance), P1's "if and only if" (false, sign
cancellation), and P3's need for monotonicity (not needed — union bound; monotonicity buys interpretability).
Full detail and counterexamples in the annex.

## Open risks

- **Eight cited sources were not opened.** Blocking before submission.
- The model's count variance sits 0.99% of the way up its feasible range, so the 101–130 interval is a
  statement about the model's dependence structure, not about the data. The manuscript must say so.

## Unproven

Whether the attributions are correct — untested until the sources are opened.
