#!/usr/bin/env Rscript
# scripts/calibration_lga_cv.R -- T13.  Leave-one-LGA-out calibration, neighbours kept.
#
# One command reproduces every number this ticket reports:
#     Rscript scripts/calibration_lga_cv.R
#
# ============================================================================
# THE QUESTION
# ============================================================================
# T12 removed one geopolitical zone at a time and the model failed (z mean
# -0.65, sd 1.65, coverage 77.5%).  But that test also removed every held-out
# LGA's NEIGHBOURS, which is not the problem the paper makes a claim about.
# The paper claims something about the 120 LGAs that hold no cluster, each of
# which sits among LGAs that do.  This script measures THAT problem: hold out
# individual LGAs while their neighbours stay in the fit, and ask whether the
# 95% intervals cover.
#
# ============================================================================
# PRE-DECLARED PASS RULE -- identical to T12, fixed before any fold is fitted
# ============================================================================
#   | check                  | pass range        |
#   |------------------------|-------------------|
#   | mean of z              | [-0.15, +0.15]    |
#   | sd of z                | [ 0.85,  1.15]    |
#   | share with |z| <= 1.96 | [ 0.90,  0.98]    |
#
# THIS RULE IS NOT REVISED AFTER THE NUMBERS APPEAR.  A failure is reported as
# a failure.  Do not re-fit, soften the rule, or change the estimand.
#
# ============================================================================
# DECLARED BEFORE THE RUN: choices the brief leaves to the script
# ============================================================================
# (A) THE ADJACENCY FILE.  The brief names data/derived/neighbours.csv and
#     describes it as "queen contiguity, 774 nodes, 2,230 edges".  The file on
#     disk is the STATE graph (37 nodes, 86 undirected edges) -- measured, not
#     assumed.  The 774/2,230 description matches the LGA graph, so the LGA
#     graph is built here from the same boundary file scripts/lga_model.R and
#     scripts/calibration_spatial.R use, and its 774 nodes / 2,230 edges / 1
#     component are asserted against the brief's own numbers.  Using the state
#     file would let two adjacent LGAs in different states be held out in the
#     same group, which is exactly the contamination rule 2 of the brief exists
#     to prevent.
#
# (B) GROUP ASSIGNMENT.  The 200 drawn LGAs are visited in DRAW order; each is
#     placed in the group where it has the fewest already-assigned members
#     sharing an edge with it, among the groups that still have capacity
#     (< 40 members), ties broken by fewest members, then lowest group number.
#     The capacity rule is what makes the split exactly 5 x 40; without it a
#     pure greedy can leave ragged groups and the design says 40.  No local
#     search, no swap pass: the achieved adjacency is reported as it falls.
#
# (C) INTERVAL CONSTRUCTION AND DESIGN VARIANCE: identical to T12, reused
#     verbatim so the two tickets are one experiment.  Marginal posterior of
#     the linear predictor (mean and sd from summary.linear.predictor),
#     Gaussian on the logit scale, cluster effect marginalised by the same
#     7-point Gauss-Hermite rule as scripts/lga_model.R, quantiles read off a
#     2001-point standard-normal probability grid.  design_var = cluster-robust
#     ratio linearisation, strata = state, PSU = cluster; single-cluster LGAs
#     get the group's median design effect on the binomial variance.
#     model_var = ((ci_high - ci_low) / (2 * 1.96))^2.
#     z = (model_mean - direct_unweighted) / sqrt(model_var + design_var).
#
# (D) COVARIATES HELD KNOWN.  The prediction row for every LGA uses that LGA's
#     mean covariate profile from the FULL household file, including held-out
#     LGAs, exactly as T12 did.  This tests the outcome model and the spatial
#     field, NOT covariate availability.  Disclosed, not hidden.
#
# (E) THE INFLATION FACTOR k = sd(z) over all 200 held-out LGAs.  "Widening
#     every interval by k" means the half-width is multiplied by k, so the
#     coverage achieved is mean(|z| <= 1.96 * k).  The out-of-fold version
#     estimates k on the other four groups and applies it to the fifth.
#
# OUT OF SCOPE: count-functional calibration (needs joint draws per fold) and
# the 120 never-clustered LGAs (no direct estimate exists for them).
# ============================================================================

suppressPackageStartupMessages({
  library(sf)
  library(spdep)
  library(INLA)
  library(jsonlite)
})
sf_use_s2(TRUE)

SEED       <- 20261124L
N_DRAW     <- 200L
N_GROUP    <- 5L
GROUP_SIZE <- 40L
GH_N       <- 7L
GRID_N     <- 2001L
FIT_LIMIT  <- 300          # seconds per fit; the brief says stop and report beyond this

