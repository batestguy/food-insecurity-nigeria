#!/usr/bin/env Rscript
# scripts/lga_model.R -- T10.  Fitted LGA-level model and the count functional.
#
# One command reproduces every number this ticket reports:
#     Rscript scripts/lga_model.R
#
# ============================================================================
# WHAT IS ESTIMATED, AND WHY IT IS THIS
# ============================================================================
# Outcome   severe_fi = 1{hfs_sev >= 0.5}, i.e. all eight FIES items affirmed.
#           Unweighted national rate is reported beside the weighted 0.2910.
#
# Unit      household, y_i ~ Bernoulli(p_i),
#             logit(p_i) = x_i'beta + f(lga_i) + f(cluster_i),
#           f(lga) BYM2 on queen contiguity over the 774 LGA polygons,
#           f(cluster) IID.  The cluster term exists because households inside a
#           DHS cluster are not independent; it is a nuisance term, not a
#           reported quantity.
#
# Covariates the EIGHT variables of data/derived/covariate_spec.md, which expand
#           into TEN design columns (education -> two dummies, age -> quadratic):
#           wealth_z, hh_size, urban, head_male, head_age_c, head_age_c2,
#           head_edu_secondary, head_edu_higher, improved_water,
#           improved_sanitation.  NO geospatial covariate enters this fit.  The
#           135 cluster-level covariates in the file are deliberately unused.
#
# The target, DECLARED BEFORE THE FIT AND NOT CHANGED AFTER SEEING IT
#           theta_s = the prevalence of severe food insecurity in LGA s for a
#           household with the LGA's mean covariate profile:
#
#             theta_s = INT expit( xbar_s'beta + u_s + z ) phi(z; 0, sd_v) dz
#
#           where u_s is the BYM2 spatial effect and the integral marginalises
#           the cluster-level IID effect v ~ N(0, sd_v^2) out of the household
#           probability.  Marginalising v is what makes theta_s a *population*
#           prevalence (the LGA's whole population contains clusters nobody
#           sampled) rather than a prediction for one realised cluster.  The
#           integral is evaluated with a 7-point Gauss-Hermite rule, which is
#           deterministic and adds no Monte Carlo error.
#
#           xbar_s is the mean covariate vector of the households sampled in s.
#           For the 120 LGAs that hold no cluster there are no such households,
#           so xbar_s is set to the mean covariate vector of the parent state's
#           sampled households.  That substitution is a declared choice and is
#           flagged per LGA in the output (`composition_source`); it does not
#           make those LGA estimates data-driven, and it does not pretend to.
#
# Threshold c = 0.50, a majority of households, fixed in advance.  0.40 and 0.60
#           are reported as sensitivity only.
#
# Functional
#           C = #{s : theta_s > c}.  Its posterior comes from the draws directly,
#           with no normal approximation.  Var(C) is decomposed as
#             Var(C) = SUM_s P_s(1-P_s) + SUM_{s!=t} (P_st - P_s P_t)
#           with every probability evaluated under the same draws, so the
#           identity holds exactly and its residual is a numerical check.
#
# Pre-specified secondary comparison (declared here, before running either fit)
#           The same model with f(lga) IID instead of BYM2.  Its purpose is
#           attribution, not model selection: shared uncertainty in beta induces
#           a pairwise term even with no spatial structure at all, so the
#           difference between the two pairwise terms is what the *spatial*
#           prior contributes.  Without this comparison a nonzero pairwise term
#           cannot be attributed to geography.
# ============================================================================

suppressPackageStartupMessages({
  library(sf)
  library(spdep)
  library(INLA)
  library(jsonlite)
})
sf_use_s2(TRUE)

SEED        <- 20261122L
N_DRAWS     <- 20000L
C_PRIMARY   <- 0.50
C_SENS      <- c(0.40, 0.60)
GH_N        <- 7L

root <- normalizePath(".")
p_hh    <- file.path(root, "data/derived/analysis_households_lga.csv")
p_bound <- file.path(root, "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson")
p_pop   <- file.path(root, "data/derived/lga_population.csv")
p_cl    <- file.path(root, "data/derived/cluster_lga_fixed.csv")
p_est   <- file.path(root, "data/derived/lga_estimates.csv")
p_cf    <- file.path(root, "data/derived/count_functional.json")
p_fs    <- file.path(root, "data/derived/lga_fit_summary.json")
p_dr    <- file.path(root, "data/derived/lga_posterior_draws.rds")

