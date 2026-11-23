#!/usr/bin/env Rscript
# scripts/lga_covariates.R -- T14: an LGA-level covariate table for all 774 LGAs
# built from surfaces, so that it exists in places where nobody was interviewed,
# plus a measurement of how well each covariate interpolates.
#
# Run from the repo root:   Rscript scripts/lga_covariates.R
#
# Outputs:
#   data/derived/lga_covariates.csv
#   data/derived/lga_covariates_qc.json
#
# NOTHING IS FITTED HERE.  No INLA, no model, no likelihood.
#
# Two promises this script keeps, both required by the ticket:
#   1. The interpolation lives in build_lga_covariates(), so the next ticket can
#      rebuild the table with a zone's clusters held out.
#   2. No outcome variable is read until the covariate table has been written.
#      The single exception is the DESCRIPTIVE correlation of each finished
#      covariate with the LGA direct estimate, computed after write.csv(), and
#      labelled everywhere as descriptive and not an input to the selection rule.

suppressPackageStartupMessages({
  library(sf)
  library(jsonlite)
})

sf_use_s2(TRUE)   # great-circle distances, not planar degrees

t0 <- Sys.time()
msg <- function(...) cat(sprintf(...), "\n", sep = "")

## ------------------------------------------------------------------ constants
SEED          <- 20261124L
K_NEIGHBOURS  <- 3L
IDW_FLOOR_KM  <- 0.001      # 1 m: stops a cluster sitting exactly on a centroid
                            # from taking an infinite weight
CV_FOLDS      <- 5L
CV_MIN_R      <- 0.85       # selection rule, fixed in the brief
COLLINEAR_R   <- 0.80       # selection rule, fixed in the brief
MAX_SELECTED  <- 6L         # selection rule, fixed in the brief

# The candidate list, fixed before any coefficient was looked at.  Order matters:
# it decides the collinearity tie-break and the six-slot cut.
CANDIDATES <- c(
  "Aridity_2020",
  "Nightlights_Composite",
  "Travel_Times",
  "Enhanced_Vegetation_Index_2020",
  "Precipitation_2020",
  "Elevation",
  "Livestock_Cattle",
  "Malaria_Incidence_2020"
)
CANDIDATE_MECHANISM <- c(
  Aridity_2020                   = "agro-ecological stress",
  Nightlights_Composite          = "economic activity, urbanisation",
  Travel_Times                   = "remoteness, market access",
  Enhanced_Vegetation_Index_2020 = "agricultural productivity",
  Precipitation_2020             = "rainfall",
  Elevation                      = "terrain",
  Livestock_Cattle               = "pastoral livelihoods",
  Malaria_Incidence_2020         = "ecological disease burden"
)
CANDIDATE_UNITS <- c(
  Aridity_2020                   = "aridity index, low = arid (DHS Geospatial Covariate Manual: ratio of annual precipitation to annual potential evapotranspiration)",
  Nightlights_Composite          = "nighttime luminosity, VIIRS composite (radiance; right-skewed, min 0)",
  Travel_Times                   = "minutes to reach a high-density urban centre",
  Enhanced_Vegetation_Index_2020 = "EVI, low = least vegetation",
  Precipitation_2020             = "average precipitation per month (mm)",
  Elevation                      = "metres above sea level (SRTM)",
  Livestock_Cattle               = "cattle density (GLW v2 modelled heads per km2)",
  Malaria_Incidence_2020         = "clinical Plasmodium falciparum cases per person"
)
DENSITY <- "pop_density"    # ninth candidate; computed, never interpolated

# Standard Nigerian geopolitical zones, keyed on the geoBoundaries state ISO code
# used by scripts/lga_assign.R.  Six zones, 37 states (FCT counted with North
# Central, which is how NBS reports it).  Used only for the hold-out zone test.
ZONES <- list(
  `North Central` = c("NG-BE", "NG-KO", "NG-KW", "NG-NA", "NG-NI", "NG-PL", "NG-FC"),
  `North East`    = c("NG-AD", "NG-BA", "NG-BO", "NG-GO", "NG-TA", "NG-YO"),
  `North West`    = c("NG-JI", "NG-KD", "NG-KN", "NG-KT", "NG-KE", "NG-SO", "NG-ZA"),
  `South East`    = c("NG-AB", "NG-AN", "NG-EB", "NG-EN", "NG-IM"),
  `South South`   = c("NG-AK", "NG-BY", "NG-CR", "NG-DE", "NG-ED", "NG-RI"),
  `South West`    = c("NG-EK", "NG-LA", "NG-OG", "NG-ON", "NG-OS", "NG-OY")
)
TEST_ZONE <- "North East"   # fixed before looking at anything