root <- normalizePath(".")
p_hh     <- file.path(root, "data/derived/analysis_households_lga.csv")
p_bound  <- file.path(root, "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson")
p_pop    <- file.path(root, "data/derived/lga_population.csv")
p_est    <- file.path(root, "data/derived/lga_estimates.csv")
p_out    <- file.path(root, "data/derived/calibration_lga_cv.csv")
p_json   <- file.path(root, "data/derived/calibration_lga_cv.json")
p_t12    <- file.path(root, "data/derived/calibration_summary.json")

for (f in c(p_hh, p_bound, p_pop, p_est)) {
  if (!file.exists(f)) stop("missing input: ", f, " -- run from the repo root", call. = FALSE)
}

msg  <- function(...) cat(sprintf(...), "\n", sep = "")
tick <- function(t0) round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)
prog <- function(...) {
  line <- paste0(format(Sys.time(), "%H:%M"), "  ", sprintf(...), "\n")
  cat(line, sep = "")
  try(cat(line, sep = "", file = file.path(root, ".agent/T13-progress.md"), append = TRUE),
      silent = TRUE)
}

set.seed(SEED)
t_all <- Sys.time()

## ==========================================================================
## 1. The data
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
if (anyNA(d$state_iso)) stop("state_iso has NA", call. = FALSE)
if (anyNA(d$lga_id))    stop("lga_id has NA", call. = FALSE)

## ==========================================================================
## 2. The spatial graph -- built ONCE over all 774 LGAs, as in T12.  See (A).
## ==========================================================================
g <- st_make_valid(st_read(p_bound, quiet = TRUE))
if (nrow(g) != 774L) stop("expected 774 LGA polygons, got ", nrow(g), call. = FALSE)
if (anyDuplicated(g$shapeID)) stop("duplicate shapeID", call. = FALSE)
LGA_ID <- g$shapeID
n_lga  <- length(LGA_ID)
lga_name <- g$shapeName

nb <- poly2nb(g, queen = TRUE)
if (length(nb) != n_lga) stop("graph node count != LGA count", call. = FALSE)
deg  <- card(nb)
comp <- n.comp.nb(nb)
msg("\nLGA graph: %d nodes, %d edges, %d component(s), %d isolate(s)",
    n_lga, sum(deg) / 2, comp$nc, sum(deg == 0))
if (sum(deg == 0)) stop("graph has isolates; BYM2 is improper there", call. = FALSE)
if (comp$nc != 1L) stop("graph is disconnected (", comp$nc, " components)", call. = FALSE)
if (sum(deg) / 2 != 2230) stop("expected 2,230 LGA edges per the brief, got ", sum(deg) / 2, call. = FALSE)

W <- nb2mat(nb, style = "B", zero.policy = TRUE)
ADJ <- (W + t(W)) > 0
if (!isTRUE(all(ADJ == t(ADJ)))) stop("adjacency not symmetric", call. = FALSE)
if (sum(ADJ) / 2 != sum(deg) / 2) stop("adjacency matrix does not match the nb object", call. = FALSE)

nb_path <- file.path(tempdir(), "lga_graph_lgacv.adj")
nb2INLA(nb_path, nb)
gr <- inla.read.graph(nb_path)
msg("INLA graph: %d nodes, %d edges", gr$n, sum(gr$nnbs) / 2)

## ---- LGA -> state ----------------------------------------------------------
pop <- read.csv(p_pop, stringsAsFactors = FALSE)
state_of_lga <- pop$state_iso[match(LGA_ID, pop$lga_id)]
if (anyNA(state_of_lga)) stop("an LGA has no parent state in lga_population.csv", call. = FALSE)

## ---- in-sample full-fit estimate, for the three-way comparison -------------
est <- read.csv(p_est, stringsAsFactors = FALSE)
if (!all(c("lga_id", "posterior_mean") %in% names(est))) stop("lga_estimates.csv lacks the needed columns", call. = FALSE)
in_sample <- est$posterior_mean[match(LGA_ID, est$lga_id)]
if (anyNA(in_sample)) stop("an LGA has no in-sample estimate", call. = FALSE)

## ==========================================================================
## 3. Covariate profiles, held KNOWN from the full file  -- see (D)
## ==========================================================================
lga_idx_full <- match(d$lga_id, LGA_ID)
if (anyNA(lga_idx_full)) stop("household lga_id not in the boundary file", call. = FALSE)
X_full <- as.matrix(d[, COV]); storage.mode(X_full) <- "double"
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
U_GRID <- seq(1e-4, 1 - 1e-4, length.out = GRID_N)
Q_GRID <- qnorm(U_GRID)

## ==========================================================================
## 4. The draw and the neighbour-avoiding split -- see (B)
## ==========================================================================
obs_lga <- sort(unique(d$lga_id))
if (length(obs_lga) != 654L)
  stop("expected 654 LGAs with at least one cluster, got ", length(obs_lga), call. = FALSE)
if (!all(obs_lga %in% LGA_ID)) stop("a clustered LGA is missing from the boundary file", call. = FALSE)

