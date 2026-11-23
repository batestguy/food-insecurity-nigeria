#!/usr/bin/env Rscript
# scripts/lga_assign.R -- assign DHS 2024 clusters to Nigeria's 774 LGAs, with a
# border-ambiguity sensitivity check.  T8.
#
# Run from the repo root:   Rscript scripts/lga_assign.R
#
# Outputs (all three written by this one command):
#   data/derived/cluster_lga.csv
#   data/derived/lga_coverage.csv
#   data/derived/lga_assignment_qc.json
#
# Assignment rule, stated once and used everywhere below:
#   1. Each LGA is assigned to exactly one state by its representative point
#      (st_point_on_surface), not by name and not by bounding box.  Nigerian LGA
#      names repeat across states, so a name join is not safe.
#   2. Each cluster takes the LGA whose polygon contains it (points-in-polygon,
#      EPSG:32632).  A cluster falling in no polygon is reported, never dropped.
#   3. "near_border" means the geodesic-style distance from the cluster to the
#      boundary of its assigned LGA is at most the DHS displacement radius for
#      that cluster's urban/rural class: 2,000 m urban, 5,000 m rural
#      (data/restricted/dhs-2024/ge/GPS_Displacement_README.txt, lines 42-43).
#   4. The sensitivity assignment moves every near_border cluster to its
#      second-nearest LGA.  Both are reported; the paper reports both.

suppressPackageStartupMessages({
  library(sf)
  library(jsonlite)
})

sf_use_s2(TRUE)

root <- normalizePath(".")
p_in_adm1 <- file.path(root, "data/public/boundaries/geoBoundaries-NGA-ADM1_simplified.geojson")
p_in_adm2 <- file.path(root, "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson")
p_in_cl   <- file.path(root, "data/restricted/dhs-2024/ge/NGGE8AFL.shp")
p_in_hh   <- file.path(root, "data/derived/analysis_households.csv")
p_out_cl  <- file.path(root, "data/derived/cluster_lga.csv")
p_out_cov <- file.path(root, "data/derived/lga_coverage.csv")
p_out_qc  <- file.path(root, "data/derived/lga_assignment_qc.json")

for (f in c(p_in_adm1, p_in_adm2, p_in_cl, p_in_hh)) {
  if (!file.exists(f)) stop("missing input: ", f, " -- run from the repo root", call. = FALSE)
}

# DHS displacement radii, read from GPS_Displacement_README.txt lines 42-43.
#   "up to 5km for rural points (with 1% of rural cluster being randomly
#    displaced up to 10km) and up to 2km for urban"
RADIUS_URBAN_M <- 2000L
RADIUS_RURAL_M <- 5000L
RADIUS_RURAL_TAIL_M <- 10000L
README_SOURCE <- paste0(
  "data/restricted/dhs-2024/ge/GPS_Displacement_README.txt line 42-43: ",
  "\"up to 5km for rural points (with 1% of rural cluster being randomly ",
  "displaced up to 10km) and up to 2km for urban\""
)

WORK_CRS <- 32632L  # UTM 32N; corroborated below against geodesic distances

msg <- function(...) cat(sprintf(...), "\n", sep = "")

## ---------------------------------------------------------------- read inputs
adm1 <- st_read(p_in_adm1, quiet = TRUE)
adm2 <- st_read(p_in_adm2, quiet = TRUE)
cl   <- st_read(p_in_cl,   quiet = TRUE)
hh   <- read.csv(p_in_hh,  stringsAsFactors = FALSE)

adm1 <- st_make_valid(adm1)
adm2 <- st_make_valid(adm2)

msg("ADM1 features: %d   ADM2 features: %d   clusters: %d   households: %d",
    nrow(adm1), nrow(adm2), nrow(cl), nrow(hh))
msg("CRS in:  ADM1 %s | ADM2 %s | clusters %s",
    st_crs(adm1)$input, st_crs(adm2)$input, st_crs(cl)$input)

adm1_p <- st_transform(adm1, WORK_CRS)
adm2_p <- st_transform(adm2, WORK_CRS)
cl_p   <- st_transform(cl,   WORK_CRS)

## --------------------------------------------- 1. LGA -> state, by geometry
lga_pt <- st_point_on_surface(st_geometry(adm2_p))
hit1   <- st_intersects(lga_pt, st_geometry(adm1_p))
n_hit1 <- lengths(hit1)

