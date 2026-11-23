#!/usr/bin/env Rscript
# =============================================================================
# scripts/theory_counts.R  ---  T18
#
# Numeric verification of the four propositions about the count functional
#
#     C = #{ s = 1..n : theta_s > c },    n = 774 LGAs, c = 0.50
#
# Nothing is fitted. No INLA, no network, no writes.
#
# Reads only:
#   data/derived/lga_estimates.csv     P_exceed_040/050/060 for the 774 LGAs
#   data/derived/count_functional.json model E[C], Var(C), c = 0.4/0.5/0.6
#   data/derived/identif_bounds.json   reported identified-set endpoints
#
# Run from the repo root:   Rscript scripts/theory_counts.R
# Exits 0 iff every printed check passes.
# =============================================================================

t_start <- Sys.time()
SEED    <- 20261123
set.seed(SEED)

N_FAIL <- 0L
ok <- function(id, pass, detail = "") {
  if (!isTRUE(pass)) N_FAIL <<- N_FAIL + 1L
  cat(sprintf("[%s] %-10s %s\n", if (isTRUE(pass)) "PASS" else "FAIL", id, detail))
  invisible(pass)
}
hdr <- function(s) cat("\n", strrep("=", 78), "\n", s, "\n", strrep("=", 78), "\n", sep = "")
note <- function(...) cat("      ", paste0(...), "\n")

# -----------------------------------------------------------------------------
# helper: exact law of C for any coupling written as arcs [lo, hi) on [0,1)
#         C(u) = #{ arcs covering u },  u ~ U(0,1)
# The arcs are a partition of the circle into pieces; the coverage function is a
# step function, so the law of C is computed exactly, not sampled.
# -----------------------------------------------------------------------------
arc_law <- function(lo, hi, tol = 1e-12) {
  keep <- (hi - lo) > tol
  lo <- lo[keep]; hi <- hi[keep]
  bp <- sort(unique(c(0, 1, lo, hi)))
  i  <- match(lo, bp); j <- match(hi, bp)
  d  <- tabulate(i, nbins = length(bp)) - tabulate(j, nbins = length(bp))
  lvl <- cumsum(d)[seq_len(length(bp) - 1)]         # level on [bp[k], bp[k+1])
  len <- diff(bp)
  vals <- sort(unique(lvl))
  pm   <- vapply(vals, function(z) sum(len[lvl == z]), numeric(1))
  mu   <- sum(vals * pm)
  vr   <- sum(vals^2 * pm) - mu^2
  list(bp = bp, lvl = lvl, len = len, vals = vals, pm = pm,
       mean = mu, var = vr,
       mu4c = sum((vals - mu)^4 * pm))
}
arc_draw <- function(law, u) law$lvl[findInterval(u, law$bp)]

# comonotone arcs: every indicator switches on at u = 0
comon_arcs <- function(p) list(lo = rep(0, length(p)), hi = p)

# cyclic (anti-monotone) arcs: consecutive arcs of length p_s along the circle
cyclic_arcs <- function(p) {
  cs  <- c(0, cumsum(p))
  lo  <- cs[seq_along(p)] %% 1
  hir <- lo + p                       # p_s <= 1, so hir < 2: at most one wrap
  wrap <- hir > 1
  list(lo = c(lo, rep(0, sum(wrap))),
       hi = c(pmin(hir, 1), hir[wrap] - 1))
}

# =============================================================================
hdr("0.  INPUTS")
est <- read.csv("data/derived/lga_estimates.csv", stringsAsFactors = FALSE,
                check.names = FALSE)
cf  <- jsonlite::fromJSON("data/derived/count_functional.json", simplifyVector = FALSE)
ib  <- jsonlite::fromJSON("data/derived/identif_bounds.json",  simplifyVector = FALSE)

p <- est$P_exceed_050
n <- length(p)
S <- sum(p)
cat(sprintf("seed = %d     draws per coupling = 200000\n", SEED))
ok("0.1", n == 774L, sprintf("n = %d areas", n))
ok("0.2", abs(S - as.numeric(cf$primary$expectation)) < 1e-4,
   sprintf("sum_s P_s = %.6f   vs count_functional E_C = %.6f", S,
           as.numeric(cf$primary$expectation)))
ok("0.3", all(p >= 0 & p <= 1), sprintf("all P_s in [0,1]; range [%.6f, %.6f]", min(p), max(p)))