drawn   <- sample(obs_lga, N_DRAW, replace = FALSE)
d_idx   <- match(drawn, LGA_ID)
A       <- ADJ[d_idx, d_idx]
grp     <- integer(N_DRAW)
members <- integer(N_GROUP)
for (v in seq_len(N_DRAW)) {
  elig <- which(members < GROUP_SIZE)
  if (!length(elig)) stop("no group has capacity left -- the split is over-subscribed", call. = FALSE)
  cost <- vapply(elig, function(k) { j <- which(grp == k); if (!length(j)) 0L else sum(A[v, j]) },
                 numeric(1))
  best <- elig[order(cost, members[elig], elig)][1L]
  grp[v] <- best
  members[best] <- members[best] + 1L
}
if (any(grp == 0L)) stop("an LGA was not assigned to a group", call. = FALSE)
if (any(members != GROUP_SIZE)) stop("group sizes are not all 40: ",
                                     paste(members, collapse = " "), call. = FALSE)
if (anyDuplicated(drawn)) stop("the draw contains a duplicate LGA", call. = FALSE)

intra_edges <- vapply(seq_len(N_GROUP), function(k) {
  j <- which(grp == k); sum(A[j, j]) / 2
}, numeric(1))
intra_pairs <- intra_edges   # one edge == one adjacent pair of held-out LGAs

msg("\n===== THE DRAW (seed %d, without replacement from the 654 clustered LGAs) =====", SEED)
msg("drew %d LGAs, split into %d groups of %d", N_DRAW, N_GROUP, GROUP_SIZE)
msg("edges among the 200 drawn LGAs: %d of the graph's %d", sum(A) / 2, sum(deg) / 2)
msg("adjacent pairs remaining INSIDE each group: %s  (max %d)",
    paste(intra_pairs, collapse = " "), max(intra_pairs))
if (any(intra_pairs > 0L))
  msg("WARNING: the split is contaminated -- %d adjacent pair(s) share a group; report this, do not hide it",
      sum(intra_pairs))
msg("first 5 drawn: %s", paste(head(drawn, 5), collapse = ", "))
prog("drew 200 LGAs (seed %d), split into 5 groups; within-group adjacency %s (max %d)",
     SEED, paste(intra_pairs, collapse = " "), max(intra_pairs))

