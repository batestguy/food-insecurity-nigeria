#!/usr/bin/env Rscript
# scripts/calibration_spatial.R -- T12.  Leave-one-zone-out calibration of the LGA intervals.
#
# One command reproduces every number this ticket reports:
#     Rscript scripts/calibration_spatial.R
#
# ============================================================================
# THE QUESTION, AND WHAT WOULD ANSWER IT
# ============================================================================
# The LGA model reports 95% intervals (101-130 for the count of LGAs above the
# 50% line).  Nothing has ever shown those intervals cover anything.  This
# script removes one of Nigeria's six geopolitical zones at a time, refits the
# SAME model on the remaining five, and asks whether the held-out intervals
# contain the held-out truth.
#
# Leave-one-ZONE-out, not leave-one-state-out, because the zones are contiguous:
# removing a whole zone removes most of the spatial neighbours of every held-out
# LGA, which is the hard case.  States nest inside zones, so every state and
# every LGA is predicted out of sample exactly once.  Six refits is affordable;
# 37 is not, and would be a weaker test because a state's neighbours would stay
# in the fit.
#
# ============================================================================
# PRE-DECLARED PASS RULE -- fixed before any fold was fitted
# ============================================================================
# Primary, pooling all six folds (each of the 654 LGAs with a direct estimate
# contributes exactly once):
#
#   | check                  | pass range        |
#   |------------------------|-------------------|
#   | mean of z              | [-0.15, +0.15]    |
#   | sd of z                | [ 0.85,  1.15]    |
#   | share with |z| <= 1.96 | [ 0.90,  0.98]    |
#
# where  z = (model_mean - direct_unweighted) / sqrt(model_var + design_var),
# model_var = ((ci_high - ci_low) / (2 * 1.96))^2.
#
# THIS RULE IS NOT REVISED AFTER THE NUMBERS APPEAR.  A failure is reported as a
# failure.  Do not re-fit, soften the rule, or change the estimand to get a pass.
#
# The naive check "is the direct estimate inside the model interval" is NOT the
# criterion and must not be used: the direct estimate carries its own sampling
# error, so that check under-covers by construction.
#
# ============================================================================
# DECLARED BEFORE THE RUN: three choices the brief leaves to the script
# ============================================================================
# (A) INTERVAL CONSTRUCTION.  Marginal posterior of the linear predictor, no
#     Monte Carlo draws.  For LGA s, INLA returns the marginal posterior of the
#     prediction row's linear predictor eta_s = xbar_s'beta + u_s; we take its
#     mean m_s and sd s_s from summary.linear.predictor and treat it as
#     Gaussian on the logit scale (which is INLA's own approximation to that
#     marginal).  Over a 2001-point standard-normal probability grid
#     u = (1e-4, ..., 1-1e-4), q = qnorm(u), eta = m_s + s_s*q, the reported
#     prevalence is
#         theta(u) = SUM_k GH_W[k] * expit(eta + sqrt(2) * sd_v * GH_X[k])
#     exactly as scripts/lga_model.R marginalises the cluster effect (same
#     7-point Gauss-Hermite nodes and weights).  Because the grid is uniform in
#     probability space, the u=0.025 and u=0.975 grid values ARE the 2.5% and
#     97.5% quantiles of theta, evaluated by linear interpolation on the grid.
#     sd_v is the posterior mean of the cluster-effect sd, from
#     summary.hyperpar (1/sqrt(mean precision)); the main script uses the mean
#     of the draw-wise sd instead, a Jensen difference of order 1%.
#     Deterministic, hence reproducible and free of Monte Carlo noise.
#
# (B) DESIGN VARIANCE.  Cluster-robust variance of the direct proportion by
#     ratio linearisation, strata = state, PSU = cluster (hv001):
#         u_c = SUM_{i in c} (y_i - p),   p = SUM y_i / SUM n_i
#         var(p) = (1/N^2) * SUM_h [n_h/(n_h-1)] * SUM_{c in h} (u_c - ubar_h)^2
#     Because an LGA lies wholly inside one state, only one stratum is non-empty
#     per LGA and the between-stratum term vanishes; the estimator therefore
#     reduces to the LGA's own clusters as PSUs.
#     SINGLE-CLUSTER LGAs: the estimator is undefined for n_h = 1 (zero residual
#     degrees of freedom).  Rather than delete 260 of the 654 LGAs, or fall back
#     to the binomial variance (which ignores clustering and would inflate |z|,
#     manufacturing a failure), a single-cluster LGA gets
#         design_var = deff_median * p(1-p)/n
#     with deff_median the median of design_var/(p(1-p)/n) over the fold's
#     multi-cluster LGAs, floored at 1.  Flagged per row in
#     `design_se_source`.  The z-check restricted to multi-cluster LGAs is
#     reported as a sensitivity, NOT as a substitute for the primary rule.
#
# (C) STATE AND ZONE COVERAGE (secondary, reported whatever happens).  LGA
#     posteriors are aggregated to the state / zone with household-count
#     weights; the aggregate variance is the weighted sum of LGA variances
#     treating LGAs as independent.  LGAs are NOT independent under BYM2, so
#     this interval is too narrow and the coverage count is biased AGAINST the
#     model.  Stated here so a pass cannot be claimed as generous.
#
# ============================================================================
# COVARIATES ARE HELD KNOWN
# ============================================================================
# The prediction row for every LGA uses that LGA's mean covariate profile from
# the FULL household file, including held-out LGAs.  So this tests the outcome
# model and the spatial field, NOT covariate availability.  In the real problem
# the 120 unclustered LGAs borrow their profile from the parent state; the same
# fallback is used here, from the full file (one fold may therefore see a
# parent-state profile built partly from held-out households).  Disclosed, not
# hidden.
#
# OUT OF SCOPE: count-functional calibration.  That needs joint draws per fold
# and is not attempted; it stays listed as unproven.
# ============================================================================

