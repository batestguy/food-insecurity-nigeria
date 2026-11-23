#!/usr/bin/env Rscript
# scripts/calibration_covariates.R -- T15.  Do five area-level covariates rescue the
# extrapolation that failed in T12?
#
# One command reproduces every number this ticket reports:
#     Rscript scripts/calibration_covariates.R
#
# ============================================================================
# THE QUESTION
# ============================================================================
# T12 removed one geopolitical zone at a time and the identical household-only
# model failed all three pre-declared checks (mean z -0.654, sd 1.648, coverage
# 0.775).  The stated cause was structural: every predictor was a household
# measurement, so a region with no households in the training set had no
# predictors of its own level.  T14 has since built five area-level covariates
# that exist for all 774 LGAs.  This script adds exactly those five as fixed
# effects and repeats T12's test unchanged.
#
# ============================================================================
# PASS RULE -- T12's, NOT RENEGOTIATED
# ============================================================================
#   | check                  | pass range        |
#   |------------------------|-------------------|
#   | mean of z              | [-0.15, +0.15]    |
#   | sd of z                | [ 0.85,  1.15]    |
#   | share with |z| <= 1.96 | [ 0.90,  0.98]    |
#
# z = (model_mean - direct_unweighted) / sqrt(model_var + design_var),
# model_var = ((ci_high - ci_low) / (2 * 1.96))^2.
# Pooled over the 654 LGAs that hold at least one cluster, each contributing once.
#
# THE RULE IS NOT REVISED AFTER THE NUMBERS APPEAR.  If it fails it is reported as
# a failure.  An improvement is reported as an improvement, never as a fix.
#
# ============================================================================
# WHAT DIFFERS FROM scripts/calibration_spatial.R -- and what does not
# ============================================================================
# IDENTICAL (copied, not re-derived): the zone map; the household columns; the
# graph built once from the full boundary file with all 774 nodes; the household
# prediction profile Xbar (full-file LGA mean, parent-state fallback for LGAs with
# no households) and the "covariates held known" disclosure that comes with it;
# the 7-point Gauss-Hermite cluster marginalisation and the 2001-point probability
# grid; the design-variance estimator and its single-cluster deff imputation; the
# fold machinery, the resumable block-per-zone write, the pooled checks, the
# state/zone aggregation.  The direct estimates are therefore numerically
# reproducible from T12's file and this script asserts that they are.
#
# DIFFERENT (the whole point): five area-level fixed effects are added --
# pop_density, Aridity_2020, Enhanced_Vegetation_Index_2020, Elevation,
# Malaria_Incidence_2020 -- and the area-level surface is REBUILT INSIDE EVERY
# FOLD from clusters outside the held-out zone, so a held-out region's own
# clusters contribute nothing to its covariates.  No other change: no logs, no
# standardisation, no interactions, no added or dropped covariate.
#
# ============================================================================
# DECLARED BEFORE THE RUN
# ============================================================================
# (1) CLUSTER COUNTS AND THE OBSERVED/UNOBSERVED SPLIT come from
#     data/derived/cluster_lga_fixed.csv (654 LGAs with >=1 cluster, 120 with
#     none, 1,380 clusters, 266 singletons) -- NOT from n_clusters_in_lga in
#     lga_covariates.csv, which was built on the pre-correction assignment and
#     lists 123 zero-cluster LGAs of which four (Ahoada West, Dambatta, Apa,
#     Arochukwu) actually hold one.
# (2) ZONE MEMBERSHIP OF A CLUSTER uses cluster_lga_fixed.csv$state_iso, which is
#     the SURVEY state (the file's own survey_state_iso).  It agrees with
#     cluster_lga.csv on 1,365 of 1,380 clusters; the 15 exceptions are the
#     reassigned ones, and 8 of them cross a zone boundary.  The household file's
#     state_iso -- which defines T12's folds and this script's folds -- is the
#     survey state, so the fixed file is the consistent source.  Asserted below.
# (3) BAKASSI has no COD-PS population, so pop_density is NA for exactly that one
#     LGA.  It has zero clusters and zero households, so its density enters no
#     likelihood term and affects only its own printed prediction row.  It is
#     filled with the median pop_density of its parent state (Cross River) and
#     flagged in the CSV and the JSON.  Nothing else is imputed.
# (4) The area-level covariate values of a TRAINING LGA are also rebuilt without
#     the held-out zone's clusters, because the whole surface is rebuilt.  That is
#     the declared design: the surface a fold sees is the surface available to a
#     real user who has not sampled that zone.
# (5) FIT LIMIT 360 s per fold (the brief's six minutes).  Beyond it the script
#     stops rather than spending the fallback budget.
# ============================================================================

suppressPackageStartupMessages({
  library(sf)
  library(spdep)
  library(INLA)
  library(jsonlite)
})
sf_use_s2(TRUE)

SEED        <- 20261123L   # T12's seed, kept so any shared randomness is shared
GH_N        <- 7L
GRID_N      <- 2001L
FIT_LIMIT   <- 360
K_NEIGHBOURS <- 3L
IDW_FLOOR_KM <- 0.001
AREA_COV    <- c("pop_density", "Aridity_2020", "Enhanced_Vegetation_Index_2020",
                 "Elevation", "Malaria_Incidence_2020")

root <- normalizePath(".")
p_hh    <- file.path(root, "data/derived/analysis_households_lga.csv")
p_bound <- file.path(root, "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson")
p_pop   <- file.path(root, "data/derived/lga_population.csv")
p_folds <- file.path(root, "data/derived/calibration_folds.csv")        # T12, READ ONLY
p_t12   <- file.path(root, "data/derived/calibration_summary.json")     # T12, READ ONLY
p_clfix <- file.path(root, "data/derived/cluster_lga_fixed.csv")
p_clus  <- file.path(root, "data/derived/cluster_lga.csv")
p_gecov <- file.path(root, "data/restricted/dhs-2024/ge/NGGC8AFL.csv")
p_shipped_cov <- file.path(root, "data/derived/lga_covariates.csv")     # T14, READ ONLY
p_out   <- file.path(root, "data/derived/calibration_cov_zone.csv")
p_sum   <- file.path(root, "data/derived/calibration_cov_summary.json")
p_prog  <- file.path(root, ".agent/T15-progress.md")

for (f in c(p_hh, p_bound, p_pop, p_folds, p_clfix, p_clus, p_gecov, p_shipped_cov)) {
  if (!file.exists(f)) stop("missing input: ", f, " -- run from the repo root", call. = FALSE)
}

msg  <- function(...) cat(sprintf(...), "\n", sep = "")
tick <- function(t0) round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)
prog <- function(...) {
  line <- paste0(format(Sys.time(), "%H:%M"), "  ", sprintf(...), "\n")
  cat(line, sep = "")
  try(cat(line, sep = "", file = p_prog, append = TRUE), silent = TRUE)
}

set.seed(SEED)
t_all <- Sys.time()

## ==========================================================================
## 1. Zone map -- copied verbatim from scripts/calibration_spatial.R
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
## 2. Household data -- identical columns to T12
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
if (anyNA(d[COV]))      stop("a household covariate has NA", call. = FALSE)
if (!all(d$severe_fi %in% c(0, 1))) stop("severe_fi is not 0/1", call. = FALSE)
if (anyNA(d$state_iso)) stop("state_iso has NA", call. = FALSE)
if (anyNA(d$hv001))     stop("hv001 has NA", call. = FALSE)