for (f in c(p_hh, p_bound, p_pop, p_cl)) {
  if (!file.exists(f)) stop("missing input: ", f, " -- run from the repo root", call. = FALSE)
}

msg <- function(...) cat(sprintf(...), "\n", sep = "")
tick <- function(t0) round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)
sha256 <- function(p) {
  if (!file.exists(p)) return(NA_character_)
  unname(toupper(tools::md5sum(p)))
}

set.seed(SEED)
t_all <- Sys.time()

## ------------------------------------------------------------- 1. the data
COV <- c("wealth_z", "hh_size", "urban", "head_male", "head_age_c", "head_age_c2",
         "head_edu_secondary", "head_edu_higher", "improved_water",
         "improved_sanitation")
NEED <- c("severe_fi", "hv005", "hv001", "geography", "lga_id", "state_iso", COV)

hdr <- scan(p_hh, what = "", sep = ",", nlines = 1L, quote = "\"", quiet = TRUE)
absent <- setdiff(NEED, hdr)
if (length(absent)) stop("missing columns: ", paste(absent, collapse = ", "), call. = FALSE)
cc <- ifelse(hdr %in% NEED, NA_character_, "NULL")
d  <- read.csv(p_hh, colClasses = cc, check.names = FALSE, stringsAsFactors = FALSE)
msg("households: %d | columns kept: %d of %d", nrow(d), length(NEED), length(hdr))

if (anyNA(d$severe_fi)) stop("severe_fi has NA", call. = FALSE)
if (anyNA(d[COV]))      stop("a covariate has NA", call. = FALSE)
if (!all(d$severe_fi %in% c(0, 1))) stop("severe_fi is not 0/1", call. = FALSE)

## ------------------------------------------------------------- 2. the graph
g <- st_make_valid(st_read(p_bound, quiet = TRUE))
if (nrow(g) != 774L) stop("expected 774 LGA polygons, got ", nrow(g), call. = FALSE)
if (anyDuplicated(g$shapeID)) stop("duplicate shapeID", call. = FALSE)

LGA_ID    <- g$shapeID                    # canonical level order, 1..774
LGA_NAME  <- g$shapeName
n_lga     <- length(LGA_ID)

nb <- poly2nb(g, queen = TRUE)
if (length(nb) != n_lga) stop("graph node count != LGA count", call. = FALSE)
deg <- card(nb)
comp <- n.comp.nb(nb)
msg("LGA graph: %d nodes, %d links, %d edges, degree %d-%d (median %d)",
    n_lga, sum(deg), sum(deg) / 2, min(deg), max(deg), median(deg))
msg("LGA graph: %d connected component(s), %d isolate(s)", comp$nc, sum(deg == 0))
if (sum(deg == 0)) stop("graph has isolates; BYM2 is improper there", call. = FALSE)
if (comp$nc != 1L) stop("graph is disconnected (", comp$nc, " components); ",
                        "the brief says stop and report rather than add a constraint silently",
                        call. = FALSE)

nb_path <- file.path(tempdir(), "lga_graph.adj")
nb2INLA(nb_path, nb)
gr <- inla.read.graph(nb_path)
msg("INLA graph: %d nodes, %d edges", gr$n, sum(gr$nnbs) / 2)

## --------------------------------------------------- 3. index and profiles
lga_idx <- match(d$lga_id, LGA_ID)
if (anyNA(lga_idx)) stop("household lga_id not in the boundary file", call. = FALSE)

clu_levels <- sort(unique(d$hv001))
clu_idx <- match(d$hv001, clu_levels)
n_clu   <- length(clu_levels)

pop <- read.csv(p_pop, stringsAsFactors = FALSE)
state_of_lga <- pop$state_iso[match(LGA_ID, pop$lga_id)]
if (anyNA(state_of_lga)) stop("an LGA has no parent state in lga_population.csv", call. = FALSE)
if (!identical(pop$lga_name[match(LGA_ID, pop$lga_id)], LGA_NAME))
  stop("lga_name disagrees between the boundary file and lga_population.csv", call. = FALSE)