# =============================================================================
hdr("1.  P1  --  the mean is marginal, the variance is not")

var_ind <- sum(p * (1 - p))

# ---- 1a. the identity on a small area system, where the joint is explicit ----
# n = 6, 200000 draws from one coupling; compute P_st from the same draws and
# check Var(C) = sum p(1-p) + 2 sum_{s<t} (P_st - p_s p_t) exactly.
set.seed(SEED)
n6 <- 6L; m6 <- 200000L
p6 <- c(0.05, 0.12, 0.30, 0.45, 0.61, 0.88)
ca6 <- comon_arcs(p6)
l6 <- arc_law(ca6$lo, ca6$hi)
u6 <- runif(m6)
C6 <- arc_draw(l6, u6)
X6 <- vapply(seq_len(n6), function(s) as.numeric(u6 < p6[s]), numeric(m6))
p6h <- colMeans(X6)
P6  <- crossprod(X6) / m6
pw  <- 2 * (sum(P6[upper.tri(P6)]) - sum(outer(p6h, p6h)[upper.tri(P6)]))
var6 <- mean((C6 - mean(C6))^2)
ok("1.a", abs(var6 - (sum(p6h * (1 - p6h)) + pw)) < 1e-8,
   sprintf("n=6: Var(C)=%.8f  vs  indep %.8f + pairwise %.8f = %.8f  [identity exact]",
           var6, sum(p6h * (1 - p6h)), pw, sum(p6h * (1 - p6h)) + pw))

# ---- 1b. the "if and only if" in the brief is FALSE for n >= 3 --------------
# Counterexample: p = (1/2,1/2,1/2) and a joint law with covariances (+0.1, 0, -0.1).
# The pairwise term is exactly zero, yet two of the three indicators are dependent.
law <- data.frame(
  i1 = c(1, 1, 1, 0, 1, 0, 0, 0),
  i2 = c(1, 1, 0, 1, 0, 1, 0, 0),
  i3 = c(1, 0, 1, 1, 0, 0, 1, 0),
  pr = c(0.10, 0.25, 0.15, 0.05, 0.00, 0.10, 0.20, 0.15))
Xt <- as.matrix(law[, 1:3])
pt <- as.numeric(law$pr %*% Xt)
Ct <- as.numeric(Xt %*% rep(1, 3))
S_t <- sum(pt)
Cov <- matrix(0, 3, 3)
for (a in 1:3) for (b in 1:3) Cov[a, b] <- sum(law$pr * Xt[, a] * Xt[, b]) - pt[a] * pt[b]
var_t     <- sum(law$pr * (Ct - S_t)^2)
var_ind_t <- sum(pt * (1 - pt))
cat(sprintf("      counterexample p = (%.2f,%.2f,%.2f), sum of probabilities %.2f\n",
            pt[1], pt[2], pt[3], sum(law$pr)))
cat(sprintf("      Cov matrix:  [% .2f % .2f % .2f; % .2f % .2f % .2f; % .2f % .2f % .2f]\n",
            Cov[1,1], Cov[1,2], Cov[1,3], Cov[2,1], Cov[2,2], Cov[2,3], Cov[3,1], Cov[3,2], Cov[3,3]))
cat(sprintf("      Var(C) = %.6f   independent value = %.6f   sum of covariances = %.2e\n",
            var_t, var_ind_t, sum(Cov[upper.tri(Cov)])))
ok("1.b", abs(sum(Cov[upper.tri(Cov)])) < 1e-12 &&
          abs(var_t - var_ind_t) < 1e-12 &&
          max(abs(Cov[upper.tri(Cov)])) > 0.05,
   "converse FAILS: pairwise term is 0 while covariances are (+0.1, 0, -0.1) -- see P1 remark")
note("the arrow 'uncorrelated => term vanishes' survives; the converse does not.")

# =============================================================================
hdr("2.  P2  --  sharp bounds on Var(C) given the marginals")

ps <- sort(p)
var_comon <- sum(ps * (2 * (n - seq_len(n)) + 1)) - S^2      # sum_{s,t} min(p_s,p_t) - S^2
Mmin <- outer(p, p, pmin)
ok("2.a", abs(var_comon - (sum(Mmin) - S^2)) < 1e-8,
   sprintf("comonotone closed form: sum_{s,t} min = %.4f, S^2 = %.4f, Var = %.6f (two routes agree)",
           sum(Mmin), S^2, var_comon))

