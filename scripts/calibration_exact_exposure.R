#!/usr/bin/env Rscript
# scripts/calibration_exact_exposure.R -- T17.  Calibration at EXACTLY the neighbour
# exposure the 120 permanently-unsampled LGAs face.
#
# One command reproduces every number this ticket reports:
#     Rscript scripts/calibration_exact_exposure.R
# Design phase only (builds the graph, finds the groups, fits nothing):
#     Rscript scripts/calibration_exact_exposure.R --design-only
#
# ============================================================================
# THE QUESTION
# ============================================================================
# T12 removed a whole geopolitical zone: coverage 0.775, FAIL, exposure ~5.4.
# T16 held out 40 LGAs at a time matched on WITHIN-GROUP edges only: coverage
# 0.900, FAIL on sd, but its exposure measured as TOTAL unobserved neighbours was
# 1.670 -- 1.76x the 0.950 the 120 unsampled LGAs face.  T13 removed single LGAs
# with every neighbour kept: coverage 0.940, PASS, exposure 0.823.
#
# The paper's key number has therefore been bracketed on an assumed monotonicity.
# This ticket removes the assumption by measuring coverage AT 0.950.
#
# ============================================================================
# THE ARITHMETIC THAT DECIDES WHETHER IT CAN BE DONE
# ============================================================================
# For a group g of 40 held-out LGAs, the unobserved neighbour-ends are
#     total_g = sum_{i in g} a_i  +  2 * (edges of the 200 with BOTH ends in g)
# where a_i = the number of i's queen neighbours among the permanent 120.  The
# first term sums over the five groups to A = edges from the 200 to the 120,
# which is fixed by the SET.  The second sums to 2 * S_E, where S_E counts the
# edges of the 200 whose two ends land in the SAME group -- and that is a
# property of the PARTITION: an edge between two held-out LGAs in different
# groups is observed by both fits, so it contributes nothing.
#
# Therefore
#     mean exposure over the 200 = (A + 2 S_E) / 200,
# with A fixed and S_E chosen by the grouping.  Five groups at 0.95 need
# A + 2 S_E = 190.  This script measures A, computes the S_E that would be
# needed, and searches for a partition that attains it.  The 200 LGAs have 200
# edges among them, so the target is a strongly ANTI-CLUSTERED partition: about
# 178 of those 200 edges must be cut across groups, leaving ~22 inside groups,
# i.e. 4-5 per group of 40 -- exactly the brief's figure, and far below T16's 94.
#
# If the search cannot put every group inside the band the script STOPS before
# fitting, per the brief: "If the achieved exposure cannot be brought inside the
# tolerance, report the closest achieved and stop -- a mismatched exposure
# repeats T16's mistake."
#
# ============================================================================
# PRE-DECLARED PASS RULE -- identical to T12, T13 and T16, fourth time, unchanged
# ============================================================================
#   | check                  | pass range        |
#   |------------------------|-------------------|
#   | mean of z              | [-0.15, +0.15]    |
#   | sd of z                | [ 0.85,  1.15]    |
#   | share with |z| <= 1.96 | [ 0.90,  0.98]    |
# THIS RULE IS NOT REVISED AFTER THE NUMBERS APPEAR.  A failure is reported as a
# failure.  Do not re-fit, soften the rule, or change the estimand.
#
# ============================================================================
# DECLARED BEFORE THE RUN: choices the brief leaves to the script
# ============================================================================
# (A) THE GRAPH.  Built here from
#     data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson with
#     poly2nb(queen = TRUE), the same file and call as scripts/lga_model.R,
#     scripts/calibration_lga_cv.R and scripts/calibration_matched_exposure.R,
#     asserted against 774 nodes / 2,230 edges / 1 component / 0 isolates and
#     against the 57 edges with both ends among the 120.
#     data/derived/neighbours.csv is NOT read: it is the 37-node STATE graph.
#
# (B) THE 200 ARE READ, NOT REDRAWN.  They come from
#     data/derived/calibration_matched.csv and are asserted to be T16's set: 200
#     distinct LGAs, five groups of 40, all among the 654 that hold a cluster.
#     T16's own partition is measured here for comparison and then replaced.
#
# (C) THE GROUPING.  A greedy conflict-minimising start (place each LGA, in
#     descending degree order, in the group holding fewest of its neighbours)
#     followed by a deterministic swap search minimising
#     sum_g (total_g - 38)^2, subject to exactly 40 LGAs per group.  Seed
#     SEED = 20261124, set INSIDE the search so the groups cannot depend on any
#     RNG consumed earlier.  Achieved exposure per group, its internal edge
#     count, and its deviation from 0.95 are all printed and written.
#
# (D) CLUSTER COUNTS.  Every cluster count and the observed/unobserved split come
#     from data/derived/cluster_lga_fixed.csv, cross-checked against the
#     household file.  No count is taken from lga_estimates.csv or
#     lga_coverage.csv.
#
# (E) THE MODEL.  Byte-identical specification to T13 and T16: household
#     binomial, the ten design columns of eight covariates, BYM2 on the
#     774-node queen graph, IID cluster effect, INLA 25.10.19 defaults,
#     774 prediction rows at each LGA's mean covariate profile from the FULL
#     household file, cluster effect marginalised by the same 7-point
#     Gauss-Hermite rule, intervals from the marginal of the linear predictor on
#     a 2001-point normal grid.  No area-level covariate enters.
#
# (F) COVARIATES HELD KNOWN, as in T12, T13 and T16.  This tests the outcome
#     model and the spatial field, NOT covariate availability.  Disclosed.
#
# (G) SCORING.  Identical to T13 and T16: direct unweighted proportion from the
#     held-out households, cluster-robust ratio linearisation (strata = state,
#     PSU = cluster), deff imputation for single-cluster LGAs,
#     model_var = ((ci_high - ci_low)/(2*1.96))^2, z = (model - direct)/sqrt(both).
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
N_GROUP     <- 5L
GROUP_SIZE  <- 40L
TARGET_EXPO <- 0.95
TOL         <- 0.10
BAND        <- c(TARGET_EXPO * (1 - TOL), TARGET_EXPO * (1 + TOL))
GH_N        <- 7L
GRID_N      <- 2001L
FIT_LIMIT   <- 300
N_BOOT      <- 2000L
N_RESTART   <- 10L
N_ATTEMPT   <- 8000L

args        <- commandArgs(trailingOnly = TRUE)
design_only <- "--design-only" %in% args