suppressPackageStartupMessages({
  library(sf)
  library(spdep)
  library(INLA)
  library(jsonlite)
})
sf_use_s2(TRUE)

SEED      <- 20261123L
GH_N      <- 7L
GRID_N    <- 2001L
FIT_LIMIT <- 300          # seconds per fold; the brief says stop and report beyond this

root <- normalizePath(".")
p_hh    <- file.path(root, "data/derived/analysis_households_lga.csv")
p_bound <- file.path(root, "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson")
p_pop   <- file.path(root, "data/derived/lga_population.csv")
p_folds <- file.path(root, "data/derived/calibration_folds.csv")
p_sum   <- file.path(root, "data/derived/calibration_summary.json")

for (f in c(p_hh, p_bound, p_pop)) {
  if (!file.exists(f)) stop("missing input: ", f, " -- run from the repo root", call. = FALSE)
}

msg  <- function(...) cat(sprintf(...), "\n", sep = "")
tick <- function(t0) round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)
prog <- function(...) {
  line <- paste0(format(Sys.time(), "%H:%M"), "  ", sprintf(...), "\n")
  cat(line, sep = "")
  try(cat(line, sep = "", file = file.path(root, ".agent/T12-progress.md"), append = TRUE),
      silent = TRUE)
}

set.seed(SEED)
t_all <- Sys.time()

## ==========================================================================
## 1. The zone map.  DECLARED, not derived from the data: Nigeria's six
##    geopolitical zones are an administrative fact, so it is written out here
##    in full and printed, and the script asserts that the 37 jurisdictions in
##    the household file land in exactly one zone each.  The codes are checked
##    against the file, not assumed: an unknown or absent code stops the run.
## ==========================================================================
ZONE_OF_STATE <- c(
  "NG-JI" = "North West", "NG-KD" = "North West", "NG-KN" = "North West",
  "NG-KT" = "North West", "NG-KE" = "North West", "NG-SO" = "North West",
  "NG-ZA" = "North West",
  "NG-AD" = "North East", "NG-BA" = "North East", "NG-BO" = "North East",
  "NG-GO" = "North East", "NG-TA" = "North East", "NG-YO" = "North East",
  "NG-BE" = "North Central", "NG-KO" = "North Central", "NG-KW" = "North Central",
  "NG-NA" = "North Central", "NG-NI" = "North Central", "NG-PL" = "North Central",
  "NG-FC" = "North Central",
  "NG-EK" = "South West", "NG-LA" = "South West", "NG-OG" = "South West",
  "NG-ON" = "South West", "NG-OS" = "South West", "NG-OY" = "South West",
  "NG-AB" = "South East", "NG-AN" = "South East", "NG-EB" = "South East",
  "NG-EN" = "South East", "NG-IM" = "South East",
  "NG-AK" = "South South", "NG-BY" = "South South", "NG-CR" = "South South",
  "NG-DE" = "South South", "NG-ED" = "South South", "NG-RI" = "South South"
)
ZONES <- c("North West", "North East", "North Central",
           "South West", "South East", "South South")

## ==========================================================================
## 2. The data
## ==========================================================================
COV <- c("wealth_z", "hh_size", "urban", "head_male", "head_age_c", "head_age_c2",
         "head_edu_secondary", "head_edu_higher", "improved_water",
         "improved_sanitation")
NEED <- c("severe_fi", "hv005", "hv001", "lga_id", "state_iso", COV)

hdr <- scan(p_hh, what = "", sep = ",", nlines = 1L, quote = "\"", quiet = TRUE)
absent <- setdiff(NEED, hdr)
if (length(absent)) stop("missing columns: ", paste(absent, collapse = ", "), call. = FALSE)
cc <- ifelse(hdr %in% NEED, NA_character_, "NULL")
d  <- read.csv(p_hh, colClasses = cc, check.names = FALSE, stringsAsFactors = FALSE)
msg("households: %d | columns kept: %d of %d", nrow(d), length(NEED), length(hdr))

if (anyNA(d$severe_fi)) stop("severe_fi has NA", call. = FALSE)
if (anyNA(d[COV]))      stop("a covariate has NA", call. = FALSE)
if (!all(d$severe_fi %in% c(0, 1))) stop("severe_fi is not 0/1", call. = FALSE)
if (anyNA(d$state_iso)) stop("state_iso has NA -- a household cannot be assigned to a zone", call. = FALSE)

## ---- the zone mapping, printed and checked ---------------------------------
states_in_data <- sort(unique(d$state_iso))
unknown <- setdiff(states_in_data, names(ZONE_OF_STATE))
unused  <- setdiff(names(ZONE_OF_STATE), states_in_data)
if (length(unknown))
  stop("state_iso value(s) with no declared zone: ", paste(unknown, collapse = ", "), call. = FALSE)
if (length(unused))
  stop("declared state(s) absent from the data: ", paste(unused, collapse = ", "), call. = FALSE)

d$zone <- unname(ZONE_OF_STATE[d$state_iso])
if (anyNA(d$zone)) stop("a household has no zone", call. = FALSE)

zone_tab <- table(factor(d$zone, levels = ZONES))
msg("\n===== ZONE MAP (declared, then checked against state_iso) =====")
for (z in ZONES) {
  st <- sort(unique(d$state_iso[d$zone == z]))
  msg("%-14s %d states: %s", z, length(st), paste(st, collapse = " "))
}
msg("total jurisdictions: %d | total states mapped: %d | zones: %d",
    length(states_in_data), length(ZONE_OF_STATE), length(ZONES))
stopifnot(length(states_in_data) == 37L, length(ZONE_OF_STATE) == 37L,
          identical(sort(names(ZONE_OF_STATE)), states_in_data))