lga_state <- rep(NA_integer_, nrow(adm2_p))
method    <- rep(NA_character_, nrow(adm2_p))

for (i in seq_len(nrow(adm2_p))) {
  if (n_hit1[i] == 1L) {
    lga_state[i] <- hit1[[i]]
    method[i]    <- "representative_point"
  } else if (n_hit1[i] > 1L) {
    # degenerate: representative point sits on a shared border.  Fall back to
    # largest shared area, which is deterministic and does not depend on ORDER.
    areas <- as.numeric(st_area(st_intersection(st_geometry(adm2_p)[i],
                                                st_geometry(adm1_p)[hit1[[i]]])))
    lga_state[i] <- hit1[[i]][which.max(areas)]
    method[i]    <- "area_overlap_tiebreak"
  } else {
    # representative point outside every state: largest area overlap, else nearest
    inter <- suppressWarnings(st_intersection(st_geometry(adm2_p)[i], st_geometry(adm1_p)))
    if (length(inter) > 0L && any(!st_is_empty(inter))) {
      areas <- as.numeric(st_area(inter)); areas[is.na(areas)] <- 0
      if (max(areas) > 0) {
        lga_state[i] <- which.max(areas)
        method[i]    <- "area_overlap_fallback"
      }
    }
    if (is.na(lga_state[i])) {
      lga_state[i] <- st_nearest_feature(st_geometry(adm2_p)[i], st_geometry(adm1_p))
      method[i]    <- "nearest_state_fallback"
    }
  }
}

stopifnot(!anyNA(lga_state), length(unique(lga_state)) <= nrow(adm1_p))

lga_tbl <- data.frame(
  lga_id      = adm2_p$shapeID,
  lga_name    = adm2_p$shapeName,
  state_iso   = adm1_p$shapeISO[lga_state],
  state_name  = adm1_p$shapeName[lga_state],
  assign_rule = method,
  stringsAsFactors = FALSE
)

state_lga_counts <- as.data.frame(table(lga_tbl$state_name), stringsAsFactors = FALSE)
names(state_lga_counts) <- c("state_name", "n_lga")

a_state_counts_sum <- sum(state_lga_counts$n_lga) == nrow(adm2_p)
a_lga_one_state    <- sum(!duplicated(lga_tbl$lga_id)) == nrow(adm2_p) && !anyNA(lga_tbl$state_iso)
a_all_states_used  <- nrow(state_lga_counts) == nrow(adm1_p)

msg("LGA->state: %d LGAs, %d states, counts sum to %d (assert %s)",
    nrow(lga_tbl), nrow(state_lga_counts), sum(state_lga_counts$n_lga),
    a_state_counts_sum)
msg("assignment rules used: %s",
    paste(sprintf("%s=%d", names(table(method)), as.integer(table(method))), collapse = ", "))

## ------------------------------------------------------ 2. cluster -> LGA
hit2 <- st_intersects(st_geometry(cl_p), st_geometry(adm2_p))
n_hit2 <- lengths(hit2)

cl_lga <- rep(NA_integer_, nrow(cl_p))
multi  <- 0L
for (i in seq_len(nrow(cl_p))) {
  cand <- hit2[[i]]
  if (length(cand) == 1L) {
    cl_lga[i] <- cand
  } else if (length(cand) > 1L) {
    # point sits on a shared border.  Deterministic tie-break: nearest
    # representative point.  Counted and reported.
    multi <- multi + 1L
    dd <- as.numeric(st_distance(st_geometry(cl_p)[i], lga_pt[cand]))
    cl_lga[i] <- cand[which.min(dd)]
  }
}
n_outside <- sum(is.na(cl_lga))
msg("clusters in exactly one LGA: %d | on a shared border (>1 LGA): %d | outside all LGAs: %d",
    sum(!is.na(cl_lga)), multi, n_outside)

# independent containment check: same question asked of the lon/lat geometries with
# s2 spherical topology instead of the projected ones.  If the two disagree, the
# projection is changing the answer and the assignment is not trustworthy.
hit2_ll <- st_intersects(st_geometry(cl), st_geometry(adm2))
same_lga <- vapply(seq_len(nrow(cl_p)), function(i) {
  cand <- hit2_ll[[i]]
  if (length(cand) == 0L) return(is.na(cl_lga[i]))
  if (length(cand) == 1L) return(!is.na(cl_lga[i]) && cand == cl_lga[i])
  !is.na(cl_lga[i]) && cl_lga[i] %in% cand
}, logical(1))
n_contain_disagree <- sum(!same_lga)
msg("containment cross-check lon/lat(s2) vs EPSG:32632: disagreements %d", n_contain_disagree)

