# T24 - report (written by the secretary)

The analyst drafted the section and hit its step cap before the compile test and this report. Verified by the
secretary, not taken from the summary.

## State

`docs/manuscript/results.tex`, about 2,320 words, seven subsections, three tables, four figures.
Compiles inside `main.tex` with Methods and the theory section: 19 pages, two passes, exit 0, no undefined
references.

## Verified against the artefacts

Every number checked against the facts table and the source files: E[C] 114.975, interval 101-130, sd 7.383,
independent 40.258, pairwise 14.248, ratio 0.354, identity residual -2.7e-3, comparator 0.187, split-half
13.37/15.12, determination 32/509/40, thresholds 196.28 and 61.28, feasible variance 0.0244 to 5492.63, sd
0.156 to 74.11, fitted 54.509 at 0.99 percent of the range, P(C>=101) of 0.476/1.000/0.984, identified
interval 87-231 with width 144, observed-only 99.13 (87-111), share 13.72 percent and 10.63-24.90 percent,
monotonicity variant 0.1372-0.2324 buying 1.3 points, the four calibration rows, the pass bands, k=1.178 and
its five out-of-fold coverages.

## Defects found and fixed by the secretary

1. **The covariate table said precipitation was kept.** It was dropped: it correlates with aridity at 0.985
   and the pre-declared rule keeps one of any such pair. The prose said the same thing wrongly. Both corrected,
   and population density added as a row, since it was never interpolated and its absence made the retained
   set look like four when it is five.
2. Two 95 percent intervals were rendered as em dashes in the count table. They exist in `count_functional.json`
   (180-213 at c=0.40, 51-73 at c=0.60) and are now filled.

## Judged sound

Failure reported as failure in every case; the exact-exposure design is explicitly not a pass and the widening
is not allowed to convert it into one; the count interval carries the model-dependence caveat in every
paragraph where it appears; the text refuses the coverage curve and gives the supported contrast instead.

## Unproven

The four figures do not exist. Their captions name a `\todo` output file and a placeholder box is drawn.
That is the next ticket.