msg("check: all 37 states land in exactly one zone (each appears once above), sum %d households",
    sum(zone_tab))
print(zone_tab)
prog("zone map printed, 37 states in 6 zones, all land once")

## ==========================================================================
## 3. The spatial graph -- built ONCE from the full boundary file, because it
##    depends only on geometry and never on the outcome or on which households
##    survive a fold.  Keeping all 774 nodes in every fold is what lets the
##    ICAR prior carry information from observed neighbours into a held-out
##    zone; dropping the zone's nodes instead would leave no neighbour structure
##    to predict from and would be a different (and uninteresting) model.  So
##    removing a zone cannot disconnect the graph, and the connectivity check
##    below is a verification, not a hope.
## ==========================================================================
g <- st_make_valid(st_read(p_bound, quiet = TRUE))
if (nrow(g) != 774L) stop("expected 774 LGA polygons, got ", nrow(g), call. = FALSE)
if (anyDuplicated(g$shapeID)) stop("duplicate shapeID", call. = FALSE)
LGA_ID <- g$shapeID
n_lga  <- length(LGA_ID)

nb <- poly2nb(g, queen = TRUE)
if (length(nb) != n_lga) stop("graph node count != LGA count", call. = FALSE)
deg  <- card(nb)
comp <- n.comp.nb(nb)
msg("\nLGA graph: %d nodes, %d edges, %d component(s), %d isolate(s)",
    n_lga, sum(deg) / 2, comp$nc, sum(deg == 0))
if (sum(deg == 0)) stop("graph has isolates; BYM2 is improper there", call. = FALSE)
if (comp$nc != 1L) stop("graph is disconnected (", comp$nc, " components)", call. = FALSE)
nb_path <- file.path(tempdir(), "lga_graph_calib.adj")
nb2INLA(nb_path, nb)
gr <- inla.read.graph(nb_path)
msg("INLA graph: %d nodes, %d edges", gr$n, sum(gr$nnbs) / 2)

## ---- LGA -> state -> zone --------------------------------------------------
pop <- read.csv(p_pop, stringsAsFactors = FALSE)
state_of_lga <- pop$state_iso[match(LGA_ID, pop$lga_id)]
if (anyNA(state_of_lga)) stop("an LGA has no parent state in lga_population.csv", call. = FALSE)
zone_of_lga <- unname(ZONE_OF_STATE[state_of_lga])
if (anyNA(zone_of_lga)) stop("an LGA's state has no declared zone", call. = FALSE)
lga_name <- g$shapeName
msg("LGAs by zone: %s", paste(sprintf("%s %d", names(table(zone_of_lga)), as.integer(table(zone_of_lga))),
                              collapse = ", "))

## ==========================================================================
## 4. Covariate profiles, held KNOWN from the full file
## ==========================================================================
lga_idx_full <- match(d$lga_id, LGA_ID)
if (anyNA(lga_idx_full)) stop("household lga_id not in the boundary file", call. = FALSE)
X_full <- as.matrix(d[, COV]); storage.mode(X_full) <- "double"
y_full <- as.integer(d$severe_fi)

n_hh_lga <- as.numeric(tabulate(lga_idx_full, nbins = n_lga))

Xbar <- matrix(NA_real_, n_lga, ncol(X_full), dimnames = list(NULL, COV))
for (k in seq_len(ncol(X_full))) {
  Xbar[, k] <- as.numeric(tapply(X_full[, k], factor(lga_idx_full, levels = seq_len(n_lga)), mean))
}
states_all <- sort(unique(state_of_lga))
Xbar_state <- matrix(NA_real_, length(states_all), ncol(X_full))
for (j in seq_along(states_all)) {
  in_s <- state_of_lga[lga_idx_full] == states_all[j]
  if (any(in_s)) Xbar_state[j, ] <- colMeans(X_full[in_s, , drop = FALSE])
}
no_data <- which(n_hh_lga == 0L)
for (i in no_data) {
  j <- match(state_of_lga[i], states_all)
  if (anyNA(Xbar_state[j, ])) stop("parent state of an empty LGA has no households", call. = FALSE)
  Xbar[i, ] <- Xbar_state[j, ]
}
if (anyNA(Xbar)) stop("covariate profile still has NA", call. = FALSE)
msg("\nLGAs: %d with households, %d using the parent-state covariate profile (from the full file)",
    n_lga - length(no_data), length(no_data))

## ---- Gauss-Hermite rule, identical to scripts/lga_model.R ------------------
GH_X <- c(-2.651961356835233, -1.673551628767471, -0.8162878828589647, 0,
           0.8162878828589647,  1.673551628767471,  2.651961356835233)
GH_W <- c( 0.0009717812450995192, 0.05451558281912703, 0.4256072526101278,
           0.8102646175568073,   0.4256072526101278,  0.05451558281912703,
           0.0009717812450995192) / sqrt(pi)
stopifnot(GH_N == length(GH_X), abs(sum(GH_W) - 1) < 1e-14)

## probability grid: uniform in u, so theta(u) IS the u-quantile of theta
U_GRID <- seq(1e-4, 1 - 1e-4, length.out = GRID_N)
Q_GRID <- qnorm(U_GRID)

## ==========================================================================
## 5. Design variance of a direct LGA proportion
## ==========================================================================
design_var <- function(y, clu, state) {
  # ratio linearisation, PSU = cluster, strata = state.  An LGA lies wholly in one
  # state, so one stratum is non-empty and this reduces to the LGA's own clusters.
  N <- length(y)
  p <- sum(y) / N
  uc <- tapply(y - p, clu, sum)          # PSU totals of the linearised variable
  h  <- as.character(tapply(as.character(state), clu, function(v) v[1L]))  # stratum of each PSU
  u_h <- split(uc, h)
  term <- vapply(u_h, function(u) {
    n_h <- length(u)
    if (n_h < 2L) return(NA_real_)
    (n_h / (n_h - 1)) * sum((u - mean(u))^2)
  }, numeric(1))
  if (anyNA(term)) return(NA_real_)
  sum(term) / N^2
}