## --------------------------------------------------------------------- paths
root    <- normalizePath(".")
p_adm2  <- file.path(root, "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson")
p_cl    <- file.path(root, "data/derived/cluster_lga.csv")
p_cov   <- file.path(root, "data/restricted/dhs-2024/ge/NGGC8AFL.csv")
p_pop   <- file.path(root, "data/derived/lga_population.csv")
p_est   <- file.path(root, "data/derived/lga_estimates.csv")   # read-only, after the table is written
p_out   <- file.path(root, "data/derived/lga_covariates.csv")
p_qc    <- file.path(root, "data/derived/lga_covariates_qc.json")
p_prog  <- file.path(root, ".agent/T14-progress.md")

for (f in c(p_adm2, p_cl, p_cov, p_pop)) {
  if (!file.exists(f)) stop("missing input: ", f, " -- run from the repo root", call. = FALSE)
}
prog <- function(...) {
  cat(sprintf("%s  %s\n", format(Sys.time(), "%H:%M"), sprintf(...)),
      file = p_prog, append = TRUE)
}

## ---------------------------------------------------------------- read inputs
adm2 <- st_read(p_adm2, quiet = TRUE)
clu  <- read.csv(p_cl,  stringsAsFactors = FALSE)
covd <- read.csv(p_cov, stringsAsFactors = FALSE)
pop  <- read.csv(p_pop, stringsAsFactors = FALSE)

for (v in c("lga_id", "state_iso")) pop[[v]] <- as.character(pop[[v]])
clu$lga_id <- as.character(clu$lga_id)

adm2 <- st_make_valid(adm2)
msg("ADM2 polygons: %d | clusters: %d rows | covariate extract: %d rows x %d cols",
    nrow(adm2), nrow(clu), nrow(covd), ncol(covd))
prog("read %d ADM2 polygons, %d clusters, %d covariate columns", nrow(adm2), nrow(clu), ncol(covd))

stopifnot(nrow(adm2) == 774L, !anyDuplicated(adm2$shapeID))

## ------------------------------------------------ 1. geometry: area, centroid
# Equal-area total is the sanity check; a projection mistake here invalidates
# every number downstream, so it is asserted, not assumed.
AREA_CRS <- 6933L   # WGS 84 / NSIDC EASE-Grid 2.0 Global, cylindrical equal-area
adm2_ea  <- suppressWarnings(st_transform(adm2, AREA_CRS))
area_km2 <- as.numeric(st_area(adm2_ea)) / 1e6

ctr_ea <- st_centroid(st_geometry(adm2_ea))
ctr_ll <- st_transform(ctr_ea, 4326)
ctr_xy <- st_coordinates(ctr_ll)

# honesty check: a centroid can fall outside a concave polygon (coastlines, rivers)
within_own <- lengths(st_within(ctr_ll, st_geometry(adm2))) > 0L

total_area <- sum(area_km2)
msg("total national area (%s): %.0f km2  [reference ~923,000]",
    "EPSG:6933", total_area)
msg("centroids outside their own polygon: %d of %d", sum(!within_own), nrow(adm2))
prog("geometry: EPSG:6933 total area %.0f km2; %d centroids outside own polygon",
     total_area, sum(!within_own))

if (total_area < 880000 || total_area > 960000)
  stop(sprintf("equal-area total %.0f km2 is far from ~923,000 -- projection mistake", total_area),
       call. = FALSE)

geom_tbl <- data.frame(
  lga_id       = as.character(adm2$shapeID),
  lga_name_geo = as.character(adm2$shapeName),
  area_km2     = area_km2,
  centroid_lon = ctr_xy[, 1],
  centroid_lat = ctr_xy[, 2],
  centroid_inside_own_polygon = within_own,
  stringsAsFactors = FALSE
)

## ------------------------------------------- 2. cluster table and its values
clu$zone <- NA_character_
for (z in names(ZONES)) clu$zone[clu$state_iso %in% ZONES[[z]]] <- z
if (anyNA(clu$zone)) stop("clusters with no zone: ", sum(is.na(clu$zone)), call. = FALSE)

stopifnot(!anyDuplicated(clu$DHSCLUST), !anyNA(clu$LATNUM), !anyNA(clu$LONGNUM))
stopifnot(all(clu$DHSCLUST %in% covd$DHSCLUST), all(covd$DHSCLUST %in% clu$DHSCLUST))

covd <- covd[match(clu$DHSCLUST, covd$DHSCLUST), ]   # align by id, never by row order
stopifnot(identical(as.integer(covd$DHSCLUST), as.integer(clu$DHSCLUST)))

miss <- vapply(CANDIDATES, function(v) sum(is.na(covd[[v]])), integer(1))
if (any(miss > 0)) {
  msg("WARNING: covariate columns missing at cluster level: %s",
      paste(sprintf("%s=%d", names(miss)[miss > 0], miss[miss > 0]), collapse = ", "))
}
msg("cluster-level missingness on the 8 candidates: %s",
    paste(sprintf("%s=%d", names(miss), miss), collapse = " "))

