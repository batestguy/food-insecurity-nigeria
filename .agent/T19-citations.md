# T19 — citation verification for `docs/theory.tex`

Started 2026-11-23. Rows are appended as each source is opened, so this file may be
partial. Every row carries a verbatim quote and a locator, or an explicit
`cannot_verify` with the routes tried.

Sources checked against the exact sentences in `docs/theory.tex`:
- L119–128 upper end of `prop:sharp` (pairwise Fréchet–Hoeffding upper bound)
- L130–131 / `lem:floor` (integer floor, proof at L144–155 — no variance-range bound used)
- L157–170 `lem:comon` (comonotone coupling attains the upper end, proved directly)
- L381–385 attribution table

---

## Row 1 — Fréchet (1951)
(pending)

## Row 2 — Hoeffding (1940)
(pending)

## Row 3 — Meilijson and Nádas (1979)

- **source**: I. Meilijson and A. Nádas, "Convex majorization with an application to the
  length of critical paths", *Journal of Applied Probability* 16(3), September 1979,
  pp. 671–677. DOI 10.2307/3213097 (= 10.1017/S002190020010782X). Short communication.
- **opened_url**: https://www.cambridge.org/core/journals/journal-of-applied-probability/article/abs/convex-majorization-with-an-application-to-the-length-of-critical-paths/AFF7ED2459941C3340180AC4F8913D64 (accessed 2026-11-23). Abstract only: the full text is paywalled — Cambridge Core shows "Get access", and the article-purchase option reads "Temporarily unavailable".
- **quote** (abstract, p. 671): "Let *X*₁ *X*₂ ··· *X*ₙ be random variables with given marginal distributions, let *I*₁,*I*₂, ···, *I*ₖ be arbitrary non-empty subsets of {1,2, ···, *n*} and let *M* = max [Σ_{i∈I_j} X_i] (*M* is the completion time of a PERT network with paths *I*ⱼ, and delay times *X*ᵢ). The paper introduces a computation of the convex supremum of *M* in the class of all joint distributions of the *X*ᵢ's with specified marginals, and of the 'bottleneck probability' of each path."
- **locator**: publisher abstract, p. 671. Keywords listed: "CONVEX AND STOCHASTIC INEQUALITY; HARDY–LITTLEWOOD MAXIMAL FUNCTION; PERT NETWORK".
- **carries_claim**: **partly** — the object is the convex supremum of a **maximum of linear combinations**, not of a plain sum; a single-path network (k = 1) reduces M to ΣXᵢ, so the comonotone sum is the k = 1 case of their computation, but the paper does not state "sums of increasing functions of one variable are maximal in convex order" as its result.
- **note**: the phrase in `theory.tex:382` ("sums of increasing functions of one variable are maximal in convex order") is a description of comonotonicity (Theorem 3(4) of Dhaene et al.), not of this paper's theorem. See Verdict Q2.

## Row 4 — Dhaene, Denuit, Goovaerts, Kaas and Vyncke (2002)

- **source**: J. Dhaene, M. Denuit, M. J. Goovaerts, R. Kaas and D. Vyncke, "The concept of
  comonotonicity in actuarial science and finance: theory", *Insurance: Mathematics and
  Economics* 31(1), 2002, pp. 3–33. DOI 10.1016/S0167-6687(02)00134-7.
- **opened_url**: authors' preprint (dated December 5, 2001, 50 pp., same text) at
  https://jandhaene.org/wp-content/uploads/2025/10/2002-dhaene-denuit-goovaerts-kaas-vyncke.pdf (accessed 2026-11-23), read through `https://r.jina.ai/`. The Elsevier version is paywalled; the preprint is the authors' own file of the published paper.
- **quote** (p. 33, §5.1): "The theorem above states that the least attractive random vector (X₁, . . . , Xₙ) with given marginals Fᵢ, in the sense that the sum of their components is largest in the convex order, has the comonotonic joint distribution, which means that it has the joint distribution of (F⁻¹₁(U), F⁻¹₂(U), . . . , F⁻¹ₙ(U))."
- **quote 2** (p. 10, §2): "As the function v defined by v(x) = x² is a convex function, it follows immediately that X ≤cx Y implies V ar[X] ≤ V ar[Y]."
- **quote 3** (p. 16, §4.1): "As we will prove in Section 5.1, the convex-largest sum of the components of a random vector with given marginals will be obtained in the case that the random vector (X₁, . . . , Xₙ) has the comonotonic distribution".
- **locator**: §5.1 p. 33 (statement of the convex-order maximality); §2 p. 10 (the variance consequence); §4.1 p. 16 (the claim announced).
- **carries_claim**: **yes** — and better than the paper's row needs: convex order maximality plus "convex order ⇒ larger variance" gives exactly "the comonotone coupling maximises Var of the sum", for arbitrary marginals, with no monotonicity requirement.
- **note**: the preprint's theorem is numbered between Theorem 8 and Theorem 11 in the OCR'd text I could read; the sentence quoted is the authorial statement of the result, which is what the paper needs. Line 2156 of the OCR also records: "random vector X is comonotonic if and only if V ar(Xᵢ + Xⱼ) = V ar(X^cᵢ + X^cⱼ)".
