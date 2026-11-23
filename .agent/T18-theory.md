# T18 — the mathematics of the count functional

**Written by the secretary** from the analyst's `docs/theory.tex` and `scripts/theory_counts.R` (the agent hit
its step cap before writing this file). Every number below was re-derived independently by me.

The manuscript section is **`docs/theory.tex`**, which compiles under a bare `article` wrapper (verified: PDF
produced, only first-pass reference warnings). This file is the audit record around it.

---

## What was asked, and the three things that were wrong with the asking

My brief proposed a route for the sharp lower bound, an "if and only if" in P1, and a monotonicity condition
in P3. **All three were wrong, and all three were caught.**

### 1. The pairwise Fréchet route gives a negative variance — it is invalid

I proposed bounding Var(C) with the Fréchet–Hoeffding bounds on each *pairwise* event. For `n ≥ 3` that is
not a valid route to the lower end. Minimal counterexample: `p = (½,½,½)`. Every pairwise lower bound is 0,
which would force `C ∈ {0,1}` and hence `Σ ≤ 1` — but `Σ = 1.5`. Applied to our own 774 marginals the route
returns **Var(C) = −4436.63**, visibly impossible, and my recomputation matches that number exactly.

**The correct sharp lower bound**, proved from first principles rather than from pairwise events: `C` is
integer-valued with mean `S = Σ p_s`, so for any coupling `Var(C) ≥ f(1−f)` where `f = S − ⌊S⌋`. Here
`f = 0.9750`, giving **0.024375**, attained by the **cyclic coupling** — place arcs of length `p_s` head to
tail around a unit circle, and `C(U)` is the number of arcs covering `U`. Then `C ∈ {⌊S⌋, ⌈S⌉}` and the
variance is exactly `f(1−f)`.

Verified by simulation, mine and the agent's: mean 114.97508 against `S = 114.975`, variance **0.024297**
against the closed form 0.024375 (Monte Carlo at 400,000 draws), support exactly `{114, 115}`.

### 2. P1's "if and only if" is false — the dependence can cancel

I asserted that the pairwise term vanishes if and only if the indicators are pairwise uncorrelated. Equality
holds in one direction only. Explicit joint with `p = (½,½,½)` and `P₁₂ = 0.35`, `P₂₃ = 0.25`, `P₁₃ = 0.15`
(verified non-negative and summing to 1, `t = 0.12` in the parametrisation): the indicators are plainly
dependent, `P₁₂ = 0.35 ≠ 0.25 = p₁p₂`, yet `Var(C) = 0.75`, identical to the independence value. The signed
covariances are `+0.1, 0, −0.1` and cancel exactly.

**Correct statement: uncorrelatedness implies the pairwise term vanishes; the converse fails.** The paper must
say it in one direction and may note cancellation as the reason.

### 3. P3 needs no monotonicity — it is the union bound

I asked for coverage of the identified set to be proved from monotonicity of the endpoints. The inequality
holds for **arbitrary** `L` and `U`: it is the union bound, `P(L(T) ≤ ℓ and U(T) ≥ u) ≥ 1 − α/2 − α/2`.

What monotonicity buys is different and worth stating separately: it makes the containment event a **single
interval of `T`**, which is what licenses the sentence "the identified set is inside whenever the statistic is
central". That is true here — both endpoints have slope exactly 1 in `C_O`, and slope exactly `p = 0.8896` in
`π_O`, with no inversion possible. Without monotonicity the containment set fragments: four disjoint pieces
were demonstrated.

**So the paper's claim survives, for a different reason than the one it would have given.** That is precisely
the kind of error a referee finds, and it was found here instead.

---

## The result the paper wants

Given the 774 marginals and nothing else, the count's variance is confined to a **very wide** interval:

| quantity | value |
|---|---|
| minimum variance (cyclic coupling) | **0.0244** — sd 0.156 |
| independence benchmark | 40.258 — sd 6.345 |
| **model posterior** | **54.509 — sd 7.383** |
| maximum variance (comonotone coupling) | **5492.63** — sd 74.11 |
| extremal sd ratio | 0.0246 to 11.68 |

