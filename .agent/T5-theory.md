# Theory annex — four propositions for the food-insecurity small-area paper

Transcribed from verified work: symbolic proofs in `.agent/T5-verification/01_sympy.out.txt`, numerical
checks in `.agent/T5-verification/02_numeric.out.txt`, data extract `.agent/T5-verification/hh.csv.gz`
(39,877 households, 1,380 clusters, 74 design strata, 37 states).

Outcome throughout: `y = 1{hfs_sev ≥ 0.5}`, which in this file is exactly the households affirming all
eight FIES items. National weighted prevalence 0.2910; state range 4.6% (Niger) to 85.0% (Yobe).

**Status summary.** P1, P2, P3 and P4 are all classical results, correctly applied. **None is new
method.** What is ours is the application to Nigerian food insecurity and the identification statement
in P3. Every proposition carries an attribution and a verification subsection.

---

## P1 — selection on the outcome tilts the model; the design inflates variance

**Assumptions.** Inclusion indicator `S` with selection probability `π(x,y) = P(S=1 | x, y)`; the
population model `P(y=1 | x)` is of interest; selection may depend on `y` and on `x`.

**Statement.** For a binary outcome,

```
odds(y=1 | x, S=1) = {π(x,1)/π(x,0)} · odds(y=1 | x)
logit P(y=1 | x, S=1) − logit P(y=1 | x) = log{π(x,1)/π(x,0)}
```

So an unweighted fit on the selected sample estimates a different intercept — and, when the ratio depends
on `x`, different slopes — from the population fit. Weighting by the inverse selection probability
recovers the population parameter.

**Proof.** Bayes' rule on the selection event:
`P(y=1|x,S=1) = π(x,1)P(y=1|x) / {π(x,1)P(y=1|x) + π(x,0)P(y=0|x)}`. Dividing the odds by the
corresponding expression with `π(x,1) = π(x,0)` gives the ratio, and taking logs gives the shift. ∎

**Verification** (real data, 27,651 selected of 39,877, `max π = 0.115`):

| Case | Predicted shift | Observed shift | Test |
|---|---|---|---|
| constant ratio `exp(1.20)` | +1.2000 | +1.2117 | \|t\| = 0.81 |
| ratio `exp(1.00 + 0.50x)` | (+1.00, +0.50) | (+0.9999, +0.5282) | \|t\| = (0.00, 1.49) |

IPW fits return to the population fit (\|t\| = (0.71, 0.05) and (0.00, 1.63)). **Passes.**

**Corollary — design effect.** Under one-stage cluster sampling with equal cluster size `m` and
intra-cluster correlation `ρ`, `Var(ȳ) = (σ²/km){1 + (m−1)ρ}`, so the design effect is
`1 + (m−1)ρ` (Kish 1965).

**Verification, and an honest limit.** Measured on the real clusters: `ρ = 0.2018` unstratified, giving
`1 + (m₀−1)ρ = 6.63`; within stratum `ρ_w = 0.0620`, giving `2.73`; the actual design-based ratio is
**4.935**. The two forms bracket the truth rather than hitting it, because this design is both stratified
and weighted and the formula assumes neither. **The corollary is a benchmark, not an identity, for this
sample — write it that way in the paper.** Do not present 4.935 as "the design effect predicted by Kish".

---

## P2 — in an unsampled area, the error is the between-area variance

**Assumptions.** `θ_s = x_s'β + u_s`, `y_s = θ_s + e_s`, `u_s ~ (0, σ²_u)`, `e_s ~ (0, ψ_s)`,
independent. `ψ_s` is the design-based sampling variance of the direct estimate.

**Statement.** With `γ_s = σ²_u/(σ²_u + ψ_s)`,

```
E[(θ̂_s − θ_s)²] = γ_s ψ_s                    (β and variance components known)
```

and as `ψ_s → ∞`, `γ_s → 0` while `γ_s ψ_s → σ²_u`. The error of an estimate in an area with no sample
therefore equals the between-area variance, and a covariate reduces it one for one by reducing `σ²_u`.
With `β` estimated the additional term is `g₂ = (1−γ)² x'(X'V⁻¹X)⁻¹x`; with variance components
estimated a further `g₃` appears (Prasad and Rao 1990), **not proved here** — our intervals come from the
bootstrap, so `g₃` never enters them.

**Proof.** `θ̂ − θ = γ(y−θ) + (1−γ)(x'β−θ) = γe − (1−γ)u`, so by independence
`E[(θ̂−θ)²] = γ²ψ + (1−γ)²σ²_u`. Substituting `γ = σ²/(σ²+ψ)` and `1−γ = ψ/(σ²+ψ)` gives
`{σ⁴ψ + ψ²σ²}/(σ²+ψ)² = σ²ψ/(σ²+ψ) = γψ`. ∎

The cross-covariance `Cov(γe − (1−γ)u, u+e)` is **identically zero**, so `MSE = g₁ + g₂` is exact and
not a Taylor approximation when `σ²_u` is known.

**Verification.** Fay–Herriot on the 37 states with `ψ_s` the design-based variance:
`σ̂²_u = 0.031280` (REML), `ψ` median `0.000425`, `γ` median **0.9866**. Monte Carlo (4,000 replicates):
mean squared error 0.00051878 against `γψ = 0.00051516`, ratio **1.0070**. With `β` estimated,
`MC/(g₁+g₂) = 0.9946`. **Passes.**