## ==========================================================================
## 6. Fold machinery, written to disk fold by fold (resumable)
## ==========================================================================
COLS <- c("lga_id", "lga_name", "state_iso", "zone", "fold", "model_mean", "ci_low", "ci_high",
          "direct_unweighted", "direct_weighted", "design_se", "design_se_source",
          "n_households", "n_clusters", "z", "has_direct",
          "fold_fit_seconds", "fold_waic", "fold_mode_status", "fold_sd_cluster",
          "fold_deff_median", "fold_n_training", "fold_n_clusters")

existing <- NULL
done_zones <- character(0)
if (file.exists(p_folds)) {
  existing <- read.csv(p_folds, stringsAsFactors = FALSE, check.names = FALSE)
  done_zones <- unique(existing$zone)
  msg("\nresuming: %s already holds %d rows from zone(s): %s",
      basename(p_folds), nrow(existing), paste(done_zones, collapse = ", "))
}

fit_fold <- function(z, k) {
  keep <- d$zone != z
  dt   <- d[keep, , drop = FALSE]
  if (!nrow(dt)) stop("zone ", z, " holds every household -- nothing left to fit", call. = FALSE)

  lga_idx <- match(dt$lga_id, LGA_ID)
  clu_levels <- sort(unique(dt$hv001))
  clu_idx <- match(dt$hv001, clu_levels)
  n_clu <- length(clu_levels)
  n_tr  <- nrow(dt)

  dat <- data.frame(y = as.integer(dt$severe_fi), as.matrix(dt[, COV]),
                    lga = lga_idx, clu = clu_idx)
  names(dat) <- c("y", COV, "lga", "clu")
  pred_rows <- data.frame(y = NA_real_, Xbar, lga = seq_len(n_lga), clu = NA_integer_)
  names(pred_rows) <- names(dat)
  dat_aug <- rbind(dat, pred_rows)
  form <- as.formula(paste("y ~ 1 +", paste(COV, collapse = " + ")))

  msg("\n--- fold %d: %s (held out) ---", k, z)
  msg("training: %d households of %d (%.1f%%), %d clusters, %d LGAs with data",
      n_tr, nrow(d), 100 * n_tr / nrow(d), n_clu, length(unique(lga_idx)))

  t0 <- Sys.time()
  fit <- inla(
    update(form, . ~ . + f(lga, model = "bym2", graph = gr) + f(clu, model = "iid")),
    family = "binomial", data = dat_aug,
    control.compute = list(waic = TRUE, dic = TRUE),
    control.predictor = list(compute = TRUE)
  )
  t_fit <- tick(t0)

  ms <- if (is.null(fit$mode$mode.status)) NA_integer_ else as.integer(fit$mode$mode.status)
  sd_v <- {
    hp <- fit$summary.hyperpar
    r  <- grep("Precision for clu", rownames(hp), fixed = TRUE)
    if (length(r) != 1L) r <- grep("clu", rownames(hp), ignore.case = TRUE)
    if (length(r) != 1L) stop("cannot identify the cluster precision in: ",
                              paste(rownames(hp), collapse = " | "), call. = FALSE)
    1 / sqrt(hp[r, "mean"])
  }
  msg("fold %d fitted in %.1f s | mode status %s | WAIC %.2f | sd(cluster) %.4f",
      k, t_fit, paste(ms, collapse = ","), fit$waic$waic, sd_v)
  if (t_fit > FIT_LIMIT)
    stop("fold ", z, " took ", t_fit, " s, above the ", FIT_LIMIT,
         " s limit; stopping rather than burning the budget on six", call. = FALSE)

  ## ---- the marginal of theta, from the marginal of eta --------------------
  slp <- fit$summary.linear.predictor
  idx <- n_tr + seq_len(n_lga)
  m_s <- slp[idx, "mean"]
  s_s <- slp[idx, "sd"]
  if (anyNA(m_s) || anyNA(s_s))
    stop("linear predictor summary has NA on a prediction row (fold ", z, ")", call. = FALSE)

  TH  <- matrix(0, n_lga, GRID_N)
  for (k2 in seq_len(GH_N)) {
    shift <- sqrt(2) * sd_v * GH_X[k2]
    TH <- TH + GH_W[k2] * plogis(outer(s_s, Q_GRID) + m_s + shift)
  }
  model_mean <- rowMeans(TH)
  ci_low  <- apply(TH, 1, function(v) approx(U_GRID, v, 0.025)$y)
  ci_high <- apply(TH, 1, function(v) approx(U_GRID, v, 0.975)$y)
  if (anyNA(TH) || any(TH < 0) || any(TH > 1)) stop("theta outside [0,1]", call. = FALSE)
  if (any(ci_low > model_mean) || any(model_mean > ci_high)) stop("quantiles out of order", call. = FALSE)

  ## ---- the truth, from the held-out households only ----------------------
  hz <- d[!keep, , drop = FALSE]
  hz$lga_idx <- match(hz$lga_id, LGA_ID)
  lv <- seq_len(n_lga)

  dh <- hz[hz$zone == z, , drop = FALSE]
  if (nrow(dh) != sum(!keep)) stop("held-out subset does not match the drop mask", call. = FALSE)

  direct_u <- rep(NA_real_, n_lga); direct_w <- rep(NA_real_, n_lga)
  dvar     <- rep(NA_real_, n_lga); dsrc     <- rep(NA_character_, n_lga)
  n_hh_out <- as.numeric(tabulate(dh$lga_idx, nbins = n_lga))
  # distinct CLUSTERS per LGA, not households: tabulating dh$lga_id directly would
  # count household rows (that is the duplicate-n_clusters defect in lga_estimates.csv)
  cl_keys  <- unique(dh[, c("lga_id", "hv001")])
  n_cl_out <- as.numeric(table(factor(cl_keys$lga_id, levels = LGA_ID)))
  if (sum(n_cl_out) != nrow(cl_keys))
    stop("cluster counts do not sum to the number of distinct clusters", call. = FALSE)
  if (any(n_cl_out > n_hh_out)) stop("an LGA has more clusters than households", call. = FALSE)

  for (i in which(n_hh_out > 0)) {
    ii <- dh$lga_idx == i
    yy <- as.integer(dh$severe_fi[ii]); ww <- dh$hv005[ii]
    cl <- dh$hv001[ii]; st <- dh$state_iso[ii]
    direct_u[i] <- mean(yy)
    direct_w[i] <- sum(ww * yy) / sum(ww)
    v <- design_var(yy, cl, st)
    if (is.na(v)) { dvar[i] <- NA_real_; dsrc[i] <- "single_cluster_pending" }
    else          { dvar[i] <- v;       dsrc[i] <- "cluster_robust" }
  }

  ## deff imputation for single-cluster LGAs, pre-declared in the header
  ok <- which(!is.na(dvar) & dvar > 0 & n_hh_out > 0)
  deff <- dvar[ok] / (direct_u[ok] * (1 - direct_u[ok]) / n_hh_out[ok])
  deff_med <- if (length(deff)) max(1, median(deff, na.rm = TRUE)) else 1
  single <- which(dsrc == "single_cluster_pending")
  if (length(single)) {
    pb <- pmin(pmax(direct_u[single], 1e-6), 1 - 1e-6)
    dvar[single] <- deff_med * pb * (1 - pb) / n_hh_out[single]
    dsrc[single] <- "deff_imputed"
  }
  msg("design variance: %d cluster-robust, %d deff-imputed (median deff %.3f), %d none",
      sum(dsrc == "cluster_robust", na.rm = TRUE), sum(dsrc == "deff_imputed", na.rm = TRUE),
      deff_med, sum(n_hh_out == 0))

  ## ---- the held-out zone's block ----------------------------------------
  zi <- which(zone_of_lga == z)
  model_var <- ((ci_high - ci_low) / (2 * 1.96))^2
  zz <- ifelse(is.na(direct_u), NA_real_,
               (model_mean - direct_u) / sqrt(model_var + dvar))

  block <- data.frame(
    lga_id = LGA_ID[zi], lga_name = lga_name[zi], state_iso = state_of_lga[zi],
    zone = z, fold = k,
    model_mean = model_mean[zi], ci_low = ci_low[zi], ci_high = ci_high[zi],
    direct_unweighted = direct_u[zi], direct_weighted = direct_w[zi],
    design_se = sqrt(dvar[zi]), design_se_source = dsrc[zi],
    n_households = n_hh_out[zi], n_clusters = n_cl_out[zi],
    z = zz[zi], has_direct = !is.na(direct_u[zi]),
    fold_fit_seconds = t_fit, fold_waic = fit$waic$waic, fold_mode_status = ms,
    fold_sd_cluster = sd_v, fold_deff_median = deff_med,
    fold_n_training = n_tr, fold_n_clusters = n_clu,
    stringsAsFactors = FALSE
  )
  block$design_se_source[is.na(block$design_se_source)] <- "none"

  ## ---- write THIS fold to disk before moving on --------------------------
  out <- if (is.null(existing)) block else rbind(existing[, COLS], block[, COLS])
  out <- out[order(out$fold, match(out$lga_id, LGA_ID)), COLS]
  write.csv(out, p_folds, row.names = FALSE)
  existing <<- out
  msg("wrote %d rows for %s | file now holds %d rows, %d zones",
      nrow(block), z, nrow(out), length(unique(out$zone)))
  prog("fold %d (%s) fitted in %.0f s, %d LGAs predicted (%d with a direct estimate), block written",
       k, z, t_fit, nrow(block), sum(block$has_direct))

  list(zone = z, fold = k, n_train = n_tr, n_clu = n_clu, t_fit = t_fit,
       mode_status = ms, waic = fit$waic$waic, sd_v = sd_v, deff_med = deff_med,
       n_block = nrow(block), n_direct = sum(block$has_direct),
       n_single = length(single))
}