root <- normalizePath(".")
p_hh    <- file.path(root, "data/derived/analysis_households_lga.csv")
p_bound <- file.path(root, "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson")
p_pop   <- file.path(root, "data/derived/lga_population.csv")
p_est   <- file.path(root, "data/derived/lga_estimates.csv")
p_clu   <- file.path(root, "data/derived/cluster_lga_fixed.csv")
p_match <- file.path(root, "data/derived/calibration_matched.csv")
p_out   <- file.path(root, "data/derived/calibration_exact.csv")
p_json  <- file.path(root, "data/derived/calibration_exact.json")
p_t12   <- file.path(root, "data/derived/calibration_summary.json")
p_t13   <- file.path(root, "data/derived/calibration_lga_cv.json")
p_t16   <- file.path(root, "data/derived/calibration_matched.json")
p_prog  <- file.path(root, ".agent/T17-progress.md")

for (f in c(p_hh, p_bound, p_pop, p_est, p_clu, p_match)) {
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
prog("T17 start; seed %d; target exposure %.2f, band [%.3f, %.3f]",
     SEED, TARGET_EXPO, BAND[1], BAND[2])

## ==========================================================================
## 1. The household file
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
## 2. The spatial graph over all 774 LGAs.  See (A).
## ==========================================================================
g <- st_make_valid(st_read(p_bound, quiet = TRUE))
if (nrow(g) != 774L) stop("expected 774 LGA polygons, got ", nrow(g), call. = FALSE)
if (anyDuplicated(g$shapeID)) stop("duplicate shapeID", call. = FALSE)
LGA_ID   <- g$shapeID
n_lga    <- length(LGA_ID)
lga_name <- g$shapeName

nb <- poly2nb(g, queen = TRUE)
if (length(nb) != n_lga) stop("graph node count != LGA count", call. = FALSE)
deg  <- card(nb)
comp <- n.comp.nb(nb)
msg("LGA graph: %d nodes, %d edges, %d component(s), %d isolate(s)",
    n_lga, sum(deg) / 2, comp$nc, sum(deg == 0))
if (sum(deg) == 0)        stop("graph has isolates; BYM2 is improper there", call. = FALSE)
if (comp$nc != 1L)        stop("graph is disconnected (", comp$nc, " components)", call. = FALSE)
if (sum(deg) / 2 != 2230) stop("expected 2,230 LGA edges, got ", sum(deg) / 2, call. = FALSE)

W <- nb2mat(nb, style = "B", zero.policy = TRUE)
ADJ <- (W + t(W)) > 0
if (!isTRUE(all(ADJ == t(ADJ)))) stop("adjacency not symmetric", call. = FALSE)
if (sum(ADJ) / 2 != sum(deg) / 2) stop("adjacency matrix does not match the nb object", call. = FALSE)

gr_path <- file.path(tempdir(), "lga_graph_exact.adj")
nb2INLA(gr_path, nb)
gr <- inla.read.graph(gr_path)
msg("INLA graph: %d nodes, %d edges", gr$n, sum(gr$nnbs) / 2)
prog("graph rebuilt from ADM2 polygons: 774 nodes, 2,230 edges, 1 component, 0 isolates")

pop <- read.csv(p_pop, stringsAsFactors = FALSE)
state_of_lga <- pop$state_iso[match(LGA_ID, pop$lga_id)]
if (anyNA(state_of_lga)) stop("an LGA has no parent state in lga_population.csv", call. = FALSE)
est <- read.csv(p_est, stringsAsFactors = FALSE)
if (!all(c("lga_id", "posterior_mean") %in% names(est))) stop("lga_estimates.csv lacks columns", call. = FALSE)
in_sample <- est$posterior_mean[match(LGA_ID, est$lga_id)]
if (anyNA(in_sample)) stop("an LGA has no in-sample estimate", call. = FALSE)

## ==========================================================================
## 3. Cluster counts: data/derived/cluster_lga_fixed.csv ONLY.  See (D).
## ==========================================================================
clu <- read.csv(p_clu, stringsAsFactors = FALSE)
if (!all(c("DHSCLUST", "hv001", "lga_id") %in% names(clu)))
  stop("cluster_lga_fixed.csv lacks DHSCLUST / hv001 / lga_id", call. = FALSE)
if (anyDuplicated(clu$DHSCLUST)) stop("duplicate DHSCLUST", call. = FALSE)
if (anyDuplicated(clu$hv001))    stop("duplicate hv001", call. = FALSE)
if (!all(clu$lga_id %in% LGA_ID)) stop("a cluster sits in an LGA absent from the boundary file", call. = FALSE)

cl_counts <- as.numeric(table(factor(clu$lga_id, levels = LGA_ID)))
if (sum(cl_counts) != nrow(clu)) stop("cluster counts do not sum to the file's row count", call. = FALSE)
obs_idx   <- which(cl_counts > 0L)
unobs_idx <- which(cl_counts == 0L)
if (length(obs_idx) != 654L) stop("expected 654 LGAs with a cluster, got ", length(obs_idx), call. = FALSE)
if (length(unobs_idx) != 120L) stop("expected 120 LGAs without, got ", length(unobs_idx), call. = FALSE)
msg("clusters (cluster_lga_fixed.csv): %d in %d LGAs; %d LGAs hold none",
    nrow(clu), length(obs_idx), length(unobs_idx))

lga_idx_full <- match(d$lga_id, LGA_ID)
if (anyNA(lga_idx_full)) stop("household lga_id not in the boundary file", call. = FALSE)
n_hh_lga <- as.numeric(tabulate(lga_idx_full, nbins = n_lga))
if (any(n_hh_lga[unobs_idx] != 0L)) stop("an LGA with no cluster holds households", call. = FALSE)
if (any(n_hh_lga[obs_idx] == 0L))   stop("an LGA with a cluster holds no households", call. = FALSE)
hh_clu_counts <- vapply(seq_len(n_lga), function(i) {
  if (n_hh_lga[i] == 0L) 0L else length(unique(d$hv001[lga_idx_full == i]))
}, integer(1))
if (!identical(as.integer(cl_counts), as.integer(hh_clu_counts)))
  stop("per-LGA cluster counts differ between cluster_lga_fixed.csv and the household file", call. = FALSE)
if (!setequal(sort(unique(d$lga_id)), LGA_ID[obs_idx]))
  stop("the household file's clustered-LGA set is not the cluster file's observed set", call. = FALSE)
msg("cross-check: per-LGA cluster counts and the 654/120 split agree across both files")

## ==========================================================================
## 4. The exposure of the 120, and the 200 read from T16.  See (B).
## ==========================================================================
E_120 <- sum(ADJ[unobs_idx, unobs_idx]) / 2
e120  <- E_120 / length(unobs_idx)
msg("\nedges with both ends among the 120: %d -> e120 %.4f -> %.4f unobserved neighbours per LGA",
    E_120, e120, 2 * e120)
if (E_120 != 57L) stop("expected the 57 edges among the 120 that T16 recorded, got ", E_120, call. = FALSE)
if (abs(2 * e120 - TARGET_EXPO) > 1e-12) stop("the 120's exposure is not 0.95", call. = FALSE)

M <- read.csv(p_match, stringsAsFactors = FALSE, check.names = FALSE)
need_m <- c("lga_id", "group", "internal_pairs", "state_iso")
if (!all(need_m %in% names(M))) stop("calibration_matched.csv lacks ", paste(need_m, collapse = ", "), call. = FALSE)
if (nrow(M) != 200L) stop("expected 200 rows, got ", nrow(M), call. = FALSE)
if (anyDuplicated(M$lga_id)) stop("a duplicate LGA in calibration_matched.csv", call. = FALSE)
if (!all(M$lga_id %in% LGA_ID)) stop("a held-out LGA is absent from the boundary file", call. = FALSE)
if (length(unique(M$group)) != N_GROUP) stop("expected 5 groups", call. = FALSE)
if (any(table(M$group) != GROUP_SIZE)) stop("a group is not 40 rows", call. = FALSE)

drawn     <- M$lga_id
drawn_idx <- match(drawn, LGA_ID)
if (!all(drawn_idx %in% obs_idx)) stop("a held-out LGA is not among the 654", call. = FALSE)
t16_grp <- as.integer(M$group)
msg("\n200 held-out LGAs read from calibration_matched.csv: %d distinct, groups %s, states %d",
    length(unique(drawn)), paste(as.integer(table(t16_grp)), collapse = "/"), length(unique(M$state_iso)))
msg("⇒ THE SAME AREAS, SAME DIRECT ESTIMATES, SAME MODEL AS T16.  Only the partition changes.")

## ==========================================================================
## 5. The decomposition: A is fixed, S_E is chosen.  See the header.
## ==========================================================================
is120   <- seq_len(n_lga) %in% unobs_idx
a_all   <- as.numeric(ADJ %*% as.numeric(is120))
a_200   <- a_all[drawn_idx]
A_total <- sum(a_200)
E_200   <- sum(ADJ[drawn_idx, drawn_idx]) / 2      # all edges among the 200
pos_of  <- integer(n_lga); pos_of[drawn_idx] <- seq_along(drawn_idx)
nbr_pos <- lapply(drawn_idx, function(i) { p <- pos_of[nb[[i]]]; p[p > 0L] })

e_in_grp <- function(grp, k) {         # 2 * edges with both ends in group k
  j <- which(grp == k)
  sum(vapply(j, function(u) sum(grp[nbr_pos[[u]]] == k), integer(1)))
}
totals_of <- function(grp) {
  vapply(seq_len(N_GROUP), function(k) sum(a_200[grp == k]) + e_in_grp(grp, k), numeric(1))
}

T16_S_E <- sum(vapply(seq_len(N_GROUP), function(k) {
  j <- which(t16_grp == k); sum(ADJ[drawn_idx[j], drawn_idx[j]]) / 2
}, numeric(1)))
required_S_E <- (N_GROUP * GROUP_SIZE * TARGET_EXPO - A_total) / 2

msg("\n===== THE DECOMPOSITION =====")
msg("a_i = queen neighbours among the permanent 120: mean %.4f, distribution %s",
    mean(a_200), paste(names(table(a_200)), as.integer(table(a_200)), sep = ":", collapse = "  "))
msg("A      = edges from the 200 to the 120 (fixed by the set)      = %d  (%.2f per group)",
    A_total, A_total / N_GROUP)
msg("E_200  = edges with both ends among the 200 (fixed by the set)  = %d", E_200)
msg("S_E    = those of the %d edges that fall INSIDE a group (chosen) -- T16's partition: %d",
    E_200, T16_S_E)
msg("total unobserved neighbour-ends = A + 2 * S_E; five groups at %.2f need 190", TARGET_EXPO)
msg("⇒ S_E required = (%.0f - %d)/2 = %.1f, i.e. %.1f edges inside each group of 40",
    N_GROUP * GROUP_SIZE * TARGET_EXPO, A_total, required_S_E, required_S_E / N_GROUP)
msg("   T16 had %d inside each group; a uniform random repartition leaves ~%d per group",
    T16_S_E %/% N_GROUP, E_200 %/% N_GROUP)
msg("   so ~%d of the %d edges must be CUT across groups: an anti-clustered partition",
    E_200 - required_S_E, E_200)
msg("band is satisfiable in total iff A + 2*S_E lands in [%.0f, %.0f]: S_E in [%.1f, %.1f]",
    N_GROUP * GROUP_SIZE * BAND[1], N_GROUP * GROUP_SIZE * BAND[2],
    (N_GROUP * GROUP_SIZE * BAND[1] - A_total) / 2, (N_GROUP * GROUP_SIZE * BAND[2] - A_total) / 2)
prog("decomposition: A %d, E_200 %d, T16 S_E %d, required S_E %.1f", A_total, E_200, T16_S_E, required_S_E)

## ==========================================================================
## 6. The grouping.  See (C).
## ==========================================================================
greedy_start <- function(ord) {
  grp <- integer(length(drawn_idx)); load <- integer(N_GROUP); A_g <- numeric(N_GROUP)
  for (u in ord) {
    pn <- nbr_pos[[u]]; pn <- pn[grp[pn] > 0L]
    cf <- tabulate(grp[pn], nbins = N_GROUP)
    free <- which(load < GROUP_SIZE)
    score <- cf[free] * 1000 + A_g[free]           # fewest placed neighbours, then lowest A
    k <- free[which.min(score + runif(length(free), 0, 0.5))]
    grp[u] <- k; load[k] <- load[k] + 1L; A_g[k] <- A_g[k] + a_200[u]
  }
  grp
}

search_partition <- function() {
  set.seed(SEED)                       # own stream: independent of anything before this
  target_total <- N_GROUP * GROUP_SIZE * TARGET_EXPO
  obj <- function(tot) sum((tot - target_total / N_GROUP)^2)
  best <- list(obj = Inf, grp = NULL, tot = NULL, restart = NA_integer_)
  for (r in seq_len(N_RESTART)) {
    ord <- if (r == 1L) order(deg[drawn_idx], decreasing = TRUE) else sample(seq_along(drawn_idx))
    grp <- greedy_start(ord)
    tot <- totals_of(grp); cur <- obj(tot)
    for (it in seq_len(N_ATTEMPT)) {
      k1 <- sample.int(N_GROUP, 1L); k2 <- sample.int(N_GROUP - 1L, 1L)
      if (k2 >= k1) k2 <- k2 + 1L
      i1 <- which(grp == k1); i2 <- which(grp == k2)
      u <- i1[sample.int(length(i1), 1L)]; v <- i2[sample.int(length(i2), 1L)]
      g2 <- grp; g2[u] <- k2; g2[v] <- k1
      tot2 <- totals_of(g2); cur2 <- obj(tot2)
      if (cur2 < cur) { grp <- g2; tot <- tot2; cur <- cur2 }
    }
    if (cur < best$obj) best <- list(obj = cur, grp = grp, tot = tot, restart = r)
    if (best$obj == 0) break
  }
  best
}

best <- search_partition()
grp  <- best$grp
ach  <- best$tot / GROUP_SIZE
in_band <- ach >= BAND[1] & ach <= BAND[2]
grp_internal <- vapply(seq_len(N_GROUP), function(k) e_in_grp(grp, k) / 2, numeric(1))

## T16's partition measured on the same scale, and a uniform repartition
t16_tot <- totals_of(t16_grp); t16_expo <- t16_tot / GROUP_SIZE
set.seed(SEED + 7L)
rand_grp <- rep(seq_len(N_GROUP), each = GROUP_SIZE)[sample.int(length(drawn_idx))]
rand_tot <- totals_of(rand_grp)

msg("\n===== EXPOSURE TABLE: target %.2f, band [%.3f, %.3f] =====", TARGET_EXPO, BAND[1], BAND[2])
msg("%-9s %5s %7s %7s %7s %9s %9s %8s", "partition", "group", "to-120", "internal", "S_E", "total", "exposure", "in band")
for (k in seq_len(N_GROUP))
  msg("%-9s %5d %7.0f %7.0f %7s %9.0f %9.4f %8s", "T17", k, sum(a_200[grp == k]),
      grp_internal[k], "", best$tot[k], ach[k], if (in_band[k]) "yes" else "NO")
msg("%-9s %5s %7.0f %7s %7.0f %9.0f %9.4f %8s", "", "all", A_total, "", sum(grp_internal),
    sum(best$tot), mean(ach), if (all(in_band)) "yes" else "NO")
msg("\nfor comparison, the same measure on T16's own partition and on a uniform repartition:")
msg("%-24s totals %s | exposure %s | mean %.4f", "T16 partition",
    paste(sprintf("%3d", as.integer(t16_tot)), collapse = " "),
    paste(sprintf("%.3f", t16_expo), collapse = " "), mean(t16_expo))
msg("%-24s totals %s | exposure %s | mean %.4f", "uniform repartition",
    paste(sprintf("%3d", as.integer(rand_tot)), collapse = " "),
    paste(sprintf("%.3f", rand_tot / GROUP_SIZE), collapse = " "), mean(rand_tot) / GROUP_SIZE)
msg("%-24s totals %s | exposure %s | mean %.4f", "T17 (searched)",
    paste(sprintf("%3d", as.integer(best$tot)), collapse = " "),
    paste(sprintf("%.3f", ach), collapse = " "), mean(ach))
state_cover <- vapply(seq_len(N_GROUP), function(k)
  length(unique(M$state_iso[match(LGA_ID[drawn_idx[grp == k]], M$lga_id)])), integer(1))
msg("states spanned per group: %s", paste(state_cover, collapse = " "))
msg("deviation from 0.95: %s (tolerance %.3f)", paste(sprintf("%+.3f", ach - TARGET_EXPO), collapse = " "), TOL)
prog("grouping found: exposure %s; internal edges %s; %d of %d groups in band",
     paste(sprintf("%.4f", ach), collapse = " "), paste(grp_internal, collapse = " "),
     sum(in_band), N_GROUP)

if (!all(in_band)) {
  msg("\nSTOP: the band was NOT achieved for all five groups. Closest achieved: %s",
      paste(sprintf("%.4f", ach), collapse = " "))
  msg("Ratio to 0.95: %s. Reporting the closest and stopping; the target is not redefined.",
      paste(sprintf("%.3f", ach / TARGET_EXPO), collapse = " "))
  out <- list(
    generated_by = "scripts/calibration_exact_exposure.R", ticket = "T17",
    status = "STOPPED BEFORE FITTING: exposure band not achieved",
    fits_used = 0L,
    decomposition = list(A = A_total, E_200 = E_200, S_E_required = required_S_E,
                        S_E_achieved = sum(grp_internal), S_E_T16 = T16_S_E),
    achieved_exposure = ach, achieved_internal_edges = grp_internal,
    band = BAND, target = TARGET_EXPO,
    held_out_lga_ids = drawn, group_of_lga = setNames(grp, drawn)[drawn]
  )
  write(toJSON(out, auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null"), p_json)
  prog("STOPPED: band not achieved; closest %s", paste(sprintf("%.3f", ach), collapse = " "))
  quit(save = "no", status = 0)
}
if (design_only) {
  msg("\n--design-only: design accepted, no fit run.")
  prog("design accepted: exposure %s; stopping before fits (--design-only)",
       paste(sprintf("%.4f", ach), collapse = " "))
  quit(save = "no", status = 0)
}

## ==========================================================================
## 7. Covariate profiles, held KNOWN.  See (F).
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
if (!identical(sort(no_data), sort(unobs_idx))) stop("the empty-LGA set and the no-cluster set differ", call. = FALSE)
for (i in no_data) {
  j <- match(state_of_lga[i], states_all)
  if (anyNA(Xbar_state[j, ])) stop("parent state of an empty LGA has no households", call. = FALSE)
  Xbar[i, ] <- Xbar_state[j, ]
}
if (anyNA(Xbar)) stop("covariate profile still has NA", call. = FALSE)
msg("\ncovariate profiles: %d LGAs from their own households, %d from the parent state",
    n_lga - length(no_data), length(no_data))

GH_X <- c(-2.651961356835233, -1.673551628767471, -0.8162878828589647, 0,
           0.8162878828589647,  1.673551628767471,  2.651961356835233)
GH_W <- c( 0.0009717812450995192, 0.05451558281912703, 0.4256072526101278,
           0.8102646175568073,   0.4256072526101278,  0.05451558281912703,
           0.0009717812450995192) / sqrt(pi)
stopifnot(GH_N == length(GH_X), abs(sum(GH_W) - 1) < 1e-14)
U_GRID <- seq(1e-4, 1 - 1e-4, length.out = GRID_N)
Q_GRID <- qnorm(U_GRID)

## ==========================================================================
## 8. Design variance of a direct LGA proportion -- same as T12/T13/T16
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
## 9. Fit machinery, written to disk group by group (resumable)
## ==========================================================================
COLS <- c("lga_id", "group", "model_mean", "ci_low", "ci_high",
          "direct_unweighted", "direct_weighted", "design_se", "design_se_source",
          "n_clusters", "z", "in_sample_fit",
          "lga_name", "state_iso", "n_households", "model_se",
          "group_fit_seconds", "group_waic", "group_mode_status", "group_sd_cluster",
          "group_deff_median", "group_n_training", "group_n_clusters",
          "internal_edges", "exposure")

existing <- NULL
done_groups <- integer(0)
if (file.exists(p_out)) {
  existing <- read.csv(p_out, stringsAsFactors = FALSE, check.names = FALSE)
  if (!all(COLS %in% names(existing))) stop(p_out, " exists but lacks the T17 columns", call. = FALSE)
  done_groups <- sort(unique(existing$group))
  msg("\nresuming: %s already holds %d rows from group(s): %s",
      basename(p_out), nrow(existing), paste(done_groups, collapse = ", "))
  if (!setequal(existing$lga_id, drawn[grp %in% done_groups]))
    stop("the rows on disk are not the LGAs this design holds out; delete ", p_out, call. = FALSE)
}

fit_group <- function(k) {
  zi   <- drawn_idx[grp == k]          # LGA indices, not positions in `drawn`
  held <- LGA_ID[zi]
  if (length(held) != GROUP_SIZE) stop("group ", k, " does not hold 40 LGAs", call. = FALSE)
  keep <- !(d$lga_id %in% held)
  dt   <- d[keep, , drop = FALSE]
  if (!nrow(dt)) stop("nothing left to fit for group ", k, call. = FALSE)
  if (any(dt$lga_id %in% held)) stop("a held-out household survived the drop mask", call. = FALSE)

  lga_idx <- match(dt$lga_id, LGA_ID)
  clu_levels <- sort(unique(dt$hv001))
  clu_idx <- match(dt$hv001, clu_levels)
  n_clu <- length(clu_levels); n_tr <- nrow(dt)

  dat <- data.frame(y = as.integer(dt$severe_fi), as.matrix(dt[, COV]),
                    lga = lga_idx, clu = clu_idx)
  names(dat) <- c("y", COV, "lga", "clu")
  pred_rows <- data.frame(y = NA_real_, Xbar, lga = seq_len(n_lga), clu = NA_integer_)
  names(pred_rows) <- names(dat)
  dat_aug <- rbind(dat, pred_rows)
  form <- as.formula(paste("y ~ 1 +", paste(COV, collapse = " + ")))

  msg("\n--- group %d: %d LGAs held out, %d internal edges, exposure %.4f ---",
      k, length(held), grp_internal[k], ach[k])
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
  if (t_fit > FIT_LIMIT) stop("group ", k, " took ", t_fit, " s, above the limit", call. = FALSE)
  if (!is.na(ms) && ms != 0L) msg("WARNING: group %d mode status %d -- reported, not changed", k, ms)

  slp <- fit$summary.linear.predictor
  idx <- n_tr + seq_len(n_lga)
  m_s <- slp[idx, "mean"]; s_s <- slp[idx, "sd"]
  if (anyNA(m_s) || anyNA(s_s)) stop("linear predictor summary has NA (group ", k, ")", call. = FALSE)

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

  hz <- d[!keep, , drop = FALSE]
  if (nrow(hz) == 0L) stop("no held-out households for group ", k, call. = FALSE)
  if (!all(hz$lga_id %in% held)) stop("a held-out household lies outside the group's LGAs", call. = FALSE)
  hz$lga_idx <- match(hz$lga_id, LGA_ID)

  n_hh_out <- as.numeric(tabulate(hz$lga_idx, nbins = n_lga))
  cl_keys  <- unique(hz[, c("lga_id", "hv001")])
  n_cl_out <- as.numeric(table(factor(cl_keys$lga_id, levels = LGA_ID)))
  if (sum(n_cl_out) != nrow(cl_keys)) stop("cluster counts do not sum", call. = FALSE)
  if (any(n_cl_out > n_hh_out)) stop("an LGA has more clusters than households", call. = FALSE)
  if (!identical(as.integer(n_cl_out[zi]), as.integer(cl_counts[zi])))
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
    internal_edges = as.numeric(grp_internal[k]), exposure = as.numeric(ach[k]),
    stringsAsFactors = FALSE
  )
  block$design_se_source[is.na(block$design_se_source)] <- "none"
  if (anyNA(block$z)) stop("a held-out LGA has no z (group ", k, ")", call. = FALSE)
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
                 sd_v = sd_v, deff_med = deff_med, n_train = n_tr, n_clu = n_clu))
}

