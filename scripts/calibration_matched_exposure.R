#!/usr/bin/env Rscript
# scripts/calibration_matched_exposure.R -- T16.  Calibrate at the neighbour
# exposure the 120 unsampled LGAs actually face.
#
# One command reproduces every number this ticket reports:
#     Rscript scripts/calibration_matched_exposure.R
# Design phase only (builds the graph, computes e120 and the matched groups,
# fits nothing):
#     Rscript scripts/calibration_matched_exposure.R --design-only
#
# ============================================================================
# THE QUESTION
# ============================================================================
# T12 removed a whole geopolitical zone: coverage 0.775, FAIL.
# T13 removed single LGAs with every neighbour kept: coverage 0.940, PASS.
# The 120 LGAs the paper makes claims about sit in neither situation.  Each of
# them has some of its neighbours unobserved too.  This script measures the
# calibration at THAT exposure, matched, rather than assumed to be "near" the
# passing end of the range.
#
# ============================================================================
# PRE-DECLARED PASS RULE -- identical to T12 and T13, third time, unchanged
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
# (A) THE GRAPH.  Built here from data/public/boundaries/geoBoundaries-NGA-ADM2
#     _simplified.geojson with poly2nb(queen = TRUE), the same file and call as
#     scripts/lga_model.R and scripts/calibration_lga_cv.R, and asserted against
#     the known 774 nodes / 2,230 edges / 1 component / 0 isolates.
#     data/derived/neighbours.csv is NOT read anywhere in this script: it is the
#     37-node STATE graph, and the brief says so.
#
# (B) THE D ESIGN DEVIATES FROM "DRAW 200 THEN SPLIT", AND THE REASON IS
#     ARITHMETIC, NOT CONVENIENCE.  A uniform draw of 40 LGAs from the 654 that
#     hold a cluster has expected internal adjacent pairs
#         C(40,2) * 2*2230 / (774*773) = 780 * 0.0074543 = 5.81,
#     whatever the seed, because the queen graph is sparse.  The target implied
#     by the 120 unsampled LGAs is ~4x that.  No random split of 200 drawn LGAs
#     can therefore land within +-20% of the target except by chance, so the
#     brief's own tolerance rule could never be met by resampling a plain draw.
#     The 200 LGAs are instead CONSTRUCTED: five disjoint groups of 40, built in
#     order from the remaining pooled LGAs by a random start plus a deterministic
#     swap search that moves the group's internal edge count to round(40*e120).
#     The seed is 20261124 as required, set inside build_design() so the groups
#     do not depend on any RNG consumed earlier.  The achieved value, the target
#     and the ratio are all printed and written; nothing is silently redefined.
#     If any group lands outside +-20% the script stops before fitting.
#
# (C) e120, THE TARGET.  The brief defines it as "the number of adjacent pairs
#     inside the set, per LGA": e120 = (edges with both ends among the 120) /
#     120.  Each edge has two ends, so a group of 40 matching e120 also matches
#     the mean number of unobserved NEIGHBOURS per unobserved LGA, which is the
#     quantity exposure actually means.  Both are printed.
#
# (D) CLUSTER COUNTS.  Every cluster count and the observed/unobserved split come
#     from data/derived/cluster_lga_fixed.csv.  n_clusters in the output is taken
#     from that file; the household-derived count is computed as well and
#     ASSERTED equal for every held-out LGA, so the two sources are checked
#     against each other rather than one being trusted.
#
# (E) THE MODEL.  Byte-identical specification to T13: household binomial, ten
#     design columns of eight covariates, BYM2 on the 774-node queen graph, IID
#     cluster effect, INLA 25.10.19 defaults, 774 prediction rows at each LGA's
#     mean covariate profile from the FULL household file, cluster effect
#     marginalised by the same 7-point Gauss-Hermite rule, intervals from the
#     marginal of the linear predictor on a 2001-point normal grid.  No
#     area-level covariate enters (T15 showed them inert; adding them would
#     confound this test with that one).
#
# (F) COVARIATES HELD KNOWN, as in T12 and T13.  This tests the outcome model and
#     the spatial field, NOT covariate availability.  Disclosed, same limitation.
#
# (G) SCORING.  Identical to T13: direct unweighted proportion from the held-out
#     households, cluster-robust ratio linearisation (strata = state, PSU =
#     cluster), deff imputation for single-cluster LGAs, model_var =
#     ((ci_high - ci_low)/(2*1.96))^2, z = (model - direct)/sqrt(both).
#
# OUT OF SCOPE: count-functional calibration (needs joint draws per fold) and the
# 120 never-clustered LGAs themselves (they have no direct estimate).
# ============================================================================

suppressPackageStartupMessages({
  library(sf)
  library(spdep)
  library(INLA)
  library(jsonlite)
})
sf_use_s2(TRUE)

SEED        <- 20261124L
N_DRAW      <- 200L
N_GROUP     <- 5L
GROUP_SIZE  <- 40L
GH_N        <- 7L
GRID_N      <- 2001L
FIT_LIMIT   <- 300          # seconds per fit; the brief says stop and report beyond this
BAND        <- 0.20         # +-20% of e120, per the brief
N_BOOT      <- 2000L        # bootstrap for the uncertainty of mean z and sd z

args        <- commandArgs(trailingOnly = TRUE)
design_only <- "--design-only" %in% args

root <- normalizePath(".")
p_hh    <- file.path(root, "data/derived/analysis_households_lga.csv")
p_bound <- file.path(root, "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson")
p_pop   <- file.path(root, "data/derived/lga_population.csv")
p_est   <- file.path(root, "data/derived/lga_estimates.csv")
p_clu   <- file.path(root, "data/derived/cluster_lga_fixed.csv")
p_out   <- file.path(root, "data/derived/calibration_matched.csv")
p_json  <- file.path(root, "data/derived/calibration_matched.json")
p_t12   <- file.path(root, "data/derived/calibration_summary.json")
p_t13   <- file.path(root, "data/derived/calibration_lga_cv.json")
p_prog  <- file.path(root, ".agent/T16-progress.md")