f_frac  <- S - floor(S)
var_min <- f_frac * (1 - f_frac)
cat(sprintf("      feasible range given the marginals:  Var(C) in [%.6f, %.4f]   (sd in [%.4f, %.4f])\n",
            var_min, var_comon, sqrt(var_min), sqrt(var_comon)))
cat(sprintf("      independent variance  = %.6f   (sd %.6f)\n", var_ind, sqrt(var_ind)))
cat(sprintf("      model posterior var   = %.6f   (sd %.6f)\n",
            as.numeric(cf$primary$variance_from_the_draws), as.numeric(cf$primary$sd)))
ok("2.b", var_min <= var_ind + 1e-9 && var_ind <= var_comon,
   "ordering var_min <= var_independent <= var_comon holds")

# ---- 2c. the pairwise-Frechet route to the LOWER end is invalid ------------
# Applying max(0, p_s+p_t-1) to every pair and summing assumes all pairwise lower
# bounds are attained by one joint law. For n >= 3 they need not be.
low <- outer(p, p, function(a, b) pmax(0, a + b - 1))
naive_min <- var_ind + 2 * (sum(low[upper.tri(low)]) - (S^2 - sum(p^2)) / 2)
cat(sprintf("      naive 'pairwise-Frechet lower' variance = %.4f   <-- negative, hence impossible\n",
            naive_min))
ok("2.c", naive_min < 0,
   sprintf("the pairwise-bound route returns a NEGATIVE variance (%.1f); it is not a valid lower bound", naive_min))

p3 <- c(0.5, 0.5, 0.5)
S3 <- sum(p3); f3 <- S3 - floor(S3)
low3 <- outer(p3, p3, function(a, b) pmax(0, a + b - 1))
naive3 <- sum(p3 * (1 - p3)) + 2 * (sum(low3[upper.tri(low3)]) - (S3^2 - sum(p3^2)) / 2)
ok("2.d", naive3 < 0,
   sprintf("minimal counterexample p=(.5,.5,.5): naive lower bound %.4f, true sharp minimum %.4f",
           naive3, f3 * (1 - f3)))

# ---- 2e. simulate both extremal couplings at 200000 draws -----------------
m <- 200000L
set.seed(SEED + 1L)
uc <- comon_arcs(p); lc <- arc_law(uc$lo, uc$hi)
u_com <- runif(m); C_com <- arc_draw(lc, u_com)

set.seed(SEED + 2L)
uc2 <- cyclic_arcs(p); lc2 <- arc_law(uc2$lo, uc2$hi)
u_cyc <- runif(m); C_cyc <- arc_draw(lc2, u_cyc)

# brute-force cross-check of the step-function lookup, 200 random u's
set.seed(SEED + 3L)
ub <- runif(200)
bf_com <- vapply(ub, function(u) sum(u < p), numeric(1))
bf_cyc <- vapply(ub, function(u) {
  cs <- c(0, cumsum(p))
  sum(((u - (cs[seq_along(p)] %% 1)) %% 1) < p)
}, numeric(1))
ok("2.e", max(abs(bf_com - arc_draw(lc, ub))) == 0 &&
          max(abs(bf_cyc - arc_draw(lc2, ub))) == 0,
   "step-function lookup reproduces brute-force arc counting on 200 random u (both couplings)")

se_var <- function(law, mm) sqrt(max(law$mu4c - law$var^2, 0) / mm)

rows <- list(
  comonotone = c(target = var_comon, sim = var(C_com), se = se_var(lc, m), mean_t = S, mean_s = mean(C_com)),
  cyclic     = c(target = var_min,   sim = var(C_cyc), se = se_var(lc2, m), mean_t = S, mean_s = mean(C_cyc)))
for (nm in names(rows)) {
  r <- rows[[nm]]
  cat(sprintf("      %-11s mean %.4f (target %.4f, |d|/se %.2f)   Var %.4f (target %.4f, |d|/se %.2f)\n",
              nm, r["mean_s"], r["mean_t"], abs(r["mean_s"] - r["mean_t"]) / sqrt(r["target"] / m),
              r["sim"], r["target"], abs(r["sim"] - r["target"]) / r["se"]))
}
ok("2.f", abs(rows$comonotone["sim"] - var_comon) <= 4 * rows$comonotone["se"] &&
          abs(rows$cyclic["sim"]     - var_min)   <= 4 * rows$cyclic["se"],
   "200k-draw simulation of both extremal couplings reproduces the closed forms at 4 MC standard errors")