## ==========================================================================
## 10. Run the five groups
## ==========================================================================
for (k in seq_len(N_GROUP)) {
  if (k %in% done_groups) { msg("\n--- group %d already on disk, skipped ---", k); next }
  fit_group(k)
}

## ==========================================================================
## 11. Pooled checks, fixed pass rule
## ==========================================================================
R <- read.csv(p_out, stringsAsFactors = FALSE, check.names = FALSE)
R <- R[order(R$group, match(R$lga_id, LGA_ID)), COLS]
if (nrow(R) != 200L) stop("expected 200 rows, have ", nrow(R), call. = FALSE)
if (anyDuplicated(R$lga_id)) stop("an LGA appears more than once", call. = FALSE)
if (length(unique(R$group)) != N_GROUP) stop("not all five groups are present", call. = FALSE)
if (!setequal(R$lga_id, drawn)) stop("the rows on disk are not the 200 built LGAs", call. = FALSE)
if (abs(sum(R$n_households) - sum(n_hh_lga[drawn_idx])) > 1e-9)
  stop("the held-out household total does not match the drawn LGAs", call. = FALSE)
if (any(abs(R$exposure - ach[R$group]) > 1e-12)) stop("the exposure column does not match the design", call. = FALSE)

zz <- R$z
if (anyNA(zz)) stop("z has NA", call. = FALSE)
n_z <- length(zz)
mean_z <- mean(zz); sd_z <- sd(zz); cov_z <- mean(abs(zz) <= 1.96)