for (f in c(p_hh, p_bound, p_pop, p_est, p_clu)) {
  if (!file.exists(f)) stop("missing input: ", f, " -- run from the repo root", call. = FALSE)
}

msg  <- function(...) cat(sprintf(...), "\n", sep = "")
tick <- function(t0) round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)
prog <- function(...) {
  line <- paste0(format(Sys.time(), "%H:%M"), "  ", sprintf(...), "\n")
  cat(line, sep = "")
  try(cat(line, sep = "", file = p_prog, append = TRUE), silent = TRUE)
}

t_all <- Sys.time()
prog("T16 start; seed %d; design-only=%s", SEED, design_only)

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
## 2. The spatial graph -- built ONCE over all 774 LGAs.  See (A).
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
comp <- n.comp.nb(nb)     # $nc component count
msg("\nLGA graph: %d nodes, %d edges, %d component(s), %d isolate(s)",
    n_lga, sum(deg) / 2, comp$nc, sum(deg == 0))
if (sum(deg) == 0) stop("graph has isolates; BYM2 is improper there", call. = FALSE)
if (comp$nc != 1L) stop("graph is disconnected (", comp$nc, " components)", call. = FALSE)
if (sum(deg) / 2 != 2230) stop("expected 2,230 LGA edges, got ", sum(deg) / 2, call. = FALSE)

W <- nb2mat(nb, style = "B", zero.policy = TRUE)
ADJ <- (W + t(W)) > 0
if (!isTRUE(all(ADJ == t(ADJ)))) stop("adjacency not symmetric", call. = FALSE)
if (sum(ADJ) / 2 != sum(deg) / 2) stop("adjacency matrix does not match the nb object", call. = FALSE)

nb_path <- file.path(tempdir(), "lga_graph_matched.adj")
nb2INLA(nb_path, nb)
gr <- inla.read.graph(nb_path)
msg("INLA graph: %d nodes, %d edges", gr$n, sum(gr$nnbs) / 2)

## ---- LGA -> state ----------------------------------------------------------
pop <- read.csv(p_pop, stringsAsFactors = FALSE)
state_of_lga <- pop$state_iso[match(LGA_ID, pop$lga_id)]
if (anyNA(state_of_lga)) stop("an LGA has no parent state in lga_population.csv", call. = FALSE)

## ---- in-sample full-fit estimate, for the descriptive comparison -----------
est <- read.csv(p_est, stringsAsFactors = FALSE)
if (!all(c("lga_id", "posterior_mean") %in% names(est)))
  stop("lga_estimates.csv lacks the needed columns", call. = FALSE)
in_sample <- est$posterior_mean[match(LGA_ID, est$lga_id)]
if (anyNA(in_sample)) stop("an LGA has no in-sample estimate", call. = FALSE)

## ==========================================================================
## 3. Cluster counts: data/derived/cluster_lga_fixed.csv ONLY.  See (D).
## ==========================================================================
clu <- read.csv(p_clu, stringsAsFactors = FALSE)
if (!all(c("DHSCLUST", "hv001", "lga_id") %in% names(clu)))
  stop("cluster_lga_fixed.csv lacks DHSCLUST / hv001 / lga_id", call. = FALSE)
if (anyDuplicated(clu$DHSCLUST)) stop("duplicate DHSCLUST in cluster_lga_fixed.csv", call. = FALSE)
if (anyDuplicated(clu$hv001))    stop("duplicate hv001 in cluster_lga_fixed.csv", call. = FALSE)
if (!all(clu$lga_id %in% LGA_ID)) stop("a cluster is assigned to an LGA absent from the boundary file", call. = FALSE)

cl_counts <- as.numeric(table(factor(clu$lga_id, levels = LGA_ID)))
if (sum(cl_counts) != nrow(clu)) stop("cluster counts do not sum to the file's row count", call. = FALSE)
obs_idx   <- which(cl_counts > 0L)
unobs_idx <- which(cl_counts == 0L)
obs_lga   <- LGA_ID[obs_idx]
unobs_lga <- LGA_ID[unobs_idx]
msg("\nclusters (cluster_lga_fixed.csv): %d in %d LGAs; %d LGAs hold none",
    nrow(clu), length(obs_idx), length(unobs_idx))
if (length(obs_idx) != 654L)
  stop("expected 654 LGAs with at least one cluster, got ", length(obs_idx), call. = FALSE)
if (length(unobs_idx) != 120L)
  stop("expected 120 LGAs with no cluster, got ", length(unobs_idx), call. = FALSE)

## cross-check the two sources against each other -- not one trusted, both checked
hh_obs <- sort(unique(d$lga_id))
if (!setequal(hh_obs, obs_lga))
  stop("the household file's clustered-LGA set is not the cluster file's observed set", call. = FALSE)
lga_idx_full <- match(d$lga_id, LGA_ID)
if (anyNA(lga_idx_full)) stop("household lga_id not in the boundary file", call. = FALSE)
n_hh_lga <- as.numeric(tabulate(lga_idx_full, nbins = n_lga))
if (any(n_hh_lga[unobs_idx] != 0L)) stop("an LGA with no cluster nevertheless holds households", call. = FALSE)
if (any(n_hh_lga[obs_idx] == 0L))   stop("an LGA with a cluster holds no households", call. = FALSE)
hh_clu_counts <- vapply(seq_len(n_lga), function(i) {
  if (n_hh_lga[i] == 0L) 0L else length(unique(d$hv001[lga_idx_full == i]))
}, integer(1))
if (!identical(as.integer(cl_counts), as.integer(hh_clu_counts)))
  stop("per-LGA cluster counts differ between cluster_lga_fixed.csv and the household file", call. = FALSE)
msg("cross-check: per-LGA cluster counts and the 654/120 split agree across both files")