## ==========================================================================
## 7. Run the six folds
## ==========================================================================
folds <- vector("list", length(ZONES))
for (k in seq_along(ZONES)) {
  z <- ZONES[k]
  if (z %in% done_zones) { msg("\n--- fold %d: %s already on disk, skipped ---", k, z); next }
  folds[[k]] <- fit_fold(z, k)
}

## ==========================================================================
## 8. Pooled checks, fixed pass rule
## ==========================================================================
R <- read.csv(p_folds, stringsAsFactors = FALSE, check.names = FALSE)
R <- R[order(R$fold, match(R$lga_id, LGA_ID)), ]
if (nrow(R) != n_lga) stop("expected ", n_lga, " rows, have ", nrow(R),
                           " -- not every LGA predicted exactly once", call. = FALSE)
if (anyDuplicated(R$lga_id)) stop("an LGA appears more than once", call. = FALSE)
if (length(unique(R$zone)) != 6L) stop("not all six zones present", call. = FALSE)

zz <- R$z[!is.na(R$z)]
n_z <- length(zz)
mean_z <- mean(zz); sd_z <- sd(zz)
cov_z  <- mean(abs(zz) <= 1.96)

PASS <- list(
  mean_z = c(-0.15, 0.15),
  sd_z   = c(0.85, 1.15),
  coverage = c(0.90, 0.98)
)
chk <- function(v, band) v >= band[1] && v <= band[2]