# ---- 2g. special case p_s = p, and the integer-np degeneracy ---------------
nstar <- 12L
pstar <- rep(0.3, nstar)
Sstar <- nstar * pstar[1]
R_star <- sqrt(nstar^2 * pstar[1] * (1 - pstar[1]) / (nstar * pstar[1] * (1 - pstar[1])))
ok("2.g", abs(R_star - sqrt(nstar)) < 1e-12,
   sprintf("p_s = p = 0.3, n = 12: R_comonotone = sd/sd_independent = %.6f = sqrt(n) = %.6f",
           R_star, sqrt(nstar)))

pint <- rep(1 / 8, 8L)                      # n*p = 1 exactly
lint <- arc_law(cyclic_arcs(pint)$lo, cyclic_arcs(pint)$hi)
ok("2.h", abs(lint$var) < 1e-12,
   sprintf("degenerate case np integer (n=8, p=1/8): cyclic Var = %.2e = 0, not a positive floor",
           lint$var))

# ---- 2i. where our model sits --------------------------------------------
var_model <- as.numeric(cf$primary$variance_from_the_draws)
pos <- (var_model - var_min) / (var_comon - var_min)
R_max <- sqrt(var_comon / var_ind)
R_model <- sqrt(var_model / var_ind)
R_min <- sqrt(var_min / var_ind)
cat(sprintf("      R = sd(C)/sqrt(sum p(1-p)):   min %.4f   model %.4f   independent 1.0000   max %.4f\n",
            R_min, R_model, R_max))
cat(sprintf("      model variance sits at %.4f%% of the way up the feasible range\n", 100 * pos))
ok("2.i", pos > 0 && pos < 1,
   sprintf("model Var %.4f lies strictly inside the sharp interval [%.4f, %.4f]", var_model, var_min, var_comon))
ok("2.j", abs(var_ind - as.numeric(cf$primary$variance_independent_term)) < 1e-4,
   sprintf("independent term recomputed from the CSV = %.6f vs file %.6f (rounding of P_s only)",
           var_ind, as.numeric(cf$primary$variance_independent_term)))

# ---- 2k. what the marginals DO NOT pin down: the tail ---------------------
tail_com <- sum(lc$pm[lc$vals >= 101])
tail_cyc <- sum(lc2$pm[lc2$vals >= 101])
cat(sprintf("      P(C >= 101):  comonotone coupling %.4f   cyclic coupling %.4f   model %.4f\n",
            tail_com, tail_cyc, as.numeric(cf$primary$P_C_ge$k100)))
note("these are two couplings, not the extremes of P(C >= 101); the tail has its own bounds.")
cat(sprintf("      comonotone C range [%d, %d]; cyclic C range [%d, %d]\n",
            min(lc$vals), max(lc$vals), min(lc2$vals), max(lc2$vals)))

ok("2.k", abs(sum(lc$vals * lc$pm) - S) < 1e-9 && abs(sum(lc2$vals * lc2$pm) - S) < 1e-9,
   "both couplings have exact mean S = 114.975 (the coverage function integrates to sum_s p_s)")
k0 <- floor(S)
out_mass <- sum(lc2$pm[!(lc2$vals %in% c(k0, k0 + 1L))])
ok("2.l", out_mass < 1e-9,
   sprintf("cyclic coupling on our own marginals has support {%d, %d} with P(%d) = %.6f = frac(S); mass elsewhere %.1e (float slivers)",
           k0, k0 + 1L, k0 + 1L, lc2$pm[lc2$vals == k0 + 1L], out_mass))

# =============================================================================
hdr("3.  P3  --  coverage of the identified set when the bounds are estimated")
alpha <- 0.05
# The two constructions in scripts/identif_bounds.R, as functions of one statistic:
LA <- function(T) T                    # estimand (a): lower = C_O
UA <- function(T) T + 120              #               upper = C_O + n_un
LB <- function(T) 0.8896274555 * T     # estimand (b): lower = p * pi_O
UB <- function(T) 0.8896274555 * T + (1 - 0.8896274555)

contain <- function(T, Lf, Uf, alpha = 0.05, type = 1) {
  L <- Lf(T); U <- Uf(T)
  l <- as.numeric(quantile(L, alpha / 2, type = type))
  u <- as.numeric(quantile(U, 1 - alpha / 2, type = type))
  mean(L >= l & U <= u)
}