## ==========================================================================
## 4. e120 -- the exposure of the 120 unsampled LGAs.  See (C).
## ==========================================================================
E_in <- sum(ADJ[unobs_idx, unobs_idx]) / 2
e120 <- E_in / length(unobs_idx)
nbr_in   <- vapply(unobs_idx, function(i) sum(ADJ[i, unobs_idx]), numeric(1))
deg_u    <- deg[unobs_idx]
share_obs <- 1 - nbr_in / deg_u
msg("\n===== THE EXPOSURE OF THE 120 UNCLUSTERED LGAs =====")
msg("adjacent pairs with BOTH ends among the 120: %d  (%.4f per LGA)  <== e120", E_in, e120)
msg("mean unobserved neighbours per unobserved LGA: %.4f (2 * e120)", 2 * e120)
msg("degree: mean %.3f median %.1f | neighbours observed: median share %.4f, min %.4f",
    mean(deg_u), median(deg_u), median(share_obs), min(share_obs))
msg("LGAs with fewer than half their neighbours observed: %d of %d",
    sum(share_obs < 0.5), length(unobs_idx))
msg("LGAs all of whose neighbours are observed: %d of %d", sum(nbr_in == 0L), length(unobs_idx))
msg("(secretary's figures for comparison: median 0.833, 2 of 120 below half, 36 fully observed, min 0.333)")

## ==========================================================================
## 5. Covariate profiles, held KNOWN from the full file.  See (F).
## ==========================================================================
X_full <- as.matrix(d[, COV]); storage.mode(X_full) <- "double"
Xbar <- matrix(NA_real_, n_lga, ncol(X_full), dimnames = list(NULL, COV))
for (k in seq_len(ncol(X_full)))
  Xbar[, k] <- as.numeric(tapply(X_full[, k], factor(lga_idx_full, levels = seq_len(n_lga)), mean))
states_all <- sort(unique(state_of_lga))
Xbar_state <- matrix(NA_real_, length(states_all), ncol(X_full))
for (j in seq_along(states_all)) {
  in_s <- state_of_lga[lga_idx_full] == states_all[j]
  if (any(in_s)) Xbar_state[j, ] <- colMeans(X_full[in_s, , drop = FALSE])
}
no_data <- which(n_hh_lga == 0L)
if (!identical(sort(no_data), sort(unobs_idx)))
  stop("the empty-LGA set and the no-cluster set are not the same 120 areas", call. = FALSE)
