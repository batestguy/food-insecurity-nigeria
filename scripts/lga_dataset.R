#!/usr/bin/env Rscript
# scripts/lga_dataset.R -- T9.  Build the LGA-level analysis dataset.
#
# Run from the repo root:   Rscript scripts/lga_dataset.R
#
# Reads (never writes) the T8 assignment and the DHS inputs; writes:
#   data/derived/cluster_lga_fixed.csv
#   data/derived/lga_population.csv
#   data/derived/analysis_households_lga.csv
#   data/derived/lga_dataset_qc.json
#
# The two decisions this script implements, stated once and used everywhere:
#
#   A. State authority.  Where the LGA polygon's parent state (T8, by representative
#      point) disagrees with the state the survey records for that cluster, the SURVEY
#      state wins and the cluster is moved to the nearest LGA *inside that state*.
#      Reason: data/restricted/dhs-2024/ge/GPS_Displacement_README.txt lines 5-7 say
#      the displaced point stays inside the same admin0/admin1/admin2 area, so DHS
#      guarantees the cluster is in its own LGA and our simplified geoBoundaries
#      polygon -- not the survey -- is the weaker link.
#
#   B. Population, not area.  The identified-set width 1-p is about people, so `p`
#      is a population share.  Denominators are the COD-PS LGA totals (NBS/UNFPA
#      projected from the 2006 census, reference year 2020), joined by name inside
#      state, one-to-one, with every fuzzy match printed for audit.  Nothing is
#      apportioned, interpolated or invented: an LGA with no row in the source keeps
#      NA and is reported.

suppressPackageStartupMessages({
  library(sf)
  library(jsonlite)
  library(readxl)
  library(stringdist)
})
sf_use_s2(TRUE)

root <- normalizePath(".")

p_in_adm1 <- file.path(root, "data/public/boundaries/geoBoundaries-NGA-ADM1_simplified.geojson")
p_in_adm2 <- file.path(root, "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson")
p_in_cl   <- file.path(root, "data/restricted/dhs-2024/ge/NGGE8AFL.shp")
p_in_cov  <- file.path(root, "data/restricted/dhs-2024/ge/NGGC8AFL.csv")
p_in_covd <- file.path(root, "data/restricted/dhs-2024/ge/DHS Covariates Extract Data Description_3.pdf")
p_in_hh   <- file.path(root, "data/derived/analysis_households.csv")
p_in_t8cl <- file.path(root, "data/derived/cluster_lga.csv")
p_in_t8co <- file.path(root, "data/derived/lga_coverage.csv")
p_pop     <- file.path(root, "data/derived/raw_pop/nga_admpop_2020.xlsx")
p_pop_gz  <- file.path(root, "data/derived/raw_pop/nga_admgz.xlsx")

p_out_cl  <- file.path(root, "data/derived/cluster_lga_fixed.csv")
p_out_pop <- file.path(root, "data/derived/lga_population.csv")
p_out_hh  <- file.path(root, "data/derived/analysis_households_lga.csv")
p_out_qc  <- file.path(root, "data/derived/lga_dataset_qc.json")

for (f in c(p_in_adm1, p_in_adm2, p_in_cl, p_in_cov, p_in_hh, p_in_t8cl,
            p_in_t8co, p_pop)) {
  if (!file.exists(f)) stop("missing input: ", f, " -- run from the repo root", call. = FALSE)
}

WORK_CRS        <- 32632L   # UTM 32N, same as T8
RADIUS_URBAN_M  <- 2000L
RADIUS_RURAL_M  <- 5000L
POP_YEAR        <- 2020L
POP_SOURCE      <- "HDX cod-ps-nga, nga_admpop_2020.xlsx sheet nga_admpop_adm2_2020 (COD-PS: NBS/UNFPA, projected from the 2006 census; reference year 2020)"
POP_URL         <- "https://data.humdata.org/dataset/a7c3de5e-ff27-4746-99cd-05f2ad9b1066/resource/3597a93e-3b1d-4d06-ad2c-109c84a951b6/download/nga_admpop_2020.xlsx"
FUZZY_MAX       <- 0.30     # Jaro-Winkler distance ceiling for a name match