## ----------------------------------- 3. distance to assigned boundary, UTM 32N
bnd_p <- st_boundary(st_geometry(adm2_p))
D_bnd <- st_distance(st_geometry(cl_p), bnd_p)          # clusters x 774, metres
D_bnd <- matrix(as.numeric(D_bnd), nrow = nrow(cl_p))

border_m <- rep(NA_real_, nrow(cl_p))
for (i in seq_len(nrow(cl_p))) {
  border_m[i] <- if (is.na(cl_lga[i])) min(D_bnd[i, ]) else D_bnd[i, cl_lga[i]]
}

# nearest LGA (used for the second choice, and for clusters outside everything)
D_lga <- st_distance(st_geometry(cl_p), st_geometry(adm2_p))
D_lga <- matrix(as.numeric(D_lga), nrow = nrow(cl_p))

second    <- rep(NA_integer_, nrow(cl_p))
second_m  <- rep(NA_real_, nrow(cl_p))
for (i in seq_len(nrow(cl_p))) {
  d <- D_lga[i, ]
  if (!is.na(cl_lga[i])) d[cl_lga[i]] <- Inf
  j <- which.min(d)
  second[i]   <- j
  second_m[i] <- d[j]
}
# clusters outside every polygon take the nearest LGA as their only candidate
nearest_lga_for_outside <- second

radius_m <- ifelse(cl$URBAN_RURA == "U", RADIUS_URBAN_M, RADIUS_RURAL_M)
near     <- !is.na(border_m) & border_m <= radius_m
near10   <- !is.na(border_m) & border_m <= ifelse(cl$URBAN_RURA == "U",
                                                  RADIUS_URBAN_M, RADIUS_RURAL_TAIL_M)
msg("near-border (<=2km urban / 5km rural): %d of %d clusters (%.1f%%); rural within 10km: %d",
    sum(near), nrow(cl_p), 100 * sum(near) / nrow(cl_p),
    sum(near10 & cl$URBAN_RURA == "R"))

## --------------------------------------- 4. projection cross-check (geodesic)
set.seed(20261122)
chk <- sample(which(!is.na(cl_lga)), min(200L, sum(!is.na(cl_lga))))
bnd_ll <- st_boundary(st_geometry(adm2))
geo_m  <- vapply(chk, function(i)
  as.numeric(st_distance(st_geometry(cl)[i], bnd_ll[cl_lga[i]])), numeric(1))
diff_m <- abs(geo_m - border_m[chk])
flip   <- sum((geo_m <= radius_m[chk]) != (border_m[chk] <= radius_m[chk]))
msg("UTM32N vs geodesic on %d clusters: median |diff| %.1f m, max %.1f m, near-border flags differing %d",
    length(chk), median(diff_m), max(diff_m), flip)

## --------------------------------------------------------- 5. sensitivity
sens_lga <- cl_lga
move     <- which(near & !is.na(second) & second != cl_lga)
sens_lga[move] <- second[move]
msg("sensitivity: %d clusters reassigned to their second-nearest LGA", length(move))

## --------------------------------------------------------- 6. households
hh_by_cluster <- as.data.frame(table(hh$hv001), stringsAsFactors = FALSE)
names(hh_by_cluster) <- c("DHSCLUST", "n_hh")
hh_by_cluster$DHSCLUST <- as.integer(hh_by_cluster$DHSCLUST)
hh_map <- hh_by_cluster$n_hh[match(cl$DHSCLUST, hh_by_cluster$DHSCLUST)]
if (anyNA(hh_map)) warning("clusters with no households in analysis_households.csv: ", sum(is.na(hh_map)))
hh_map[is.na(hh_map)] <- 0L

## --------------------------------------------------------- 7. cluster_lga.csv
cl_out <- data.frame(
  DHSCLUST        = cl$DHSCLUST,
  hv001           = cl$DHSCLUST,
  LATNUM          = cl$LATNUM,
  LONGNUM         = cl$LONGNUM,
  URBAN_RURA      = cl$URBAN_RURA,
  state_iso       = lga_tbl$state_iso[cl_lga],
  state_name      = lga_tbl$state_name[cl_lga],
  lga_name        = lga_tbl$lga_name[cl_lga],
  lga_id          = lga_tbl$lga_id[cl_lga],
  border_distance_m = round(border_m, 1),
  near_border     = near,
  lga_second_choice = lga_tbl$lga_id[second],
  border_radius_m = as.integer(radius_m),
  stringsAsFactors = FALSE
)
# clusters outside every polygon keep NA geometry fields but are still rows, so
# the join is never silently lossy (the count is in the QC file and in n_outside)
write.csv(cl_out, p_out_cl, row.names = FALSE)