PASS <- list(mean_z = c(-0.15, 0.15), sd_z = c(0.85, 1.15), coverage = c(0.90, 0.98))
chk <- function(v, band) v >= band[1] && v <= band[2]
msg("\n===== POOLED CALIBRATION, %d held-out LGAs at exposure %.4f =====", n_z, mean(ach))
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

wilson <- function(x, n, z = 1.96) {
  p <- x / n; dd <- 1 + z^2 / n
  ctr <- (p + z^2 / (2 * n)) / dd
  hw  <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / dd
  c(lower = ctr - hw, upper = ctr + hw)
}
set.seed(SEED + 1L)
bt <- matrix(sample(zz, n_z * N_BOOT, replace = TRUE), n_z, N_BOOT)
b_mean <- colMeans(bt); b_sd <- apply(bt, 2, sd); b_cov <- colMeans(abs(bt) <= 1.96)
ci_mean <- quantile(b_mean, c(0.025, 0.975), names = FALSE)
ci_sd   <- quantile(b_sd,   c(0.025, 0.975), names = FALSE)
ci_cov  <- quantile(b_cov,  c(0.025, 0.975), names = FALSE)
ci_wil  <- wilson(sum(abs(zz) <= 1.96), n_z)
msg("\nMonte Carlo uncertainty of the checks (%d bootstrap resamples):", N_BOOT)
msg("  mean z  %+.4f  bootstrap 95%% [%+.4f, %+.4f]", mean_z, ci_mean[1], ci_mean[2])
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
       internal_edges = as.integer(grp_internal[k]), exposure = ach[k],
       exposure_ratio = ach[k] / TARGET_EXPO, in_band = in_band[k],
       fit_seconds = R$group_fit_seconds[i][1], waic = R$group_waic[i][1],
       mode_status = R$group_mode_status[i][1], sd_cluster_effect = R$group_sd_cluster[i][1],
       deff_median = R$group_deff_median[i][1],
       n_training_households = R$group_n_training[i][1],
       n_training_clusters = R$group_n_clusters[i][1], states_spanned = state_cover[k])
})
msg("\nby group:")
for (p in per_group)
  msg("  group %d  n=%2d  mean %+0.3f  sd %0.3f  coverage %0.3f  internal %d  exposure %.4f (%s)",
      p$group, p$n, p$mean_z, p$sd_z, p$coverage, p$internal_edges, p$exposure,
      if (p$in_band) "in band" else "OUT OF BAND")