for (i in no_data) {
  j <- match(state_of_lga[i], states_all)
  if (anyNA(Xbar_state[j, ])) stop("parent state of an empty LGA has no households", call. = FALSE)
  Xbar[i, ] <- Xbar_state[j, ]
}
if (anyNA(Xbar)) stop("covariate profile still has NA", call. = FALSE)
msg("\ncovariate profiles: %d LGAs from their own households, %d from the parent state (held known)",
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
## 6. The matched construction.  See (B).
## ==========================================================================
T_edges <- GROUP_SIZE * e120                 # target internal pairs per group
band_lo <- T_edges * (1 - BAND)
band_hi <- T_edges * (1 + BAND)
E_random <- choose(GROUP_SIZE, 2) * (2 * sum(deg) / 2) / (n_lga * (n_lga - 1))

msg("\n===== THE MATCHED CONSTRUCTION (seed %d) =====", SEED)
msg("target internal pairs per group of %d: %.2f  -> +-%.0f%% band [%.2f, %.2f]",
    GROUP_SIZE, T_edges, 100 * BAND, band_lo, band_hi)
msg("uniform random split of 40 from the graph would give %.2f pairs on average (%.2fx too low)",
    E_random, T_edges / E_random)

build_group <- function(pool, target, size, restarts = 400L, swaps = 800L) {
  best <- list(dev = Inf, S = integer(0), E = NA_real_, restart = NA_integer_, swaps = NA_integer_)
  for (r in seq_len(restarts)) {
    S <- sample(pool, size)
    Sflag <- logical(n_lga); Sflag[S] <- TRUE
    dS <- integer(n_lga)
    for (u in S) { xu <- nb[[u]]; dS[xu] <- dS[xu] + 1L }
    E  <- sum(dS[S]) / 2
    it_used <- 0L
    for (it in seq_len(swaps)) {
      need <- target - E
      if (abs(need) <= 0.5) break
      outside <- pool[!Sflag[pool]]
      if (!length(outside)) break
      gv <- dS[outside]; lu <- dS[S]
      dev <- abs(outer(gv, lu, "-") - need)
      m   <- min(dev)
      cand <- which(dev == m, arr.ind = TRUE)
      pick <- cand[sample.int(nrow(cand), 1L), ]
      v <- outside[pick[1L]]; u <- S[pick[2L]]
      delta <- gv[pick[1L]] - lu[pick[2L]]
      Sflag[u] <- FALSE; Sflag[v] <- TRUE
      S[S == u] <- v
      xu <- nb[[u]]; dS[xu] <- dS[xu] - 1L
      xv <- nb[[v]]; dS[xv] <- dS[xv] + 1L
      E <- E + delta
      it_used <- it
    }
    dv <- abs(E - target)
    if (dv < best$dev) best <- list(dev = dv, S = S, E = E, restart = r, swaps = it_used)
    if (dv <= max(0.5, 0.01 * target)) break
  }
  best
}

build_design <- function() {
  set.seed(SEED)                 # own stream: independent of anything before this call
  pool <- obs_idx
  members <- vector("list", N_GROUP)
  for (k in seq_len(N_GROUP)) {
    b <- build_group(pool, T_edges, GROUP_SIZE)
    members[[k]] <- sort(b$S)
    pool <- setdiff(pool, b$S)
    msg("group %d built: %d pairs (target %.2f, ratio %.3f), restart %d, %d swaps, pool left %d",
        k, as.integer(b$E), T_edges, b$E / T_edges, b$restart, b$swaps, length(pool))
  }
  members
}

grp_of <- function(members) {
  out <- integer(n_lga)
  for (k in seq_along(members)) out[members[[k]]] <- k
  out
}

members <- build_design()
grp_lga <- grp_of(members)
drawn_idx <- sort(unlist(members))
drawn <- LGA_ID[drawn_idx]
if (length(drawn) != N_DRAW) stop("not 200 LGAs were built", call. = FALSE)
if (anyDuplicated(drawn)) stop("the construction holds a duplicate LGA", call. = FALSE)
if (!all(drawn %in% obs_lga)) stop("a held-out LGA is not in the 654 clustered LGAs", call. = FALSE)

A <- ADJ[drawn_idx, drawn_idx]
intra_pairs <- vapply(seq_len(N_GROUP), function(k) {
  j <- which(grp_lga[drawn_idx] == k); sum(A[j, j]) / 2
}, numeric(1))
ach <- intra_pairs / GROUP_SIZE
ratio <- ach / e120
in_band <- ratio >= 1 - BAND & ratio <= 1 + BAND

msg("\n===== EXPOSURE TABLE: target versus achieved =====")
msg("%-6s %8s %10s %10s %8s %8s", "group", "LGAs", "pairs", "pairs/LGA", "ratio", "in band")
for (k in seq_len(N_GROUP))
  msg("%-6d %8d %10d %10.4f %8.3f %8s", k, GROUP_SIZE, as.integer(intra_pairs[k]),
      ach[k], ratio[k], if (in_band[k]) "yes" else "NO")
msg("%-6s %8d %10.4f %10.4f %8.3f %8s", "e120", length(unobs_idx), E_in, e120, 1, "-")
msg("target band on pairs/LGA: [%.4f, %.4f]", e120 * (1 - BAND), e120 * (1 + BAND))

state_cover <- vapply(seq_len(N_GROUP), function(k)
  length(unique(state_of_lga[members[[k]]])), integer(1))
msg("states spanned per group: %s", paste(state_cover, collapse = " "))

exposure_block <- list(
  definition = paste("e120 = adjacent pairs with both ends among the 120 unclustered LGAs,",
                     "divided by 120; a group of 40 matching it also matches the mean number of",
                     "unobserved neighbours per unobserved LGA"),
  n_unclustered = length(unobs_idx),
  internal_pairs_among_120 = E_in,
  e120 = e120,
  mean_unobserved_neighbours_per_lga = 2 * e120,
  degree_mean = mean(deg_u), degree_median = median(deg_u),
  median_share_of_neighbours_observed = median(share_obs),
  min_share_of_neighbours_observed = min(share_obs),
  n_with_under_half_observed = sum(share_obs < 0.5),
  n_fully_observed_neighbourhood = sum(nbr_in == 0L),
  secretary_figures = list(median_share_observed = 0.833, n_under_half = 2L,
                           n_fully_observed = 36L, min_share_observed = 0.333),
  target_pairs_per_group = T_edges,
  band = c(lower = band_lo, upper = band_hi),
  band_on_pairs_per_lga = c(lower = e120 * (1 - BAND), upper = e120 * (1 + BAND)),
  expected_pairs_under_a_uniform_split = E_random,
  achieved = lapply(seq_len(N_GROUP), function(k) list(
    group = k, n_lgas = GROUP_SIZE,
    internal_pairs = as.integer(intra_pairs[k]),
    pairs_per_lga = ach[k], ratio_to_e120 = ratio[k], in_band = in_band[k],
    states_spanned = state_cover[k])),
  all_groups_in_band = all(in_band)
)
msg("\nexposure band achieved for all groups: %s", if (all(in_band)) "YES" else "NO")

## ---- POST-FIRST-RUN AUDIT.  Descriptive; the design and the pass rule are
## ---- untouched.  It measures what exposure the design ACTUALLY applied.
## The 120 have unobserved neighbours only among themselves.  A held-out
## clustered LGA has those plus its neighbours among the permanent 120, which
## are in no fit of any ticket.  The brief's e120 captures the first term only.
adj120_h <- vapply(drawn_idx, function(i) sum(ADJ[i, unobs_idx]), numeric(1))
within_h <- vapply(seq_along(drawn_idx), function(j) {
  gk <- grp_lga[drawn_idx[j]]
  sum(ADJ[drawn_idx[j], drawn_idx[grp_lga[drawn_idx] == gk]])
}, numeric(1))
audit <- list(
  status = paste("added after the five fits, before this block was written; it changes neither the",
                 "design nor the pre-declared pass rule, and no number in the verdict depends on it"),
  what_it_measures = paste("total unobserved neighbours per held-out LGA: neighbours held out with it,",
                           "plus neighbours among the 120 that no fit of any ticket ever sees"),
  set120_unobserved_neighbours_mean = mean(nbr_in),
  set120_distribution = as.list(table(factor(nbr_in, levels = 0:max(nbr_in)))),
  heldout_within_group_mean = mean(within_h),
  heldout_adjacent_to_the_120_mean = mean(adj120_h),
  heldout_total_mean = mean(within_h + adj120_h),
  ratio_heldout_total_to_set120 = mean(within_h + adj120_h) / mean(nbr_in),
  all_654_adjacent_to_the_120_mean = mean(vapply(obs_idx, function(i) sum(ADJ[i, unobs_idx]), numeric(1))),
  consequence = paste("the groups are MORE exposed than the 120: 1.67 unobserved neighbours against",
                      "0.95, 1.76x. T16 is therefore a harsher test than the paper's problem, and the",
                      "120's coverage is bracketed between T16 (exposure 1.67) and T13 (exposure 0.73,",
                      "the 120's adjacency alone) rather than equal to T16's number")
)
msg("\n===== EXPOSURE ACTUALLY APPLIED (descriptive audit) =====")
msg("120 set: unobserved neighbours per LGA %.4f (distribution %s)",
    audit$set120_unobserved_neighbours_mean,
    paste(names(table(nbr_in)), table(nbr_in), sep = ":", collapse = "  "))
msg("held-out: within-group %.4f + adjacent to the 120 %.4f = %.4f total  (%.3f x the 120's)",
    audit$heldout_within_group_mean, audit$heldout_adjacent_to_the_120_mean,
    audit$heldout_total_mean, audit$ratio_heldout_total_to_set120)
msg("T13's exposure by the same measure: %.4f (mean adjacency to the 120 over the 654)",
    audit$all_654_adjacent_to_the_120_mean)

if (!all(in_band)) {
  msg("\nSTOP: the +-%.0f%% exposure band was NOT achieved. Best achieved: %s",
      100 * BAND, paste(sprintf("%.4f", ach), collapse = " "))
  msg("Ratio to e120: %s. Report the closest achieved; do not redefine the target.",
      paste(sprintf("%.3f", ratio), collapse = " "))
  out <- list(
    generated_by = "scripts/calibration_matched_exposure.R",
    ticket = "T16", stopped_before_fitting = TRUE,
    stopped_reason = "exposure band not achieved by the matched construction",
    exposure = exposure_block,
    held_out_lga_ids = drawn, group_of_lga = setNames(grp_lga[drawn_idx], drawn)[drawn]
  )
  write(toJSON(out, auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null"), p_json)
  prog("STOPPED: exposure band not achieved; achieved %s vs target %.4f",
       paste(sprintf("%.3f", ach), collapse = " "), e120)
  quit(save = "no", status = 0)
}

if (design_only) {
  msg("\n--design-only: design accepted, no fit run.")
  prog("design accepted: e120 %.4f; achieved %s; stopping before fits (--design-only)",
       e120, paste(sprintf("%.4f", ach), collapse = " "))
  quit(save = "no", status = 0)
}

## ==========================================================================
## 7. Design variance of a direct LGA proportion -- same as T12/T13
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
## 8. Fit machinery, written to disk group by group (resumable)
## ==========================================================================
COLS <- c("lga_id", "group", "model_mean", "ci_low", "ci_high",
          "direct_unweighted", "direct_weighted", "design_se", "design_se_source",
          "n_clusters", "z", "in_sample_fit",
          "lga_name", "state_iso", "n_households", "model_se",
          "group_fit_seconds", "group_waic", "group_mode_status", "group_sd_cluster",
          "group_deff_median", "group_n_training", "group_n_clusters",
          "internal_pairs")

existing <- NULL
done_groups <- integer(0)
if (file.exists(p_out)) {
  existing <- read.csv(p_out, stringsAsFactors = FALSE, check.names = FALSE)
  if (!all(COLS %in% names(existing))) stop(p_out, " exists but lacks the T16 columns", call. = FALSE)
  done_groups <- sort(unique(existing$group))
  msg("\nresuming: %s already holds %d rows from group(s): %s",
      basename(p_out), nrow(existing), paste(done_groups, collapse = ", "))
  if (!setequal(existing$lga_id, drawn[grp_lga[drawn_idx] %in% done_groups]))
    stop("the rows on disk are not the LGAs this design holds out; delete ", p_out, call. = FALSE)
}

fit_group <- function(k) {
  held <- LGA_ID[members[[k]]]
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

  msg("\n--- group %d: %d LGAs held out, %d internal pairs ---", k, length(held), intra_pairs[k])
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
  if (!is.na(ms) && ms != 0L)
    msg("WARNING: group %d mode status %d -- reported, specification not changed", k, ms)

  ## ---- the marginal of theta, from the marginal of eta (identical to T13) --
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
  ## (D): the reported count comes from cluster_lga_fixed.csv; assert it matches this group
  if (!identical(as.integer(n_cl_out[members[[k]]]), as.integer(cl_counts[members[[k]]])))
    stop("held-out cluster counts disagree with cluster_lga_fixed.csv (group ", k, ")", call. = FALSE)

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
  zi <- members[[k]]
  if (anyNA(zi)) stop("a held-out LGA is missing from the boundary file", call. = FALSE)
  model_var <- ((ci_high - ci_low) / (2 * 1.96))^2
  zz <- ifelse(is.na(direct_u), NA_real_, (model_mean - direct_u) / sqrt(model_var + dvar))

  block <- data.frame(
    lga_id = LGA_ID[zi], group = k,
    model_mean = model_mean[zi], ci_low = ci_low[zi], ci_high = ci_high[zi],
    direct_unweighted = direct_u[zi], direct_weighted = direct_w[zi],
    design_se = sqrt(dvar[zi]), design_se_source = dsrc[zi],
    n_clusters = cl_counts[zi], z = zz[zi], in_sample_fit = in_sample[zi],
    lga_name = lga_name[zi], state_iso = state_of_lga[zi],
    n_households = n_hh_out[zi], model_se = sqrt(model_var[zi]),
    group_fit_seconds = t_fit, group_waic = fit$waic$waic, group_mode_status = ms,
    group_sd_cluster = sd_v, group_deff_median = deff_med,
    group_n_training = n_tr, group_n_clusters = n_clu,
    internal_pairs = as.integer(intra_pairs[k]),
    stringsAsFactors = FALSE
  )
  block$design_se_source[is.na(block$design_se_source)] <- "none"
  if (anyNA(block$z)) stop("a held-out LGA has no z -- it had households but no direct estimate", call. = FALSE)
  if (nrow(block) != GROUP_SIZE) stop("block is not 40 rows", call. = FALSE)
  if (any(block$n_households != n_hh_lga[zi])) stop("held-out household counts do not match the full file", call. = FALSE)

  out <- if (is.null(existing)) block[, COLS] else rbind(existing[COLS], block[, COLS])
  out <- out[order(out$group, match(out$lga_id, LGA_ID)), COLS]
  write.csv(out, p_out, row.names = FALSE)
  existing <<- out
  msg("wrote %d rows for group %d | file now holds %d rows, %d group(s)",
      nrow(block), k, nrow(out), length(unique(out$group)))
  prog("group %d fitted %.0f s, 40 predicted, block written (file holds %d rows)", k, t_fit, nrow(out))

  invisible(list(group = k, t_fit = t_fit, mode_status = ms, waic = fit$waic$waic,
                 sd_v = sd_v, deff_med = deff_med, n_train = n_tr, n_clu = n_clu,
                 n_single = length(single)))
}

## ==========================================================================
## 9. Run the five groups
## ==========================================================================
for (k in seq_len(N_GROUP)) {
  if (k %in% done_groups) { msg("\n--- group %d already on disk, skipped ---", k); next }
  fit_group(k)
}

## ==========================================================================
## 10. Pooled checks, fixed pass rule
## ==========================================================================
keep_cols <- COLS
R <- read.csv(p_out, stringsAsFactors = FALSE, check.names = FALSE)
R <- R[order(R$group, match(R$lga_id, LGA_ID)), keep_cols]
if (nrow(R) != N_DRAW) stop("expected ", N_DRAW, " rows, have ", nrow(R), call. = FALSE)
if (anyDuplicated(R$lga_id)) stop("an LGA appears more than once", call. = FALSE)
if (length(unique(R$group)) != N_GROUP) stop("not all five groups are present", call. = FALSE)
if (!setequal(R$lga_id, drawn)) stop("the rows on disk are not the 200 built LGAs", call. = FALSE)
if (abs(sum(R$n_households) - sum(n_hh_lga[drawn_idx])) > 1e-9)
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
prog("z: mean %+0.4f sd %.4f coverage %.4f -> %s", mean_z, sd_z, cov_z,
     if (all_pass) "PASS" else "FAIL")

## uncertainty of the three checks themselves (no extra fits)
wilson <- function(x, n, z = 1.96) {
  p <- x / n; dd <- 1 + z^2 / n
  ctr <- (p + z^2 / (2 * n)) / dd
  hw  <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / dd
  c(lower = ctr - hw, upper = ctr + hw)
}
set.seed(SEED + 1L)
bt <- matrix(sample(zz, n_z * N_BOOT, replace = TRUE), n_z, N_BOOT)
b_mean <- colMeans(bt); b_sd <- apply(bt, 2, sd)
b_cov  <- colMeans(abs(bt) <= 1.96)
ci_mean <- quantile(b_mean, c(0.025, 0.975), names = FALSE)
ci_sd   <- quantile(b_sd,   c(0.025, 0.975), names = FALSE)
ci_cov  <- quantile(b_cov,  c(0.025, 0.975), names = FALSE)
ci_wil  <- wilson(sum(abs(zz) <= 1.96), n_z)
msg("\nMonte Carlo uncertainty of the checks (%d bootstrap resamples):", N_BOOT)
msg("  mean z  %.4f  bootstrap 95%% [%.4f, %.4f]", mean_z, ci_mean[1], ci_mean[2])
msg("  sd z    %.4f  bootstrap 95%% [%.4f, %.4f]", sd_z, ci_sd[1], ci_sd[2])
msg("  coverage %.4f  bootstrap 95%% [%.4f, %.4f]  Wilson [%.4f, %.4f]",
    cov_z, ci_cov[1], ci_cov[2], ci_wil[1], ci_wil[2])

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
       internal_pairs = as.integer(intra_pairs[k]),
       pairs_per_lga = ach[k], ratio_to_e120 = ratio[k], in_band = in_band[k],
       fit_seconds = R$group_fit_seconds[i][1],
       waic = R$group_waic[i][1], mode_status = R$group_mode_status[i][1],
       sd_cluster_effect = R$group_sd_cluster[i][1],
       deff_median = R$group_deff_median[i][1],
       n_training_households = R$group_n_training[i][1],
       n_training_clusters = R$group_n_clusters[i][1],
       states_spanned = state_cover[k])
})
msg("\nby group:")
for (p in per_group)
  msg("  group %d  n=%2d  mean %+0.3f  sd %0.3f  coverage %0.3f  internal pairs %d (%.3f x e120) %s",
      p$group, p$n, p$mean_z, p$sd_z, p$coverage, p$internal_pairs, p$ratio_to_e120,
      if (p$in_band) "" else "OUT OF BAND")