X <- as.matrix(d[, COV])
storage.mode(X) <- "double"
y <- as.integer(d$severe_fi)

n_hh_lga  <- as.numeric(tabulate(lga_idx, nbins = n_lga))
n_clu_tab <- table(factor(d$lga_id, levels = LGA_ID))
n_clu_lga <- as.numeric(n_clu_tab)

# mean covariate profile per LGA, and the parent-state fallback
Xbar <- matrix(NA_real_, n_lga, ncol(X), dimnames = list(NULL, COV))
for (k in seq_len(ncol(X))) {
  Xbar[, k] <- as.numeric(tapply(X[, k], factor(lga_idx, levels = seq_len(n_lga)), mean))
}
states <- sort(unique(state_of_lga))
Xbar_state <- matrix(NA_real_, length(states), ncol(X))
for (j in seq_along(states)) {
  in_s <- state_of_lga[lga_idx] == states[j]
  if (any(in_s)) Xbar_state[j, ] <- colMeans(X[in_s, , drop = FALSE])
}
no_data <- which(n_hh_lga == 0L)
for (i in no_data) {
  j <- match(state_of_lga[i], states)
  if (anyNA(Xbar_state[j, ])) stop("parent state of an empty LGA has no households", call. = FALSE)
  Xbar[i, ] <- Xbar_state[j, ]
}
if (anyNA(Xbar)) stop("covariate profile still has NA", call. = FALSE)
composition_source <- ifelse(n_hh_lga > 0L, "lga", "parent_state")
msg("LGAs: %d with households, %d using the parent-state covariate profile", n_lga - length(no_data),
    length(no_data))

# Gauss-Hermite rule for E_{z~N(0,1)}; nodes/weights are the standard 7-point rule,
# divided by sqrt(pi) and rescaled by sqrt(2) so they integrate against N(0,1).
GH_X <- c(-2.651961356835233, -1.673551628767471, -0.8162878828589647, 0,
           0.8162878828589647,  1.673551628767471,  2.651961356835233)
GH_W <- c( 0.0009717812450995192, 0.05451558281912703, 0.4256072526101278,
           0.8102646175568073,   0.4256072526101278,  0.05451558281912703,
           0.0009717812450995192) / sqrt(pi)
stopifnot(GH_N == length(GH_X), GH_N == length(GH_W))
stopifnot(abs(sum(GH_W) - 1) < 1e-14)
stopifnot(abs(sum(GH_W * (sqrt(2) * GH_X)^2) - 1) < 1e-14)

## ------------------------------------------- 4. weighted vs unweighted rates
w <- d$hv005
w_nat <- sum(w * y) / sum(w)
w_unw <- mean(y)
msg("national severe_fi: unweighted %.4f | weighted %.4f | gap %.4f",
    w_unw, w_nat, w_unw - w_nat)

## ------------------------------------------------------------------ 5. fit
dat <- data.frame(y = y, X, lga = lga_idx, clu = clu_idx)
n_obs <- nrow(dat)

# Augmented data: the observed households, then one prediction row per LGA at that LGA's mean
# covariate profile with no response and no cluster. The cluster effect is left as NA so it
# contributes zero, giving eta_s = xbar_s'beta + b_s. The cluster effect is then marginalised
# analytically by Gauss-Hermite below, which is the correct population quantity.
pred_rows <- data.frame(y = NA_real_, Xbar, lga = seq_len(n_lga), clu = NA_integer_)
names(pred_rows) <- names(dat)
dat_aug <- rbind(dat, pred_rows)
form <- as.formula(paste("y ~ 1 +", paste(COV, collapse = " + ")))

fit_primary <- function() {
  inla(
    update(form, . ~ . + f(lga, model = "bym2", graph = gr) + f(clu, model = "iid")),
    family = "binomial", data = dat_aug,
    control.compute = list(waic = TRUE, dic = TRUE, config = TRUE),
    control.predictor = list(compute = TRUE)
  )
}

msg("\nfitting BYM2 ...")
t0 <- Sys.time()
fitS <- fit_primary()
t_fitS <- tick(t0)
mode_status <- if (is.null(fitS$mode$mode.status)) NA_integer_ else fitS$mode$mode.status
msg("BYM2 fit: %.1f s | mode status %s | WAIC %.2f", t_fitS,
    paste(as.character(mode_status), collapse = ","), fitS$waic$waic)