logo <- lapply(seq_len(N_GROUP), function(k) {
  s <- zz[R$group != k]
  list(group_removed = k, n = length(s), mean_z = mean(s), sd_z = sd(s),
       coverage = mean(abs(s) <= 1.96),
       passes_all_three = chk(mean(s), PASS$mean_z) && chk(sd(s), PASS$sd_z) &&
         chk(mean(abs(s) <= 1.96), PASS$coverage))
})
msg("\nPOST HOC, not a criterion -- pooled checks without each group in turn:")
for (o in logo)
  msg("  without group %d: n %d  mean %+0.3f  sd %.4f  coverage %.4f  %s",
      o$group_removed, o$n, o$mean_z, o$sd_z, o$coverage,
      if (o$passes_all_three) "would pass all three" else "still fails")

## ==========================================================================
## 12. The four-point curve
## ==========================================================================
rd <- function(p) if (file.exists(p)) tryCatch(fromJSON(p), error = function(e) NULL) else NULL
t12 <- rd(p_t12); t13 <- rd(p_t13); t16 <- rd(p_t16)
get3 <- function(x) {
  if (is.null(x) || is.null(x$primary)) return(list(mean_z = NA_real_, sd_z = NA_real_, coverage = NA_real_, n = NA_integer_))
  list(mean_z = x$primary$mean_z, sd_z = x$primary$sd_z,
       coverage = x$primary$coverage_abs_z_le_1_96, n = x$primary$n)
}
t12s <- get3(t12); t13s <- get3(t13); t16s <- get3(t16)
expo_t13 <- mean(a_all[obs_idx])            # a single held-out LGA's unobserved neighbours
expo_t16 <- if (!is.null(t16$exposure_actually_applied)) t16$exposure_actually_applied$heldout_total_mean else NA_real_