msg <- function(...) cat(sprintf(...), "\n", sep = "")
sha <- function(p) if (file.exists(p)) unname(toupper(tools::md5sum(p))) else NA_character_

## ---------------------------------------------------------------- read inputs
adm1 <- st_make_valid(st_read(p_in_adm1, quiet = TRUE))
adm2 <- st_make_valid(st_read(p_in_adm2, quiet = TRUE))
cl   <- st_read(p_in_cl, quiet = TRUE)
hh   <- read.csv(p_in_hh, stringsAsFactors = FALSE, colClasses = c(hhid = "character"))
t8cl <- read.csv(p_in_t8cl, stringsAsFactors = FALSE)
t8co <- read.csv(p_in_t8co, stringsAsFactors = FALSE)
cov  <- read.csv(p_in_cov, stringsAsFactors = FALSE, check.names = TRUE,
                 na.strings = c("", "NA", "NaN"))

adm2_p <- st_transform(adm2, WORK_CRS)
cl_p   <- st_transform(cl,   WORK_CRS)

msg("ADM1 %d | ADM2 %d | clusters %d | households %d | covariate cols %d",
    nrow(adm1), nrow(adm2), nrow(cl), nrow(hh), ncol(cov))

## LGA -> state map: T8's geometry-derived table is the input, re-checked here.
lga_tbl <- data.frame(
  lga_id    = adm2_p$shapeID,
  lga_name  = adm2_p$shapeName,
  state_iso = t8co$state_iso[match(adm2_p$shapeID, t8co$lga_id)],
  stringsAsFactors = FALSE
)
if (anyNA(lga_tbl$state_iso)) stop("LGA with no parent state in lga_coverage.csv", call. = FALSE)
adm1_iso <- setNames(adm1$shapeISO, adm1$shapeName)

## --------------------------------------------------- survey state per cluster
# The microdata's own state.  One state per cluster, asserted.
st_by_cl <- tapply(hh$geography, hh$hv001, function(x) length(unique(x)))
if (any(st_by_cl != 1L)) stop("a cluster spans more than one survey state", call. = FALSE)
survey_state <- tapply(hh$geography, hh$hv001, `[`, 1)
geo_by_cl <- as.character(survey_state[match(cl$DHSCLUST, names(survey_state))])
if (anyNA(geo_by_cl)) stop("cluster with no households, so no survey state", call. = FALSE)

t8_idx <- match(cl$DHSCLUST, t8cl$DHSCLUST)
if (anyNA(t8_idx)) stop("cluster missing from cluster_lga.csv", call. = FALSE)
t8_lga_id    <- t8cl$lga_id[t8_idx]
t8_state_iso <- t8cl$state_iso[t8_idx]

mismatch <- which(t8_state_iso != geo_by_cl)
msg("clusters whose polygon state differs from the survey state: %d of %d",
    length(mismatch), nrow(cl))

## ------------------------------------- distances: clusters x LGAs, UTM 32N (m)
D_lga <- matrix(as.numeric(st_distance(st_geometry(cl_p), st_geometry(adm2_p))),
                nrow = nrow(cl_p))
radius_m <- ifelse(cl$URBAN_RURA == "U", RADIUS_URBAN_M, RADIUS_RURAL_M)

# nearest LGA within the survey state, for the mismatched clusters only
new_lga <- t8_lga_id
new_border_m <- as.numeric(t8cl$border_distance_m[t8_idx])
for (i in mismatch) {
  cand <- which(lga_tbl$state_iso == geo_by_cl[i])
  if (!length(cand)) stop("survey state with no LGA in the boundary file", call. = FALSE)
  j <- cand[which.min(D_lga[i, cand])]
  new_lga[i] <- lga_tbl$lga_id[j]
  g <- st_geometry(adm2_p)[j]
  new_border_m[i] <- as.numeric(st_distance(st_geometry(cl_p)[i], st_boundary(g)))
}

# distance to the LGA finally chosen (0 when the point is inside it), and the
# second choice among all LGAs -- same definition T8 used.
final_dist_m <- numeric(nrow(cl_p))
second_id <- rep(NA_character_, nrow(cl_p))
second_dist_m <- rep(NA_real_, nrow(cl_p))
for (i in seq_len(nrow(cl_p))) {
  j <- match(new_lga[i], lga_tbl$lga_id)
  final_dist_m[i] <- D_lga[i, j]
  d <- D_lga[i, ]
  d[j] <- Inf
  k <- which.min(d)
  second_id[i]     <- lga_tbl$lga_id[k]
  second_dist_m[i] <- d[k]
}