states_in_data <- sort(unique(d$state_iso))
unknown <- setdiff(states_in_data, names(ZONE_OF_STATE))
unused  <- setdiff(names(ZONE_OF_STATE), states_in_data)
if (length(unknown)) stop("state_iso with no declared zone: ", paste(unknown, collapse = ", "), call. = FALSE)
if (length(unused))  stop("declared state absent from the data: ", paste(unused, collapse = ", "), call. = FALSE)
d$zone <- unname(ZONE_OF_STATE[d$state_iso])
if (anyNA(d$zone)) stop("a household has no zone", call. = FALSE)

msg("\n===== ZONE MAP (copied from T12, checked against state_iso) =====")
for (z in ZONES) {
  st <- sort(unique(d$state_iso[d$zone == z]))
  msg("%-14s %d states: %s", z, length(st), paste(st, collapse = " "))
}
stopifnot(length(states_in_data) == 37L, length(ZONE_OF_STATE) == 37L,
          identical(sort(names(ZONE_OF_STATE)), states_in_data))
print(table(factor(d$zone, levels = ZONES)))

## ==========================================================================
## 3. Cluster table -- the authority for counts, the observed split and zones
## ==========================================================================
clf <- read.csv(p_clfix, stringsAsFactors = FALSE)
cl0 <- read.csv(p_clus,  stringsAsFactors = FALSE)
stopifnot(nrow(clf) == 1380L, !anyDuplicated(clf$DHSCLUST))
stopifnot(identical(clf$hv001, clf$DHSCLUST))
m0 <- match(clf$DHSCLUST, cl0$DHSCLUST)
if (anyNA(m0)) stop("cluster_lga_fixed.csv has ids absent from cluster_lga.csv", call. = FALSE)
# coordinates must be identical, or the covariate surface would depend on which
# file supplied the points
if (max(abs(clf$LATNUM - cl0$LATNUM[m0])) > 1e-12 ||
    max(abs(clf$LONGNUM - cl0$LONGNUM[m0])) > 1e-12)
  stop("coordinates differ between cluster_lga.csv and cluster_lga_fixed.csv", call. = FALSE)

clf$zone <- unname(ZONE_OF_STATE[clf$state_iso])
if (anyNA(clf$zone)) stop("a cluster's survey state has no declared zone", call. = FALSE)

n_cl_fixed <- table(clf$lga_id)
msg("\nclusters: %d | LGAs with >=1 cluster: %d | with none: %d | singletons: %d",
    nrow(clf), length(n_cl_fixed), 774L - length(n_cl_fixed), sum(n_cl_fixed == 1))
stopifnot(length(n_cl_fixed) == 654L, sum(n_cl_fixed == 1) == 266L)

## every household's cluster must exist, and its state must be the survey state
if (!all(d$hv001 %in% clf$DHSCLUST)) stop("a household cluster is absent from cluster_lga_fixed.csv", call. = FALSE)
hh_state_of_clu <- tapply(d$state_iso, d$hv001, function(v) length(unique(v)))
if (any(hh_state_of_clu != 1L)) stop("a cluster's households disagree on state_iso", call. = FALSE)
hh_state <- vapply(split(d$state_iso, d$hv001), `[`, "", 1L)
mis <- names(hh_state)[hh_state != clf$state_iso[match(names(hh_state), clf$DHSCLUST)]]
if (length(mis)) stop("household state_iso disagrees with cluster_lga_fixed.csv for ",
                      length(mis), " clusters", call. = FALSE)
msg("check: 1,380 clusters, household state_iso == cluster_lga_fixed.csv$state_iso on all of them")

cluster_zone <- setNames(clf$zone, clf$DHSCLUST)
for (z in ZONES)
  msg("  %-14s %3d clusters (excluded in its fold)", z, sum(cluster_zone == z))
prog("inputs read: 37 states/6 zones, %d clusters, %d LGAs with clusters, %d without",
     nrow(clf), length(n_cl_fixed), 774L - length(n_cl_fixed))

## ==========================================================================
## 4. Spatial graph -- built once, all 774 nodes, exactly as T12
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
if (comp$nc != 1L) stop("graph is disconnected", call. = FALSE)
nb_path <- file.path(tempdir(), "lga_graph_cov.adj")
nb2INLA(nb_path, nb)
gr <- inla.read.graph(nb_path)

pop <- read.csv(p_pop, stringsAsFactors = FALSE)
state_of_lga <- pop$state_iso[match(LGA_ID, pop$lga_id)]
if (anyNA(state_of_lga)) stop("an LGA has no parent state in lga_population.csv", call. = FALSE)
zone_of_lga <- unname(ZONE_OF_STATE[state_of_lga])
lga_name <- g$shapeName

## ==========================================================================
## 5. Household covariate profile -- held known, exactly as T12
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
msg("LGAs: %d with households, %d using the parent-state household profile, %d with no cluster (fixed file)",
    n_lga - length(no_data), length(no_data),
    sum(!(LGA_ID %in% names(n_cl_fixed))))
if (length(no_data) != 120L) stop("expected 120 LGAs with no households from the fixed cluster file, got ",
                                  length(no_data), call. = FALSE)

## ---- Gauss-Hermite rule and probability grid, identical to T12 -------------
GH_X <- c(-2.651961356835233, -1.673551628767471, -0.8162878828589647, 0,
           0.8162878828589647,  1.673551628767471,  2.651961356835233)
GH_W <- c( 0.0009717812450995192, 0.05451558281912703, 0.4256072526101278,
           0.8102646175568073,   0.4256072526101278,  0.05451558281912703,
           0.0009717812450995192) / sqrt(pi)
stopifnot(GH_N == length(GH_X), abs(sum(GH_W) - 1) < 1e-14)
U_GRID <- seq(1e-4, 1 - 1e-4, length.out = GRID_N)
Q_GRID <- qnorm(U_GRID)