msg("\n===== POOLED CALIBRATION, %d LGAs with a direct estimate =====", n_z)
msg("mean of z            = %+0.4f   pass band [%+.2f, %+.2f]   %s",
    mean_z, PASS$mean_z[1], PASS$mean_z[2], if (chk(mean_z, PASS$mean_z)) "PASS" else "FAIL")
msg("sd of z              =  %0.4f   pass band [ %.2f,  %.2f]   %s",
    sd_z, PASS$sd_z[1], PASS$sd_z[2], if (chk(sd_z, PASS$sd_z)) "PASS" else "FAIL")
msg("share |z| <= 1.96    =  %0.4f   pass band [ %.2f,  %.2f]   %s",
    cov_z, PASS$coverage[1], PASS$coverage[2], if (chk(cov_z, PASS$coverage)) "PASS" else "FAIL")
all_pass <- chk(mean_z, PASS$mean_z) && chk(sd_z, PASS$sd_z) && chk(cov_z, PASS$coverage)
msg("ALL THREE CHECKS: %s", if (all_pass) "PASS" else "FAIL")

## sensitivity: multi-cluster LGAs only (the subset where design_var is defined)
mc <- !is.na(R$z) & R$design_se_source == "cluster_robust"
sens_mc <- list(n = sum(mc), mean_z = mean(R$z[mc]), sd_z = sd(R$z[mc]),
                coverage = mean(abs(R$z[mc]) <= 1.96))
msg("\nsensitivity, %d multi-cluster LGAs only: mean %+0.4f | sd %.4f | coverage %.4f",
    sens_mc$n, sens_mc$mean_z, sens_mc$sd_z, sens_mc$coverage)

## sensitivity: per-fold
per_fold <- lapply(ZONES, function(z) {
  v <- R$z[!is.na(R$z) & R$zone == z]
  list(zone = z, n = length(v), mean_z = mean(v), sd_z = sd(v),
       coverage = mean(abs(v) <= 1.96))
})
msg("\nby zone:")
for (p in per_fold)
  msg("  %-14s n=%3d  mean %+0.3f  sd %0.3f  coverage %0.3f",
      p$zone, p$n, p$mean_z, p$sd_z, p$coverage)

## ==========================================================================
## 9. Secondary: state and zone coverage (household-weighted LGA aggregation)
## ==========================================================================
agg <- function(key, label) {
  keys <- sort(unique(key))
  res <- lapply(keys, function(kk) {
    i <- key == kk & R$n_households > 0
    if (!any(i)) return(NULL)
    wt <- R$n_households[i] / sum(R$n_households[i])
    mv <- sum(wt * R$model_mean[i])
    sds <- (R$ci_high[i] - R$ci_low[i]) / (2 * 1.96)
    sdv <- sqrt(sum(wt^2 * sds^2))     # LGAs independent  -> narrowest possible
    sdp <- sum(wt * sds)               # LGAs perfectly correlated -> widest possible
    du  <- sum(wt * R$direct_unweighted[i])
    ins <- function(s) { lo <- max(0, mv - 1.96 * s); hi <- min(1, mv + 1.96 * s)
                         du >= lo && du <= hi }
    list(key = kk, n_lga = sum(i), model_mean = mv, direct = du,
         lo = max(0, mv - 1.96 * sdv), hi = min(1, mv + 1.96 * sdv),
         inside = ins(sdv), inside_if_perfectly_correlated = ins(sdp),
         sd_if_independent = sdv, sd_if_perfectly_correlated = sdp)
  })
  res <- Filter(Negate(is.null), res)
  n_in  <- sum(vapply(res, `[[`, logical(1), "inside"))
  n_inp <- sum(vapply(res, `[[`, logical(1), "inside_if_perfectly_correlated"))
  msg("\n%s coverage: %d of %d inside the model's 95%% interval (expected %d under perfect calibration)",
      label, n_in, length(res), round(0.95 * length(res)))
  msg("  bound: if LGAs were perfectly correlated the count would be %d of %d",
      n_inp, length(res))
  list(level = label, n = length(res), n_inside = n_in,
       expected_under_perfect_calibration = 0.95 * length(res),
       n_inside_if_lgas_perfectly_correlated = n_inp,
       outside = vapply(Filter(function(x) !x$inside, res), `[[`, "", "key"),
       detail = lapply(res, function(x) list(key = x$key, n_lga = x$n_lga,
                                             model_mean = x$model_mean, lo = x$lo, hi = x$hi,
                                             direct = x$direct, inside = x$inside,
                                             inside_if_perfectly_correlated = x$inside_if_perfectly_correlated,
                                             sd_if_independent = x$sd_if_independent,
                                             sd_if_perfectly_correlated = x$sd_if_perfectly_correlated)))
}

st_cov <- agg(R$state_iso, "state")
zn_cov <- agg(R$zone, "zone")
msg("\nstates whose direct estimate falls outside: %s",
    if (length(st_cov$outside)) paste(st_cov$outside, collapse = ", ") else "none")
msg("zones  whose direct estimate falls outside: %s",
    if (length(zn_cov$outside)) paste(zn_cov$outside, collapse = ", ") else "none")
prog("z-checks: mean %.4f sd %.4f coverage %.4f -> %s | states inside %d of 37",
     mean_z, sd_z, cov_z, if (all_pass) "PASS" else "FAIL", st_cov$n_inside)