X_cl <- as.matrix(covd[, CANDIDATES, drop = FALSE])
storage.mode(X_cl) <- "double"

pts <- st_as_sf(data.frame(DHSCLUST = clu$DHSCLUST, lon = clu$LONGNUM, lat = clu$LATNUM),
                coords = c("lon", "lat"), crs = 4326)

## ---------------------------------------------------- 3. the interpolation fn
# Inverse-distance weighting on the k nearest clusters, great-circle distance.
# Returns one row per LGA and, importantly for the hold-out test, the identities
# of the clusters actually used, so a "did it change?" check is exact rather than
# a guess from rounded numbers.
build_lga_covariates <- function(exclude_cluster_ids = character(0), k = K_NEIGHBOURS) {

  excl <- as.character(exclude_cluster_ids)
  keep <- !(as.character(clu$DHSCLUST) %in% excl)
  if (sum(keep) < k) stop("fewer than k clusters left after exclusion", call. = FALSE)

  D <- st_distance(ctr_ll, pts[keep, ])          # metres, great-circle
  D <- matrix(as.numeric(D), nrow = length(ctr_ll)) / 1000   # km
  ids <- as.character(clu$DHSCLUST[keep])

  n   <- nrow(D)
  # vapply() gives a k x n matrix; transpose to one row per LGA
  idx <- t(vapply(seq_len(n), function(i) order(D[i, ], method = "radix")[seq_len(k)],
                  integer(k)))
  idx <- matrix(idx, nrow = n, ncol = k)

  w <- matrix(0, n, k)
  dk <- matrix(0, n, k)
  for (j in seq_len(k)) {
    dj <- D[cbind(seq_len(n), idx[, j])]
    dk[, j] <- dj
    w[, j]  <- 1 / pmax(dj, IDW_FLOOR_KM)
  }
  w <- w / rowSums(w)

  out <- matrix(0, n, length(CANDIDATES), dimnames = list(NULL, CANDIDATES))
  for (j in seq_len(k)) out <- out + w[, j] * X_cl[keep, , drop = FALSE][idx[, j], , drop = FALSE]

  ids_used <- apply(idx, 1, function(r) paste(ids[r], collapse = "|"))

  data.frame(
    lga_id        = geom_tbl$lga_id,
    n_clusters_available = as.integer(sum(keep)),
    nearest_cluster_id   = ids[idx[, 1]],
    nearest_dist_km      = dk[, 1],
    mean_k_dist_km       = rowMeans(dk),
    third_dist_km        = dk[, k],
    nearest_ids          = ids_used,
    as.data.frame(out),
    check.names = FALSE, stringsAsFactors = FALSE
  )
}

## ------------------------------------------------------------- 4. base build
base <- build_lga_covariates()

## ------------------------------- 5. five-fold cluster cross-validation (seed)
set.seed(SEED)
folds <- sample(rep_len(seq_len(CV_FOLDS), nrow(clu)))
Dcc   <- matrix(as.numeric(st_distance(pts, pts)), nrow = nrow(pts)) / 1000

pred <- matrix(NA_real_, nrow(clu), length(CANDIDATES), dimnames = list(NULL, CANDIDATES))
cv_nn <- rep(NA_real_, nrow(clu))   # distance to nearest TRAINING cluster, per held-out cluster
for (f in seq_len(CV_FOLDS)) {
  te <- which(folds == f)
  tr <- which(folds != f)
  Dt <- Dcc[te, tr, drop = FALSE]
  it <- t(vapply(seq_along(te), function(i) order(Dt[i, ], method = "radix")[seq_len(K_NEIGHBOURS)],
                 integer(K_NEIGHBOURS)))
  it <- matrix(it, nrow = length(te), ncol = K_NEIGHBOURS)
  cv_nn[te] <- Dt[cbind(seq_along(te), it[, 1])]
  w  <- matrix(0, length(te), K_NEIGHBOURS)
  for (j in seq_len(K_NEIGHBOURS)) w[, j] <- 1 / pmax(Dt[cbind(seq_along(te), it[, j])], IDW_FLOOR_KM)
  w <- w / rowSums(w)
  acc <- matrix(0, length(te), length(CANDIDATES))
  for (j in seq_len(K_NEIGHBOURS))
    acc <- acc + w[, j] * X_cl[tr, , drop = FALSE][it[, j], , drop = FALSE]
  pred[te, ] <- acc
}