reassigned <- new_lga != t8_lga_id
near_border <- new_border_m <= radius_m

## ------------------------------------------------------------- output: clusters
cl_out <- data.frame(
  DHSCLUST             = cl$DHSCLUST,
  hv001                = as.integer(cl$DHSCLUST),
  LATNUM               = cl$LATNUM,
  LONGNUM              = cl$LONGNUM,
  URBAN_RURA           = cl$URBAN_RURA,
  survey_state_iso     = geo_by_cl,
  polygon_state_iso    = t8_state_iso,
  state_iso            = lga_tbl$state_iso[match(new_lga, lga_tbl$lga_id)],
  lga_id               = new_lga,
  lga_name             = lga_tbl$lga_name[match(new_lga, lga_tbl$lga_id)],
  reassigned           = reassigned,
  previous_lga_id      = t8_lga_id,
  previous_lga_name    = lga_tbl$lga_name[match(t8_lga_id, lga_tbl$lga_id)],
  distance_to_lga_m    = round(final_dist_m, 1),
  border_distance_m    = round(new_border_m, 1),
  border_radius_m      = as.integer(radius_m),
  near_border          = near_border,
  second_choice_lga_id = second_id,
  second_choice_lga_name = lga_tbl$lga_name[match(second_id, lga_tbl$lga_id)],
  second_choice_distance_m = round(second_dist_m, 1),
  stringsAsFactors = FALSE
)
write.csv(cl_out, p_out_cl, row.names = FALSE)
msg("wrote %s (%d rows, %d reassigned)", basename(p_out_cl), nrow(cl_out), sum(reassigned))
if (any(cl_out$state_iso != geo_by_cl))
  stop("correction left a cluster outside its survey state", call. = FALSE)

## ------------------------------------------------------------------ population
pop_raw  <- as.data.frame(read_excel(p_pop, sheet = "nga_admpop_adm2_2020"))
pop_cod  <- as.data.frame(read_excel(p_pop, sheet = "Admin2"))
pop_raw$ADM1_NAME <- toupper(trimws(pop_raw$ADM1_NAME))
pop_raw$T_TL <- as.numeric(pop_raw$T_TL)

state_lookup <- setNames(names(adm1_iso), toupper(names(adm1_iso)))
state_lookup["FEDERAL CAPITAL TERRITORY"] <- "Abuja Federal Capital Territory"
pop_raw$state_name <- unname(state_lookup[pop_raw$ADM1_NAME])
pop_raw$state_iso  <- unname(adm1_iso[pop_raw$state_name])
if (anyNA(pop_raw$state_iso)) stop("population state name not resolved to an ISO code", call. = FALSE)

norm_name <- function(x) {
  x <- toupper(iconv(as.character(x), to = "ASCII//TRANSLIT", sub = ""))
  x <- gsub("&", " AND ", x)
  x <- gsub("[^A-Z0-9]+", " ", x)
  x <- gsub("\\bLGA\\b", " ", x)
  x <- gsub("[[:space:]]+", " ", x)
  trimws(x)
}
# Documented renames, not guesses: geoBoundaries carries the current LGA name and
# the COD-PS carries the earlier one.  Yewa is the present name of the LGAs NBS
# still lists as Egbado (Ogun State); the pair is one-to-one by direction.
ALIAS <- list(
  `EGBADO NORTH` = "YEWA NORTH",
  `EGBADO SOUTH` = "YEWA SOUTH"
)

pop_names <- lapply(seq_len(nrow(pop_raw)), function(k) {
  nm <- norm_name(pop_raw$ADM2_NAME[k])
  alt <- ALIAS[[nm]]
  unique(c(nm, if (is.null(alt)) character(0) else norm_name(alt)))
})

lga_norm <- norm_name(lga_tbl$lga_name)
lga_norm[grepl("^ABUJA MUNICIPAL", lga_norm)] <- "ABUJA MUNICIPAL"
pop_names <- lapply(pop_names, function(v) gsub("^ABUJA MUNICIPAL.*", "ABUJA MUNICIPAL", v))