hp <- fitS$summary.hyperpar
msg("hyperparameters (INLA internal scale):")
print(round(hp[, c("mean", "sd", "0.025quant", "0.5quant", "0.975quant")], 4))

## ------------------------------------------- 6. draws and the theta function
extract <- function(fit, tag_lga, tag_clu, n_obs_expected) {
  smp <- inla.posterior.sample(N_DRAWS, fit)
  v1  <- smp[[1]]$latent
  nm  <- if (!is.null(rownames(v1))) rownames(v1) else names(v1)

  # the LGA linear predictor comes from the prediction rows, not from reconstructing the
  # two BYM2 blocks (INLA exposes those separately and their combination is not a plain sum)
  i_pred <- match(paste0("Predictor:", n_obs + seq_len(n_lga)), nm)
  if (anyNA(i_pred)) stop("prediction rows not found in the posterior samples", call. = FALSE)

  M <- N_DRAWS
  ETA <- matrix(NA_real_, M, n_lga)
  SDV <- numeric(M)
  want_prec <- paste0("Precision for ", tag_clu)
  for (m in seq_len(M)) {
    lv <- smp[[m]]$latent
    vv <- if (is.null(dim(lv))) as.numeric(lv) else as.numeric(lv[, 1])
    if (length(vv) != length(nm)) stop("latent length changed between samples", call. = FALSE)
    ETA[m, ] <- vv[i_pred]
    h  <- smp[[m]]$hyperpar
    if (is.null(h)) stop("posterior samples carry no hyperparameters", call. = FALSE)
    k_prec <- which(names(h) == want_prec)
    if (length(k_prec) != 1L) k_prec <- grep(tag_clu, names(h), fixed = TRUE)
    if (length(k_prec) != 1L)
      stop("cannot find the precision of '", tag_clu, "' in the samples: ",
           paste(names(h), collapse = " | "), call. = FALSE)
    SDV[m] <- 1 / sqrt(h[k_prec[1]])
  }
  list(ETA = ETA, SDV = SDV, sample_names = nm, hnames = names(smp[[1]]$hyperpar))
}

msg("\ndrawing %d posterior samples ...", N_DRAWS)
t0 <- Sys.time()
D <- extract(fitS, "lga", "clu", n_clu)
t_draw <- tick(t0)
msg("draws: %.1f s | sd_v posterior mean %.4f | hyperpar names: %s",
    t_draw, mean(D$SDV), paste(D$hnames, collapse = " | "))

# theta_s per draw: the LGA linear predictor from the prediction rows, then the cluster effect
# marginalised by Gauss-Hermite so this is a population prevalence, not a prediction for one cluster.
theta_draws <- function(D, Xbar) {
  M <- nrow(D$ETA)
  TH <- matrix(NA_real_, M, n_lga)
  for (m in seq_len(M)) {
    mu <- D$ETA[m, ]
    acc <- numeric(n_lga)
    for (k in seq_len(GH_N)) {
      acc <- acc + GH_W[k] * plogis(mu + sqrt(2) * D$SDV[m] * GH_X[k])
    }
    TH[m, ] <- acc
  }
  TH
}

t0 <- Sys.time()
TH <- theta_draws(D, Xbar)
t_theta <- tick(t0)
msg("theta draws: %.1f s", t_theta)
if (anyNA(TH) || any(TH < 0) || any(TH > 1)) stop("theta outside [0,1]", call. = FALSE)