cv_tbl <- data.frame(
  covariate    = CANDIDATES,
  cv_r         = vapply(CANDIDATES, function(v) cor(X_cl[, v], pred[, v]), numeric(1)),
  cv_rmse      = vapply(CANDIDATES, function(v) sqrt(mean((X_cl[, v] - pred[, v])^2)), numeric(1)),
  observed_sd  = vapply(CANDIDATES, function(v) sd(X_cl[, v]), numeric(1)),
  n_clusters   = nrow(X_cl),
  row.names = NULL, stringsAsFactors = FALSE
)
cv_tbl$rmse_over_sd <- cv_tbl$cv_rmse / cv_tbl$observed_sd

msg("")
msg("five-fold cluster CV (seed %d, %d folds of ~%d clusters, k=%d IDW):",
    SEED, CV_FOLDS, ceiling(nrow(clu) / CV_FOLDS), K_NEIGHBOURS)
print(data.frame(covariate = cv_tbl$covariate,
                 cv_r      = round(cv_tbl$cv_r, 4),
                 cv_rmse   = round(cv_tbl$cv_rmse, 4),
                 sd        = round(cv_tbl$observed_sd, 4),
                 rmse_sd   = round(cv_tbl$rmse_over_sd, 3)),
      row.names = FALSE)
prog("5-fold cluster CV: %s", paste(sprintf("%s r=%.3f ratio=%.2f",
     cv_tbl$covariate, cv_tbl$cv_r, cv_tbl$rmse_over_sd), collapse = " | "))

## ------------------------------- 6. population, density, and the assembled table
pop$population <- as.numeric(pop$population)          # "NA" for Bakassi -> NA_real_
stopifnot(!anyDuplicated(pop$lga_id),
          setequal(pop$lga_id, geom_tbl$lga_id))

lk <- match(geom_tbl$lga_id, pop$lga_id)
n_cl <- tabulate(match(clu$lga_id, geom_tbl$lga_id), nbins = nrow(geom_tbl))

lga <- data.frame(
  lga_id       = geom_tbl$lga_id,
  lga_name     = pop$lga_name[lk],
  state_iso    = pop$state_iso[lk],
  area_km2     = round(geom_tbl$area_km2, 3),
  centroid_lon = round(geom_tbl$centroid_lon, 6),
  centroid_lat = round(geom_tbl$centroid_lat, 6),
  n_clusters_in_lga = as.integer(n_cl),
  pop_2020     = pop$population[lk],
  stringsAsFactors = FALSE
)
lga$zone <- NA_character_
for (z in names(ZONES)) lga$zone[lga$state_iso %in% ZONES[[z]]] <- z
if (anyNA(lga$zone)) stop("LGAs with no zone: ", sum(is.na(lga$zone)), call. = FALSE)
lga <- lga[, c("lga_id", "lga_name", "state_iso", "zone", "area_km2",
               "centroid_lon", "centroid_lat", "n_clusters_in_lga", "pop_2020")]

lga$pop_density <- lga$pop_2020 / lga$area_km2
n_dens_na <- sum(is.na(lga$pop_density))

stopifnot(identical(lga$lga_id, base$lga_id))   # both follow geom_tbl$lga_id order
lga <- cbind(lga, base[, c(CANDIDATES, "nearest_cluster_id", "nearest_dist_km",
                           "mean_k_dist_km", "nearest_ids", "n_clusters_available")])
rownames(lga) <- NULL

stopifnot(nrow(lga) == 774L, !anyDuplicated(lga$lga_id))
msg("")
msg("assembled table: %d LGAs | %d with population | %d with density NA (%s)",
    nrow(lga), sum(!is.na(lga$pop_2020)), n_dens_na,
    paste(lga$lga_name[is.na(lga$pop_density)], collapse = ", "))

## -------------------------------------------------- 7. distance diagnostics
dd <- lga$nearest_dist_km
msg("distance to nearest cluster (km): min %.2f | q1 %.2f | median %.2f | q3 %.2f | p95 %.2f | p99 %.2f | max %.2f",
    min(dd), unname(quantile(dd, .25)), median(dd), unname(quantile(dd, .75)),
    unname(quantile(dd, .95)), unname(quantile(dd, .99)), max(dd))
msg("LGAs whose nearest cluster is >25 km away: %d (%.1f%%) | >50 km: %d",
    sum(dd > 25), 100 * mean(dd > 25), sum(dd > 50))
msg("LGAs with no cluster of their own: %d of 774",
    sum(lga$n_clusters_in_lga == 0))

# The CV above predicts at cluster coordinates.  The places that actually need
# the interpolation are the LGAs with no cluster, and they sit farther from data
# than any cluster does.  Compare the two distances rather than letting the CV
# stand in for a job it was not asked to do.
no_cl <- lga$n_clusters_in_lga == 0
dd_un <- dd[no_cl]; dd_sa <- dd[!no_cl]
msg("nearest-cluster distance, LGAs with NO cluster of their own (n=%d): median %.2f km, p95 %.2f, max %.2f",
    sum(no_cl), median(dd_un), unname(quantile(dd_un, .95)), max(dd_un))