## ==========================================================================
## 5. Design variance of a direct LGA proportion -- same as T12
## ==========================================================================
design_var <- function(y, clu, state) {
  N <- length(y)
  p <- sum(y) / N
  uc <- tapply(y - p, clu, sum)
  h  <- as.character(tapply(as.character(state), clu, function(v) v[1L]))
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
## 6. Fit machinery, written to disk group by group (resumable)
## ==========================================================================
COLS <- c("lga_id", "group", "model_mean", "ci_low", "ci_high",
          "direct_unweighted", "direct_weighted", "design_se", "design_se_source",
          "n_clusters", "z", "in_sample_fit",
          "lga_name", "state_iso", "n_households", "model_se",
          "group_fit_seconds", "group_waic", "group_mode_status", "group_sd_cluster",
          "group_deff_median", "group_n_training", "group_n_clusters")

existing <- NULL
done_groups <- integer(0)
if (file.exists(p_out)) {
  existing <- read.csv(p_out, stringsAsFactors = FALSE, check.names = FALSE)
  done_groups <- sort(unique(existing$group))
  msg("\nresuming: %s already holds %d rows from group(s): %s",
      basename(p_out), nrow(existing), paste(done_groups, collapse = ", "))
}

fit_group <- function(k) {
  held <- drawn[grp == k]
  if (length(held) != GROUP_SIZE) stop("group ", k, " does not hold 40 LGAs", call. = FALSE)
  keep <- !(d$lga_id %in% held)
  dt   <- d[keep, , drop = FALSE]
  if (!nrow(dt)) stop("group ", k, " holds every household -- nothing left to fit", call. = FALSE)
  if (any(dt$lga_id %in% held)) stop("a held-out household survived the drop mask", call. = FALSE)

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

  msg("\n--- group %d: %d LGAs held out ---", k, length(held))
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
  msg("group %d fitted in %.1f s | mode status %s | WAIC %.2f | sd(cluster) %.4f",
      k, t_fit, paste(ms, collapse = ","), fit$waic$waic, sd_v)
  if (t_fit > FIT_LIMIT)
    stop("group ", k, " took ", t_fit, " s, above the ", FIT_LIMIT,
         " s limit; stopping rather than burning the budget", call. = FALSE)

  ## ---- the marginal of theta, from the marginal of eta (identical to T12) --
  slp <- fit$summary.linear.predictor
  idx <- n_tr + seq_len(n_lga)
  m_s <- slp[idx, "mean"]
  s_s <- slp[idx, "sd"]
  if (anyNA(m_s) || anyNA(s_s))
    stop("linear predictor summary has NA on a prediction row (group ", k, ")", call. = FALSE)

  TH <- matrix(0, n_lga, GRID_N)
  for (k2 in seq_len(GH_N)) {
    shift <- sqrt(2) * sd_v * GH_X[k2]
    TH <- TH + GH_W[k2] * plogis(outer(s_s, Q_GRID) + m_s + shift)
  }
  model_mean <- rowMeans(TH)
  ci_low  <- apply(TH, 1, function(v) approx(U_GRID, v, 0.025)$y)
  ci_high <- apply(TH, 1, function(v) approx(U_GRID, v, 0.975)$y)
  if (anyNA(TH) || any(TH < -1e-12) || any(TH > 1 + 1e-12)) stop("theta outside [0,1]", call. = FALSE)
  if (any(ci_low > model_mean) || any(model_mean > ci_high)) stop("quantiles out of order", call. = FALSE)

  ## ---- the truth, from the held-out households ONLY -----------------------
  hz <- d[!keep, , drop = FALSE]
  if (nrow(hz) == 0L) stop("no held-out households for group ", k, call. = FALSE)
  if (!all(hz$lga_id %in% held)) stop("the held-out set holds a household outside the group's LGAs", call. = FALSE)
  hz$lga_idx <- match(hz$lga_id, LGA_ID)

  n_hh_out <- as.numeric(tabulate(hz$lga_idx, nbins = n_lga))
  cl_keys  <- unique(hz[, c("lga_id", "hv001")])
  n_cl_out <- as.numeric(table(factor(cl_keys$lga_id, levels = LGA_ID)))
  if (sum(n_cl_out) != nrow(cl_keys))
    stop("cluster counts do not sum to the number of distinct clusters", call. = FALSE)
  if (any(n_cl_out > n_hh_out)) stop("an LGA has more clusters than households", call. = FALSE)

  direct_u <- rep(NA_real_, n_lga); direct_w <- rep(NA_real_, n_lga)
  dvar     <- rep(NA_real_, n_lga); dsrc     <- rep(NA_character_, n_lga)
  for (i in which(n_hh_out > 0)) {
    ii <- hz$lga_idx == i
    yy <- as.integer(hz$severe_fi[ii]); ww <- hz$hv005[ii]
    direct_u[i] <- mean(yy)
    direct_w[i] <- sum(ww * yy) / sum(ww)
    v <- design_var(yy, hz$hv001[ii], hz$state_iso[ii])
    if (is.na(v)) { dvar[i] <- NA_real_; dsrc[i] <- "single_cluster_pending" }
    else          { dvar[i] <- v;       dsrc[i] <- "cluster_robust" }
  }

  ok <- which(!is.na(dvar) & dvar > 0 & n_hh_out > 0)
  deff <- dvar[ok] / (direct_u[ok] * (1 - direct_u[ok]) / n_hh_out[ok])
  deff_med <- if (length(deff)) max(1, median(deff, na.rm = TRUE)) else 1
  single <- which(dsrc == "single_cluster_pending")
  if (length(single)) {
    pb <- pmin(pmax(direct_u[single], 1e-6), 1 - 1e-6)
    dvar[single] <- deff_med * pb * (1 - pb) / n_hh_out[single]
    dsrc[single] <- "deff_imputed"
  }
  msg("design variance: %d cluster-robust, %d deff-imputed (median deff %.3f), %d with no household",
      sum(dsrc == "cluster_robust", na.rm = TRUE), sum(dsrc == "deff_imputed", na.rm = TRUE),
      deff_med, sum(n_hh_out == 0))

  ## ---- the group's block --------------------------------------------------
  zi <- match(held, LGA_ID)
  if (anyNA(zi)) stop("a held-out LGA is missing from the boundary file", call. = FALSE)
  model_var <- ((ci_high - ci_low) / (2 * 1.96))^2
  zz <- ifelse(is.na(direct_u), NA_real_, (model_mean - direct_u) / sqrt(model_var + dvar))

  block <- data.frame(
    lga_id = LGA_ID[zi], group = k,
    model_mean = model_mean[zi], ci_low = ci_low[zi], ci_high = ci_high[zi],
    direct_unweighted = direct_u[zi], direct_weighted = direct_w[zi],
    design_se = sqrt(dvar[zi]), design_se_source = dsrc[zi],
    n_clusters = n_cl_out[zi], z = zz[zi], in_sample_fit = in_sample[zi],
    lga_name = lga_name[zi], state_iso = state_of_lga[zi],
    n_households = n_hh_out[zi], model_se = sqrt(model_var[zi]),
    group_fit_seconds = t_fit, group_waic = fit$waic$waic, group_mode_status = ms,
    group_sd_cluster = sd_v, group_deff_median = deff_med,
    group_n_training = n_tr, group_n_clusters = n_clu,
    stringsAsFactors = FALSE
  )
  block$design_se_source[is.na(block$design_se_source)] <- "none"
  if (anyNA(block$z)) stop("a held-out LGA has no z -- it had households but no direct estimate", call. = FALSE)
  if (nrow(block) != GROUP_SIZE) stop("block is not 40 rows", call. = FALSE)

  out <- if (is.null(existing)) block[, COLS] else rbind(existing[COLS], block[, COLS])
  out <- out[order(out$group, match(out$lga_id, LGA_ID)), COLS]
  write.csv(out, p_out, row.names = FALSE)
  existing <<- out
  msg("wrote %d rows for group %d | file now holds %d rows, %d group(s)",
      nrow(block), k, nrow(out), length(unique(out$group)))
  prog("group %d fitted %.0f s, 40 predicted, block written (file holds %d rows)",
       k, t_fit, nrow(out))

  invisible(list(group = k, t_fit = t_fit, mode_status = ms, waic = fit$waic$waic,
                 sd_v = sd_v, deff_med = deff_med, n_train = n_tr, n_clu = n_clu,
                 n_single = length(single)))
}

## ==========================================================================
## 7. Run the five groups
## ==========================================================================
for (k in seq_len(N_GROUP)) {
  if (k %in% done_groups) { msg("\n--- group %d already on disk, skipped ---", k); next }
  fit_group(k)
}

## ==========================================================================
## 8. Pooled checks, fixed pass rule
## ==========================================================================
R <- read.csv(p_out, stringsAsFactors = FALSE, check.names = FALSE)
R <- R[order(R$group, match(R$lga_id, LGA_ID)), ]
if (nrow(R) != N_DRAW) stop("expected ", N_DRAW, " rows, have ", nrow(R), call. = FALSE)
if (anyDuplicated(R$lga_id)) stop("an LGA appears more than once", call. = FALSE)
if (length(unique(R$group)) != N_GROUP) stop("not all five groups are present", call. = FALSE)
if (!setequal(R$lga_id, drawn)) stop("the rows on disk are not the 200 drawn LGAs", call. = FALSE)
if (abs(sum(R$n_households) - sum(n_hh_lga[match(drawn, LGA_ID)])) > 1e-9)
  stop("the held-out household total does not match the drawn LGAs' household total", call. = FALSE)

zz <- R$z
if (anyNA(zz)) stop("z has NA", call. = FALSE)
n_z <- length(zz)
mean_z <- mean(zz); sd_z <- sd(zz); cov_z <- mean(abs(zz) <= 1.96)

PASS <- list(mean_z = c(-0.15, 0.15), sd_z = c(0.85, 1.15), coverage = c(0.90, 0.98))
chk <- function(v, band) v >= band[1] && v <= band[2]

msg("\n===== POOLED CALIBRATION, %d held-out LGAs =====", n_z)
msg("mean of z            = %+0.4f   pass band [%+.2f, %+.2f]   %s",
    mean_z, PASS$mean_z[1], PASS$mean_z[2], if (chk(mean_z, PASS$mean_z)) "PASS" else "FAIL")
msg("sd of z              =  %0.4f   pass band [ %.2f,  %.2f]   %s",
    sd_z, PASS$sd_z[1], PASS$sd_z[2], if (chk(sd_z, PASS$sd_z)) "PASS" else "FAIL")
msg("share |z| <= 1.96    =  %0.4f   pass band [ %.2f,  %.2f]   %s",
    cov_z, PASS$coverage[1], PASS$coverage[2], if (chk(cov_z, PASS$coverage)) "PASS" else "FAIL")
all_pass <- chk(mean_z, PASS$mean_z) && chk(sd_z, PASS$sd_z) && chk(cov_z, PASS$coverage)
msg("ALL THREE CHECKS: %s", if (all_pass) "PASS" else "FAIL")
prog("z: mean %+0.4f sd %.4f coverage %.4f -> %s; k = %.4f",
     mean_z, sd_z, cov_z, if (all_pass) "PASS" else "FAIL", sd_z)

mc <- R$design_se_source == "cluster_robust"
sens_mc <- list(n = sum(mc), mean_z = mean(R$z[mc]), sd_z = sd(R$z[mc]),
                coverage = mean(abs(R$z[mc]) <= 1.96))
msg("\nsensitivity, %d multi-cluster LGAs only: mean %+0.4f | sd %.4f | coverage %.4f",
    sens_mc$n, sens_mc$mean_z, sens_mc$sd_z, sens_mc$coverage)

per_group <- lapply(seq_len(N_GROUP), function(k) {
  i <- R$group == k
  list(group = k, n = sum(i), mean_z = mean(R$z[i]), sd_z = sd(R$z[i]),
       coverage = mean(abs(R$z[i]) <= 1.96),
       n_single_cluster = sum(R$design_se_source[i] == "deff_imputed"),
       intra_group_adjacent_pairs = intra_pairs[k],
       fit_seconds = R$group_fit_seconds[i][1],
       waic = R$group_waic[i][1], mode_status = R$group_mode_status[i][1],
       sd_cluster_effect = R$group_sd_cluster[i][1],
       deff_median = R$group_deff_median[i][1],
       n_training_households = R$group_n_training[i][1],
       n_training_clusters = R$group_n_clusters[i][1])
})
msg("\nby group:")
for (p in per_group)
  msg("  group %d  n=%2d  mean %+0.3f  sd %0.3f  coverage %0.3f  adjacent pairs in group %d",
      p$group, p$n, p$mean_z, p$sd_z, p$coverage, p$intra_group_adjacent_pairs)

## ==========================================================================
## 9. The remedy: the inflation factor k, and out-of-fold validation of k
## ==========================================================================
k_all <- sd_z
cov_after_k <- mean(abs(zz) <= 1.96 * k_all)
msg("\ninflation factor k = sd(z) = %.4f", k_all)
msg("coverage if every interval is widened by k: %.4f", cov_after_k)

oof <- lapply(seq_len(N_GROUP), function(k) {
  tr <- zz[R$group != k]
  te <- zz[R$group == k]
  kk <- sd(tr)
  list(test_group = k, n_test = length(te),
       k_from_other_groups = kk,
       coverage_in_test_group = mean(abs(te) <= 1.96 * kk))
})
cov_oof <- vapply(oof, `[[`, numeric(1), "coverage_in_test_group")
msg("\nout-of-fold k (estimate on four groups, apply to the fifth):")
for (o in oof)
  msg("  test group %d  n=%2d  k_-g = %.4f  coverage %.4f",
      o$test_group, o$n_test, o$k_from_other_groups, o$coverage_in_test_group)
msg("  five coverages: %s | mean %.4f | min %.4f | max %.4f",
    paste(sprintf("%.4f", cov_oof), collapse = " "), mean(cov_oof), min(cov_oof), max(cov_oof))
prog("out-of-fold k: coverages %s", paste(sprintf("%.3f", cov_oof), collapse = " "))

## ==========================================================================
## 10. The three-way comparison (in-sample / out-of-sample / direct)
## ==========================================================================
tw <- function(x) list(n = length(x), mean = mean(x), median = median(x), sd = sd(x),
                       min = min(x), max = max(x))
three_way <- list(
  in_sample_full_fit = c(tw(R$in_sample_fit),
                         list(correlation_with_direct = cor(R$in_sample_fit, R$direct_unweighted),
                              mean_minus_direct = mean(R$in_sample_fit - R$direct_unweighted),
                              compression_ratio_vs_direct = sd(R$in_sample_fit) / sd(R$direct_unweighted))),
  out_of_sample_fold = c(tw(R$model_mean),
                         list(correlation_with_direct = cor(R$model_mean, R$direct_unweighted),
                              mean_minus_direct = mean(R$model_mean - R$direct_unweighted),
                              compression_ratio_vs_direct = sd(R$model_mean) / sd(R$direct_unweighted))),
  direct_unweighted = tw(R$direct_unweighted),
  note = paste("in-sample is posterior_mean from data/derived/lga_estimates.csv (the full fit that sees",
               "every household); out-of-sample is this ticket's fold estimate for the same LGA;",
               "direct is the held-out unweighted proportion. Compression below 1 is the shrinkage",
               "signature -- the fold field is pulled toward its neighbours.")
)
msg("\nthree-way comparison over the %d held-out LGAs:", N_DRAW)
msg("  in-sample  mean %.4f  sd %.4f  cor with direct %.3f  mean diff %+0.4f",
    three_way$in_sample_full_fit$mean, three_way$in_sample_full_fit$sd,
    three_way$in_sample_full_fit$correlation_with_direct,
    three_way$in_sample_full_fit$mean_minus_direct)
msg("  out-of-smp mean %.4f  sd %.4f  cor with direct %.3f  mean diff %+0.4f",
    three_way$out_of_sample_fold$mean, three_way$out_of_sample_fold$sd,
    three_way$out_of_sample_fold$correlation_with_direct,
    three_way$out_of_sample_fold$mean_minus_direct)
msg("  direct     mean %.4f  sd %.4f", three_way$direct_unweighted$mean,
    three_way$direct_unweighted$sd)

## ==========================================================================
## 11. Comparison against T12, read from its summary file
## ==========================================================================
t12 <- if (file.exists(p_t12)) fromJSON(p_t12) else NULL
t12_cmp <- if (is.null(t12)) {
  list(available = FALSE, note = "data/derived/calibration_summary.json not found")
} else {
  list(
    available = TRUE,
    source = "data/derived/calibration_summary.json (T12, leave-one-zone-out)",
    t12_scheme = "leave-one-geopolitical-zone-out, 654 LGAs, neighbours removed with the zone",
    t12_n = t12$primary$n,
    t12_mean_z = t12$primary$mean_z,
    t12_sd_z = t12$primary$sd_z,
    t12_coverage = t12$primary$coverage_abs_z_le_1_96,
    t12_k = t12$primary$sd_z,
    t13_n = n_z, t13_mean_z = mean_z, t13_sd_z = sd_z, t13_coverage = cov_z, t13_k = k_all,
    delta_mean_z = mean_z - t12$primary$mean_z,
    delta_sd_z = sd_z - t12$primary$sd_z,
    delta_coverage = cov_z - t12$primary$coverage_abs_z_le_1_96,
    reading = paste("same pass rule, same estimator, same scoring; the only change is what is",
                    "removed. If T13 passes where T12 failed, the failure is extrapolation to a",
                    "region with no neighbours, not interpolation among observed neighbours.")
  )
}

## ==========================================================================
## 12. Summary file
## ==========================================================================
construction <- paste(
  "Leave-one-LGA-out cross-validation of the LGA model, with each held-out LGA's neighbours",
  "left in the fit. 200 of the 654 LGAs that hold at least one cluster are drawn at random",
  "without replacement (seed 20261124) and split into 5 groups of 40 by a capacity-constrained",
  "greedy rule that places each drawn LGA in the group where it has the fewest already-assigned",
  "edge-sharing members, so that one held-out LGA does not remove another's neighbourhood; the",
  "number of adjacent pairs remaining inside each group is reported. Each group is one fit: that",
  "group's 40 LGAs' households are dropped and the identical household-level binomial model is",
  "refitted (ten design columns of eight covariates, BYM2 on the queen-contiguity graph over all",
  "774 LGAs built once from the full boundary file, IID cluster effect, INLA 25.10.19 defaults),",
  "then the 40 LGAs are predicted from prediction rows at each LGA's mean covariate profile taken",
  "from the FULL household file (covariates held known) with cluster index NA. theta_s is the LGA",
  "prevalence with the cluster effect marginalised by the same 7-point Gauss-Hermite rule as",
  "scripts/lga_model.R; 95% intervals come from the marginal posterior of the linear predictor",
  "(mean and sd from summary.linear.predictor, Gaussian on the logit scale) mapped through that",
  "integral on a 2001-point standard-normal probability grid, so no Monte Carlo draws are used.",
  "The truth is the direct unweighted proportion from the held-out households of each LGA; its",
  "variance is a cluster-robust ratio linearisation with strata = state and PSU = cluster (hv001).",
  "LGAs with a single cluster have no estimable design variance and are imputed the group's median",
  "design effect on the binomial variance. z = (model_mean - direct) / sqrt(model_var + design_var)",
  "with model_var = ((ci_high - ci_low)/(2*1.96))^2. Pass rule fixed before any fit, identical to",
  "T12: mean(z) in [-0.15, 0.15], sd(z) in [0.85, 1.15], share |z| <= 1.96 in [0.90, 0.98], pooled",
  "over the 200 held-out LGAs. The adjacency file named in the brief is the 37-node state graph;",
  "the 774-node, 2230-edge LGA graph was built from the boundary file and its edge count asserted.",
  "Count-functional calibration is NOT tested: it needs joint draws per fold.", sep = " ")

sum_json <- list(
  generated_by = "scripts/calibration_lga_cv.R",
  command = "Rscript scripts/calibration_lga_cv.R",
  ticket = "T13",
  generated_on = as.character(Sys.Date()),
  seed = SEED,
  r_version = R.version.string,
  inla_version = as.character(packageVersion("INLA")),
  construction = construction,
  design = list(
    scheme = "leave-one-LGA-out, neighbours retained within the fit",
    n_held_out = N_DRAW, n_groups = N_GROUP, group_size = GROUP_SIZE,
    sampling_frame = "654 LGAs holding at least one cluster",
    draw_seed = SEED,
    held_out_lga_ids = drawn,
    group_of_lga = setNames(grp, drawn)[drawn],
    graph_source = "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson (queen contiguity)",
    graph_nodes = n_lga, graph_edges = sum(deg) / 2, graph_components = comp$nc,
    adjacency_file_note = paste("the brief names data/derived/neighbours.csv as the 774-node LGA graph;",
                                "that file is the 37-node STATE graph (172 directed rows, 86 undirected",
                                "edges). The LGA graph was built from the boundary file instead and its",
                                "2230 edges asserted against the brief's own numbers."),
    adjacency_report = lapply(seq_len(N_GROUP), function(k) list(
      group = k, n_lgas = sum(grp == k),
      adjacent_pairs_within_group = intra_pairs[k],
      edges_among_all_200_drawn = sum(A) / 2,
      contaminated = intra_pairs[k] > 0L)),
    covariates_held_known = TRUE, geospatial_covariates_used = 0L,
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
    rule_changed_after_seeing_values = FALSE,
    identical_to_T12_rule = TRUE
  ),
  primary = list(n = n_z, mean_z = mean_z, median_z = median(zz), sd_z = sd_z,
                 min_z = min(zz), max_z = max(zz),
                 coverage_abs_z_le_1_96 = cov_z,
                 n_abs_z_gt_1_96 = sum(abs(zz) > 1.96),
                 n_abs_z_gt_2_58 = sum(abs(zz) > 2.58),
                 rms_z = sqrt(mean(zz^2))),
  sensitivity = list(
    multi_cluster_lgas_only = sens_mc,
    by_group = per_group,
    note = paste("the multi-cluster subset uses only LGAs whose design variance is directly",
                 "estimable; it is a sensitivity, not a substitute for the pre-declared primary rule")
  ),
  inflation_factor = list(
    k = k_all,
    definition = "k = sd(z) over all 200 held-out LGAs; widening every interval by k multiplies the half-width by k",
    coverage_after_widening_by_k = cov_after_k,
    k_alternative_rms = sqrt(mean(zz^2)),
    coverage_after_widening_by_rms = mean(abs(zz) <= 1.96 * sqrt(mean(zz^2))),
    note = paste("k is estimated on the same 200 residuals it is applied to; the out-of-fold",
                 "block below is the honest validation of it")
  ),
  out_of_fold_k = list(
    per_test_group = oof,
    coverages = cov_oof,
    mean_coverage = mean(cov_oof), min_coverage = min(cov_oof), max_coverage = max(cov_oof),
    n_per_test_group = GROUP_SIZE,
    note = paste("k estimated on four groups and applied to the fifth, five times. Each coverage",
                 "is a mean over 40 LGAs, so its binomial standard error at 0.95 is about 0.034;",
                 "read the spread of the five, not one of them alone")
  ),
  three_way_comparison = three_way,
  comparison_against_T12 = t12_cmp,
  descriptive_not_a_criterion = list(
    naive_interval_coverage = list(
      n_interval_contains_direct = sum(R$ci_low <= R$direct_unweighted & R$direct_unweighted <= R$ci_high),
      share = mean(R$ci_low <= R$direct_unweighted & R$direct_unweighted <= R$ci_high),
      note = paste("descriptive only; the direct estimate carries its own sampling error, so this",
                   "under-covers by construction and is NOT the criterion")),
    bias = list(
      mean_model_minus_direct = mean(R$model_mean - R$direct_unweighted),
      median_model_minus_direct = median(R$model_mean - R$direct_unweighted),
      share_of_lgas_model_below_direct = mean(R$model_mean < R$direct_unweighted)),
    variance_shares = list(
      median_model_se = median(R$model_se),
      median_design_se = median(R$design_se, na.rm = TRUE),
      mean_share_of_z_variance_from_design = mean(R$design_se^2 /
                                                   (R$design_se^2 + R$model_se^2), na.rm = TRUE))
  ),
  fit_times_seconds = vapply(seq_len(N_GROUP), function(k) R$group_fit_seconds[R$group == k][1], numeric(1)),
  total_fit_seconds = sum(vapply(seq_len(N_GROUP), function(k) R$group_fit_seconds[R$group == k][1], numeric(1))),
  limitations = list(
    count_functional_not_tested = TRUE,
    never_clustered_lgas_not_tested = TRUE,
    n_never_clustered_excluded = length(no_data),
    covariates_held_known = TRUE,
    linear_predictor_marginal_assumed_gaussian = TRUE,
    survey_design_not_in_likelihood = TRUE,
    single_cluster_lgas_deff_imputed = sum(R$design_se_source == "deff_imputed"),
    n_degenerate_direct_zero_or_one = sum(R$direct_unweighted %in% c(0, 1)),
    note = paste("the held-out LGAs are the 654 that hold a cluster; the 120 LGAs with no cluster",
                 "still have no direct estimate and are not tested here")
  )
)
write(toJSON(sum_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null"), p_json)
msg("\nwrote %s (%.1f KB)", basename(p_json), file.size(p_json) / 1024)

## ==========================================================================
## 13. Final print
## ==========================================================================
msg("\n================ RESULT ================")
msg("groups: %d | LGAs held out: %d | adjacent pairs within groups: %s",
    N_GROUP, nrow(R), paste(intra_pairs, collapse = " "))
msg("fit seconds per group: %s (total %.0f)",
    paste(sprintf("%.0f", vapply(seq_len(N_GROUP), function(k) R$group_fit_seconds[R$group == k][1], numeric(1))),
          collapse = " | "), sum(R$group_fit_seconds[!duplicated(R$group)]))
msg("mean z %+0.4f  sd z %.4f  coverage %.4f -> %s",
    mean_z, sd_z, cov_z, if (all_pass) "PASS" else "FAIL")
msg("k = %.4f  coverage after widening by k = %.4f", k_all, cov_after_k)
msg("out-of-fold k coverages: %s", paste(sprintf("%.4f", cov_oof), collapse = " "))
msg("elapsed: %.1f s", tick(t_all))
prog("summary written; %d/%d groups on disk, all checks %s", length(unique(R$group)),
     N_GROUP, if (all_pass) "PASS" else "FAIL")