## ------------------------------------------- 7. the count functional, one c
count_functional <- function(TH, c) {
  Z  <- TH > c                       # M x n_lga logical
  Cm <- rowSums(Z)
  M  <- nrow(Z)
  P  <- colMeans(Z)                  # P_s
  Pst <- crossprod(Z) / M           # P_st = (1/M) Z'Z, n_lga x n_lga, from the same draws
  Dm  <- Pst - outer(P, P)           # Cov(1{theta_s>c}, 1{theta_t>c})
  var_indep <- sum(P * (1 - P))      # the independent term, SUM_s P_s(1-P_s)
  var_full  <- sum(Dm)               # independent + pairwise, exactly
  var_pair  <- var_full - var_indep  # the pairwise term, SUM_{s!=t}(P_st - P_s P_t)
  var_draws <- var(Cm)
  list(
    c = c, M = M, P = P, Pst = Pst, C = Cm,
    E_C = mean(Cm), sd_C = sd(Cm), median_C = unname(quantile(Cm, 0.5)),
    q025_C = unname(quantile(Cm, 0.025)), q975_C = unname(quantile(Cm, 0.975)),
    q05_C = unname(quantile(Cm, 0.05)), q95_C = unname(quantile(Cm, 0.95)),
    var_indep = var_indep,
    var_pair = var_pair,
    var_from_terms = var_indep + var_pair,
    var_from_draws = var_draws,
    identity_residual = (var_indep + var_pair) - var_draws,
    diag_residual = max(abs(diag(Pst) - P)),
    ratio_pair_to_indep = var_pair / var_indep,
    sd_indep = sqrt(var_indep),
    sd_inflation = sqrt(var_draws / var_indep),
    share_exceed = mean(TH > c)
  )
}

msg("\ncount functional ...")
t0 <- Sys.time()
CF <- count_functional(TH, C_PRIMARY)
CF_sens <- lapply(C_SENS, function(cc) count_functional(TH, cc))
names(CF_sens) <- as.character(C_SENS)
t_cf <- tick(t0)
msg("count functional: %.1f s", t_cf)

## split-half stability of the pairwise term -- is it Monte Carlo noise?
split_half <- function(TH, c) {
  M <- nrow(TH)
  hs <- list(odd = seq(1, M, by = 2), even = seq(2, M, by = 2))
  v <- vapply(hs, function(ii) count_functional(TH[ii, , drop = FALSE], c)$var_pair, numeric(1))
  list(var_pair_half1 = unname(v[1]), var_pair_half2 = unname(v[2]),
       rel_difference = unname(abs(v[1] - v[2]) / ((v[1] + v[2]) / 2)))
}
SH <- split_half(TH, C_PRIMARY)
msg("split-half pairwise variance: %.2f vs %.2f (relative difference %.4f)",
    SH$var_pair_half1, SH$var_pair_half2, SH$rel_difference)

## ------------------------------------------------- 8. per-LGA table, checks
P <- CF$P
# Jensen gap. The reported theta_s averages expit at the LGA's MEAN covariate
# profile. The alternative is the LGA's actual population prevalence, i.e. the
# mean of expit over its own households. Both are evaluated at the posterior mean
# of (beta, u) with the cluster effect marginalised the same way, so the gap is
# purely the within-LGA averaging, not a difference in parameters.
gh_marg <- function(mu, sdv) {
  acc <- numeric(length(mu))
  for (k in seq_len(GH_N)) acc <- acc + GH_W[k] * plogis(mu + sqrt(2) * sdv * GH_X[k])
  acc
}
sdv_hat <- mean(D$SDV)
eta_hat <- colMeans(D$ETA)          # posterior mean linear predictor per LGA, at its mean profile
theta_reported_mean_profile <- gh_marg(eta_hat, sdv_hat)

# direct (unmodelled) LGA proportion, for context only
y_bar <- ifelse(n_hh_lga > 0,
                as.numeric(tapply(y, factor(lga_idx, levels = seq_len(n_lga)), sum)) / n_hh_lga,
                NA_real_)
has <- n_hh_lga > 0

# how determined is each LGA's classification?
sat_hi <- sum(P > 0.95); sat_lo <- sum(P < 0.05)
coin   <- sum(P > 0.40 & P < 0.60)

# spread of the LGA linear predictor, against the sd implied by the BYM2 precision
prec_mean <- hp[grep("lga", rownames(hp), ignore.case = TRUE)[1], "mean"]
sd_implied <- 1 / sqrt(prec_mean)
sd_emp     <- sd(eta_hat)