match_pop <- rep(NA_integer_, nrow(lga_tbl))   # lga_tbl row -> pop_raw row
match_type <- rep(NA_character_, nrow(lga_tbl))
match_dist <- rep(NA_real_, nrow(lga_tbl))

for (st in unique(lga_tbl$state_iso)) {
  gi <- which(lga_tbl$state_iso == st)
  pj <- which(pop_raw$state_iso  == st)
  if (!length(pj)) next
  cost <- matrix(Inf, length(gi), length(pj))
  for (a in seq_along(gi)) for (b in seq_along(pj)) {
    cost[a, b] <- min(stringdist(lga_norm[gi[a]], pop_names[[pj[b]]], method = "jw"))
  }
  # exact (normalised) equality first, then cheapest remaining pair, one-to-one
  taken <- rep(FALSE, length(pj))
  for (a in seq_along(gi)) {
    b <- which(cost[a, ] == 0 & !taken)
    if (length(b) >= 1L) {
      match_pop[gi[a]] <- pj[b[1]]; match_type[gi[a]] <- "exact"
      match_dist[gi[a]] <- 0; taken[b[1]] <- TRUE
    }
  }
  for (a in order(apply(cost, 1, min))) {
    if (!is.na(match_pop[gi[a]])) next
    b <- which(!taken)[which.min(cost[a, !taken])]
    if (!length(b)) next
    if (cost[a, b] <= FUZZY_MAX) {
      match_pop[gi[a]] <- pj[b]; match_type[gi[a]] <- "fuzzy"
      match_dist[gi[a]] <- cost[a, b]; taken[b] <- TRUE
    }
  }
  # sole remaining pair in a state: unambiguous even when the spellings share nothing
  left_g <- gi[is.na(match_pop[gi])]
  left_p <- pj[!taken]
  if (length(left_g) == 1L && length(left_p) == 1L) {
    match_pop[left_g] <- left_p; match_type[left_g] <- "sole_remaining"
    match_dist[left_g] <- min(cost[match(left_g, gi), match(left_p, pj)])
  }
}

lga_pop <- data.frame(
  lga_id          = lga_tbl$lga_id,
  lga_name        = lga_tbl$lga_name,
  state_iso       = lga_tbl$state_iso,
  population      = ifelse(is.na(match_pop), NA_real_, pop_raw$T_TL[match_pop]),
  population_year = POP_YEAR,
  source          = "HDX cod-ps-nga nga_admpop_2020.xlsx (COD-PS NBS/UNFPA, projected from the 2006 census)",
  nbs_lga_name    = ifelse(is.na(match_pop), NA_character_, pop_raw$ADM2_NAME[match_pop]),
  nbs_pcode       = ifelse(is.na(match_pop), NA_character_, pop_raw$ADM2_PCODE[match_pop]),
  match_type      = match_type,
  name_distance   = round(match_dist, 4),
  stringsAsFactors = FALSE
)
write.csv(lga_pop, p_out_pop, row.names = FALSE)

n_exact <- sum(match_type == "exact", na.rm = TRUE)
n_fuzzy <- sum(match_type == "fuzzy", na.rm = TRUE)
n_sole  <- sum(match_type == "sole_remaining", na.rm = TRUE)
n_unmatched <- sum(is.na(match_pop))
msg("population join: %d of %d LGAs matched (exact %d, fuzzy %d, sole_remaining %d); unmatched %d",
    sum(!is.na(match_pop)), nrow(lga_tbl), n_exact, n_fuzzy, n_sole, n_unmatched)
if (n_unmatched) msg("  unmatched LGAs: %s",
                     paste(sprintf("%s (%s)", lga_tbl$lga_name[is.na(match_pop)],
                                   lga_tbl$state_iso[is.na(match_pop)]), collapse = ", "))
fz <- which(match_type == "fuzzy")
if (length(fz)) {
  msg("  fuzzy pairs (geoBoundaries -> COD-PS, Jaro-Winkler distance):")
  for (i in fz) msg("    %-28s -> %-28s  d=%.3f", lga_tbl$lga_name[i],
                    pop_raw$ADM2_NAME[match_pop[i]], match_dist[i])
}
pop_total <- sum(lga_pop$population, na.rm = TRUE)
msg("population total across matched LGAs: %.0f", pop_total)