## ---- POST HOC, DESCRIPTIVE ONLY.  Dropping a group after seeing the result
## ---- is NOT a permitted specification and is not used as one; this says only
## ---- how concentrated the excess dispersion is.
logo <- lapply(seq_len(N_GROUP), function(k) {
  s <- zz[R$group != k]
  list(group_removed = k, n = length(s), mean_z = mean(s), sd_z = sd(s),
       coverage = mean(abs(s) <= 1.96), passes_all_three = chk(mean(s), PASS$mean_z) &&
         chk(sd(s), PASS$sd_z) && chk(mean(abs(s) <= 1.96), PASS$coverage))
})
msg("\nPOST HOC, not a criterion -- pooled checks without each group in turn:")
for (o in logo)
  msg("  without group %d: n %d  mean %+0.3f  sd %.4f  coverage %.4f  %s",
      o$group_removed, o$n, o$mean_z, o$sd_z, o$coverage,
      if (o$passes_all_three) "would pass all three" else "still fails")

## ==========================================================================
## 11. The three-experiment comparison.  Read from the other tickets' artefacts.
## ==========================================================================
rd <- function(p) if (file.exists(p)) tryCatch(fromJSON(p), error = function(e) NULL) else NULL
t12 <- rd(p_t12); t13 <- rd(p_t13)
get3 <- function(x) {
  if (is.null(x) || is.null(x$primary)) return(list(mean_z = NA_real_, sd_z = NA_real_, coverage = NA_real_, n = NA_integer_))
  list(mean_z = x$primary$mean_z, sd_z = x$primary$sd_z,
       coverage = x$primary$coverage_abs_z_le_1_96, n = x$primary$n)
}
t12s <- get3(t12); t13s <- get3(t13)