design_var <- function(y, clu, state) {
  N <- length(y); p <- sum(y) / N
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
## 6. The area-level covariate surface, rebuilt per fold
##    build_lga_covariates() is copied from scripts/lga_covariates.R (T14) with
##    its constants unchanged, because sourcing that script would rewrite the
##    shipped files.  Section 6b proves the copy reproduces the shipped table.
## ==========================================================================
adm2_ea <- suppressWarnings(st_transform(g, 6933L))
ctr_ll  <- st_transform(st_centroid(st_geometry(adm2_ea)), 4326)
ctr_xy  <- st_coordinates(ctr_ll)
# T14 rounded area to 3 decimals BEFORE dividing population by it (lga$area_km2 is
# constructed as round(geom_tbl$area_km2, 3) and lga$pop_density is computed from that
# rounded column).  The reproduction check below found this: with unrounded area the
# density differed by up to 3.05 per km2, which is pure rounding, not a method change.
area_km2 <- round(as.numeric(st_area(adm2_ea)) / 1e6, 3)

CANDIDATES <- c("Aridity_2020", "Nightlights_Composite", "Travel_Times",
                "Enhanced_Vegetation_Index_2020", "Precipitation_2020", "Elevation",
                "Livestock_Cattle", "Malaria_Incidence_2020")
gec <- read.csv(p_gecov, stringsAsFactors = FALSE)
stopifnot(nrow(gec) == 1380L, !anyDuplicated(gec$DHSCLUST),
          setequal(gec$DHSCLUST, clf$DHSCLUST))
gec <- gec[match(clf$DHSCLUST, gec$DHSCLUST), ]     # align by id, never by row order
stopifnot(identical(as.integer(gec$DHSCLUST), as.integer(clf$DHSCLUST)))
miss <- vapply(CANDIDATES, function(v) sum(is.na(gec[[v]])), integer(1))
if (any(miss > 0)) stop("missing cluster-level covariate values: ",
                        paste(names(miss)[miss > 0], collapse = ", "), call. = FALSE)
X_cl <- as.matrix(gec[, CANDIDATES, drop = FALSE]); storage.mode(X_cl) <- "double"

# points from the FIXED cluster file (identical coordinates to cluster_lga.csv, asserted)
pts <- st_as_sf(data.frame(DHSCLUST = clf$DHSCLUST, lon = clf$LONGNUM, lat = clf$LATNUM),
                coords = c("lon", "lat"), crs = 4326)

build_lga_covariates <- function(exclude_cluster_ids = character(0), k = K_NEIGHBOURS) {
  excl <- as.character(exclude_cluster_ids)
  keep <- !(as.character(clf$DHSCLUST) %in% excl)
  if (sum(keep) < k) stop("fewer than k clusters left after exclusion", call. = FALSE)
  D <- st_distance(ctr_ll, pts[keep, ])
  D <- matrix(as.numeric(D), nrow = length(ctr_ll)) / 1000
  ids <- as.character(clf$DHSCLUST[keep])
  n   <- nrow(D)
  idx <- t(vapply(seq_len(n), function(i) order(D[i, ], method = "radix")[seq_len(k)],
                  integer(k)))
  idx <- matrix(idx, nrow = n, ncol = k)
  w <- matrix(0, n, k); dk <- matrix(0, n, k)
  for (j in seq_len(k)) {
    dj <- D[cbind(seq_len(n), idx[, j])]
    dk[, j] <- dj
    w[, j]  <- 1 / pmax(dj, IDW_FLOOR_KM)
  }
  w <- w / rowSums(w)
  out <- matrix(0, n, length(CANDIDATES), dimnames = list(NULL, CANDIDATES))
  for (j in seq_len(k)) out <- out + w[, j] * X_cl[keep, , drop = FALSE][idx[, j], , drop = FALSE]
  ids_used <- apply(idx, 1, function(r) paste(ids[r], collapse = "|"))
  data.frame(lga_id = as.character(g$shapeID),
             n_clusters_available = as.integer(sum(keep)),
             nearest_cluster_id   = ids[idx[, 1]],
             nearest_dist_km      = dk[, 1],
             mean_k_dist_km       = rowMeans(dk),
             third_dist_km        = dk[, k],
             nearest_ids          = ids_used,
             as.data.frame(out),
             check.names = FALSE, stringsAsFactors = FALSE)
}

## ---- 6a. population density, exactly as T14 computed it -------------------
pop$population <- as.numeric(pop$population)
lk <- match(LGA_ID, pop$lga_id)
pop_density <- pop$population[lk] / area_km2
dens_na <- which(is.na(pop_density))
msg("\npop_density: %d of 774 missing (%s); filled with the parent-state median (no clusters, no households)",
    length(dens_na), paste(lga_name[dens_na], collapse = ", "))
for (i in dens_na) {
  same <- which(state_of_lga == state_of_lga[i] & !is.na(pop_density))
  if (!length(same)) stop("no state neighbour to borrow a density from", call. = FALSE)
  pop_density[i] <- median(pop_density[same])
}
stopifnot(!anyNA(pop_density))

## ---- 6b. the copy must reproduce T14's shipped table exactly --------------
full <- build_lga_covariates()
shipped <- read.csv(p_shipped_cov, stringsAsFactors = FALSE)
shipped <- shipped[match(full$lga_id, shipped$lga_id), ]
stopifnot(!anyNA(shipped$lga_id))
rep_diff <- max(abs(as.matrix(full[, CANDIDATES]) - as.matrix(shipped[, CANDIDATES])))
dens_diff <- max(abs(pop_density - shipped$pop_density), na.rm = TRUE)
msg("reproduction of data/derived/lga_covariates.csv on the 8 interpolated candidates: max |diff| = %.3e",
    rep_diff)
msg("reproduction of pop_density: max |diff| = %.3e", dens_diff)
if (rep_diff > 1e-9 || dens_diff > 1e-9)
  stop("the copied surface builder does not reproduce T14's shipped table; the fold rebuild would not be T14's method",
       call. = FALSE)
prog("surface builder reproduces T14's shipped table: max |diff| %.2e on 8 candidates, %.2e on density",
     rep_diff, dens_diff)

FULL_AREA <- cbind(pop_density = pop_density, as.matrix(full[, AREA_COV[-1], drop = FALSE]))
rownames(FULL_AREA) <- NULL

## ==========================================================================
## 7. Fold machinery
## ==========================================================================
BASE_COLS <- c("lga_id", "lga_name", "state_iso", "zone", "fold", "model_mean", "ci_low", "ci_high",
               "direct_unweighted", "direct_weighted", "design_se", "design_se_source",
               "n_households", "n_clusters", "z", "has_direct",
               "fold_fit_seconds", "fold_waic", "fold_mode_status", "fold_sd_cluster",
               "fold_deff_median", "fold_n_training", "fold_n_clusters")
EXTRA_COLS <- c("fold_bym2_phi", "fold_bym2_prec", "fold_cov_clusters_available",
                "fold_cov_lgas_changed", "pop_density_imputed", AREA_COV,
                paste0("fold_beta_", AREA_COV),
                paste0("fold_beta_lo_", AREA_COV),
                paste0("fold_beta_hi_", AREA_COV))
COLS <- c(BASE_COLS, EXTRA_COLS)

existing <- NULL
done_zones <- character(0)
if (file.exists(p_out)) {
  existing <- read.csv(p_out, stringsAsFactors = FALSE, check.names = FALSE)
  # a block written by an earlier version of this script can lack columns added since
  # (the fold_beta_* columns were added after North West's block was written); fill them
  # so rbind() cannot fail and the gap shows up as NA rather than as a silent drop
  for (v in setdiff(COLS, names(existing))) existing[[v]] <- NA
  done_zones <- unique(existing$zone)
  msg("\nresuming: %s already holds %d rows from zone(s): %s",
      basename(p_out), nrow(existing), paste(done_zones, collapse = ", "))
}

fold_surface <- function(z) {
  excl <- names(cluster_zone)[cluster_zone == z]
  s <- build_lga_covariates(exclude_cluster_ids = excl)
  used <- strsplit(s$nearest_ids, "|", fixed = TRUE)
  if (any(vapply(used, function(v) any(v %in% excl), logical(1))))
    stop("a rebuilt surface still interpolates from an excluded cluster (zone ", z, ")", call. = FALSE)
  if (any(s$n_clusters_available != nrow(clf) - length(excl)))
    stop("a rebuilt surface did not exclude every cluster of zone ", z, call. = FALSE)
  s <- s[match(LGA_ID, s$lga_id), ]
  if (anyNA(s$lga_id)) stop("rebuilt surface is not in LGA_ID order", call. = FALSE)
  A <- cbind(pop_density = pop_density, as.matrix(s[, AREA_COV[-1], drop = FALSE]))
  changed <- sum(apply(abs(A - FULL_AREA) > 1e-12, 1, any))
  list(A = A, n_excluded = length(excl), n_avail = s$n_clusters_available[1],
       changed = changed, nearest_dist = s$nearest_dist_km)
}

fit_fold <- function(z, k) {
  t_s <- Sys.time()
  S <- fold_surface(z)
  msg("\n--- fold %d: %s held out ---", k, z)
  msg("covariate surface rebuilt without %d clusters (%d available); %d of 774 LGAs changed values",
      S$n_excluded, S$n_avail, S$changed)

  keep <- d$zone != z
  dt   <- d[keep, , drop = FALSE]
  if (!nrow(dt)) stop("zone ", z, " holds every household", call. = FALSE)

  lga_idx <- match(dt$lga_id, LGA_ID)
  clu_levels <- sort(unique(dt$hv001))
  clu_idx <- match(dt$hv001, clu_levels)
  n_clu <- length(clu_levels); n_tr <- nrow(dt)

  A_tr <- S$A[lga_idx, , drop = FALSE]
  if (anyNA(A_tr)) stop("NA in a training area covariate (fold ", z, ")", call. = FALSE)

  dat <- data.frame(y = as.integer(dt$severe_fi), as.matrix(dt[, COV]), A_tr,
                    lga = lga_idx, clu = clu_idx, check.names = FALSE)
  names(dat) <- c("y", COV, AREA_COV, "lga", "clu")
  pred_rows <- data.frame(y = NA_real_, Xbar, S$A, lga = seq_len(n_lga), clu = NA_integer_,
                          check.names = FALSE)
  names(pred_rows) <- names(dat)
  dat_aug <- rbind(dat, pred_rows)
  form <- as.formula(paste("y ~ 1 +", paste(c(COV, AREA_COV), collapse = " + ")))

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
  hp <- fit$summary.hyperpar
  r_cl <- grep("Precision for clu", rownames(hp), fixed = TRUE)
  if (length(r_cl) != 1L) stop("cannot identify the cluster precision in: ",
                               paste(rownames(hp), collapse = " | "), call. = FALSE)
  sd_v <- 1 / sqrt(hp[r_cl, "mean"])
  r_ph <- grep("Phi for lga", rownames(hp), fixed = TRUE)
  r_pr <- grep("Precision for lga", rownames(hp), fixed = TRUE)
  phi  <- if (length(r_ph) == 1L) hp[r_ph, "mean"] else NA_real_
  prec <- if (length(r_pr) == 1L) hp[r_pr, "mean"] else NA_real_
  msg("fold %d fitted in %.1f s | mode status %s | WAIC %.2f | sd(cluster) %.4f | BYM2 phi %.4f prec %.4f",
      k, t_fit, paste(ms, collapse = ","), fit$waic$waic, sd_v, phi, prec)
  if (t_fit > FIT_LIMIT)
    stop("fold ", z, " took ", t_fit, " s, above the ", FIT_LIMIT, " s limit", call. = FALSE)

  slp <- fit$summary.linear.predictor
  idx <- n_tr + seq_len(n_lga)
  m_s <- slp[idx, "mean"]; s_s <- slp[idx, "sd"]
  if (anyNA(m_s) || anyNA(s_s)) stop("linear predictor summary has NA on a prediction row", call. = FALSE)

  TH <- matrix(0, n_lga, GRID_N)
  for (k2 in seq_len(GH_N)) {
    shift <- sqrt(2) * sd_v * GH_X[k2]
    TH <- TH + GH_W[k2] * plogis(outer(s_s, Q_GRID) + m_s + shift)
  }
  model_mean <- rowMeans(TH)
  ci_low  <- apply(TH, 1, function(v) approx(U_GRID, v, 0.025)$y)
  ci_high <- apply(TH, 1, function(v) approx(U_GRID, v, 0.975)$y)
  if (anyNA(TH) || any(TH < 0) || any(TH > 1)) stop("theta outside [0,1]", call. = FALSE)
  if (any(ci_low > model_mean) || any(model_mean > ci_high)) stop("quantiles out of order", call. = FALSE)

  ## ---- the truth, from the held-out households only (identical to T12) ----
  dh <- d[d$zone == z, , drop = FALSE]
  if (nrow(dh) != sum(!keep)) stop("held-out subset does not match the drop mask", call. = FALSE)
  dh$lga_idx <- match(dh$lga_id, LGA_ID)
  direct_u <- rep(NA_real_, n_lga); direct_w <- rep(NA_real_, n_lga)
  dvar <- rep(NA_real_, n_lga); dsrc <- rep(NA_character_, n_lga)
  n_hh_out <- as.numeric(tabulate(dh$lga_idx, nbins = n_lga))
  cl_keys  <- unique(dh[, c("lga_id", "hv001")])
  n_cl_out <- as.numeric(table(factor(cl_keys$lga_id, levels = LGA_ID)))
  if (sum(n_cl_out) != nrow(cl_keys)) stop("cluster counts do not sum to distinct clusters", call. = FALSE)

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

  zi <- which(zone_of_lga == z)
  model_var <- ((ci_high - ci_low) / (2 * 1.96))^2
  zz <- ifelse(is.na(direct_u), NA_real_, (model_mean - direct_u) / sqrt(model_var + dvar))

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
    fold_bym2_phi = phi, fold_bym2_prec = prec,
    fold_cov_clusters_available = S$n_avail, fold_cov_lgas_changed = S$changed,
    pop_density_imputed = FALSE,
    stringsAsFactors = FALSE, check.names = FALSE
  )
  # the five area covariates by explicit assignment: data.frame() prefixes a matrix
  # argument with the argument name (A.pop_density, ...), which silently dropped them
  # from COLS on the first run
  for (v in AREA_COV) block[[v]] <- S$A[zi, v]
  # the five area-level coefficients, persisted per fold: this is what lets a resumed
  # run report them without refitting
  fx <- fit$summary.fixed
  if (!all(AREA_COV %in% rownames(fx)))
    stop("the fit does not report all five area-level coefficients", call. = FALSE)
  for (v in AREA_COV) {
    block[[paste0("fold_beta_", v)]]    <- unname(fx[v, "mean"])
    block[[paste0("fold_beta_lo_", v)]] <- unname(fx[v, "0.025quant"])
    block[[paste0("fold_beta_hi_", v)]] <- unname(fx[v, "0.975quant"])
  }
  if (!all(COLS %in% names(block)))
    stop("block is missing columns: ", paste(setdiff(COLS, names(block)), collapse = ", "), call. = FALSE)
  block$pop_density_imputed[block$lga_id %in% LGA_ID[dens_na]] <- TRUE
  block$design_se_source[is.na(block$design_se_source)] <- "none"

  out <- if (is.null(existing)) block else rbind(existing[, COLS, drop = FALSE], block[, COLS, drop = FALSE])
  out <- out[order(out$fold, match(out$lga_id, LGA_ID)), COLS]
  write.csv(out, p_out, row.names = FALSE)
  existing <<- out
  msg("wrote %d rows for %s | file now holds %d rows, %d zones",
      nrow(block), z, nrow(out), length(unique(out$zone)))
  prog("fold %d %s: %d clusters excluded, %d of 774 LGAs changed covariates, fitted %.0f s, %d LGAs predicted (%d with a direct estimate)",
       k, z, S$n_excluded, S$changed, t_fit, nrow(block), sum(block$has_direct))
  if (any(abs(zz[zi]) > 1.96, na.rm = TRUE))
    prog("  fold %d: %d of %d LGAs outside the model's 95%% interval", k,
         sum(abs(zz[zi]) > 1.96, na.rm = TRUE), sum(!is.na(zz[zi])))

  list(zone = z, fold = k, n_train = n_tr, n_clu = n_clu, t_fit = t_fit,
       mode_status = ms, waic = fit$waic$waic, sd_v = sd_v,
       phi = phi, prec = prec, n_excluded = S$n_excluded, n_avail = S$n_avail,
       changed = S$changed, n_block = nrow(block), n_direct = sum(block$has_direct),
       n_single = length(single), fixed = fit$summary.fixed,
       hyperpar = hp, setup_seconds = tick(t_s) - t_fit)
}

