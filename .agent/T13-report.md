# T13 — calibration when a single LGA is removed and its neighbours stay

**Written by the secretary.** The analyst hit its step cap with the experiment complete and on disk but
before writing this file. Every number below was recomputed by me from the artefacts, and the design
integrity claim was checked against a graph I built myself.

## The answer

**The pre-declared rule passes, on all three criteria.** This is the test that matches what the paper
actually claims: an area with no data, surrounded by areas that have some.

| check | pass band | value | verdict |
|---|---|---|---|
| mean of z | −0.15 to +0.15 | **−0.0515** | PASS |
| sd of z | 0.85 to 1.15 | **1.1111** | PASS |
| share \|z\| ≤ 1.96 | 0.90 to 0.98 | **0.9400** | PASS |

200 LGAs held out, in five groups of 40, each predicted by a model that had never seen it. Five fits,
49–61 s each, 272 s total.

**The remedy is validated, not asserted.** Widening every interval by `k = 1.1111` lifts coverage to
**0.95**. Applying `k` fitted on four groups to the fifth, with each group taking its turn:

| test group | `k` from the other four | coverage in the held-out group |
|---|---|---|
| 1 | 1.1397 | 1.000 |
| 2 | 1.1406 | 1.000 |
| 3 | 1.0967 | 0.950 |
| 4 | 1.0799 | 0.900 |
| 5 | 1.0961 | 0.925 |

Mean 0.955. The correction is stable across folds, so it is a calibration, not a number fitted to the
residuals it is judged on.

## The two tests together

| design | what it asks | mean z | sd z | coverage |
|---|---|---|---|---|
| T12, whole zone removed | can the model map a region it never sampled? | −0.654 | 1.648 | **0.775** |
| T13, one LGA removed | can it place a single area among observed neighbours? | −0.052 | 1.111 | **0.940** |

In-sample the model correlates 0.975 with the direct estimates; out of sample here it still correlates
0.768, against 0.195 when a whole zone was removed. Interpolation is calibrated. Extrapolation is not.
That pair of sentences is the manuscript's honest position, and neither number can be quoted without the
other.

## Verified by the secretary

- **z recomputed from the fold file**: mean −0.0515, sd 1.1111, coverage 0.9400; max |my z − stored z| =
  1.3e−14 (rounding). All three bands evaluated independently.
- **All five out-of-fold coverages recomputed** from the file: 1.000, 1.000, 0.950, 0.900, 0.925, mean 0.955.
- **The design is not contaminated, checked against a graph I built myself** from the ADM2 polygons
  (`poly2nb`, queen): 774 polygons, **2,230 edges**; 200 distinct drawn LGAs; **136 edges with both ends
  drawn**, and **0 of those within the same group**. The agent's claim is correct.
- **Fold integrity**: 200 distinct LGAs, 40 per group, all 200 drawn from the 654 that hold a cluster.
- **Three-way comparison** recomputed: in-sample mean 0.2961 (sd 0.1911, r 0.975), out-of-sample 0.2933
  (sd 0.1685, r 0.768), direct 0.3019 (sd 0.2185).

## Deviations

1. **A fact in my brief was wrong, and the agent caught it.** I wrote that `data/derived/neighbours.csv`
   was the 774-node queen graph. It is the **37-node state** graph (86 undirected edges). The agent built
   the LGA graph from the boundary file instead and asserted 2,230 edges — which my own build confirms.
   Had it trusted the brief, adjacent LGAs in different states could have shared a group and contaminated
   the design. This is the second brief error of this kind in two days; the lesson is that a file named
   `neighbours.csv` is not evidence of which graph it holds.
2. Two bugs in the agent's own code, both self-disclosed: a mis-paired symmetry check (`lower.tri` against
   `upper.tri`, which do not correspond) and a `sprintf("%d", <double>)` crash in the final print block.
   The second crashed after the JSON was written and was re-run through the resume path; no fit was wasted.
3. Group assignment used a capacity-constrained greedy in draw order, declared in the script header before
   any fit. It achieved zero within-group adjacency, so no swap pass was needed.
4. No report file and no progress line after the final group.

## Open risks

1. **Per-group coverage is noisy.** 40 LGAs per group gives a binomial standard error near 0.034 at a true
   0.95, so a single group's 0.900 or 1.000 is not evidence either way. Only the pooled 200 are the
   pre-declared check, and only the pooled number should appear in the manuscript.
2. **The 120 never-clustered LGAs cannot be scored.** They have no direct estimate, so this test says
   nothing about them directly. It says something adjacent and useful: removing one area's data does not
   break the model. It does not prove the 120 are right.
3. Covariates were held known for held-out areas, which flatters the model slightly. The zone test failed
   anyway; this test passed anyway.
4. The count interval (101–130) remains unvalidated. These tests calibrate areas, not the joint functional.

## Unproven

Joint calibration of the count. Whether the covariates now being built (T14) improve the out-of-sample
correlation of 0.768 — that is T15, and the honest expectation is that it rises modestly, not to 0.975.