cmp <- data.frame(
  experiment = c("T12 leave-one-zone-out", "T16 matched exposure", "T13 leave-one-LGA-out"),
  neighbours_kept = c("0% (zone removed with the area)", "matched to the 120 (within-group exposure)",
                      "100% (single LGA removed)"),
  n = c(t12s$n, n_z, t13s$n),
  mean_z = c(t12s$mean_z, mean_z, t13s$mean_z),
  sd_z = c(t12s$sd_z, sd_z, t13s$sd_z),
  coverage = c(t12s$coverage, cov_z, t13s$coverage),
  stringsAsFactors = FALSE
)
msg("\n===== THREE-EXPERIMENT COMPARISON (same pass rule, same estimator, same scoring) =====")
msg("%-26s %6s %8s %8s %9s", "design", "n", "mean z", "sd z", "coverage")
for (i in seq_len(nrow(cmp)))
  msg("%-26s %6d %+8.3f %8.3f %9.3f   %s", cmp$experiment[i], cmp$n[i], cmp$mean_z[i],
      cmp$sd_z[i], cmp$coverage[i],
      if (i == 2L) paste0("exposure ", sprintf("%.3f", ach[1]), "-", sprintf("%.3f", ach[N_GROUP]), " pairs/LGA") else "")

lies_between <- function(a, b, x) (x - a) * (x - b) <= 0
between <- list(
  coverage_between_T12_and_T13 = lies_between(t12s$coverage, t13s$coverage, cov_z),
  sd_z_between_T12_and_T13     = lies_between(t12s$sd_z, t13s$sd_z, sd_z),
  mean_z_between_T12_and_T13   = lies_between(t12s$mean_z, t13s$mean_z, mean_z),
  distances = list(
    mean_z_from_T12 = mean_z - t12s$mean_z, mean_z_from_T13 = mean_z - t13s$mean_z,
    sd_z_from_T12 = sd_z - t12s$sd_z,       sd_z_from_T13 = sd_z - t13s$sd_z,
    coverage_from_T12 = cov_z - t12s$coverage, coverage_from_T13 = cov_z - t13s$coverage)
)
msg("\nbetween T12 and T13?  coverage %s | sd z %s | mean z %s",
    between$coverage_between_T12_and_T13, between$sd_z_between_T12_and_T13,
    between$mean_z_between_T12_and_T13)