**The model's variance sits 0.99% of the way up its own feasible range.** Two consequences, both of which
belong in the paper and neither of which is comfortable:

1. **The marginals do not identify the count's variance.** They permit a standard deviation anywhere from 0.16
   to 74. The reported 7.38 — and therefore the interval 101 to 130 — is a statement about the model's
   dependence structure, not a statement the data supports. This is the same lesson as the identification
   bound, one level down: `E[C]` is marginal, `Var(C)` is not, and the second is doing all the work in the
   headline.
2. **The claim that spatial dependence "matters by 16%" is a model claim.** Relative to what the marginals
   allow, 54.5 is barely above independence. That does not make it wrong; it makes it an assumption, and it
   must be labelled one.

## Numeric verification — run by the secretary

| check | command | result |
|---|---|---|
| script runs | `Rscript scripts/theory_counts.R` | exit 0, 24 checks pass, 0 failures, 0.3 s |
| independent variance | recomputed from `P_exceed_050` | 40.258330 (file 40.25832955) |
| comonotone variance | exact integral of `(N(u) − S)²` over sorted marginals | **5492.630075**, matches |
| naive pairwise lower bound | recomputed | **−4436.6336**, matches — and invalid |
| `f(1−f)` | `S = 114.975`, `f = 0.975` | 0.024375 |
| two-point minimum | search over integer supports | attained at `{114,115}`, `P(115)=0.975` |
| cyclic coupling | 400,000 draws on the unit circle | mean 114.97508, var **0.024297**, support `{114,115}` |
| P1 counterexample | explicit joint, cells checked | dependent, `Var = 0.75` = independence value |
| P4 | three thresholds against `count_functional.json` | `E[C]` 196.28 > 114.98 > 61.28; `E[C] = n·frac` to 1.3e−6; 0 violations of `P(>0.4) ≥ P(>0.5) ≥ P(>0.6)` across 774 areas |
| LaTeX | `pdflatex` under a bare wrapper | PDF produced, no errors |

## Attribution — and a rule violation to fix before submission

The paper must not claim any of this as new. Comonotonicity, the convex-order maximality of sums of
comonotone indicators, `f(1−f)` as the least variance of an integer-valued variable with a given mean, and the
Fréchet–Hoeffding bounds are all classical. Our contribution is the assembly and the application to 774
Nigerian areas.

**But the attribution table in `docs/theory.tex` cites Fréchet, Hoeffding, Meilijson–Nádas, Dhaene,
Popoviciu, Bhatia–Davis, Manski and Imbens–Manski, and none was opened in this session.** The project rule is
that no citation enters a draft unopened. **This is a blocking item before submission**, not a caveat: each
must be opened, the claim it is cited for confirmed, and the citation corrected if the attribution is wrong.
The most exposed ones are Meilijson–Nádas (convex order / comonotone sums) and Popoviciu–Bhatia–Davis
(variance bounds) — if either does not say what it is cited for, the proposition is still true but the
attribution has to be rebuilt.

## What the manuscript must now say

- The mean is marginal; the variance is not; the second is where the paper's headline lives.
- Sharp bounds from the marginals alone, both attained, with the interval quoted: sd in 0.156 to 74.11.
- The model's 7.38 is a modelling claim, not a datum, and the paper says so in that sentence.
- The identified-set construction covers by the union bound; monotonicity is what makes it interpretable.
- The count is non-increasing in the crisis line, with nested identified sets — so the 40%, 50% and 60% figures
  are one family, not three independent claims.

## Unproven

- Whether the comonotone and cyclic couplings are *attainable jointly with the marginal specific to each LGA* —
  both are valid couplings of the marginal vector, so yes, but the paper should say "for this marginal vector"
  rather than "in principle".
- The citations, as above.
- Everything the four calibration designs left unproven carries over unchanged.