# state agreement with DHS's own ADM1NAME (a check, not an input to the rule)
dhs_state <- cl$ADM1NAME
dhs_state[dhs_state == "Fct"] <- "Abuja Federal Capital Territory"
dhs_state[dhs_state == "Nassarawa"] <- "Nasarawa"
agree <- !is.na(cl_out$state_name) & cl_out$state_name == dhs_state
mismatch_idx <- which(!agree)
msg("cluster state agrees with DHS ADM1NAME: %d of %d; mismatches %d",
    sum(agree), nrow(cl_out), length(mismatch_idx))
if (length(mismatch_idx) > 0) {
  mm <- data.frame(
    DHSCLUST = cl$DHSCLUST[mismatch_idx],
    dhs_adm1 = dhs_state[mismatch_idx],
    assigned_state = cl_out$state_name[mismatch_idx],
    assigned_lga = cl_out$lga_name[mismatch_idx],
    stringsAsFactors = FALSE
  )
  print(utils::head(mm, 20), row.names = FALSE)
}

# what those disagreements cost a state-level rollup:  the LGA's parent state is
# what an LGA-level table rolls up to, and DHS ADM1NAME is what the microdata's
# `geography` column says.  If they differ, summing LGA counts will not exactly
# reproduce the state counts.  Quantified here rather than left implicit.
state_poly <- table(cl_out$state_name)
state_dhs  <- table(dhs_state)
all_st     <- union(names(state_poly), names(state_dhs))
d_poly <- as.integer(state_poly[all_st]); d_poly[is.na(d_poly)] <- 0L
d_dhs  <- as.integer(state_dhs[all_st]);  d_dhs[is.na(d_dhs)]  <- 0L
delta_st <- d_poly - d_dhs
delta_tbl <- data.frame(state_name = all_st[delta_st != 0],
                        n_clusters_polygon = d_poly[delta_st != 0],
                        n_clusters_dhs = d_dhs[delta_st != 0],
                        delta = delta_st[delta_st != 0],
                        stringsAsFactors = FALSE)
if (nrow(delta_tbl)) print(delta_tbl, row.names = FALSE)
msg("state cluster counts: max |polygon - DHS ADM1NAME| = %d, states differing = %d",
    max(abs(delta_st)), sum(delta_st != 0))

## --------------------------------------------------------- 8. lga_coverage.csv
idx_all <- seq_len(nrow(lga_tbl))
ok_cl <- !is.na(cl_lga)
cnt  <- tabulate(cl_lga[ok_cl], nbins = nrow(lga_tbl))
cnts <- tabulate(sens_lga[!is.na(sens_lga)], nbins = nrow(lga_tbl))
hh_by_lga <- as.numeric(tapply(hh_map[ok_cl],
                               factor(cl_lga[ok_cl], levels = idx_all),
                               sum, default = 0))

cov_out <- data.frame(
  lga_id   = lga_tbl$lga_id,
  lga_name = lga_tbl$lga_name,
  state_iso = lga_tbl$state_iso,
  n_clusters = as.integer(cnt),
  n_households = as.integer(round(hh_by_lga)),
  n_clusters_sensitivity = as.integer(cnts),
  stringsAsFactors = FALSE
)
write.csv(cov_out, p_out_cov, row.names = FALSE)

bucket <- function(x) {
  c(`0` = sum(x == 0), `1` = sum(x == 1), `2-4` = sum(x >= 2 & x <= 4), `5+` = sum(x >= 5))
}
b_primary <- bucket(cnt)
b_sens    <- bucket(cnts)

n_zero  <- sum(cnt == 0L)
n_zero_s <- sum(cnts == 0L)
changed <- sum(cnt != cnts)
to0     <- sum(cnt > 0L & cnts == 0L)
from0   <- sum(cnt == 0L & cnts > 0L)
msg("LGAs with 0 clusters: %d of %d (p = %.3f covered); sensitivity %d",
    n_zero, nrow(lga_tbl), 1 - n_zero / nrow(lga_tbl), n_zero_s)