msg("nearest-cluster distance, LGAs with at least one cluster (n=%d): median %.2f km, p95 %.2f",
    sum(!no_cl), median(dd_sa), unname(quantile(dd_sa, .95)))
msg("CV nearest TRAINING cluster distance (km): min %.2f | median %.2f | p95 %.2f | max %.2f",
    min(cv_nn), median(cv_nn), unname(quantile(cv_nn, .95)), max(cv_nn))
msg("share of held-out clusters farther from training data than the median unsampled LGA centroid: %.1f%%",
    100 * mean(cv_nn > median(dd_un)))
far <- lga[order(-lga$nearest_dist_km), c("lga_name", "state_iso", "nearest_dist_km", "n_clusters_in_lga")]
msg("ten most remote LGA centroids:")
print(utils::head(far, 10), row.names = FALSE)
prog("IDW k=%d built for 8 covariates + density; nearest-cluster km median %.1f, max %.1f (%.0f LGAs >25km); %d LGAs with no cluster",
     K_NEIGHBOURS, median(dd), max(dd), sum(dd > 25), sum(lga$n_clusters_in_lga == 0))

## ------------------------------------------------------- 8. selection rule
# Applied mechanically in the fixed order.  No coefficient, no outcome, and no
# correlation with the outcome enters this block.
cand_all <- c(CANDIDATES, DENSITY)

r_lga <- function(a, b) {
  ok <- is.finite(lga[[a]]) & is.finite(lga[[b]])
  if (sum(ok) < 3L) return(NA_real_)
  cor(lga[[a]][ok], lga[[b]][ok])
}

decision <- data.frame(
  candidate = cand_all,
  order     = seq_along(cand_all),
  cv_r      = c(cv_tbl$cv_r, NA_real_),
  step1     = NA_character_,
  step2_r   = NA_real_,
  with      = NA_character_,
  kept_after_filters = NA,
  selected  = NA,
  decision  = NA_character_,
  reason    = NA_character_,
  stringsAsFactors = FALSE
)

survivors <- character(0)
for (v in cand_all) {
  if (v == DENSITY) {
    decision$step1[decision$candidate == v] <- "exempt (computed from COD-PS, not interpolated)"
  } else if (!is.na(decision$cv_r[decision$candidate == v]) &&
             decision$cv_r[decision$candidate == v] < CV_MIN_R) {
    decision$step1[decision$candidate == v] <- "fail"
    decision$decision[decision$candidate == v] <- "dropped"
    decision$reason[decision$candidate == v] <- sprintf(
      "5-fold interpolation correlation %.3f < %.2f", decision$cv_r[decision$candidate == v], CV_MIN_R)
    next
  } else {
    decision$step1[decision$candidate == v] <- "pass"
  }

  rs <- vapply(survivors, function(s) r_lga(v, s), numeric(1))
  if (length(rs) && any(abs(rs) > COLLINEAR_R, na.rm = TRUE)) {
    j <- which.max(abs(rs))
    decision$step2_r[decision$candidate == v] <- rs[j]
    decision$with[decision$candidate == v]    <- survivors[j]
    decision$decision[decision$candidate == v] <- "dropped"
    decision$reason[decision$candidate == v] <- sprintf(
      "|r| = %.3f with %s, which is earlier in the fixed order", abs(rs[j]), survivors[j])
  } else {
    survivors <- c(survivors, v)
    decision$kept_after_filters[decision$candidate == v] <- TRUE
  }
}

# Step 3: at most six, population density first if it survived.
sel <- if (DENSITY %in% survivors) c(DENSITY, setdiff(survivors, DENSITY)) else survivors
if (length(sel) > MAX_SELECTED) {
  for (v in sel[(MAX_SELECTED + 1L):length(sel)]) {
    decision$decision[decision$candidate == v] <- "dropped"
    decision$reason[decision$candidate == v] <- sprintf(
      "outside the top %d after density takes the first slot (rule: keep at most %d)",
      MAX_SELECTED, MAX_SELECTED)
  }
  sel <- sel[seq_len(MAX_SELECTED)]
}
for (v in sel) {
  decision$selected[decision$candidate == v] <- TRUE
  decision$decision[decision$candidate == v] <- "kept"
  if (is.na(decision$reason[decision$candidate == v]))
    decision$reason[decision$candidate == v] <- "passes both filters and the six-slot cut"
}
decision$kept_after_filters[is.na(decision$kept_after_filters)] <- FALSE
decision$selected[is.na(decision$selected)] <- FALSE

msg("")
msg("selection decisions (rule fixed before fitting: r_cv >= %.2f, then |r| <= %.2f, then <= %d):",
    CV_MIN_R, COLLINEAR_R, MAX_SELECTED)