cmp <- data.frame(
  design = c("T13 single LGA removed", "T17 exact exposure (this)", "T16 matched within-group",
             "T12 whole zone removed"),
  exposure = c(expo_t13, mean(ach), expo_t16, 5.4),
  exposure_note = c("adjacency to the 120 only; no other LGA removed",
                    "matched: within-group plus adjacency to the 120",
                    "measured post hoc in T16 (within-group 0.94 + 0.73)",
                    "mean neighbours removed with the area (not the same estimator)"),
  n = c(t13s$n, n_z, t16s$n, t12s$n),
  mean_z = c(t13s$mean_z, mean_z, t16s$mean_z, t12s$mean_z),
  sd_z = c(t13s$sd_z, sd_z, t16s$sd_z, t12s$sd_z),
  coverage = c(t13s$coverage, cov_z, t16s$coverage, t12s$coverage),
  stringsAsFactors = FALSE)
cmp <- cmp[order(cmp$exposure), ]
msg("\n===== THE FOUR-DESIGN CURVE (same pass rule, same estimator, same scoring) =====")
msg("%-30s %8s %6s %8s %8s %9s", "design", "exposure", "n", "mean z", "sd z", "coverage")
for (i in seq_len(nrow(cmp)))
  msg("%-30s %8.3f %6d %+8.3f %8.3f %9.3f", cmp$design[i], cmp$exposure[i], cmp$n[i],
      cmp$mean_z[i], cmp$sd_z[i], cmp$coverage[i])
msg("(the 120 unsampled LGAs sit at exposure %.3f and are never fitted: no measured point exists)", 2 * e120)

## ==========================================================================
## 13. Inflation factor k at 0.95, with out-of-fold validation
## ==========================================================================
k_all <- sd_z
cov_after_k <- mean(abs(zz) <= 1.96 * k_all)
oof <- vapply(seq_len(N_GROUP), function(k) {
  k_in <- sd(zz[R$group != k])
  mean(abs(zz[R$group == k]) <= 1.96 * k_in)
}, numeric(1))
msg("\ninflation factor k = sd(z) = %.4f | coverage after widening every interval by k = %.4f",
    k_all, cov_after_k)