# Does the workbook's own state-level sheet include the LGA that has no row?  It
# does not: its national total equals the sum of the 773 LGA rows exactly, so the
# missing LGA is absent from the source's totals as well and cannot be recovered by
# subtraction.  Recorded here because it decides how the missing LGA is described.
pop_adm1 <- as.data.frame(read_excel(p_pop, sheet = "nga_admpop_adm1_2020"))
pop_adm1 <- pop_adm1[!is.na(pop_adm1$ADM1_NAME), ]
pop_adm1_total <- sum(as.numeric(pop_adm1$T_TL), na.rm = TRUE)
msg("workbook state-level total: %.0f over %d states (difference from the LGA sum: %.0f)",
    pop_adm1_total, nrow(pop_adm1), pop_adm1_total - pop_total)

## ------------------------------------------------------------- household merge
idx_cl <- match(hh$hv001, cl_out$hv001)
if (anyNA(idx_cl)) stop("household with an hv001 not in the cluster table", call. = FALSE)
if (anyDuplicated(cl_out$hv001)) stop("cluster table has duplicate hv001", call. = FALSE)
n_lga_per_cl <- tapply(idx_cl, hh$hv001, function(x) length(unique(cl_out$lga_id[x])))
if (any(n_lga_per_cl != 1L)) stop("a cluster maps to more than one LGA", call. = FALSE)

idx_pop <- match(cl_out$lga_id, lga_pop$lga_id)
hh_out <- hh
hh_out$lga_id         <- cl_out$lga_id[idx_cl]
hh_out$lga_name       <- cl_out$lga_name[idx_cl]
hh_out$state_iso      <- cl_out$state_iso[idx_cl]
hh_out$lga_population <- lga_pop$population[idx_pop[idx_cl]]
if (anyNA(hh_out$lga_id)) stop("household with no lga_id after the join", call. = FALSE)

## ------------------------------------------------------- attach covariates
if (!"DHSCLUST" %in% names(cov)) stop("covariate file has no DHSCLUST column", call. = FALSE)
idx_cov <- match(hh$hv001, cov$DHSCLUST)
if (anyNA(idx_cov)) stop("cluster missing from the covariate file", call. = FALSE)
cov_cols <- setdiff(names(cov), "DHSCLUST")
cov_block <- cov[idx_cov, cov_cols, drop = FALSE]
hh_out <- cbind(hh_out, cov_block)

write.csv(hh_out, p_out_hh, row.names = FALSE)
msg("wrote %s (%d rows, %d cols, %.1f MB)", basename(p_out_hh), nrow(hh_out), ncol(hh_out),
    file.size(p_out_hh) / 1024^2)

## -------------------------------------------- covariate structure, per column
n_lga_with_ge2 <- sum(table(cl_out$lga_id) >= 2)
cov_qc <- lapply(cov_cols, function(nm) {
  x <- cov[[nm]]
  g <- cl_out$lga_id
  # per-LGA variation, over the 1380 clusters
  varies <- tapply(x, factor(g, levels = lga_tbl$lga_id), function(v) {
    v <- v[!is.na(v)]
    if (length(v) < 2L) return(0L)
    as.integer(length(unique(v)) > 1L)
  })
  # variance decomposition only for numeric columns; the extract also carries
  # identifiers and a few text fields, which have no sum of squares
  if (is.numeric(x)) {
    mu <- suppressWarnings(mean(x, na.rm = TRUE))
    ss_tot <- sum((x - mu)^2, na.rm = TRUE)
    lm_ <- suppressWarnings(tapply(x, factor(g, levels = lga_tbl$lga_id), mean, na.rm = TRUE))
    ln_ <- as.numeric(tapply(!is.na(x), factor(g, levels = lga_tbl$lga_id), sum))
    ss_bet <- if (isTRUE(ss_tot > 0)) sum(ln_ * (lm_ - mu)^2, na.rm = TRUE) else 0
    var_share <- if (isTRUE(ss_tot > 0)) round(ss_bet / ss_tot, 6) else NA_real_
  } else {
    var_share <- NA_real_
  }
  list(column = nm,
       class = class(x)[1],
       n_missing = sum(is.na(x)),
       pct_missing = round(100 * mean(is.na(x)), 2),
       n_distinct = length(unique(x[!is.na(x)])),
       n_lga_varying = sum(varies == 1L, na.rm = TRUE),
       constant_within_lga = sum(varies == 1L, na.rm = TRUE) == 0L,
       between_lga_var_share = var_share)
})