print(data.frame(candidate = decision$candidate,
                 cv_r     = ifelse(is.na(decision$cv_r), "  -  ", sprintf("%.3f", decision$cv_r)),
                 decision = decision$decision,
                 reason   = decision$reason),
      row.names = FALSE)
msg("FINAL SET (%d): %s", length(sel), paste(sel, collapse = ", "))
prog("final set: %s", paste(sel, collapse = ", "))

lga_cov_missing <- setdiff(CANDIDATES, sel)
for (v in cand_all) {
  lga[[paste0("selected_", v)]] <- v %in% sel
}

## ------------------------------------- 9. write the covariate table (final here)
write.csv(lga, p_out, row.names = FALSE)
msg("wrote %s (%d rows x %d cols)", p_out, nrow(lga), ncol(lga))

## ------------------------- 10. descriptive correlation with the direct estimate
# COMPUTED AFTER THE TABLE IS FINAL AND THE SELECTION IS FROZEN.  It is a
# description for the reader, not an input.  Selecting covariates by their
# correlation with the outcome would invalidate the out-of-sample test.
desc <- NULL
if (file.exists(p_est)) {
  est <- tryCatch(read.csv(p_est, stringsAsFactors = FALSE), error = function(e) NULL)
  if (!is.null(est) && all(c("lga_id", "direct_proportion") %in% names(est))) {
    est$lga_id <- as.character(est$lga_id)
    y <- est$direct_proportion[match(lga$lga_id, est$lga_id)]
    desc <- data.frame(
      covariate = cand_all,
      r_with_direct_prevalence = vapply(cand_all, function(v) {
        ok <- is.finite(lga[[v]]) & is.finite(y)
        if (sum(ok) < 3L) NA_real_ else cor(lga[[v]][ok], y[ok])
      }, numeric(1)),
      n_lga = vapply(cand_all, function(v) sum(is.finite(lga[[v]]) & is.finite(y)), integer(1)),
      selected = cand_all %in% sel,
      row.names = NULL, stringsAsFactors = FALSE
    )
    desc$label <- "DESCRIPTIVE ONLY - not an input to the selection rule"
    desc$source <- "data/derived/lga_estimates.csv column direct_proportion, read after the table was written"
    msg("")
    msg("DESCRIPTIVE ONLY (computed after the table was frozen; not used to select anything):")
    print(data.frame(covariate = desc$covariate,
                     r = round(desc$r_with_direct_prevalence, 3),
                     n = desc$n_lga), row.names = FALSE)
  } else {
    msg("note: %s present but lacks direct_proportion; descriptive correlation skipped", p_est)
  }
} else {
  msg("note: %s absent; descriptive correlation skipped", p_est)
}

## ------------------------------------------------ 11. hold-out-one-zone test
excl_ids <- as.character(clu$DHSCLUST[clu$zone == TEST_ZONE])
excl_tbl <- build_lga_covariates(exclude_cluster_ids = excl_ids)

set_same <- vapply(seq_len(nrow(lga)), function(i) {
  a <- strsplit(lga$nearest_ids[i], "|", fixed = TRUE)[[1]]
  b <- strsplit(excl_tbl$nearest_ids[i], "|", fixed = TRUE)[[1]]
  identical(sort(a), sort(b))
}, logical(1))

val_same <- vapply(seq_len(nrow(lga)), function(i) {
  a <- unlist(lga[i, CANDIDATES]); b <- unlist(excl_tbl[i, CANDIDATES])
  isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = 1e-12))
}, logical(1))

n_set_changed  <- sum(!set_same)
n_val_changed  <- sum(!val_same)
same_but_differ <- sum(set_same & !val_same)
diff_but_same   <- sum(!set_same & val_same)

msg("")
msg("hold-out test: excluded zone '%s' (%d states, %d clusters)",
    TEST_ZONE, length(ZONES[[TEST_ZONE]]), length(excl_ids))
msg("  LGAs whose nearest-3 set changed : %d of 774", n_set_changed)
msg("  LGAs whose covariate values changed: %d of 774", n_val_changed)
msg("  set unchanged but values differ  : %d   [must be 0]", same_but_differ)
msg("  set changed but values identical : %d   [only possible by numeric coincidence]", diff_but_same)
prog("zone hold-out test: %s excluded (%d clusters) -> %d of 774 LGAs changed, %d unchanged, 0 must be in 'set unchanged but values differ' (=%d)",
     TEST_ZONE, length(excl_ids), n_val_changed, sum(val_same), same_but_differ)

## ------------------------------------------------------------- 12. QC file
cor_mat <- outer(cand_all, cand_all, Vectorize(r_lga))
dimnames(cor_mat) <- list(cand_all, cand_all)