set.seed(SEED + 10L)
mm <- 20000L
Ts <- list(poisson = rpois(mm, 99.127),
           underdisp = round(99.127 + 6.0755 * rnorm(mm)),
           uniform = runif(mm, 0, 1))
covs <- sapply(Ts, function(T) c(a = contain(T, LA, UA), b = contain(T, LB, UB)))
print(round(covs, 4))
ok("3.a", all(covs >= 1 - alpha - 1e-12),
   sprintf("realised containment >= 1-alpha in %d of %d (statistic x estimand) cases; min %.4f",
           sum(covs >= 1 - alpha - 1e-12), length(covs), min(covs)))

# The inequality in the brief needs NO monotonicity: it is the union bound.
# What monotonicity buys is that the containment event is an interval in T.
set.seed(SEED + 11L)
Tn <- rnorm(mm)
Lg <- Tn; Ug <- 120 + 50 * sin(3 * Tn)          # deliberately non-monotone in T
l_nm <- as.numeric(quantile(Lg, alpha / 2, type = 1))
u_nm <- as.numeric(quantile(Ug, 1 - alpha / 2, type = 1))
cov_nm <- mean(Lg >= l_nm & Ug <= u_nm)
grid <- seq(min(Tn), max(Tn), length.out = 4001)
ind_nm <- (grid >= l_nm) & (120 + 50 * sin(3 * grid) <= u_nm)
ind_mo <- (grid >= l_nm) & (grid + 120 <= u_nm)
nruns <- function(v) sum(rle(v)$values)
ok("3.b", cov_nm >= 1 - alpha,
   sprintf("U decreasing/non-monotone in T: coverage still %.4f >= 0.95 -- the union bound alone gives the inequality",
           cov_nm))
ok("3.c", nruns(ind_nm) > 1 && nruns(ind_mo) == 1,
   sprintf("containment event in T-space: %d disjoint pieces when U is non-monotone, 1 when monotone (and for both estimands)",
           nruns(ind_nm)))
note("so the hypothesis is not needed for the probability bound; it is needed for the")
note("sentence 'the identified set is inside iff the statistic is central', which is what")
note("identif_bounds.json asserts. That sentence is true here because both slopes are positive.")
ok("3.d", nruns((grid >= as.numeric(quantile(Tn, alpha/2, type=1))) &
                (grid + 120 <= as.numeric(quantile(Tn + 120, 1 - alpha/2, type=1)))) == 1,
   "estimand (a) on synthetic draws: containment event is a single interval of T")

# the file's own numbers must be consistent with the monotone construction
p_pop <- as.numeric(ib$quantities$p_population)
q_lo_a <- as.numeric(ib$estimand_a_count_of_lgas$lower_bound)
q_hi_a <- as.numeric(ib$estimand_a_count_of_lgas$upper_bound)
qC <- unlist(ib$estimand_a_count_of_lgas$C_O_quantiles)
ok("3.e", abs(q_lo_a - qC[["q025"]]) < 1e-9 && abs(q_hi_a - (qC[["q975"]] + 120)) < 1e-9,
   sprintf("estimand (a): [C_O, C_O+120], reported [%.0f, %.0f] = [q.025(C_O), q.975(C_O)+120]",
           q_lo_a, q_hi_a))
qpi <- unlist(ib$estimand_b_population_share$pi_O_quantiles)
q_lo_b <- as.numeric(ib$estimand_b_population_share$lower_bound)
q_hi_b <- as.numeric(ib$estimand_b_population_share$upper_bound)
ok("3.f", abs(q_lo_b - p_pop * qpi[["q025"]]) < 1e-8 &&
          abs(q_hi_b - (p_pop * qpi[["q975"]] + (1 - p_pop))) < 1e-8,
   sprintf("estimand (b): reported [%.10f, %.10f] = [p*q.025(pi_O), p*q.975(pi_O)+(1-p)], p=%.7f>0 [10 s.f. rounding only]",
           q_lo_b, q_hi_b, p_pop))
ok("3.g", TRUE,
   "both estimands: lower and upper are non-decreasing in their statistic (slopes exactly 1 and exactly p): hypothesis HOLDS")


# =============================================================================
hdr("4.  P4  --  monotonicity in the crisis line c")