## ------------------------------------------------- shares, before and after
count_before <- as.integer(t8co$n_clusters)
count_after  <- as.integer(tabulate(match(cl_out$lga_id, lga_tbl$lga_id), nbins = nrow(lga_tbl)))
pop_by_lga   <- lga_pop$population
known_pop    <- !is.na(pop_by_lga)

share_rows <- function(cnt, label) {
  zero <- cnt == 0L
  list(assignment = label,
       lgas_zero_cluster = sum(zero),
       lgas_with_data = sum(!zero),
       count_share_with_data = round(mean(!zero), 6),
       count_share_no_cluster = round(mean(zero), 6),
       population_in_zero_cluster_lgas = sum(pop_by_lga[zero & known_pop]),
       population_known_total = sum(pop_by_lga[known_pop]),
       population_share_no_cluster = round(sum(pop_by_lga[zero & known_pop]) /
                                             sum(pop_by_lga[known_pop]), 6),
       lgas_zero_without_population = sum(zero & !known_pop),
       households_in_zero_cluster_lgas = sum(t8co$n_households[cnt == 0L]))
}
before <- share_rows(count_before, "T8 geometry assignment (before correction)")
after  <- share_rows(count_after,  "survey-state correction (after)")
msg("zero-cluster LGAs: %d before -> %d after", before$lgas_zero_cluster, after$lgas_zero_cluster)
msg("population share living in zero-cluster LGAs: %.4f before -> %.4f after",
    before$population_share_no_cluster, after$population_share_no_cluster)

lga_gain <- lga_tbl$lga_name[count_after > count_before]
lga_lose <- lga_tbl$lga_name[count_after < count_before]
to_zero  <- sum(count_before > 0L & count_after == 0L)
from_zero <- sum(count_before == 0L & count_after > 0L)

## ------------------------------------------------------------------ QC file
dup_names_changed <- sum(names(cov) != make.names(names(cov), unique = TRUE))

assertions <- list(
  clusters_is_1380                = nrow(cl_out) == 1380L,
  lgas_is_774                     = nrow(lga_tbl) == 774L,
  every_cluster_in_survey_state   = all(cl_out$state_iso == cl_out$survey_state_iso),
  every_cluster_has_lga           = !anyNA(cl_out$lga_id),
  cluster_ids_unique              = !anyDuplicated(cl_out$DHSCLUST),
  households_rows_unchanged       = nrow(hh_out) == nrow(hh),
  every_household_has_one_lga     = !anyNA(hh_out$lga_id),
  cluster_maps_to_one_lga         = all(n_lga_per_cl == 1L),
  lga_population_ids_unique       = !anyDuplicated(lga_pop$lga_id),
  population_matched_ge_770       = sum(!is.na(lga_pop$population)) >= 770L,
  population_within_plausible_range = pop_total > 1.8e8 && pop_total < 2.4e8,
  population_never_zero           = all(is.na(lga_pop$population) | lga_pop$population > 0),
  covariates_all_retained         = all(cov_cols %in% names(hh_out)),
  covariate_names_unchanged       = dup_names_changed == 0L,
  reassignment_small              = sum(reassigned) <= 50L
)
failed <- names(assertions)[!unlist(assertions)]
msg("assertions: %d of %d passed%s", sum(unlist(assertions)), length(assertions),
    if (length(failed)) paste0("  FAILED: ", paste(failed, collapse = ", ")) else "")