## ==========================================================================
## 10. Summary file
## ==========================================================================
construction <- paste(
  "Leave-one-geopolitical-zone-out cross-validation of the LGA model.",
  "Each fold drops every household in one of the six zones, refits the identical",
  "household-level binomial model (ten design columns of eight covariates, BYM2 on the",
  "queen-contiguity graph over all 774 LGAs built once from the full boundary file, IID",
  "cluster effect, INLA 25.10.19 defaults), then predicts the held-out zone's LGAs from",
  "prediction rows placed at each LGA's mean covariate profile taken from the FULL",
  "household file (covariates held known) with cluster index NA. theta_s is the LGA",
  "prevalence with the cluster effect marginalised by the same 7-point Gauss-Hermite rule",
  "as scripts/lga_model.R. 95% intervals come from the marginal posterior of the linear",
  "predictor (mean and sd from summary.linear.predictor, Gaussian on the logit scale)",
  "mapped through that integral on a 2001-point standard-normal probability grid; no",
  "Monte Carlo draws are used, so the intervals carry no simulation noise.",
  "The truth is the direct unweighted proportion from the held-out households of each",
  "LGA; its variance is a cluster-robust ratio linearisation with strata = state and",
  "PSU = cluster (hv001). LGAs with a single cluster have no estimable design variance",
  "and are imputed the fold's median design effect on the binomial variance.",
  "z = (model_mean - direct) / sqrt(model_var + design_var).",
  "Pass rule fixed before any fold was fitted: mean(z) in [-0.15, 0.15], sd(z) in",
  "[0.85, 1.15], share |z| <= 1.96 in [0.90, 0.98], pooled over the 654 LGAs that hold",
  "at least one cluster. The 120 unclustered LGAs have no direct estimate and are excluded.",
  "State and zone coverage aggregate LGA posteriors with household weights and treat the",
  "LGAs as independent, which understates the aggregate interval width; that secondary",
  "count is therefore biased against the model, not for it.",
  "Count-functional calibration is NOT tested: it needs joint draws per fold.",
  sep = " ")

first_num <- function(x) { x <- suppressWarnings(as.numeric(as.character(x)))
                           x <- x[!is.na(x)]; if (!length(x)) NA_real_ else x[1] }

# Every per-fold quantity is read back from the fold block on disk, so a resumed
# run reports the same numbers as the run that actually fitted the fold.
fold_times <- vapply(ZONES, function(z) first_num(R$fold_fit_seconds[R$zone == z]), numeric(1))
fold_detail <- lapply(ZONES, function(z) {
  i <- R$zone == z
  list(zone = z, fold = first_num(R$fold[i]),
       n_training_households = first_num(R$fold_n_training[i]),
       n_clusters = first_num(R$fold_n_clusters[i]),
       fit_seconds = first_num(R$fold_fit_seconds[i]),
       mode_status = first_num(R$fold_mode_status[i]),
       waic = first_num(R$fold_waic[i]),
       sd_cluster_effect = first_num(R$fold_sd_cluster[i]),
       median_deff_used = first_num(R$fold_deff_median[i]),
       n_lgas = sum(i), n_with_direct = sum(R$has_direct[i]),
       n_single_cluster_imputed = sum(R$design_se_source[i] == "deff_imputed"))
})