msg("T16 minus T12: mean z %+0.3f | sd z %+0.3f | coverage %+0.3f",
    between$distances$mean_z_from_T12, between$distances$sd_z_from_T12,
    between$distances$coverage_from_T12)
msg("T16 minus T13: mean z %+0.3f | sd z %+0.3f | coverage %+0.3f",
    between$distances$mean_z_from_T13, between$distances$sd_z_from_T13,
    between$distances$coverage_from_T13)
if (!chk(cov_z, PASS$coverage) && cov_z <= t12s$coverage + 0.02)
  msg("VERDICT: T16 is no better than T12 -- neighbour exposure is not the mechanism;")
if (!chk(cov_z, PASS$coverage) && cov_z <= t12s$coverage + 0.02)
  msg("         the paper's transfer argument does not survive this test.")

## inflation factor, for continuity with T13
k_all <- sd_z
cov_after_k <- mean(abs(zz) <= 1.96 * k_all)
msg("\ninflation factor k = sd(z) = %.4f | coverage after widening every interval by k = %.4f",
    k_all, cov_after_k)

## ==========================================================================
## 12. Summary file
## ==========================================================================
construction <- paste(
  "Calibration at the neighbour exposure the 120 unsampled LGAs actually face.  The exposure is",
  "measured, not assumed: from the queen-contiguity graph over the 774 LGAs (built from",
  "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson, 774 nodes, 2,230 edges, one",
  "component, zero isolates), e120 = adjacent pairs with both ends among the 120 LGAs holding no",
  "cluster, divided by 120.  200 of the 654 LGAs that hold at least one cluster are then built into",
  "five disjoint groups of 40, each group's internal adjacent-pair count brought to round(40*e120) by",
  "a random start plus a deterministic swap search, so every group sits within +-20% of e120.  A",
  "uniform random split could not: its expected internal pairs are only C(40,2)*2*2230/(774*773) =",
  "5.81, about a quarter of the target.  Each group is one fit: that group's 40 LGAs' households are",
  "dropped and the identical household-level binomial model is refitted (ten design columns of eight",
  "covariates, BYM2 on the 774-node graph, IID cluster effect, INLA 25.10.19 defaults, no area-level",
  "covariates), then all 774 LGAs are predicted from prediction rows at each LGA's mean covariate",
  "profile taken from the FULL household file (covariates held known), cluster effect marginalised by",
  "the same 7-point Gauss-Hermite rule as scripts/lga_model.R.  The truth is the direct unweighted",
  "proportion from each held-out LGA's own households, with a cluster-robust ratio linearisation",
  "(strata = state, PSU = cluster) and median-design-effect imputation for single-cluster LGAs.",
  "z = (model_mean - direct)/sqrt(model_var + design_var).  Pass rule fixed before any fit and",
  "identical to T12 and T13: mean(z) in [-0.15,0.15], sd(z) in [0.85,1.15], share |z| <= 1.96 in",
  "[0.90,0.98].  Cluster counts and the observed/unobserved split come from",
  "data/derived/cluster_lga_fixed.csv and are cross-checked against the household file.",
  "Count-functional calibration is NOT tested: it needs joint draws per fold.", sep = " ")