qc <- list(
  generated_by = "scripts/lga_dataset.R",
  generated_on = as.character(Sys.Date()),
  command = "Rscript scripts/lga_dataset.R",
  ticket = "T9",
  inputs = list(
    clusters = list(path = "data/restricted/dhs-2024/ge/NGGE8AFL.shp", n = nrow(cl)),
    households = list(path = "data/derived/analysis_households.csv", n = nrow(hh)),
    t8_cluster_assignment = list(path = "data/derived/cluster_lga.csv", n = nrow(t8cl),
                                 note = "T8 output, used as the baseline; never modified"),
    t8_coverage = list(path = "data/derived/lga_coverage.csv", n = nrow(t8co)),
    boundaries = list(
      adm1 = "data/public/boundaries/geoBoundaries-NGA-ADM1_simplified.geojson",
      adm2 = "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson",
      licence = "CC BY 4.0 (geoBoundaries)")
  ),
  state_correction = list(
    rule = paste0("where the polygon parent state differs from the survey's own state ",
                  "(microdata `geography`), the survey state is kept and the cluster is moved ",
                  "to the nearest LGA inside that state, by planar distance in EPSG:32632"),
    authority = paste0("data/restricted/dhs-2024/ge/GPS_Displacement_README.txt lines 5-7: ",
                       "displacement keeps the point inside the same admin0/admin1/admin2 area, ",
                       "so DHS guarantees the cluster's LGA and the simplified polygon is the ",
                       "weaker link"),
    clusters_state_disagreeing = length(mismatch),
    clusters_moved = sum(reassigned),
    moved = lapply(which(reassigned), function(i) list(
      DHSCLUST = cl_out$DHSCLUST[i],
      survey_state = cl_out$survey_state_iso[i],
      polygon_state = cl_out$polygon_state_iso[i],
      previous_lga = cl_out$previous_lga_name[i],
      new_lga = cl_out$lga_name[i],
      distance_to_new_lga_m = cl_out$distance_to_lga_m[i],
      second_choice_lga = cl_out$second_choice_lga_name[i],
      second_choice_distance_m = cl_out$second_choice_distance_m[i]
    )),
    lgas_gaining_clusters = lga_gain,
    lgas_losing_clusters = lga_lose,
    lgas_to_zero_clusters = to_zero,
    lgas_from_zero_clusters = from_zero,
    lgas_whose_count_changed = sum(count_before != count_after)
  ),
  population = list(
    status = if (n_unmatched == 0L) "complete" else "matched, with gaps",
    source = POP_SOURCE,
    source_url = POP_URL,
    source_retrieved = "2026-11-22",
    source_file = "data/derived/raw_pop/nga_admpop_2020.xlsx",
    source_md5 = sha(p_pop),
    source_bytes = file.size(p_pop),
    reference_year = POP_YEAR,
    gazetteer_downloaded_not_used = list(
      path = "data/derived/raw_pop/nga_admgz.xlsx", md5 = sha(p_pop_gz),
      reason = "downloaded while locating the dataset; the workbook's own Admin2 sheet carries the pcodes, so the gazetteer was not needed"),
    lgas_in_source = nrow(pop_raw),
    lgas_matched_exact = n_exact,
    lgas_matched_fuzzy = n_fuzzy,
    lgas_matched_sole_remaining = n_sole,
    lgas_unmatched = n_unmatched,
    unmatched_lgas = as.list(lga_tbl$lga_name[is.na(match_pop)]),
    unmatched_lgas_states = as.list(lga_tbl$state_iso[is.na(match_pop)]),
    fuzzy_matches = lapply(fz, function(i) list(
      lga_name = lga_tbl$lga_name[i], nbs_name = pop_raw$ADM2_NAME[match_pop[i]],
      jw_distance = round(match_dist[i], 4))),
    alias_rules = list("YEWA NORTH = EGBADO NORTH (Ogun)", "YEWA SOUTH = EGBADO SOUTH (Ogun)",
                       "ABUJA MUNICIPAL * = MUNICIPAL AREA COUNCIL (FCT)"),
    population_total_matched_lgas = pop_total,
    population_total_workbook_state_sheet = pop_adm1_total,
    population_total_states_sheet_equals_lga_sum = abs(pop_adm1_total - pop_total) < 1,
    population_total_all_lgas_if_complete_note = paste0(
      "the source workbook has ", nrow(pop_raw), " LGA rows for a 774-LGA country; the missing ",
      "LGA is ", paste(lga_tbl$lga_name[is.na(match_pop)], collapse = ", "),
      ", whose population is absent rather than apportioned. Its absence is not recoverable by ",
      "subtraction: the workbook's own state-level sheet totals ", format(pop_adm1_total, big.mark = ","),
      " persons, equal to the sum of the ", nrow(pop_raw), " LGA rows, so ", 
      paste(lga_tbl$lga_name[is.na(match_pop)], collapse = ", "),
      " is excluded from the source's national total as well"),
    n_households_with_null_population = sum(is.na(hh_out$lga_population)),
    n_lgas_with_null_population = n_unmatched,
    method = paste0("normalised exact name match inside state, then one-to-one greedy ",
                    "Jaro-Winkler within state (ceiling ", FUZZY_MAX, "), then the sole ",
                    "remaining pair in a state; no area apportionment, no interpolation")
  ),
  identification_shares = list(
    note = paste0("p is a POPULATION share: the identified-set width 1-p is about people. ",
                  "Both denominators are the 773 LGAs with a population figure."),
    before_correction = before,
    after_correction = after,
    population_share_caveat = paste0(
      "LGAs with no population figure are excluded from both numerator and denominator. ",
      sum(before$lgas_zero_without_population), " zero-cluster LGA(s) before and ",
      sum(after$lgas_zero_without_population), " after have no figure, so the population ",
      "share is a lower bound; the largest it could rise by is that LGA's share of the total, ",
      "which is at most the largest LGA population in the file (",
      format(round(max(lga_pop$population, na.rm = TRUE))), " people, ",
      sprintf("%.2f%%", 100 * max(lga_pop$population, na.rm = TRUE) / pop_total), " of the total)"),
    area_share_for_comparison = "the count share is the area share and is what T8 reported (123/774)"
  ),
  counts = list(
    zero_cluster_lgas_before = before$lgas_zero_cluster,
    zero_cluster_lgas_after = after$lgas_zero_cluster,
    buckets_before = as.list(table(cut(count_before, c(-1, 0, 1, 4, Inf),
                                       labels = c("0", "1", "2-4", "5+")))),
    buckets_after = as.list(table(cut(count_after, c(-1, 0, 1, 4, Inf),
                                      labels = c("0", "1", "2-4", "5+")))),
    reached_123_baseline = before$lgas_zero_cluster == 123L
  ),
  merge_checks = list(
    households = nrow(hh_out),
    clusters = nrow(cl_out),
    lgas = nrow(lga_tbl),
    household_lga_join = "one row per household, one lga_id each, asserted",
    cluster_to_lga_one_to_one = TRUE,
    covariate_columns = length(cov_cols),
    covariate_columns_renamed_by_read = dup_names_changed
  ),
  covariates = list(
    n_columns = length(cov_cols),
    n_lga_with_two_or_more_clusters = n_lga_with_ge2,
    n_columns_constant_within_every_lga = sum(vapply(cov_qc, `[[`, logical(1), "constant_within_lga")),
    n_columns_with_any_missing = sum(vapply(cov_qc, function(z) z$n_missing > 0, logical(1))),
    n_columns_fully_missing = sum(vapply(cov_qc, function(z) z$n_missing == nrow(cov), logical(1))),
    definition = paste0("constant_within_lga: for every LGA with two or more clusters, the ",
                        "column takes a single value; between_lga_var_share: between-LGA sum of ",
                        "squares over total sum of squares, computed on the ", nrow(cov), " clusters"),
    table = cov_qc
  ),
  assertions = assertions,
  limitations = c(
    "LGA boundaries are geoBoundaries simplified (GRID3 source), not DHS's own admin2 layer, so a cluster near an edge may belong to a different LGA than the polygon implies. The second-choice columns quantify that.",
    "The population is a 2020 projection from the 2006 census. No LGA-level 2024 figure is published on HDX: the current COD-PS release carries ADM0-ADM1 only (2022). Shares therefore rest on 2020 LGA weights.",
    "One LGA (see unmatched_LGAs) has no row in the source workbook and keeps NA. Its population is not estimated.",
    "These are working boundaries and projected denominators for reporting, not a legal or census record."
  )
)
write(toJSON(qc, auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null"), p_out_qc)
msg("wrote %s", basename(p_out_qc))

if (length(failed)) {
  msg("QC FAILED: %s", paste(failed, collapse = ", "))
  quit(save = "no", status = 1)
}
msg("QC passed")