## ==========================================================================
## 8. Run the six folds
## ==========================================================================
folds <- vector("list", length(ZONES))
for (k in seq_along(ZONES)) {
  z <- ZONES[k]
  if (z %in% done_zones) { msg("\n--- fold %d: %s already on disk, skipped ---", k, z); next }
  folds[[k]] <- fit_fold(z, k)
}

## ==========================================================================
## 9. Pooled checks -- T12's rule, unchanged
## ==========================================================================
R <- read.csv(p_out, stringsAsFactors = FALSE, check.names = FALSE)
R <- R[order(R$fold, match(R$lga_id, LGA_ID)), ]
if (nrow(R) != n_lga) stop("expected 774 rows, have ", nrow(R), call. = FALSE)
if (anyDuplicated(R$lga_id)) stop("an LGA appears more than once", call. = FALSE)
if (length(unique(R$zone)) != 6L) stop("not all six zones present", call. = FALSE)

zz <- R$z[!is.na(R$z)]
n_z <- length(zz)
mean_z <- mean(zz); sd_z <- sd(zz); cov_z <- mean(abs(zz) <= 1.96)
PASS <- list(mean_z = c(-0.15, 0.15), sd_z = c(0.85, 1.15), coverage = c(0.90, 0.98))
chk <- function(v, band) v >= band[1] && v <= band[2]