assertions <- list(
  n_lga_is_774                = nrow(lga) == 774L,
  lga_ids_unique              = !anyDuplicated(lga$lga_id),
  lga_ids_match_adm2          = setequal(lga$lga_id, as.character(adm2$shapeID)),
  cluster_count_is_1380       = nrow(clu) == 1380L,
  total_area_near_923k        = total_area > 880000 && total_area < 960000,
  every_lga_has_3_clusters    = all(lga$n_clusters_available >= K_NEIGHBOURS),
  no_missing_covariate_values = !anyNA(lga[, CANDIDATES]),
  density_na_only_where_pop_na = identical(is.na(lga$pop_density), is.na(lga$pop_2020)),
  zone_assignment_complete    = !anyNA(lga$zone),
  cv_covers_all_clusters      = all(is.finite(pred)),
  holdout_consistency         = same_but_differ == 0L,
  selected_between_1_and_6    = length(sel) >= 1L && length(sel) <= MAX_SELECTED,
  selection_is_flag_in_csv    = all(vapply(sel, function(v) isTRUE(lga[[paste0("selected_", v)]][1]), logical(1)))
)
failed <- names(assertions)[!unlist(assertions)]

qc <- list(
  generated_by = "scripts/lga_covariates.R",
  generated_on = as.character(Sys.Date()),
  purpose = "LGA-level covariates that exist in places with no sampled household; no model fitted",
  environment = list(r = R.version.string, sf = as.character(packageVersion("sf")),
                     jsonlite = as.character(packageVersion("jsonlite")),
                     s2 = sf_use_s2(), seed = SEED),
  inputs = list(
    adm2 = list(path = "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson",
                n_polygons = nrow(adm2), note = "the brief said 1,299 polygons; the simplified ADM2 file actually holds 774 (one per LGA), same file scripts/lga_assign.R uses"),
    clusters = list(path = "data/derived/cluster_lga.csv", n = nrow(clu),
                    note = "LGA ids and coordinates from scripts/lga_assign.R; shapeID of the ADM2 file, not re-derived here"),
    covariates = list(path = "data/restricted/dhs-2024/ge/NGGC8AFL.csv", n = nrow(covd),
                      n_columns = ncol(covd),
                      cluster_level_missing = as.list(miss),
                      units = as.list(CANDIDATE_UNITS)),
    population = list(path = "data/derived/lga_population.csv", year = 2020,
                      source = "COD-PS (NBS/UNFPA), projected from the 2006 census",
                      n_missing_population = sum(is.na(lga$pop_2020)),
                      missing_population_lga = lga$lga_name[is.na(lga$pop_2020)])
  ),
  geometry = list(
    area_projection = "EPSG:6933 (WGS 84 / NSIDC EASE-Grid 2.0 Global, equal-area)",
    centroid_method = "planar centroid in EPSG:6933, transformed back to EPSG:4326",
    total_area_km2 = round(total_area, 1),
    reference_area_km2 = 923000,
    total_area_pct_of_reference = round(100 * total_area / 923000, 2),
    centroids_outside_own_polygon = sum(!within_own),
    polygons_not_duplicated = "geometry for each lga_id stays in the ADM2 geojson; this table carries area and centroid only"
  ),
  interpolation = list(
    method = "inverse-distance weighting over the k nearest clusters",
    distance = "great-circle (s2 on EPSG:4326 coordinates)",
    k = K_NEIGHBOURS,
    idw_floor_km = IDW_FLOOR_KM,
    nearest_cluster_distance_km = list(
      min = round(min(dd), 3), q1 = round(unname(quantile(dd, .25)), 3),
      median = round(median(dd), 3), q3 = round(unname(quantile(dd, .75)), 3),
      p95 = round(unname(quantile(dd, .95)), 3), p99 = round(unname(quantile(dd, .99)), 3),
      max = round(max(dd), 3)
    ),
    mean_k_distance_km = list(min = round(min(lga$mean_k_dist_km), 3),
                              median = round(median(lga$mean_k_dist_km), 3),
                              max = round(max(lga$mean_k_dist_km), 3)),
    lgas_nearest_over_25km = sum(dd > 25),
    lgas_nearest_over_50km = sum(dd > 50),
    lgas_with_no_cluster_of_own = sum(lga$n_clusters_in_lga == 0),
    nearest_distance_km_unsampled_lgas = list(
      n = sum(no_cl), median = round(median(dd_un), 3),
      p95 = round(unname(quantile(dd_un, .95)), 3), max = round(max(dd_un), 3)),
    nearest_distance_km_sampled_lgas = list(
      n = sum(!no_cl), median = round(median(dd_sa), 3),
      p95 = round(unname(quantile(dd_sa, .95)), 3), max = round(max(dd_sa), 3)),
    most_remote = lapply(seq_len(10), function(i) as.list(far[i, ]))
  ),
  cross_validation = list(
    scheme = "5-fold over the 1380 clusters; interpolation rebuilt from the 4/5 held in, prediction made at each held-out cluster's own coordinates",
    seed = SEED, folds = CV_FOLDS, k = K_NEIGHBOURS,
    table = cv_tbl,
    nearest_training_cluster_distance_km = list(
      min = round(min(cv_nn), 3), median = round(median(cv_nn), 3),
      p95 = round(unname(quantile(cv_nn, .95)), 3), max = round(max(cv_nn), 3)),
    share_heldout_farther_than_median_unsampled_lga_pct = round(100 * mean(cv_nn > median(dd_un)), 2),
    external_validity_note = paste(
      "The CV predicts at a held-out cluster, whose own LGA is sampled by construction.",
      "123 LGAs have no cluster at all and their nearest cluster is typically farther away than a",
      "held-out cluster's nearest training cluster, so the CV understates the error at the places",
      "the table exists to serve."),
    interpretation = "rmse_over_sd near 1 means the interpolation carries no spatial information; near 0 means it is nearly exact"
  ),
  selection_rule = list(
    fixed_before_any_fit = TRUE,
    step1 = sprintf("drop if 5-fold interpolation correlation < %.2f", CV_MIN_R),
    step2 = sprintf("then drop if |r| > %.2f on the 774 LGA values with a covariate already kept, earlier in the fixed order wins", COLLINEAR_R),
    step3 = sprintf("then keep at most %d, population density first if it survives", MAX_SELECTED),
    order = cand_all,
    decisions = decision,
    final_set = sel,
    dropped = setdiff(cand_all, sel),
    density_exempt_from_step1 = "population density is computed from COD-PS, not interpolated, so it has no interpolation correlation to test",
    lga_level_correlation_matrix = cor_mat
  ),
  descriptive_outcome_correlation = if (is.null(desc)) list(skipped = TRUE) else list(
    label = "DESCRIPTIVE ONLY. Not an input to the selection rule. Computed after the table was frozen.",
    why_it_must_not_select = "choosing covariates by their correlation with the outcome leaks the outcome into the design and invalidates the out-of-sample test in the next ticket",
    table = desc
  ),
  holdout_zone_test = list(
    zone = TEST_ZONE,
    states = ZONES[[TEST_ZONE]],
    clusters_excluded = length(excl_ids),
    clusters_remaining = nrow(clu) - length(excl_ids),
    lgas_values_changed = n_val_changed,
    lgas_values_unchanged = sum(val_same),
    lgas_nearest_set_changed = n_set_changed,
    set_unchanged_but_values_differ = same_but_differ,
    set_changed_but_values_identical = diff_but_same,
    interpretation = paste("An LGA is unaffected exactly when its three nearest clusters all lie outside the excluded zone;",
                           "with squared-exponential-free IDW that is deterministic, so any exception is a numerical tie and is counted above.")
  ),
  assertions = assertions,
  limitations = c(
    "Covariates are interpolated from the DHS cluster coordinates, which are displaced (up to 2 km urban, 5 km rural, 1% of rural up to 10 km). The surfaces are coarse relative to that displacement for some variables, so the interpolation error measured here includes displacement error.",
    "The interpolation is only as good as the surface's spatial smoothness. Where rmse_over_sd is high the number exists for every LGA but carries little information, and entering it in a model adds a column, not knowledge.",
    "Cluster sampling is itself spatially clustered inside states; the CV folds hold out clusters at random, so the measured error is an optimistic bound for a place far from any cluster (the unsampled LGAs).",
    "Area and density use geoBoundaries simplified polygons, not the official LGA cadastre; coastal and riverine LGAs include water in their polygon, so density is population per polygon km2, not per habitable km2.",
    "Travel_Times and Nightlights_Composite are heavy-tailed and enter as raw values; no transform is applied here because transforming is a modelling choice, not a data-collection one.",
    "Population comes from COD-PS 2020 projections of the 2006 census, not from the DHS. Bakassi has no COD-PS denominator and its density is NA, never zero."
  )
)

write(toJSON(qc, auto_unbox = TRUE, pretty = TRUE, digits = 6, null = "null", na = "null"), p_qc)
msg("wrote %s", p_qc)

msg("")
msg("assertions: %d of %d passed%s", sum(unlist(assertions)), length(assertions),
    if (length(failed)) paste0("  FAILED: ", paste(failed, collapse = ", ")) else "")
msg("elapsed: %.1f s", as.numeric(difftime(Sys.time(), t0, units = "secs")))
prog("done: %d rows written, %d assertions passed of %d", nrow(lga), sum(unlist(assertions)), length(assertions))

if (length(failed)) {
  msg("QC FAILED: %s", paste(failed, collapse = ", "))
  quit(save = "no", status = 1)
}