est <- data.frame(
  lga_id = LGA_ID, lga_name = LGA_NAME, state_iso = state_of_lga,
  n_clusters = n_clu_lga, n_households = n_hh_lga,
  composition_source = composition_source,
  posterior_mean = colMeans(TH),
  posterior_median = apply(TH, 2, median),
  posterior_sd = apply(TH, 2, sd),
  ci_low = apply(TH, 2, function(v) quantile(v, 0.025, names = FALSE)),
  ci_high = apply(TH, 2, function(v) quantile(v, 0.975, names = FALSE)),
  P_exceed_040 = CF_sens[["0.4"]]$P,
  P_exceed_050 = P,
  P_exceed_060 = CF_sens[["0.6"]]$P,
  direct_proportion = y_bar,
  lga_population = pop$population[match(LGA_ID, pop$lga_id)],
  stringsAsFactors = FALSE
)
names(est)[names(est) == "P_exceed_040"] <- "P_exceed_040"
names(est)[names(est) == "P_exceed_040"] <- "P_exceed_040"
write.csv(est, p_est, row.names = FALSE)
msg("\nwrote %s (%d rows)", basename(p_est), nrow(est))

## ------------------------------------------------ 9. secondary: IID LGA fit
msg("\nfitting the IID-LGA comparison ...")
t0 <- Sys.time()
fitI <- inla(
  update(form, . ~ . + f(lga, model = "iid") + f(clu, model = "iid")),
  family = "binomial", data = dat_aug,
  control.compute = list(waic = TRUE, dic = TRUE, config = TRUE),
  control.predictor = list(compute = TRUE)
)
t_fitI <- tick(t0)
msg("IID fit: %.1f s | WAIC %.2f", t_fitI, fitI$waic$waic)

set.seed(SEED + 1L)
DI <- extract(fitI, "lga", "clu", n_clu)
THI <- theta_draws(DI, Xbar)
CFI <- count_functional(THI, C_PRIMARY)
msg("IID: E[C] %.1f | indep %.1f | pair %.1f | ratio %.4f",
    CFI$E_C, CFI$var_indep, CFI$var_pair, CFI$ratio_pair_to_indep)

## ---------------------------------------------------------- 10. write things
q <- function(x, p) unname(quantile(x, p))
ks <- c(100, 150, 200, 250, 300)

cf_block <- function(x) {
  list(
    threshold = x$c,
    n_draws = x$M,
    expectation = x$E_C,
    sd = x$sd_C,
    median = x$median_C,
    quantiles = list(q025 = x$q025_C, q05 = x$q05_C, q50 = x$median_C,
                     q95 = x$q95_C, q975 = x$q975_C),
    variance_independent_term = x$var_indep,
    variance_pairwise_term = x$var_pair,
    variance_from_the_two_terms = x$var_from_terms,
    variance_from_the_draws = x$var_from_draws,
    identity_residual = x$identity_residual,
    ratio_pairwise_to_independent = x$ratio_pair_to_indep,
    independent_variance_sd = x$sd_indep,
    sd_if_lgas_treated_as_independent = x$sd_indep,
    sd_inflation_from_pairwise = x$sd_inflation,
    fraction_of_areas_above_threshold = x$share_exceed,
    P_C_gt = setNames(lapply(ks, function(k) mean(x$C > k)), paste0("k", ks)),
    P_C_ge = setNames(lapply(ks, function(k) mean(x$C >= k)), paste0("k", ks))
  )
}