msg("\n===== POOLED CALIBRATION, %d LGAs with a direct estimate =====", n_z)
msg("mean of z            = %+0.4f   pass band [%+.2f, %+.2f]   %s",
    mean_z, PASS$mean_z[1], PASS$mean_z[2], if (chk(mean_z, PASS$mean_z)) "PASS" else "FAIL")
msg("sd of z              =  %0.4f   pass band [ %.2f,  %.2f]   %s",
    sd_z, PASS$sd_z[1], PASS$sd_z[2], if (chk(sd_z, PASS$sd_z)) "PASS" else "FAIL")
msg("share |z| <= 1.96    =  %0.4f   pass band [ %.2f, %.2f]   %s",
    cov_z, PASS$coverage[1], PASS$coverage[2], if (chk(cov_z, PASS$coverage)) "PASS" else "FAIL")
all_pass <- chk(mean_z, PASS$mean_z) && chk(sd_z, PASS$sd_z) && chk(cov_z, PASS$coverage)
msg("ALL THREE CHECKS: %s", if (all_pass) "PASS" else "FAIL")

mc <- !is.na(R$z) & R$design_se_source == "cluster_robust"
sens_mc <- list(n = sum(mc), mean_z = mean(R$z[mc]), sd_z = sd(R$z[mc]),
                coverage = mean(abs(R$z[mc]) <= 1.96))
msg("\nsensitivity, %d multi-cluster LGAs only: mean %+0.4f | sd %.4f | coverage %.4f",
    sens_mc$n, sens_mc$mean_z, sens_mc$sd_z, sens_mc$coverage)

per_fold <- lapply(ZONES, function(z) {
  v <- R$z[!is.na(R$z) & R$zone == z]
  list(zone = z, n = length(v), mean_z = mean(v), sd_z = sd(v), coverage = mean(abs(v) <= 1.96))
})
msg("\nby zone:")
for (p in per_fold)
  msg("  %-14s n=%3d  mean %+0.3f  sd %0.3f  coverage %0.3f",
      p$zone, p$n, p$mean_z, p$sd_z, p$coverage)

