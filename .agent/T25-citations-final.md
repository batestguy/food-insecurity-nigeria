# T25 - citation policy, final state

Written by the secretary; the analyst hit its step cap after the edits but before the compile test and report.

## What changed in `docs/theory.tex`

Six sources could not be opened, so six citations were removed and the results they supported are now proved
in the text: the pairwise bounds (two lines), the mixture bound for the partially identified tail (a new
Lemma, one line), and the nesting of identified sets (now citing that lemma rather than asserting a form).

Kept, with their verification status: Meilijson and Nadas (1979), abstract only, cited for convex-order
maximality of sums of increasing functions; Dhaene et al. (2002), opened with three verbatim quotes;
Imbens and Manski (2004), opened and quoted, as the contrast. Bhatia and Davis was removed entirely: the
lattice lemma needs no range bound, so the corrected DOI had nothing to attach to.

## Verified by the secretary

- `docs/theory.tex` compiles twice under a bare wrapper, exit 0, five pages, no undefined references.
- **Zero `\cite` commands and zero `\bibitem` entries**, so there is no bibliography that could disagree with
  the text. Every attribution lives in the table with a status of "proved here" or "theirs".
- **Zero occurrences of "quoted"**, which the earlier table used falsely for six sources.
- Proposition numbering checked: `prop:meanvar` is Proposition 1 and `prop:sharp` is Proposition 2, which is
  what Methods and Results referred to numerically. Both have now been changed to `\ref` so the numbers cannot
  drift.
- New lemma `lem:identified` placed after `prop:sharp` deliberately, so existing cross-references keep their
  numbers.

## Added by the secretary

The paragraph the analyst did not finish: the interval is explicitly not an Imbens-Manski confidence set, with
the distinction stated as ours covering the whole identified set, which is the more demanding object.

## Judgement to state in the paper

Two propositions now rest on their own proofs rather than on a citation. That is a stronger claim about our
text and a weaker claim about the literature. The attribution section says so: the names Fréchet-Hoeffding and
Manski are kept for orientation, with no bibliography entry, and both bounds are proved where they are used.
A referee will read the new lemma as ours, which is correct - it is the classical bound, proved here.

## Unproven

Nothing about the removed citations can be re-asserted without opening them. Frechet (1951) appears never to
have been digitised; Hoeffding (1940) was not found; both Manski papers and Horowitz-Manski exist only as
scans without a text layer.