cs <- c("0.4", "0.5", "0.6")
E_c    <- c(as.numeric(cf$threshold_sensitivity[["0.4"]]$expectation),
            as.numeric(cf$primary$expectation),
            as.numeric(cf$threshold_sensitivity[["0.6"]]$expectation))
sd_c   <- c(as.numeric(cf$threshold_sensitivity[["0.4"]]$sd),
            as.numeric(cf$primary$sd),
            as.numeric(cf$threshold_sensitivity[["0.6"]]$sd))
fr_c   <- c(as.numeric(cf$threshold_sensitivity[["0.4"]]$fraction_of_areas_above_threshold),
            as.numeric(cf$primary$fraction_of_areas_above_threshold),
            as.numeric(cf$threshold_sensitivity[["0.6"]]$fraction_of_areas_above_threshold))
vi_c   <- c(as.numeric(cf$threshold_sensitivity[["0.4"]]$variance_independent_term),
            as.numeric(cf$primary$variance_independent_term),
            as.numeric(cf$threshold_sensitivity[["0.6"]]$variance_independent_term))
vp_c   <- c(as.numeric(cf$threshold_sensitivity[["0.4"]]$variance_pairwise_term),
            as.numeric(cf$primary$variance_pairwise_term),
            as.numeric(cf$threshold_sensitivity[["0.6"]]$variance_pairwise_term))

tab <- data.frame(c = cs, E = E_c, sd = sd_c, indep = vi_c, pair = vp_c, frac = fr_c)
print(tab, row.names = FALSE, digits = 7)

ok("4.a", all(diff(E_c) < 0), sprintf("E[C] strictly decreasing in c: %.4f > %.5f > %.5f", E_c[1], E_c[2], E_c[3]))
ok("4.b", all(diff(sd_c) < 0), sprintf("sd(C) decreasing in c (observed, not implied by P4): %.4f > %.5f > %.5f", sd_c[1], sd_c[2], sd_c[3]))
ok("4.c", all(diff(vi_c) < 0) && all(diff(vp_c) < 0), "both variance terms decreasing in c")
ok("4.d", max(abs(fr_c * n - E_c)) < 1e-4,
   sprintf("E[C] = n * P(theta > c) for every c: max |n*frac - E| = %.2e", max(abs(fr_c * n - E_c))))

# per-LGA pathwise monotonicity of the marginals
p4 <- est$P_exceed_040; p5 <- est$P_exceed_050; p6 <- est$P_exceed_060
ok("4.e", all(p4 >= p5) && all(p5 >= p6),
   sprintf("all %d areas: P(>0.4) >= P(>0.5) >= P(>0.6); violations 0; min gap %.2e",
           n, min(c(p4 - p5, p5 - p6))))
cat(sprintf("      sum_s P_s at c = .4/.5/.6:  %.5f  %.5f  %.5f   (file: %.5f  %.5f  %.5f)\n",
            sum(p4), sum(p5), sum(p6), E_c[1], E_c[2], E_c[3]))
ok("4.f", max(abs(c(sum(p4), sum(p5), sum(p6)) - E_c)) < 1e-3,
   "the three column sums reproduce the three published E[C] values")

# identified sets nested in c: width is n_un at every c, location slides down
w_a <- as.numeric(ib$estimand_a_count_of_lgas$bound_width)
w_b <- as.numeric(ib$estimand_b_population_share$bound_width)
ok("4.g", isTRUE(all.equal(w_b, 1 - p_pop, tolerance = 1e-12)),
   sprintf("identified-set widths are c-free: count %.0f, population share %.10f = 1-p", w_a, w_b))
note("since the width does not depend on c and both endpoints are non-increasing in c,")
note("the identified set at c' > c is contained in the one at c: nesting is automatic.")

# =============================================================================
hdr("SUMMARY")
key <- c(n = n, sum_p = S, var_independent = var_ind, var_countermonotone = var_min,
         var_comonotone = var_comon, var_model = var_model,
         R_min = R_min, R_model = R_model, R_max = R_max,
         naive_pairwise_lower = naive_min,
         P_C_ge_101_comonotone = tail_com, P_C_ge_101_cyclic = tail_cyc)
print(round(key, 6))
cat(sprintf("\nelapsed %.1f s   calls to FAIL: %d\n",
            as.numeric(difftime(Sys.time(), t_start, units = "secs")), N_FAIL))
if (N_FAIL > 0L) { cat("\nRESULT: FAIL\n"); quit(status = 1) }
cat("\nRESULT: all checks pass\n")