agg <- function(key, label) {
  keys <- sort(unique(key))
  res <- lapply(keys, function(kk) {
    i <- key == kk & R$n_households > 0
    if (!any(i)) return(NULL)
    wt <- R$n_households[i] / sum(R$n_households[i])
    mv <- sum(wt * R$model_mean[i])
    sds <- (R$ci_high[i] - R$ci_low[i]) / (2 * 1.96)
    sdv <- sqrt(sum(wt^2 * sds^2)); sdp <- sum(wt * sds)
    du <- sum(wt * R$direct_unweighted[i])
    ins <- function(s) { lo <- max(0, mv - 1.96 * s); hi <- min(1, mv + 1.96 * s); du >= lo && du <= hi }
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
  msg("  bound: if LGAs were perfectly correlated the count would be %d of %d", n_inp, length(res))
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

## ---- integrity: truth and design variance must be T12's, unchanged --------
t12 <- read.csv(p_folds, stringsAsFactors = FALSE, check.names = FALSE)
t12 <- t12[match(R$lga_id, t12$lga_id), ]
stopifnot(identical(R$lga_id, t12$lga_id), identical(R$zone, t12$zone))
d_direct <- max(abs(R$direct_unweighted - t12$direct_unweighted), na.rm = TRUE)
d_dse    <- max(abs(R$design_se - t12$design_se), na.rm = TRUE)
d_nhh    <- max(abs(R$n_households - t12$n_households))
d_ncl    <- max(abs(R$n_clusters - t12$n_clusters))
msg("\nintegrity vs T12 on the same 774 rows: max |d direct| %.3e | max |d design_se| %.3e | max |d n_households| %g | max |d n_clusters| %g",
    d_direct, d_dse, d_nhh, d_ncl)
if (d_direct > 1e-10 || d_dse > 1e-10)
  stop("the direct estimates or design variances differ from T12's; the folds are not the same folds", call. = FALSE)
prog("pooled z: mean %+0.4f sd %.4f coverage %.4f -> %s (T12: -0.6539 / 1.6481 / 0.7752)",
     mean_z, sd_z, cov_z, if (all_pass) "PASS" else "FAIL")

## ==========================================================================
## 10. Side-by-side against T12
## ==========================================================================
ok <- R$has_direct
oos <- function(m, direct) {
  sl <- cov(direct, m) / var(direct)
  list(correlation = cor(direct, m), slope_on_direct = sl,
       intercept = mean(m) - sl * mean(direct),
       mean_model = mean(m), mean_direct = mean(direct),
       sd_model = sd(m), sd_direct = sd(direct), compression_ratio = sd(m) / sd(direct))
}
oos15 <- oos(R$model_mean[ok], R$direct_unweighted[ok])
oos12 <- oos(t12$model_mean[ok], t12$direct_unweighted[ok])

t12_sum <- fromJSON(p_t12, simplifyVector = FALSE)
t12_checks <- list(
  mean_z = t12_sum$pass_rule_declared_before_fitting$mean_z$value,
  sd_z   = t12_sum$pass_rule_declared_before_fitting$sd_z$value,
  coverage = t12_sum$pass_rule_declared_before_fitting$coverage_abs_z_le_1_96$value
)
# recompute T12's checks from its own file and require the stored values to match
z12 <- t12$z[!is.na(t12$z)]
rec12 <- c(mean_z = mean(z12), sd_z = sd(z12), coverage = mean(abs(z12) <= 1.96))
d_store <- max(abs(rec12 - unlist(t12_checks)))
msg("T12 stored checks reproduced from calibration_folds.csv: max |diff| %.2e (stored values are rounded in the JSON)", d_store)
if (d_store > 1e-6)
  stop("recomputed T12 checks disagree with calibration_summary.json by ", d_store, call. = FALSE)

zone_rows <- lapply(ZONES, function(z) {
  i  <- R$zone == z & ok
  i12 <- t12$zone == z & ok
  list(zone = z, n = sum(i),
       direct_mean_unweighted = mean(R$direct_unweighted[i]),
       direct_mean_hhweighted = weighted.mean(R$direct_unweighted[i], R$n_households[i]),
       model_t12 = mean(t12$model_mean[i12]),
       model_t15 = mean(R$model_mean[i]),
       model_t12_hhweighted = weighted.mean(t12$model_mean[i12], t12$n_households[i12]),
       model_t15_hhweighted = weighted.mean(R$model_mean[i], R$n_households[i]),
       mean_z_t12 = mean(t12$z[i12]), mean_z_t15 = mean(R$z[i]),
       coverage_t12 = mean(abs(t12$z[i12]) <= 1.96), coverage_t15 = mean(abs(R$z[i]) <= 1.96))
})
msg("\nzone                    n   direct   T12 model  T15 model   z T12    z T15")
for (p in zone_rows)
  msg("  %-14s %3d  %7.3f  %8.3f  %8.3f  %+7.3f  %+7.3f",
      p$zone, p$n, p$direct_mean_unweighted, p$model_t12, p$model_t15, p$mean_z_t12, p$mean_z_t15)

## ---- hyperparameters and coefficients, per fold ---------------------------
fold_hyper <- lapply(ZONES, function(z) {
  i <- R$zone == z
  list(zone = z,
       bym2_phi = R$fold_bym2_phi[i][1], bym2_precision = R$fold_bym2_prec[i][1],
       sd_spatial_marginal = 1 / sqrt(R$fold_bym2_prec[i][1]),
       sd_cluster = R$fold_sd_cluster[i][1],
       fit_seconds = R$fold_fit_seconds[i][1], waic = R$fold_waic[i][1],
       mode_status = R$fold_mode_status[i][1],
       cov_clusters_available = R$fold_cov_clusters_available[i][1],
       cov_lgas_changed = R$fold_cov_lgas_changed[i][1],
       t12_sd_cluster = t12$fold_sd_cluster[i][1],
       t12_fit_seconds = t12$fold_fit_seconds[i][1], t12_waic = t12$fold_waic[i][1])
})
msg("\nBYM2 per fold: %s", paste(sprintf("%s phi=%.3f prec=%.2f", sapply(fold_hyper, `[[`, "zone"),
    sapply(fold_hyper, `[[`, "bym2_phi"), sapply(fold_hyper, `[[`, "bym2_precision")), collapse = " | "))

## fixed effects: one row per (zone, covariate), read back from the zone file, so a
## resumed run reports the coefficients of folds it did not refit
coef_tbl <- do.call(rbind, lapply(ZONES, function(z) {
  i <- which(R$zone == z)[1]
  data.frame(fold_zone = z, term = AREA_COV,
             mean = unlist(R[i, paste0("fold_beta_", AREA_COV)], use.names = FALSE),
             q025 = unlist(R[i, paste0("fold_beta_lo_", AREA_COV)], use.names = FALSE),
             q975 = unlist(R[i, paste0("fold_beta_hi_", AREA_COV)], use.names = FALSE),
             stringsAsFactors = FALSE)
}))
coef_missing <- unique(coef_tbl$fold_zone[is.na(coef_tbl$mean)])
coef_tbl <- coef_tbl[!is.na(coef_tbl$mean), ]
rownames(coef_tbl) <- NULL
if (length(coef_missing))
  msg("note: no coefficient row for zone(s) %s -- their blocks predate the persistence fix",
      paste(coef_missing, collapse = ", "))

msg("\n===== COEFFICIENTS OF THE FIVE AREA-LEVEL COVARIATES (by fold) =====")
if (nrow(coef_tbl)) {
  a <- coef_tbl[coef_tbl$term %in% AREA_COV, ]
  a$sign <- ifelse(a$mean > 0, "+", ifelse(a$mean < 0, "-", "0"))
  a$sig  <- ifelse(a$q025 > 0 | a$q975 < 0, "*", " ")
  for (j in seq_len(nrow(a)))
    msg("  %-14s %-30s %+10.4g  [%+10.4g, %+10.4g] %s", a$fold_zone[j], a$term[j],
        a$mean[j], a$q025[j], a$q975[j], a$sig[j])
  n_zone_beta <- length(unique(a$fold_zone))
  msg("sign agreement across the %d folds that report coefficients: %s", n_zone_beta,
      paste(sprintf("%s %d of %d negative", AREA_COV,
                    sapply(AREA_COV, function(v) sum(a$mean[a$term == v] < 0)), n_zone_beta),
            collapse = " | "))
}

## ==========================================================================
## 11. Summary file
## ==========================================================================
aridity_sentence <- paste(
  "\"Units: Index between 0 (most arid) and 300 (most wet).\" and \"The dataset represents",
  "the average monthly precipitation divided by average monthly potential evapotranspiration,",
  "an aridity index defined by the United Nations Environmental Programme (UNEP).\" -- page 10",
  "of 42 (printed page 9) of 'DHS Covariates Extract Data Description_3.pdf', entry",
  "'Column Name: Aridity YEAR', derived from CRU TS v4.05 at 0.5 degrees.")
aridity_note <- paste(
  "Read from the shipped PDF, not from a variable name: a HIGHER Aridity_2020 means WETTER.",
  "The same page also says 'If the aridity index becomes higher than normal in a region, the",
  "climate tends to suffer from drought', which refers to a deviation above normal, not to the",
  "level, and is contradicted by the units line and by the P/PET definition; the units line governs.",
  "Independent empirical check on the 774 LGA values: r(Aridity_2020, Precipitation_2020) = +0.985",
  "and r(Aridity_2020, Elevation) = -0.623 in T14's correlation matrix, both only possible if a",
  "higher index is wetter. So the reported r = -0.458 with severe food insecurity is 'wetter LGA,",
  "less severe food insecurity', the expected direction, not a misread sign.")

construction <- paste(
  "Leave-one-geopolitical-zone-out cross-validation of the LGA model, T12's design with five",
  "area-level fixed effects added. Each fold drops every household in one of the six zones and",
  "refits the identical household-level binomial model: ten household design columns plus",
  "pop_density, Aridity_2020, Enhanced_Vegetation_Index_2020, Elevation and",
  "Malaria_Incidence_2020 as fixed effects (raw scale, no transform, no interaction), BYM2 on the",
  "queen-contiguity graph over all 774 LGAs built once from the full boundary file, IID cluster",
  "effect, INLA 25.10.19 defaults. The five area-level covariates are REBUILT INSIDE EVERY FOLD by",
  "T14's build_lga_covariates() with that fold's zone clusters excluded (inverse-distance weighting",
  "over the 3 nearest remaining clusters, great-circle distance, floor 0.001 km), so a held-out",
  "region's own clusters contribute nothing to its covariates; the script asserts that no rebuilt",
  "nearest-3 set contains an excluded cluster and that the builder reproduces T14's shipped table",
  "to 1e-9. Prediction rows sit at each LGA's mean household covariate profile (taken from the FULL",
  "file, as in T12, so household covariates are held known) with cluster index NA, and cluster",
  "counts and the observed/unobserved split come from cluster_lga_fixed.csv (654 LGAs with at least",
  "one cluster, 120 with none, 1,380 clusters). theta_s is the LGA prevalence with the cluster effect",
  "marginalised by the same 7-point Gauss-Hermite rule as scripts/lga_model.R; 95% intervals come",
  "from the marginal posterior of the linear predictor mapped through that integral on a 2001-point",
  "standard-normal probability grid, no Monte Carlo draws. The truth is the direct unweighted",
  "proportion from the held-out households of each LGA with a cluster-robust ratio linearisation",
  "(strata = state, PSU = cluster), single-cluster LGAs imputed the fold's median design effect.",
  "z = (model_mean - direct) / sqrt(model_var + design_var). Pass rule fixed before any fold was",
  "fitted and identical to T12: mean(z) in [-0.15, 0.15], sd(z) in [0.85, 1.15], share |z| <= 1.96",
  "in [0.90, 0.98], pooled over the 654 LGAs that hold at least one cluster.",
  "State and zone coverage treat LGAs as independent, which understates the aggregate interval.",
  "Count-functional calibration is NOT tested: it needs joint draws per fold.",
  sep = " ")

first_num <- function(x) { x <- suppressWarnings(as.numeric(as.character(x)))
                           x <- x[!is.na(x)]; if (!length(x)) NA_real_ else x[1] }

sum_json <- list(
  generated_by = "scripts/calibration_covariates.R",
  command = "Rscript scripts/calibration_covariates.R",
  ticket = "T15",
  generated_on = as.character(Sys.Date()),
  seed = SEED,
  r_version = R.version.string,
  inla_version = tryCatch({
    v <- inla.version()$version
    if (!length(v) || !nzchar(paste(v, collapse = ""))) as.character(packageVersion("INLA"))
    else paste(v, collapse = ".")
  }, error = function(e) as.character(packageVersion("INLA"))),
  construction = construction,
  design = list(
    scheme = "leave-one-geopolitical-zone-out",
    n_folds = 6L, zones = ZONES, zones_skipped_from_disk = done_zones,
    graph_nodes = n_lga, graph_edges = sum(deg) / 2, graph_components = comp$nc,
    geospatial_covariates_used = 5L, area_covariates = AREA_COV,
    area_covariate_surface_built_per_fold = TRUE,
    household_covariates_held_known = TRUE,
    cluster_counts_source = "data/derived/cluster_lga_fixed.csv",
    n_clusters = nrow(clf), n_lga_with_cluster = length(n_cl_fixed),
    n_lga_without_cluster = 774L - length(n_cl_fixed), n_singleton_lgas = sum(n_cl_fixed == 1),
    weights_in_likelihood = FALSE,
    outcome_in_likelihood = "severe_fi = 1{hfs_sev >= 0.5}",
    differ_from_T12 = "five area-level fixed effects added; area-level surface rebuilt inside each fold; nothing else"
  ),
  covariate_surface = list(
    builder = "copy of build_lga_covariates() from scripts/lga_covariates.R, constants unchanged",
    reproduction_of_shipped_table = list(max_abs_diff_candidates = rep_diff,
                                        max_abs_diff_pop_density = dens_diff,
                                        tolerance = 1e-9, reproduced = (rep_diff <= 1e-9 && dens_diff <= 1e-9)),
    k = K_NEIGHBOURS, idw_floor_km = IDW_FLOOR_KM,
    per_fold = lapply(fold_hyper, function(f) list(
      zone = f$zone, clusters_excluded = 1380 - f$cov_clusters_available,
      clusters_available = f$cov_clusters_available, lgas_values_changed = f$cov_lgas_changed,
      excluded_set_absent_from_every_nearest3 = TRUE)),
    pop_density_imputation = list(
      n_imputed = length(dens_na),
      lga = lga_name[dens_na], state = state_of_lga[dens_na], rule = "parent-state median",
      why = paste("Bakassi has no COD-PS population. It has no cluster and no household, so the",
                  "value enters no likelihood term and affects only its own prediction row."))
  ),
  aridity_definition = list(
    direction = "higher = wetter",
    sentence = aridity_sentence,
    source = "data/restricted/dhs-2024/ge/DHS Covariates Extract Data Description_3.pdf, page 10 of 42",
    note = aridity_note),
  pass_rule_declared_before_fitting = list(
    same_as_T12 = TRUE,
    mean_z = list(pass_range = PASS$mean_z, value = mean_z, pass = chk(mean_z, PASS$mean_z)),
    sd_z = list(pass_range = PASS$sd_z, value = sd_z, pass = chk(sd_z, PASS$sd_z)),
    coverage_abs_z_le_1_96 = list(pass_range = PASS$coverage, value = cov_z, pass = chk(cov_z, PASS$coverage)),
    all_three_pass = all_pass, n_z = n_z, rule_changed_after_seeing_values = FALSE),
  primary = list(n = n_z, mean_z = mean_z, median_z = median(zz), sd_z = sd_z,
                 min_z = min(zz), max_z = max(zz), coverage_abs_z_le_1_96 = cov_z,
                 n_abs_z_gt_1_96 = sum(abs(zz) > 1.96), n_abs_z_gt_2_58 = sum(abs(zz) > 2.58)),
  comparison_vs_T12 = list(
    mean_z = list(T12 = rec12[["mean_z"]], T15 = mean_z, delta = mean_z - rec12[["mean_z"]],
                  pass_T12 = FALSE, pass_T15 = chk(mean_z, PASS$mean_z)),
    sd_z = list(T12 = rec12[["sd_z"]], T15 = sd_z, delta = sd_z - rec12[["sd_z"]],
                pass_T12 = FALSE, pass_T15 = chk(sd_z, PASS$sd_z)),
    coverage = list(T12 = rec12[["coverage"]], T15 = cov_z, delta = cov_z - rec12[["coverage"]],
                    pass_T12 = FALSE, pass_T15 = chk(cov_z, PASS$coverage)),
    out_of_sample_fit = list(
      T12 = list(correlation = oos12$correlation, compression_ratio = oos12$compression_ratio,
                 slope_on_direct = oos12$slope_on_direct, mean_model = oos12$mean_model,
                 sd_model = oos12$sd_model),
      T15 = list(correlation = oos15$correlation, compression_ratio = oos15$compression_ratio,
                 slope_on_direct = oos15$slope_on_direct, mean_model = oos15$mean_model,
                 sd_model = oos15$sd_model),
      mean_direct = oos15$mean_direct, sd_direct = oos15$sd_direct),
    by_zone = zone_rows,
    integrity_checks = list(
      max_abs_diff_direct_unweighted = d_direct, max_abs_diff_design_se = d_dse,
      max_abs_diff_n_households = d_nhh, max_abs_diff_n_clusters = d_ncl,
      note = paste("the truth and its variance are recomputed, not copied, and must equal T12's to",
                   "1e-10; agreement is the proof that the folds and the scoring are the same")),
    improvement_but_still_fails = !all_pass,
    wording = if (all_pass) "passes the pre-declared rule" else
      "improved relative to T12 on the reported checks where stated, and still fails the pre-declared rule"
  ),
  hyperparameters = list(
    per_fold = fold_hyper,
    bym2_phi_range = range(sapply(fold_hyper, `[[`, "bym2_phi")),
    bym2_precision_range = range(sapply(fold_hyper, `[[`, "bym2_precision")),
    T12_bym2_not_on_disk = paste("T12 wrote no BYM2 phi or precision to disk; calibration_folds.csv",
                                 "carries only fold_sd_cluster, and calibration_summary.json",
                                 "records no hyperparameter block. The before/after comparison of the",
                                 "BYM2 mixing parameter therefore cannot be made from artefacts and",
                                 "T12 was not refitted (the ticket forbids a second fit).")),
  coefficients = list(
    area_level_terms = AREA_COV,
    table = if (nrow(coef_tbl)) split(coef_tbl, coef_tbl$term) else list(),
    folds_without_coefficient_row = coef_missing,
    why_a_fold_can_be_missing = if (length(coef_missing)) paste0(
      "the block(s) for ", paste(coef_missing, collapse = ", "), " were written by an earlier",
      " version of this script that did not yet persist the coefficient table. A fold already on",
      " disk is not refitted, so those zones have no coefficient row; their predictions, their",
      " z values and their contribution to every calibration number are unaffected.") else
      "every fold reports its coefficients",
    note = paste("raw scale, so the size of a coefficient is per unit of the covariate as shipped:",
                 "per person per km2 of density, per aridity index point (0 arid to 300 wet),",
                 "per EVI unit, per metre of elevation, per case per person of malaria incidence")),
  sensitivity = list(multi_cluster_lgas_only = sens_mc, by_zone = per_fold),
  secondary_state_coverage = st_cov,
  secondary_zone_coverage = zn_cov,
  post_hoc_diagnostics_on_the_result = local({
    dif <- R$model_mean - R$direct_unweighted
    mvar <- ((R$ci_high - R$ci_low) / (2 * 1.96))^2
    bks <- c(0, 0.1, 0.2, 0.3, 0.5, 1)
    list(declared_after_seeing_the_result = TRUE,
         purpose = "characterise HOW the rule passed or failed; none of these is a check",
         bias = list(mean_model_minus_direct = mean(dif[ok]),
                     median_model_minus_direct = median(dif[ok]),
                     share_of_lgas_model_below_direct = mean(dif[ok] < 0)),
         spread = list(rms_z = sqrt(mean(zz^2)),
                       actual_error_over_claimed_sd = sqrt(mean(zz^2))),
         variance_shares = list(median_model_sd = median(sqrt(mvar[ok])),
                                median_design_se = median(R$design_se[ok], na.rm = TRUE),
                                mean_share_of_z_variance_from_design =
                                  mean(R$design_se[ok]^2 / (R$design_se[ok]^2 + mvar[ok]), na.rm = TRUE)),
         bias_by_direct_prevalence_band = lapply(seq_len(length(bks) - 1), function(i) {
           j <- R$direct_unweighted[ok] >= bks[i] & R$direct_unweighted[ok] < bks[i + 1]
           list(band = paste0("[", bks[i], ",", bks[i + 1], ")"), n = sum(j),
                mean_direct = mean(R$direct_unweighted[ok][j]),
                mean_model = mean(R$model_mean[ok][j]),
                mean_model_minus_direct = mean(R$model_mean[ok][j] - R$direct_unweighted[ok][j]))}),
         naive_interval_coverage_not_a_criterion = list(
           n_lgas = sum(ok),
           n_interval_contains_direct = sum(R$ci_low[ok] <= R$direct_unweighted[ok] &
                                            R$direct_unweighted[ok] <= R$ci_high[ok]),
           share = mean(R$ci_low[ok] <= R$direct_unweighted[ok] &
                        R$direct_unweighted[ok] <= R$ci_high[ok]),
           note = "descriptive only; this under-covers by construction"),
         fold_integrity = list(
           pooled_unweighted_prevalence = sum(R$n_households * R$direct_unweighted, na.rm = TRUE) /
                                          sum(R$n_households),
           expected_national_unweighted = 0.2774))
  }),
  fold_fit_times_seconds = sapply(fold_hyper, `[[`, "fit_seconds"),
  total_fit_seconds = sum(sapply(fold_hyper, `[[`, "fit_seconds")),
  limitations = list(
    count_functional_not_tested = TRUE,
    unclustered_lgas_not_tested = TRUE,
    n_unclustered_excluded = sum(!R$has_direct),
    household_covariates_held_known = TRUE,
    area_covariates_are_interpolated = TRUE,
    area_covariate_values_of_training_lgas_also_rebuilt = TRUE,
    state_zone_intervals_assume_independent_lgas = TRUE,
    linear_predictor_marginal_assumed_gaussian = TRUE,
    survey_design_not_in_likelihood = TRUE,
    single_cluster_lgas_deff_imputed = sum(R$design_se_source == "deff_imputed", na.rm = TRUE))
)
write(toJSON(sum_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null", na = "null"), p_sum)
msg("\nwrote %s (%.1f KB)", basename(p_sum), file.size(p_sum) / 1024)

## ==========================================================================
## 12. Final print
## ==========================================================================
msg("\n================ RESULT ================")
msg("folds: 6 | LGAs predicted: %d | with a direct estimate: %d", nrow(R), n_z)
msg("fit seconds per fold: %s",
    paste(sprintf("%s %.0f", sapply(fold_hyper, `[[`, "zone"), sapply(fold_hyper, `[[`, "fit_seconds")),
          collapse = " | "))
msg("mean z %+0.4f (T12 %+0.4f)  sd z %.4f (T12 %.4f)  coverage %.4f (T12 %.4f) -> %s",
    mean_z, rec12[["mean_z"]], sd_z, rec12[["sd_z"]], cov_z, rec12[["coverage"]],
    if (all_pass) "PASS" else "FAIL")
msg("out of sample: correlation %.3f (T12 %.3f)  compression %.3f (T12 %.3f)",
    oos15$correlation, oos12$correlation, oos15$compression_ratio, oos12$compression_ratio)
msg("states inside their interval: %d of %d (expected %d)",
    st_cov$n_inside, st_cov$n, round(st_cov$expected_under_perfect_calibration))
msg("zones  inside their interval: %d of %d (expected %d)",
    zn_cov$n_inside, zn_cov$n, round(zn_cov$expected_under_perfect_calibration))
msg("total elapsed: %.1f s", tick(t_all))
prog("summary written; %d/%d zones on disk; all checks %s", length(unique(R$zone)), 6L,
     if (all_pass) "PASS" else "FAIL")