**A correction worth recording.** An earlier version of this brief wrote `MSE = γψ + (1−γ)²σ²_u`. That
expression equals `γψ(2−γ)` — it double counts, adding the squared shrinkage bias on top of an error that
already contains it — and its limit as `ψ → ∞` is `2σ²_u` rather than `σ²_u`. Measured on the real states
the old form is `1.0134` times too large, exactly `2−γ` at the median. Use `γψ`.

**Substantive finding, and it constrains the paper.** At roughly a thousand households per state, `γ`
median 0.9866 means the model moves the direct estimate by 0.0026 on average (maximum 0.020). **At state
level, small-area estimation is very nearly a no-op**: the direct estimates are already more precise than
the between-state spread. The value of the hierarchical model is at LGA level, where `ψ` is large. A
state-level-only paper would be vulnerable to exactly that objection.

---

## P3 — where nothing is observed, the tail is not identified

**Assumptions.** Areas partitioned into observed `O` (population share `p`) and unobserved `U`. Let
`π_O = P(θ > c | area observed)`.

**Statement.** With no assumptions about the unobserved areas,

```
P(θ > c) ∈ [ p·π_O ,  p·π_O + (1 − p) ]        width = 1 − p
```

Under the monotonicity assumption that unobserved areas are no better than observed ones
(`π_U ≥ π_O`), the set tightens to `[π_O, pπ_O + (1−p)]`, width `(1−p)(1−π_O)`.

**Proof.** The population tail is the mixture `p·π_O + (1−p)·π_U` with `π_U ∈ [0,1]`, which is an interval
in `π_U`; monotonicity restricts `π_U` to `[π_O, 1]`. ∎ (Manski 1990; Manski and Pepper 2000.)

**Data consequence — decisive.** Every one of Nigeria's 37 states is sampled, the smallest holding 706
households (Niger). So `p = 1` and the identified set has **zero width**: at state level the tail *is*
identified, up to sampling error, and P3 says nothing.

At LGA level the position is the opposite extreme. The person file contains **no LGA, ward or
enumeration-area identifier** — the geography stops at `shstate1`, with `hv001` the cluster and `hv023` the
74 design strata. So every LGA is unobserved, `p = 0`, and the identified set is `[0, 1]`: **nothing about
any LGA is identified from these files alone.**

Hence P3 becomes a real theorem only once the cluster coordinates arrive and clusters can be mapped into
LGAs. It is the strongest argument for obtaining `NGGE8AFL.ZIP`, and it belongs in the paper as a statement
about what the data can and cannot support — not as a rhetorical flourish.

---

## P4 — the policy threshold is a cost ratio

**Assumptions.** Two actions, act or not; loss `c_FP` for acting where `θ ≤ c`, `c_FN` for not acting where
`θ > c`, zero otherwise; posterior `P_ex = P(θ > c | y)`.

**Statement.**

```
E[L(act) | y]   = c_FP (1 − P_ex)
E[L(not) | y]   = c_FN · P_ex
act  ⇔  P_ex > c_FP / (c_FP + c_FN)
```

For a count `T = Nθ` with `N` known, `E[T] = N·E[θ]` and `Var(T) = N²Var(θ)`; with `N` random and
independent of `θ`, `Var(T) = V_N·E[θ]² + E_N²·Var(θ) + V_N·Var(θ)` by the law of total variance.
(Berger 1985, Bayes risk.)

**Proof.** Compare the two posterior expected losses; the inequality in `P_ex` is linear. ∎

**Verification.** Algebra confirmed symbolically; the grid-minimisation check and a posterior count were
**not** run, because no Bayesian fit exists yet. They are to be added with the first fitted model.

**Caution for the write-up.** The household weights in the extract are normalised (they sum to `n`), so
absolute population counts are not recoverable from it. Report P4 through population **shares**, which are
scale-free, and obtain any absolute count from an external population denominator deliberately, not from
memory.

---

## Attribution — none of this is new method

| Proposition | Source | Our contribution |
|---|---|---|
| P1 selection tilt | Manski and Lerman (1977); Prentice and Pyke (1979) | applied; the exact shift is the textbook identity |
| P1 corollary, design effect | Kish (1965) | measured, with the mismatch reported rather than hidden |
| P2 mean squared error | Fay and Herriot (1979); Rao and Molina (2015) §6.2.2 | applied; the zero cross-covariance is a clean restatement |
| P2 `g₃` | Prasad and Rao (1990) | cited, **not** proved |
| P3 bounds | Manski (1990); Manski and Pepper (2000) | applied to Nigerian geography, where it bites |
| P4 Bayes rule | Berger (1985) | applied to a policy threshold |

**The paper's claim is therefore not "a new estimator".** It is: a design-aware, benchmarked application
with an explicit statement of what is and is not identified — plus whatever the LGA-level fit shows once
the coordinates exist.

## Still unproven

- P1's design-effect corollary does not hold as an identity for this stratified, weighted design.
- `g₃` is cited, not derived, and is not in our intervals.
- P3's LGA statement cannot be applied until clusters are mapped to LGAs.
- P4's decision rule has no fitted posterior behind it yet.
- The covariate reduction in `σ²_u` has not been measured on our data; the analytic claim is that the
  unsampled-area error equals `σ²_u`, and that is what the covariate phase must quantify.