msg("clusters per LGA: 0=%d 1=%d 2-4=%d 5+=%d | sensitivity 0=%d 1=%d 2-4=%d 5+=%d",
    b_primary[1], b_primary[2], b_primary[3], b_primary[4],
    b_sens[1], b_sens[2], b_sens[3], b_sens[4])
msg("LGAs whose cluster count changed under sensitivity: %d (to zero %d, from zero %d)",
    changed, to0, from0)

## --------------------------------------------------------------- 9. QC file
assertions <- list(
  lga_count_is_774            = nrow(adm2_p) == 774L,
  state_count_is_37           = nrow(adm1_p) == 37L,
  cluster_count_is_1380       = nrow(cl_p) == 1380L,
  every_lga_has_one_state     = !anyNA(lga_tbl$state_iso),
  lga_ids_unique              = !anyDuplicated(lga_tbl$lga_id),
  per_state_lga_counts_sum_774 = a_state_counts_sum,
  state_lga_counts_sum_table  = sum(state_lga_counts$n_lga) == 774L,
  all_37_states_receive_lgas  = a_all_states_used,
  clusters_outside_all_lgas_ok = n_outside <= 5L,
  containment_agrees = n_contain_disagree == 0L,
  cluster_ids_unique          = !anyDuplicated(cl_out$DHSCLUST),
  cluster_ids_join_microdata  = all(cl$DHSCLUST %in% hh$hv001),
  hv001_equals_dhsclust       = identical(as.integer(cl_out$DHSCLUST), as.integer(cl_out$hv001)),
  sensitivity_rows_unchanged  = nrow(cl_out) == 1380L,
  no_na_border_distance       = !anyNA(border_m)
)
failed <- names(assertions)[!unlist(assertions)]
msg("assertions: %d of %d passed%s", sum(unlist(assertions)), length(assertions),
    if (length(failed)) paste0("  FAILED: ", paste(failed, collapse = ", ")) else "")

