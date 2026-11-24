# T30 — report (secretary)

The writer produced both files and reached its step cap before the build, with shell denied to it. The
secretary ran the verification and wrote this report. The prose is the agent's.

## State

| file | words (math stripped) | words (agent's count) |
|---|---|---|
| `docs/manuscript/conclusions.tex` | 244 | 278 |
| `docs/manuscript/declaration.tex` | 143 | 146 |

Conclusions: four paragraphs — the count as a distinct posterior quantity and the 14% independence
shortfall; the feasible sd range 0.156–74.11 and the identified count 87–231 with 120 of 144 being
assumption; the calibration result at 0.890 and 0.775 with k = 1.178 checked out of fold; and the
transfer claim, explicitly not a new estimator.

Declaration: competing interests, funding, ethics, data availability with the repository and both
licences, acknowledgement. No invented funder, grant number or ethics approval number.

## Verified by the secretary

- **Builds**: three passes, exit 0, **26 pages**, no undefined references, **zero overfull boxes**, no
  LaTeX warnings at all now that the reference list is filled.
- **Forbidden-word check re-run**: zero hits for "first", "novel", "unprecedented", "no one has",
  "state of the art", "we have solved", and zero `\cite`, zero `\todo`.
- **The 14% is right**: 6.3449 / 7.3830 = 0.8594, so an independence calculation reports a standard
  deviation 14.1% below the fitted one, which is what the sentence says.
- **Every number in Conclusions traced** to `count_functional.json` or `identif_bounds.json`: 115,
  101–130, 0.156, 74.11, 0.99%, 87, 231, 144, 120, 11.04%, 0.890, 0.775, 1.178.
- **Pages inspected as images, not just compiled**: page 25 carries Conclusions and Declaration; both
  read cleanly.

## Repairs made by the secretary

The four Declaration items sat flush against one another with no vertical space, which made a labelled
list read as a single paragraph. `\medskip` inserted before each item after the first.

## Unproven

Whether "no further ethical approval was required" is exactly right for the author's institution. It is
the standard statement for de-identified secondary data from the DHS Program, and the author must
confirm it is true of his own institution before submission — the secretary cannot verify it.

## Still outstanding

The abstract is a placeholder box on page 1 (ticket T31, running).