cf_json <- list(
  generated_by = "scripts/lga_model.R",
  command = "Rscript scripts/lga_model.R",
  ticket = "T10",
  seed = SEED,
  n_draws = N_DRAWS,
  n_areas = n_lga,
  primary_threshold = C_PRIMARY,
  estimand = paste0("C = #{s : theta_s > c}, theta_s the LGA prevalence for a household with ",
                    "the LGA's mean covariate profile, cluster effect marginalised over N(0,sd_v^2)"),
  decomposition = paste0("Var(C) = sum_s P_s(1-P_s) + sum_{s!=t}(P_st - P_s P_t); all three ",
                         "matrices evaluated under the same draws, so the identity is exact ",
                         "and identity_residual is floating-point error"),
  headline = list(
    E_C = CF$E_C, sd_C = CF$sd_C, median_C = CF$median_C,
    variance_independent_term = CF$var_indep,
    variance_pairwise_term = CF$var_pair,
    ratio_pairwise_to_independent = CF$ratio_pair_to_indep,
    sd_if_independent = CF$sd_indep,
    sd_actual = CF$sd_C
  ),
  primary = cf_block(CF),
  threshold_sensitivity = setNames(lapply(seq_along(C_SENS), function(i) cf_block(CF_sens[[i]])),
                                   as.character(C_SENS)),
  monte_carlo = list(
    n_draws = N_DRAWS,
    split_half_pairwise_variance = SH,
    note = paste0("the pairwise term is a sum of ~598k covariances estimated from the same ",
                  "draws; the split-half difference bounds its Monte Carlo noise")
  ),
  determination = list(
    areas_with_P_above_095 = sat_hi,
    areas_with_P_below_005 = sat_lo,
    areas_with_P_between_040_and_060 = coin,
    areas_with_no_cluster = length(no_data),
    areas_using_parent_state_covariate_profile = sum(composition_source == "parent_state")
  ),
  iid_lga_comparison = list(
    purpose = paste0("attribution only: with f(lga) IID the pairwise term can only come from ",
                     "shared beta uncertainty, so the difference from the BYM2 pairwise term ",
                     "is the spatial contribution"),
    waic = fitI$waic$waic, E_C = CFI$E_C, sd_C = CFI$sd_C,
    variance_independent_term = CFI$var_indep,
    variance_pairwise_term = CFI$var_pair,
    ratio_pairwise_to_independent = CFI$ratio_pair_to_indep,
    sd_if_independent = CFI$sd_indep,
    variance_from_the_two_terms = CFI$var_from_terms,
    variance_from_the_draws = CFI$var_from_draws
  )
)
write(toJSON(cf_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null"), p_cf)

fs_json <- list(
  generated_by = "scripts/lga_model.R",
  command = "Rscript scripts/lga_model.R",
  ticket = "T10",
  generated_on = as.character(Sys.Date()),
  seed = SEED,
  r_version = R.version.string,
  inla_version = as.character(inla.version()$version),
  inputs = list(
    households = list(path = "data/derived/analysis_households_lga.csv", n = nrow(d),
                      md5 = sha256(p_hh)),
    boundaries = list(path = "data/public/boundaries/geoBoundaries-NGA-ADM2_simplified.geojson",
                      n = nrow(g), md5 = sha256(p_bound)),
    population = list(path = "data/derived/lga_population.csv", n = nrow(pop), md5 = sha256(p_pop),
                      note = "773 of 774 LGAs carry a population; Bakassi is absent from the source. Not used in the fit."),
    clusters = list(path = "data/derived/cluster_lga_fixed.csv", md5 = sha256(p_cl))
  ),
  model = list(
    outcome = "severe_fi = 1{hfs_sev >= 0.5}, all eight FIES items affirmed",
    formula = paste(deparse(update(form, . ~ . + f(lga, model = "bym2", graph = gr) +
                                     f(clu, model = "iid"))), collapse = " "),
    family = "binomial, single trial per household",
    covariates = COV,
    n_covariates_as_variables = 8L,
    note_covariate_count = paste0("eight variables per data/derived/covariate_spec.md, ten design ",
                                  "columns: head_edu enters as two dummies and head_age as a ",
                                  "quadratic"),
    geospatial_covariates_used = 0L,
    weights_in_likelihood = FALSE,
    cluster_effect = "IID, nuisance, marginalised out of the reported target",
    spatial_effect = "BYM2, queen contiguity over 774 LGA polygons"
  ),
  graph = list(
    method = "spdep::poly2nb(queen = TRUE) on geoBoundaries ADM2 simplified, st_make_valid first",
    nodes = n_lga, links = sum(deg), edges = sum(deg) / 2,
    degree_min = min(deg), degree_median = median(deg), degree_max = max(deg),
    components = comp$nc, isolates = sum(deg == 0),
    constraint_needed = FALSE
  ),
  priors = list(
    source = "INLA 25.10.19 defaults, read from inla.models()$latent$bym2 in this session",
    bym2_precision = "pc.prec(1, 0.01) on log precision: P(sd > 1) = 0.01",
    bym2_phi = "pc(0.5, 0.5) on logit(phi): P(phi < 0.5) = 0.5",
    cluster_precision = "INLA default for model = iid: pc.prec(1, 0.01)",
    fixed_effects = "INLA default: Gaussian, mean 0, precision 0 (flat)"
  ),
  hyperparameters = list(
    table = lapply(rownames(hp), function(rn) list(
      name = rn, mean = hp[rn, "mean"], sd = hp[rn, "sd"],
      q025 = hp[rn, "0.025quant"], q500 = hp[rn, "0.5quant"], q975 = hp[rn, "0.975quant"])),
    sd_implied_by_precision = sd_implied,
    empirical_sd_of_lga_effect = sd_emp,
    scaling_note = paste0("BYM2 assumes the marginal sd equals 1/sqrt(prec) whatever phi is. ",
                          "The empirical sd of the lga draws is the check on that; a large ",
                          "disagreement would mean the ICAR component is not scaled as assumed.")
  ),
  fit = list(
    waic = fitS$waic$waic, waic_p_eff = fitS$waic$p.eff,
    dic = fitS$dic$dic, dic_p_eff = fitS$dic$p.eff,
    mode_status = mode_status,
    n_observations = nrow(d),
    n_clusters = n_clu,
    n_lgas = n_lga
  ),
  timing_seconds = list(
    bym2_fit = t_fitS, posterior_draws = t_draw, theta_draws = t_theta,
    count_functional = t_cf, iid_fit = t_fitI, total = tick(t_all)
  ),
  national_rates = list(
    unweighted = w_unw, weighted = w_nat, gap_unweighted_minus_weighted = w_unw - w_nat,
    weights_used_in_likelihood = FALSE,
    note = paste0("hv005 is carried for reporting only. Every model estimate is unweighted, so ",
                  "the model and the weighted national rate are not on the same footing; the gap ",
                  "is disclosed rather than corrected.")
  ),
  checks = list(
    identity_residual_threshold_050 = CF$identity_residual,
    diagonal_residual_pst_equals_ps = CF$diag_residual,
    split_half_pairwise = SH,
    bym2_scaling = list(precision_mean = prec_mean, sd_implied = sd_implied,
                        empirical_sd_of_lga_linear_predictor = sd_emp,
                        ratio = sd_emp / sd_implied),
    area_classification = list(above_095 = sat_hi, below_005 = sat_lo,
                               between_040_and_060 = coin, n_areas = n_lga),
    correlation_posterior_median_vs_direct = suppressWarnings(
      cor(est$posterior_median[has], est$direct_proportion[has], method = "spearman")),
    covariate_matrix_rank = qr(X)$rank
  )
)
write(toJSON(fs_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null"), p_fs)

saveRDS(list(theta = TH, exceed_050 = TH > C_PRIMARY, P_050 = P, Pst_050 = CF$Pst,
             C_050 = CF$C, lga_id = LGA_ID, seed = SEED, n_draws = N_DRAWS,
             theta_iid = THI, method = "scripts/lga_model.R"),
        p_dr)
msg("wrote %s, %s, %s (%.1f MB), %s (%.1f MB)",
    basename(p_est), basename(p_cf), basename(p_fs),
    file.size(p_fs) / 1024, basename(p_dr), file.size(p_dr) / 1024^2)

## --------------------------------------------------------------- 11. summary
msg("\n================ RESULT ================")
msg("c = %.2f", C_PRIMARY)
msg("E[C] = %.1f   median = %.0f   95%% interval [%.0f, %.0f]   sd = %.2f",
    CF$E_C, CF$median_C, CF$q025_C, CF$q975_C, CF$sd_C)
msg("variance, independent term      : %10.2f   (sd %.2f)", CF$var_indep, CF$sd_indep)
msg("variance, pairwise term         : %10.2f", CF$var_pair)
msg("ratio  pairwise / independent   : %10.4f", CF$ratio_pair_to_indep)
msg("total variance from terms       : %10.2f", CF$var_from_terms)
msg("total variance from the draws   : %10.2f", CF$var_from_draws)
msg("identity residual               : %10.3e", CF$identity_residual)
msg("sd inflation from pairwise      : %10.4f", CF$sd_inflation)
msg("IID-LGA comparison: E[C] %.1f, indep %.2f, pair %.2f, ratio %.4f",
    CFI$E_C, CFI$var_indep, CFI$var_pair, CFI$ratio_pair_to_indep)
msg("total elapsed: %.1f s", tick(t_all))