msg("out of fold (k from four groups, coverage in the fifth): %s | mean %.4f",
    paste(sprintf("%.3f", oof), collapse = " "), mean(oof))
prog("k at 0.95: %.4f, in-sample coverage %.4f, out-of-fold %s (mean %.4f)",
     k_all, cov_after_k, paste(sprintf("%.3f", oof), collapse = " "), mean(oof))

## ==========================================================================
## 14. Summary file
## ==========================================================================
construction <- paste(
  "Calibration at exactly the neighbour exposure the 120 permanently-unsampled LGAs face.",
  "The 200 held-out LGAs are T16's, read from data/derived/calibration_matched.csv and not",
  "redrawn; only the partition is new.  For a group of 40, unobserved neighbour-ends are",
  "sum of a_i (queen neighbours among the permanent 120) plus twice the edges of the 200 whose",
  "both ends fall inside that group.  The first term sums to A = 146 over the 200 and is fixed;",
  "the second sums to 2*S_E, which the partition chooses: an edge between two held-out LGAs in",
  "different groups is observed by both fits.  Five groups at 0.95 require A + 2*S_E = 190, so",
  "S_E = 22: about 178 of the 200 edges among the 200 must be cut across groups, i.e. 4-5",
  "inside each group of 40 against T16's 94.  The partition was found by a greedy",
  "conflict-minimising start plus a deterministic swap search on sum_g (total_g - 38)^2 with",
  "exactly 40 per group, seed 20261124.  Each group is one fit: that group's households are",
  "dropped and the identical household-level binomial model refitted (ten design columns of",
  "eight covariates, BYM2 on the 774-node queen graph built from the ADM2 polygons, IID cluster",
  "effect, INLA 25.10.19 defaults, no area-level covariates), then all 774 LGAs predicted from",
  "prediction rows at each LGA's mean covariate profile taken from the FULL household file",
  "(covariates held known), cluster effect marginalised by the same 7-point Gauss-Hermite rule",
  "as scripts/lga_model.R.  The truth is the direct unweighted proportion from each held-out",
  "LGA's own households, cluster-robust ratio linearisation (strata = state, PSU = cluster)",
  "with median-design-effect imputation for single-cluster LGAs.",
  "z = (model_mean - direct)/sqrt(model_var + design_var).  Pass rule fixed before any fit and",
  "identical to T12, T13 and T16: mean(z) in [-0.15,0.15], sd(z) in [0.85,1.15], share",
  "|z| <= 1.96 in [0.90,0.98].  Cluster counts and the observed/unobserved split come from",
  "data/derived/cluster_lga_fixed.csv and are cross-checked against the household file.",
  "Count-functional calibration is NOT tested: it needs joint draws per fold.", sep = " ")