sum_json <- list(
  generated_by = "scripts/calibration_spatial.R",
  command = "Rscript scripts/calibration_spatial.R",
  ticket = "T12",
  generated_on = as.character(Sys.Date()),
  seed = SEED,
  r_version = R.version.string,
  inla_version = as.character(inla.version()$version),
  construction = construction,
  design = list(
    scheme = "leave-one-geopolitical-zone-out",
    n_folds = 6L,
    zones = ZONES,
    zones_skipped_from_disk = done_zones,
    graph_nodes = n_lga, graph_edges = sum(deg) / 2,
    graph_components = comp$nc,
    graph_note = paste("the graph is built once from the full boundary file and keeps all 774",
                       "nodes in every fold, so removing a zone cannot disconnect it; held-out",
                       "LGAs have no observations but retain their ICAR neighbours"),
    covariates_held_known = TRUE,
    geospatial_covariates_used = 0L,
    weights_in_likelihood = FALSE,
    outcome_in_likelihood = "severe_fi = 1{hfs_sev >= 0.5}"
  ),
  pass_rule_declared_before_fitting = list(
    mean_z = list(pass_range = PASS$mean_z, value = mean_z, pass = chk(mean_z, PASS$mean_z)),
    sd_z = list(pass_range = PASS$sd_z, value = sd_z, pass = chk(sd_z, PASS$sd_z)),
    coverage_abs_z_le_1_96 = list(pass_range = PASS$coverage, value = cov_z,
                                  pass = chk(cov_z, PASS$coverage)),
    all_three_pass = all_pass,
    n_z = n_z,
    rule_changed_after_seeing_values = FALSE
  ),
  primary = list(n = n_z, mean_z = mean_z, median_z = median(zz), sd_z = sd_z,
                 min_z = min(zz), max_z = max(zz),
                 coverage_abs_z_le_1_96 = cov_z,
                 n_abs_z_gt_1_96 = sum(abs(zz) > 1.96),
                 n_abs_z_gt_2_58 = sum(abs(zz) > 2.58)),
  sensitivity = list(
    multi_cluster_lgas_only = sens_mc,
    by_zone = per_fold,
    note = paste("the multi-cluster subset uses only LGAs whose design variance is directly",
                 "estimable; it is a sensitivity, not a substitute for the pre-declared primary rule")
  ),
  secondary_state_coverage = st_cov,
  secondary_zone_coverage = zn_cov,
  post_hoc_diagnostics_on_the_failure = local({
    ok  <- R$has_direct
    dif <- R$model_mean - R$direct_unweighted
    mvar <- ((R$ci_high - R$ci_low) / (2 * 1.96))^2
    list(
      declared_after_seeing_the_failure = TRUE,
      purpose = paste("characterise HOW the pre-declared rule failed; none of these numbers is a",
                      "check and none of them can turn the FAIL into a PASS"),
      bias = list(
        mean_model_minus_direct = mean(dif[ok]),
        median_model_minus_direct = median(dif[ok]),
        share_of_lgas_model_below_direct = mean(dif[ok] < 0),
        by_zone = lapply(ZONES, function(z) {
          i <- ok & R$zone == z
          list(zone = z, mean_model_minus_direct = mean(dif[i]),
               share_model_below_direct = mean(dif[i] < 0))
        })
      ),
      spread = list(
        sd_z = sd(zz), rms_z = sqrt(mean(zz^2)),
        actual_error_over_claimed_sd = sqrt(mean(zz^2)),
        note = paste("z already divides by the model's own sd, so rms_z is the factor by which",
                     "the real out-of-sample error exceeds the uncertainty the model claims")
      ),
      variance_shares = list(
        median_model_sd = median(sqrt(mvar[ok])),
        median_design_se = median(R$design_se[ok], na.rm = TRUE),
        mean_share_of_z_variance_from_design = mean(R$design_se[ok]^2 /
          (R$design_se[ok]^2 + mvar[ok]), na.rm = TRUE)
      ),
      out_of_sample_fit = local({
        x <- R$direct_unweighted[ok]; yv <- R$model_mean[ok]
        sl <- cov(x, yv) / var(x)
        list(correlation = cor(x, yv), slope_model_on_direct = sl,
             intercept = mean(yv) - sl * mean(x),
             sd_direct = sd(x), sd_model = sd(yv),
             compression_ratio = sd(yv) / sd(x),
             note = paste("slope well below 1 and compression below 1 are the shrinkage signature:",
                          "the field reproduces the level of the region it saw, not the level of the",
                          "region it did not"))
      }),
      bias_by_direct_prevalence_band = local({
        bks <- c(0, 0.1, 0.2, 0.3, 0.5, 1)
        x <- R$direct_unweighted[ok]; yv <- R$model_mean[ok]
        lapply(seq_len(length(bks) - 1), function(i) {
          j <- x >= bks[i] & x < bks[i + 1]
          list(band = paste0("[", bks[i], ",", bks[i + 1], ")"), n = sum(j),
               mean_direct = mean(x[j]), mean_model = mean(yv[j]),
               mean_model_minus_direct = mean(yv[j] - x[j]))
        })
      }),
      naive_interval_coverage_not_a_criterion = list(
        n_lgas = sum(ok),
        n_interval_contains_direct = sum(R$ci_low[ok] <= R$direct_unweighted[ok] &
                                         R$direct_unweighted[ok] <= R$ci_high[ok]),
        share = mean(R$ci_low[ok] <= R$direct_unweighted[ok] &
                     R$direct_unweighted[ok] <= R$ci_high[ok]),
        note = paste("descriptive only. The brief forbids this as the criterion because the direct",
                     "estimate carries its own sampling error, so this share under-covers by",
                     "construction; the z check above is the pre-declared one")
      ),
      fold_integrity = list(
        pooled_unweighted_prevalence = sum(R$n_households * R$direct_unweighted, na.rm = TRUE) /
                                       sum(R$n_households),
        expected_national_unweighted = 0.2774,
        note = paste("every household sits in exactly one predicted LGA, so the household-weighted",
                     "pool of the direct estimates must reproduce the national unweighted rate;",
                     "agreement is the check that the fold split lost nobody and double-counted nobody")
      ),
      state_coverage_bound = list(
        n_inside_lower_bound_independent_lgas = st_cov$n_inside,
        n_inside_upper_bound_perfectly_correlated_lgas = st_cov$n_inside_if_lgas_perfectly_correlated,
        note = paste("the pre-declared state check used the independence aggregation, which",
                     "understates the interval; BYM2 with phi near 0.97 puts the truth near the",
                     "upper bound. The bound is reported so 8 of 37 is not over-read")
      )
    )
  }),
  fold_fit_times_seconds = fold_times,
  total_fit_seconds = sum(unlist(fold_times), na.rm = TRUE),
  folds = fold_detail,
  limitations = list(
    count_functional_not_tested = TRUE,
    unclustered_lgas_not_tested = TRUE,
    n_unclustered_excluded = sum(!R$has_direct),
    covariates_held_known = TRUE,
    state_zone_intervals_assume_independent_lgas = TRUE,
    linear_predictor_marginal_assumed_gaussian = TRUE,
    survey_design_not_in_likelihood = TRUE,
    single_cluster_lgas_deff_imputed = sum(R$design_se_source == "deff_imputed", na.rm = TRUE)
  )
)
write(toJSON(sum_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null"), p_sum)
msg("\nwrote %s (%.1f KB)", basename(p_sum), file.size(p_sum) / 1024)

## ==========================================================================
## 11. Final print
## ==========================================================================
msg("\n================ RESULT ================")
msg("folds: %d | LGAs predicted: %d | with a direct estimate: %d", 6L, nrow(R), n_z)
msg("fit seconds per fold: %s", paste(sprintf("%s %.0f", ZONES, unlist(fold_times)), collapse = " | "))
msg("mean z %+0.4f  sd z %.4f  coverage %.4f -> %s",
    mean_z, sd_z, cov_z, if (all_pass) "PASS" else "FAIL")
msg("states inside their interval: %d of %d (expected %d)",
    st_cov$n_inside, st_cov$n, round(st_cov$expected_under_perfect_calibration))
msg("zones  inside their interval: %d of %d (expected %d)",
    zn_cov$n_inside, zn_cov$n, round(zn_cov$expected_under_perfect_calibration))
msg("total elapsed: %.1f s", tick(t_all))
prog("summary written; %d/%d folds on disk, all checks %s",
     length(unique(R$zone)), 6L, if (all_pass) "PASS" else "FAIL")