qc <- list(
  generated_by = "scripts/lga_assign.R",
  generated_on = as.character(Sys.Date()),
  inputs = list(
    clusters = list(path = "data/restricted/dhs-2024/ge/NGGE8AFL.shp",
                    n = nrow(cl_p), crs = st_crs(cl)$input,
                    displacement_readme = "data/restricted/dhs-2024/ge/GPS_Displacement_README.txt"),
    adm1 = list(path = "data/public/boundaries/geoBoundaries-NGA-ADM1_simplified.geojson",
                n = nrow(adm1), crs = st_crs(adm1)$input, licence = "CC BY 4.0 (geoBoundaries)"),
    adm2 = list(path = "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson",
                n = nrow(adm2), crs = st_crs(adm2)$input, licence = "CC BY 4.0 (geoBoundaries)"),
    households = list(path = "data/derived/analysis_households.csv", n = nrow(hh))
  ),
  working_crs = "EPSG:32632 (UTM 32N)",
  assignment_rule = list(
    lga_to_state = "representative point (st_point_on_surface) tested against state polygons; not a name join, because Nigerian LGA names repeat across states",
    cluster_to_lga = "points-in-polygon against the 774 ADM2 polygons in EPSG:32632",
    near_border = "distance from cluster to the boundary of its assigned LGA <= the DHS displacement radius for that urban/rural class",
    second_choice = "nearest LGA other than the assigned one, by planar distance in EPSG:32632",
    sensitivity = "all near-border clusters moved to their second-nearest LGA; both assignments shipped"
  ),
  displacement = list(
    radius_urban_m = RADIUS_URBAN_M,
    radius_rural_m = RADIUS_RURAL_M,
    radius_rural_tail_m = RADIUS_RURAL_TAIL_M,
    source = README_SOURCE,
    also_stated = "the displacement is restricted so the displaced point stays inside the same admin0, admin1 and admin2 (LGA) as the true point (same README, lines 5-7); therefore a near-border cluster here is ambiguous because the geoBoundaries LGA edges are not DHS's LGA edges, not because DHS moved the point out of its own LGA"
  ),
  counts = list(
    states = nrow(adm1), lgas = nrow(adm2), clusters = nrow(cl_p),
    households = nrow(hh),
    clusters_in_exactly_one_lga = sum(!is.na(cl_lga)),
    clusters_on_shared_border_tiebroken = multi,
    clusters_outside_all_lgas = n_outside,
    clusters_near_border = sum(near),
    clusters_near_border_pct = round(100 * sum(near) / nrow(cl_p), 2),
    clusters_near_border_urban = sum(near & cl$URBAN_RURA == "U"),
    clusters_near_border_rural = sum(near & cl$URBAN_RURA == "R"),
    rural_clusters_within_10km_of_border = sum(near10 & cl$URBAN_RURA == "R"),
    clusters_reassigned_in_sensitivity = length(move),
    lgas_with_zero_clusters = n_zero,
    lgas_with_zero_clusters_sensitivity = n_zero_s,
    share_lgas_with_data = round(1 - n_zero / nrow(lga_tbl), 4),
    share_lgas_with_data_sensitivity = round(1 - n_zero_s / nrow(lga_tbl), 4),
    lgas_count_changed_under_sensitivity = changed,
    lgas_to_zero_under_sensitivity = to0,
    lgas_from_zero_under_sensitivity = from0
  ),
  clusters_per_lga = list(
    primary = as.list(b_primary),
    sensitivity = as.list(b_sens)
  ),
  assignment_rule_usage = as.list(table(method)),  per_state_lga_counts = setNames(as.list(state_lga_counts$n_lga), state_lga_counts$state_name),
  border_distance_m = list(
    min = round(min(border_m), 1), q1 = round(unname(quantile(border_m, .25)), 1),
    median = round(median(border_m), 1), q3 = round(unname(quantile(border_m, .75)), 1),
    max = round(max(border_m), 1)
  ),
  projection_check = list(
    method = "EPSG:32632 distance vs geodesic (s2) distance to the same boundary, random sample",
    n = length(chk), seed = 20261122L,
    median_abs_diff_m = round(median(diff_m), 2),
    max_abs_diff_m = round(max(diff_m), 2),
    near_border_flags_differing = flip
  ),
  containment_check = list(
    method = "st_intersects on lon/lat with s2 vs on EPSG:32632",
    disagreements = as.integer(n_contain_disagree)
  ),
  cluster_state_vs_dhs_adm1name = list(
    agree = as.integer(sum(agree)), disagree = as.integer(length(mismatch_idx)),
    mismatches = if (length(mismatch_idx)) lapply(seq_along(mismatch_idx), function(k)
      list(DHSCLUST = cl$DHSCLUST[mismatch_idx[k]],
           dhs_adm1 = dhs_state[mismatch_idx[k]],
           assigned_state = cl_out$state_name[mismatch_idx[k]],
           assigned_lga = cl_out$lga_name[mismatch_idx[k]])) else list()
  ),
  state_rollup_conflict = list(
    note = paste0("A cluster's LGA parent state (geoBoundaries) disagrees with DHS's own ",
                  "ADM1NAME for the clusters listed above. LGA counts therefore roll up to ",
                  "slightly different state counts than the microdata's `geography` column. ",
                  "State-level aggregates must use the microdata state variable, not the LGA rollup."),
    max_abs_difference = as.integer(max(abs(delta_st))),
    n_states_differing = as.integer(sum(delta_st != 0)),
    table = if (nrow(delta_tbl)) lapply(seq_len(nrow(delta_tbl)), function(k)
      as.list(delta_tbl[k, ])) else list()
  ),
  assertions = assertions,
  limitations = c(
    "LGA boundaries are geoBoundaries simplified (NGA-ADM2, GRID3 source). They are not DHS's own LGA polygons, so a cluster within the displacement radius of an edge may be in a different LGA than the geoBoundaries edge implies.",
    "DHS displaces every cluster, and restricts displacement to the same LGA. The assignment below therefore uses displaced coordinates; that is unavoidable and is the reason for the sensitivity column.",
    "LGA boundaries are working boundaries for reporting, not a legal or electoral record.",
    "n_households counts households in data/derived/analysis_households.csv, not population. Household weights in the DHS extract are normalised, so absolute population is not recoverable."
  )
)

write(toJSON(qc, auto_unbox = TRUE, pretty = TRUE, digits = 6, null = "null"), p_out_qc)

msg("wrote %s", p_out_cl)
msg("wrote %s", p_out_cov)
msg("wrote %s", p_out_qc)

if (length(failed)) {
  msg("QC FAILED: %s", paste(failed, collapse = ", "))
  quit(save = "no", status = 1)
}
msg("QC passed")