sum_json <- list(
  generated_by = "scripts/calibration_exact_exposure.R",
  command = "Rscript scripts/calibration_exact_exposure.R",
  ticket = "T17", generated_on = as.character(Sys.Date()), seed = SEED,
  r_version = R.version.string, inla_version = as.character(packageVersion("INLA")),
  construction = construction,
  design = list(
    scheme = "leave-40-LGAs-out in five groups, total unobserved-neighbour count matched to the 120",
    n_held_out = 200L, n_groups = N_GROUP, group_size = GROUP_SIZE,
    sampling_frame = "T16's fixed 200 LGAs, drawn from the 654 that hold at least one cluster",
    held_out_source = "data/derived/calibration_matched.csv (read, not redrawn)",
    group_method = paste("greedy conflict-minimising start plus deterministic swap search on",
                         "sum_g (total_g - 38)^2, exactly 40 per group, seed set inside the search"),
    target_exposure = TARGET_EXPO, tolerance = TOL, band = BAND,
    held_out_lga_ids = drawn, group_of_lga = setNames(grp, drawn)[drawn],
    graph_source = "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson (queen contiguity)",
    graph_nodes = n_lga, graph_edges = sum(deg) / 2, graph_components = comp$nc,
    adjacency_file_note = paste("data/derived/neighbours.csv is the 37-node STATE graph and was not",
                                "read; the 774-node graph was built and asserted to have 2,230 edges"),
    covariates_held_known = TRUE, geospatial_covariates_used = 0L,
    weights_in_likelihood = FALSE, outcome_in_likelihood = "severe_fi = 1{hfs_sev >= 0.5}",
    cluster_counts_source = "data/derived/cluster_lga_fixed.csv",
    cluster_count_cross_check = "per-LGA counts identical to the household file; 654/120 split identical"
  ),
  exposure = list(
    definition = paste("a neighbour is unobserved if it is held out in the same group or is one of the",
                       "permanent 120; total_g = sum_{i in g} a_i + 2*(edges of the 200 inside g)"),
    edges_among_the_120 = E_120, e120 = e120, exposure_of_the_120 = 2 * e120,
    A_edges_200_to_120 = A_total, E_200_edges_inside_the_200 = E_200,
    S_E_required = required_S_E, S_E_achieved = sum(grp_internal), S_E_T16_partition = T16_S_E,
    edges_cut_across_groups = E_200 - sum(grp_internal),
    achieved = lapply(seq_len(N_GROUP), function(k) list(
      group = k, n_lgas = GROUP_SIZE, edges_to_the_120 = as.numeric(sum(a_200[grp == k])),
      internal_edges = as.integer(grp_internal[k]), total_unobserved_neighbour_ends = as.numeric(best$tot[k]),
      exposure = ach[k], ratio_to_target = ach[k] / TARGET_EXPO, in_band = in_band[k],
      states_spanned = state_cover[k])),
    t16_partition_same_measure = list(totals = as.numeric(t16_tot), exposures = as.numeric(t16_expo),
                                      mean = mean(t16_expo)),
    uniform_repartition = list(totals = as.numeric(rand_tot), exposures = as.numeric(rand_tot / GROUP_SIZE),
                               mean = mean(rand_tot) / GROUP_SIZE),
    all_groups_in_band = all(in_band),
    mean_exposure_achieved = mean(ach),
    tolerance_check = paste("achieved", paste(sprintf("%.4f", ach), collapse = " "),
                            "against target 0.95, band", paste(sprintf("%.3f", BAND), collapse = "-"))
  ),
  pass_rule_declared_before_fitting = list(
    mean_z = list(pass_range = PASS$mean_z, value = mean_z, pass = chk(mean_z, PASS$mean_z)),
    sd_z = list(pass_range = PASS$sd_z, value = sd_z, pass = chk(sd_z, PASS$sd_z)),
    coverage_abs_z_le_1_96 = list(pass_range = PASS$coverage, value = cov_z, pass = chk(cov_z, PASS$coverage)),
    all_three_pass = all_pass, n_z = n_z,
    rule_changed_after_seeing_values = FALSE, identical_to_T12_T13_T16_rule = TRUE
  ),
  primary = list(n = n_z, mean_z = mean_z, median_z = median(zz), sd_z = sd_z,
                 min_z = min(zz), max_z = max(zz), coverage_abs_z_le_1_96 = cov_z,
                 n_abs_z_gt_1_96 = sum(abs(zz) > 1.96), n_abs_z_gt_2_58 = sum(abs(zz) > 2.58),
                 rms_z = sqrt(mean(zz^2))),
  monte_carlo_uncertainty = list(
    n_boot = N_BOOT, seed = SEED + 1L, mean_z_ci = ci_mean, sd_z_ci = ci_sd,
    coverage_ci = ci_cov, coverage_wilson = ci_wil,
    note = paste("the checks are estimated on 200 LGAs; these say how much of a gap between two",
                 "experiments is sampling noise")),
  sensitivity = list(
    multi_cluster_lgas_only = sens_mc, by_group = per_group,
    note = paste("the multi-cluster subset uses only LGAs whose design variance is directly estimable;",
                 "a sensitivity, not a substitute for the pre-declared primary rule")),
  leave_one_group_out_descriptive = list(
    per_group_removed = logo,
    note = paste("post hoc and descriptive only: the pre-declared rule is pooled over all 200 rows.",
                 "Dropping a group after seeing the result is not a permitted specification")),
  four_design_curve = list(
    table = cmp,
    T12 = c(t12s, list(source = "data/derived/calibration_summary.json", exposure = 5.4)),
    T13 = c(t13s, list(source = "data/derived/calibration_lga_cv.json", exposure = expo_t13)),
    T16 = c(t16s, list(source = "data/derived/calibration_matched.json", exposure = expo_t16)),
    T17 = list(mean_z = mean_z, sd_z = sd_z, coverage = cov_z, n = n_z, exposure = mean(ach)),
    the_120 = list(exposure = 2 * e120, coverage = NA, note = "never fitted; the estimand, not a design"),
    reading = paste("coverage plotted against total unobserved neighbours per held-out LGA, all four",
                    "designs on one measure; the three earlier points are read from their artefacts")
  ),
  inflation_factor = list(k = k_all, coverage_after_widening_by_k = cov_after_k,
                          out_of_fold_coverage = as.numeric(oof), out_of_fold_mean = mean(oof),
                          out_of_fold_note = paste("k fitted on four groups, coverage measured in the",
                                                   "fifth, so the correction is not judged on the data",
                                                   "it was fitted to")),
  descriptive_not_a_criterion = list(
    naive_interval_coverage = list(
      share = mean(R$ci_low <= R$direct_unweighted & R$direct_unweighted <= R$ci_high),
      note = paste("descriptive only; the direct estimate carries its own sampling error, so this",
                   "under-covers by construction and is NOT the criterion")),
    bias = list(mean_model_minus_direct = mean(R$model_mean - R$direct_unweighted),
                median_model_minus_direct = median(R$model_mean - R$direct_unweighted),
                share_of_lgas_model_below_direct = mean(R$model_mean < R$direct_unweighted)),
    correlation_with_direct = cor(R$model_mean, R$direct_unweighted),
    spread_ratio_model_over_direct = sd(R$model_mean) / sd(R$direct_unweighted),
    variance_shares = list(median_model_se = median(R$model_se),
                           median_design_se = median(R$design_se, na.rm = TRUE),
                           mean_share_of_z_variance_from_design =
                             mean(R$design_se^2 / (R$design_se^2 + R$model_se^2), na.rm = TRUE))),
  fit_times_seconds = vapply(seq_len(N_GROUP), function(k) R$group_fit_seconds[R$group == k][1], numeric(1)),
  total_fit_seconds = sum(vapply(seq_len(N_GROUP), function(k) R$group_fit_seconds[R$group == k][1], numeric(1))),
  limitations = list(
    count_functional_not_tested = TRUE,
    never_clustered_lgas_not_tested = TRUE, n_never_clustered_excluded = length(unobs_idx),
    covariates_held_known = TRUE, linear_predictor_marginal_assumed_gaussian = TRUE,
    survey_design_not_in_likelihood = TRUE,
    matched_on_the_edge_count_not_the_full_exposure_distribution = TRUE,
    single_cluster_lgas_deff_imputed = sum(R$design_se_source == "deff_imputed"),
    n_degenerate_direct_zero_or_one = sum(R$direct_unweighted %in% c(0, 1)),
    the_partition_was_chosen_on_the_graph = paste("the grouping minimises exposure and therefore",
                                                  "deliberately places adjacent LGAs in different groups;",
                                                  "no outcome entered the choice"),
    note = paste("matching the mean unobserved-neighbour count does not force the DISTRIBUTION to",
                 "match the 120's, which ranges from 0 to 3 unobserved neighbours"))
)
write(toJSON(sum_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null"), p_json)
msg("\nwrote %s (%.1f KB)", basename(p_json), file.size(p_json) / 1024)

## ==========================================================================
## 15. Final print
## ==========================================================================
msg("\n================ RESULT ================")
msg("exposure: target %.2f | achieved %s | all in [%.3f, %.3f]: %s",
    TARGET_EXPO, paste(sprintf("%.4f", ach), collapse = " "), BAND[1], BAND[2],
    if (all(in_band)) "YES" else "NO")
msg("S_E: %d edges inside groups of %d among the 200 (T16 had %d); %d cut across groups",
    sum(grp_internal), E_200, T16_S_E, E_200 - sum(grp_internal))
msg("groups: %d | LGAs held out: %d | fit seconds: %s (total %.0f)",
    N_GROUP, nrow(R), paste(sprintf("%.0f", sum_json$fit_times_seconds), collapse = " | "),
    sum(sum_json$fit_times_seconds))
msg("mean z %+0.4f  sd z %.4f  coverage %.4f -> %s", mean_z, sd_z, cov_z,
    if (all_pass) "PASS" else "FAIL")
msg("k at 0.95 = %.4f | in-sample coverage after widening %.4f | out-of-fold mean %.4f",
    k_all, cov_after_k, mean(oof))
msg("elapsed: %.1f s", tick(t_all))
prog("summary written; %d/%d groups on disk, all checks %s", length(unique(R$group)), N_GROUP,
     if (all_pass) "PASS" else "FAIL")