sum_json <- list(
  generated_by = "scripts/calibration_matched_exposure.R",
  command = "Rscript scripts/calibration_matched_exposure.R",
  ticket = "T16",
  generated_on = as.character(Sys.Date()),
  seed = SEED,
  r_version = R.version.string,
  inla_version = as.character(packageVersion("INLA")),
  construction = construction,
  design = list(
    scheme = "matched neighbour exposure: leave-40-LGAs-out in five groups, exposure matched to the 120",
    n_held_out = N_DRAW, n_groups = N_GROUP, group_size = GROUP_SIZE,
    sampling_frame = "654 LGAs holding at least one cluster (cluster_lga_fixed.csv)",
    draw_seed = SEED,
    draw_method = paste("constructed, not a plain uniform draw: random start plus a swap search",
                        "per group, groups built in order from the remaining pool, seed set inside",
                        "build_design() so the groups cannot depend on earlier RNG use"),
    held_out_lga_ids = drawn,
    group_of_lga = setNames(grp_lga[drawn_idx], drawn)[drawn],
    graph_source = "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson (queen contiguity)",
    graph_nodes = n_lga, graph_edges = sum(deg) / 2, graph_components = comp$nc,
    adjacency_file_note = paste("data/derived/neighbours.csv is the 37-node STATE graph and was not",
                                "read by this script; the 774-node graph was built and its edge count",
                                "asserted to be 2,230"),
    covariates_held_known = TRUE, geospatial_covariates_used = 0L,
    weights_in_likelihood = FALSE,
    outcome_in_likelihood = "severe_fi = 1{hfs_sev >= 0.5}",
    cluster_counts_source = "data/derived/cluster_lga_fixed.csv",
    cluster_count_cross_check = "per-LGA cluster counts identical to the household file; 654/120 split identical"
  ),
  exposure = exposure_block,
  exposure_actually_applied = audit,
  leave_one_group_out_descriptive = list(
    per_group_removed = logo,
    note = paste("post hoc and descriptive only: the pre-declared rule is pooled over all 200 rows.",
                 "Dropping a group after seeing the result is not a permitted specification; this",
                 "block exists to show whether the excess dispersion is one group or the whole design")),
  pass_rule_declared_before_fitting = list(
    mean_z = list(pass_range = PASS$mean_z, value = mean_z, pass = chk(mean_z, PASS$mean_z)),
    sd_z = list(pass_range = PASS$sd_z, value = sd_z, pass = chk(sd_z, PASS$sd_z)),
    coverage_abs_z_le_1_96 = list(pass_range = PASS$coverage, value = cov_z,
                                  pass = chk(cov_z, PASS$coverage)),
    all_three_pass = all_pass, n_z = n_z,
    rule_changed_after_seeing_values = FALSE,
    identical_to_T12_and_T13_rule = TRUE
  ),
  primary = list(n = n_z, mean_z = mean_z, median_z = median(zz), sd_z = sd_z,
                 min_z = min(zz), max_z = max(zz),
                 coverage_abs_z_le_1_96 = cov_z,
                 n_abs_z_gt_1_96 = sum(abs(zz) > 1.96),
                 n_abs_z_gt_2_58 = sum(abs(zz) > 2.58),
                 rms_z = sqrt(mean(zz^2))),
  monte_carlo_uncertainty = list(
    n_boot = N_BOOT, seed = SEED + 1L,
    mean_z_ci = ci_mean, sd_z_ci = ci_sd, coverage_ci = ci_cov,
    coverage_wilson = ci_wil,
    note = paste("the checks are themselves estimated on 200 LGAs; these intervals say how much of a",
                 "difference between two experiments is sampling noise"))
  ,
  sensitivity = list(
    multi_cluster_lgas_only = sens_mc,
    by_group = per_group,
    note = paste("the multi-cluster subset uses only LGAs whose design variance is directly",
                 "estimable; it is a sensitivity, not a substitute for the pre-declared primary rule")
  ),
  three_experiment_comparison = list(
    table = cmp,
    T12 = c(t12s, list(source = "data/derived/calibration_summary.json")),
    T16 = list(mean_z = mean_z, sd_z = sd_z, coverage = cov_z, n = n_z,
               exposure_pairs_per_lga_min = min(ach), exposure_pairs_per_lga_max = max(ach)),
    T13 = c(t13s, list(source = "data/derived/calibration_lga_cv.json")),
    between_T12_and_T13 = between,
    reading = paste("if T16 lies between T12 and T13 the neighbour exposure is the mechanism; if T16",
                    "is no better than T12 the transfer argument fails and must be reported as failing")
  ),
  inflation_factor = list(k = k_all, coverage_after_widening_by_k = cov_after_k),
  descriptive_not_a_criterion = list(
    naive_interval_coverage = list(
      n_interval_contains_direct = sum(R$ci_low <= R$direct_unweighted & R$direct_unweighted <= R$ci_high),
      share = mean(R$ci_low <= R$direct_unweighted & R$direct_unweighted <= R$ci_high),
      note = paste("descriptive only; the direct estimate carries its own sampling error, so this",
                   "under-covers by construction and is NOT the criterion")),
    bias = list(mean_model_minus_direct = mean(R$model_mean - R$direct_unweighted),
                median_model_minus_direct = median(R$model_mean - R$direct_unweighted),
                share_of_lgas_model_below_direct = mean(R$model_mean < R$direct_unweighted)),
    correlation_with_direct = cor(R$model_mean, R$direct_unweighted),
    spread_ratio_model_over_direct = sd(R$model_mean) / sd(R$direct_unweighted),
    variance_shares = list(
      median_model_se = median(R$model_se), median_design_se = median(R$design_se, na.rm = TRUE),
      mean_share_of_z_variance_from_design = mean(R$design_se^2 /
                                                   (R$design_se^2 + R$model_se^2), na.rm = TRUE))
  ),
  fit_times_seconds = vapply(seq_len(N_GROUP), function(k) R$group_fit_seconds[R$group == k][1], numeric(1)),
  total_fit_seconds = sum(vapply(seq_len(N_GROUP), function(k) R$group_fit_seconds[R$group == k][1], numeric(1))),
  limitations = list(
    count_functional_not_tested = TRUE,
    never_clustered_lgas_not_tested = TRUE,
    n_never_clustered_excluded = length(unobs_idx),
    covariates_held_known = TRUE,
    linear_predictor_marginal_assumed_gaussian = TRUE,
    survey_design_not_in_likelihood = TRUE,
    matched_on_the_edge_count_not_the_full_exposure_distribution = TRUE,
    single_cluster_lgas_deff_imputed = sum(R$design_se_source == "deff_imputed"),
    n_degenerate_direct_zero_or_one = sum(R$direct_unweighted %in% c(0, 1)),
    note = paste("matching the internal edge count matches the MEAN unobserved-neighbour count;",
                 "the distribution across the group is not forced to match the 120's,",
                 "whose exposure ranges from 0 to 1/3 in share-of-neighbours terms")
  )
)
write(toJSON(sum_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null"), p_json)
msg("\nwrote %s (%.1f KB)", basename(p_json), file.size(p_json) / 1024)

## ==========================================================================
## 13. Final print
## ==========================================================================
msg("\n================ RESULT ================")
msg("exposure: e120 = %.4f pairs/LGA | achieved %s | all in +-%.0f%% band: %s",
    e120, paste(sprintf("%.4f", ach), collapse = " "), 100 * BAND,
    if (all(in_band)) "YES" else "NO")
msg("groups: %d | LGAs held out: %d | fit seconds: %s (total %.0f)",
    N_GROUP, nrow(R), paste(sprintf("%.0f", sum_json$fit_times_seconds), collapse = " | "),
    sum(sum_json$fit_times_seconds))
msg("mean z %+0.4f  sd z %.4f  coverage %.4f -> %s", mean_z, sd_z, cov_z,
    if (all_pass) "PASS" else "FAIL")
msg("elapsed: %.1f s", tick(t_all))
prog("summary written; %d/%d groups on disk, all checks %s", length(unique(R$group)),
     N_GROUP, if (all_pass) "PASS" else "FAIL")
