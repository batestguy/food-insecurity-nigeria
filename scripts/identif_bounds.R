#!/usr/bin/env Rscript
# scripts/identif_bounds.R  ---  T11
#
# Identification bounds on (a) the count of LGAs above the crisis line and
# (b) the population share living in one, given that 120 of 774 LGAs hold no
# survey cluster at all.
#
# Construction is PRE-DECLARED in .agent/T11-brief.md and implemented as written.
# Proposition applied: P3 of .agent/T5-theory.md (Manski 1990; Manski & Pepper 2000).
#
# Reads:  data/derived/lga_posterior_draws.rds   (joint posterior draws, 20000 x 774)
#         data/derived/lga_estimates.csv         (774 rows, observed/unobserved status)
#         data/derived/lga_population.csv        (774 rows, population denominators)
# Writes: data/derived/identif_bounds.json
#         data/derived/identif_bounds_lga.csv
#
# Run from the repo root:  Rscript scripts/identif_bounds.R

t_start <- Sys.time()

stopifnot(file.exists("data/derived/lga_posterior_draws.rds"),
          file.exists("data/derived/lga_estimates.csv"),
          file.exists("data/derived/lga_population.csv"))

log_lines <- character(0)
say <- function(...) {
  txt <- paste0(...)
  cat(txt, "\n")
  log_lines <<- c(log_lines, txt)
  invisible(NULL)
}
sep <- function() say(strrep("-", 72))

C_LINE  <- 0.50   # crisis line, fixed by the brief
N_Q     <- 0.025  # tail probability for the draws-based interval on the bounds

# ---------------------------------------------------------------- 0. the draws
sep(); say("0. WHAT THE DRAW FILE ACTUALLY CONTAINS"); sep()

draws <- readRDS("data/derived/lga_posterior_draws.rds")
say("class(rds)      : ", paste(class(draws), collapse = ", "))
say("names(rds)      : ", paste(names(draws), collapse = ", "))
for (nm in names(draws)) {
  e <- draws[[nm]]
  d <- if (is.null(dim(e))) "no dim" else paste(dim(e), collapse = " x ")
  say(sprintf("  %-12s class=%-18s dim=%-14s len=%d",
              nm, paste(class(e), collapse = "/"), d, length(e)))
}
say("method string   : ", as.character(draws$method))
say("seed in file    : ", as.character(draws$seed))
say("n_draws in file : ", as.character(draws$n_draws))

theta <- draws$theta          # n_draws x n_areas  (prevalence for the LGA mean profile)
excd  <- draws$exceed_050     # n_draws x n_areas  (should be 1{theta > C_LINE})
stopifnot(is.matrix(theta), is.matrix(excd), nrow(theta) == nrow(excd),
          ncol(theta) == ncol(excd))

n_draws <- nrow(theta)
n_areas <- ncol(theta)
say("using           : ", n_draws, " draws x ", n_areas, " areas (per-LGA prevalence, joint)")

# ------------------------------------------------------- 1. areas, population
sep(); say("1. OBSERVED / UNOBSERVED, POPULATION SHARE p"); sep()

est <- read.csv("data/derived/lga_estimates.csv", stringsAsFactors = FALSE,
                check.names = FALSE)
pop <- read.csv("data/derived/lga_population.csv", stringsAsFactors = FALSE,
                check.names = FALSE)
stopifnot(nrow(est) == n_areas, nrow(pop) == n_areas)

# column alignment: the rds must be in the same order as lga_estimates.csv
if (!identical(as.character(draws$lga_id), as.character(est$lga_id))) {
  say("FAIL: lga_id order in the rds does not match lga_estimates.csv")
  stop("draw column order not aligned with lga_estimates.csv")
}
say("column order    : rds lga_id identical to lga_estimates.csv lga_id  [ok]")

pop_s <- pop$population[match(est$lga_id, pop$lga_id)]
obs   <- !is.na(est$n_clusters) & est$n_clusters >= 1
U     <- !obs
n_obs <- sum(obs)
n_un  <- sum(U)
say("observed LGAs   : ", n_obs, "   unobserved LGAs: ", n_un,
    "   total: ", n_areas)

no_denom <- est$lga_name[is.na(pop_s) | pop_s <= 0]
say("no population denominator (", length(no_denom), "): ",
    paste(no_denom, collapse = ", "))

valid <- !is.na(pop_s) & pop_s > 0
say("LGAs used for p : ", sum(valid), " (both numerator and denominator)")

p_population <- sum(pop_s[valid & obs]) / sum(pop_s[valid])
p_area       <- sum(obs) / n_areas

say(sprintf("p_population    : %.10f   (= %.5f%%)", p_population, 100 * p_population))
say(sprintf("p_area          : %.10f   (= %.5f%%)  [654/774; reported, not used in any bound]",
            p_area, 100 * p_area))
say(sprintf("population total: %.0f", sum(pop_s[valid])))

# ---- CHECK 2 (brief, "Done means") -----------------------------------------
chk2_target <- 0.88963
chk2_diff   <- abs(p_population - chk2_target)
say(sprintf("CHECK 2  p_population = %.10f ; target 0.88963 ; |diff| = %.3e ; tol 1e-5 ; %s",
            p_population, chk2_diff, ifelse(chk2_diff <= 1e-5, "PASS", "FAIL")))
if (chk2_diff > 1e-5) {
  say("STOP: p_population does not reproduce the value recorded in AGENTS.md.")
  stop("p_population does not reproduce 0.88963 to 1e-5")
}

# ------------------------------------------------- 2. consistency of the draws
sep(); say("2. INTERNAL CONSISTENCY OF THE SAVED DRAWS"); sep()

# does exceed_050 equal 1{theta > C_LINE}?
ind <- 1L * (theta > C_LINE)
d_ex <- max(abs(as.numeric(excd) - as.numeric(ind)))
say(sprintf("max |exceed_050 - 1{theta > %.2f}| = %.3e  %s",
            C_LINE, d_ex, ifelse(d_ex == 0, "[exact]", "[recomputed from theta]")))
excd <- ind  # use the recomputed indicator; identical when the file is consistent

# do the draw means reproduce the published posterior_mean?
pm_model <- colMeans(theta)
pm_csv   <- est$posterior_mean
d_pm     <- max(abs(pm_model - pm_csv), na.rm = TRUE)
say(sprintf("max |colMeans(theta) - posterior_mean(csv)| = %.3e", d_pm))

# P_050 in the rds vs the means of the indicator
d_p50 <- max(abs(colMeans(excd) - draws$P_050))
say(sprintf("max |colMeans(exceed_050) - P_050(rds)|   = %.3e", d_p50))

# ---------------------------------------------- 3. estimand (a): count of LGAs
sep(); say("3. ESTIMAND (a)  C = #{s : theta_s > c},  c = 0.50"); sep()

C_all <- rowSums(excd)              # all 774 areas, model's own quantity
C_O   <- rowSums(excd[, obs, drop = FALSE])   # observed LGAs only

mean_C_O <- mean(C_O)

# ---- CHECK 1 (brief, "Done means") -----------------------------------------
sum_P_obs_rds <- sum(draws$P_050[obs])
chk1_diff_rds <- abs(sum_P_obs_rds - mean_C_O)
say(sprintf("CHECK 1  sum_{s in O} P_050(rds) = %.10f ; mean over draws of C_O = %.10f ; |diff| = %.3e ; %s",
            sum_P_obs_rds, mean_C_O, chk1_diff_rds,
            ifelse(chk1_diff_rds <= 1e-6, "PASS", "FAIL")))

sum_P_obs_csv <- sum(est$P_exceed_050[obs])
say(sprintf("CHECK 1b same sum from lga_estimates.csv (rounded to 5 dp) = %.5f ; |diff| = %.3e  [rounding only]",
            sum_P_obs_csv, abs(sum_P_obs_csv - mean_C_O)))

chk_99127 <- abs(mean_C_O - 99.127)
say(sprintf("CHECK 1c mean C_O = %.6f ; target 99.127 ; |diff| = %.3e ; %s",
            mean_C_O, chk_99127, ifelse(chk_99127 <= 1e-3, "PASS", "FAIL")))

if (chk1_diff_rds > 1e-6) {
  say("STOP: the observed-only exceedance sum does not match the draw-level count.")
  stop("check 1 failed")
}
if (chk_99127 > 1e-3) {
  say("STOP: the observed-only exceedance sum does not reproduce 99.127.")
  stop("observed exceedance sum does not reproduce 99.127")
}

say(sprintf("mean C over all 774 areas (model headline) = %.6f  [count_functional: 114.975]",
            mean(C_all)))
say(sprintf("model-implied expected count in the %d unobserved LGAs = %.6f", n_un, mean(C_all) - mean_C_O))
if (abs(draws$C_050[1] - C_all[1]) > 0) {
  say(sprintf("note: file C_050[1] = %s vs recomputed %s", draws$C_050[1], C_all[1]))
}

# per-draw identification bounds: [C_O, C_O + n_un]
lower_C <- C_O
upper_C <- C_O + n_un
qC      <- quantile(C_O, probs = c(N_Q, 0.5, 1 - N_Q), type = 7, names = FALSE)
say(sprintf("C_O across draws: mean %.3f  sd %.3f  min %d  max %d",
            mean_C_O, sd(C_O), min(C_O), max(C_O)))
say(sprintf("C_O quantiles (2.5%%, 50%%, 97.5%%) : %.1f  %.1f  %.1f", qC[1], qC[2], qC[3]))
say(sprintf("identified set per draw : [C_O, C_O + %d]   width %d (assumption, not data)",
            n_un, n_un))
say(sprintf("draws-based interval on the identified set : [%.1f, %.1f]  width %.1f",
            qC[1], qC[3] + n_un, (qC[3] + n_un) - qC[1]))

# ------------------------------- 4. estimand (b): population share in crisis
sep(); say("4. ESTIMAND (b)  population share living in an LGA above the line"); sep()

w_obs  <- pop_s[obs]
w_obs[is.na(w_obs)] <- 0
n_w_na <- sum(is.na(pop_s[obs]))
if (n_w_na > 0) say("WARNING: ", n_w_na, " observed LGAs have no population; weighted as 0")
W_obs <- sum(w_obs)
say(sprintf("observed population (denominator of pi_O) = %.0f  (%.4f%% of national)",
            W_obs, 100 * W_obs / sum(pop_s[valid])))

pi_O <- as.numeric((excd[, obs, drop = FALSE] %*% w_obs) / W_obs)  # per draw
mean_pi_O <- mean(pi_O)

# per-draw Manski bounds: [p*pi_O, p*pi_O + (1-p)]
lower_pi <- p_population * pi_O
upper_pi <- p_population * pi_O + (1 - p_population)
qp <- quantile(pi_O, probs = c(N_Q, 0.5, 1 - N_Q), type = 7, names = FALSE)
say(sprintf("pi_O across draws: mean %.6f (%.4f%%)  sd %.6f  q2.5/50/97.5 = %.6f / %.6f / %.6f",
            mean_pi_O, 100 * mean_pi_O, sd(pi_O), qp[1], qp[2], qp[3]))
say(sprintf("bound width 1 - p = %.6f * 100 = %.4f percentage points", 1 - p_population,
            100 * (1 - p_population)))
say(sprintf("draws-based interval on the identified set : [%.6f, %.6f]  (%.4f%% to %.4f%%)",
            quantile(lower_pi, N_Q, type = 7, names = FALSE),
            quantile(upper_pi, 1 - N_Q, type = 7, names = FALSE),
            100 * quantile(lower_pi, N_Q, type = 7, names = FALSE),
            100 * quantile(upper_pi, 1 - N_Q, type = 7, names = FALSE)))

# ------------------------------- 5. monotonicity variant (labelled, not headline)
sep(); say("5. MONOTONICITY VARIANT (assumption, not the headline)"); sep()

mono_lower <- pi_O
mono_upper <- p_population * pi_O + (1 - p_population)
say(sprintf("ASSMP: pi_U >= pi_O -- unclustered LGAs are assumed no better than observed ones."))
say(sprintf("          This is an assumption about Nigeria that these data cannot test."))
say(sprintf("mean identified set under the assumption : [%.6f, %.6f]  (%.4f%% to %.4f%%)",
            mean(mono_lower), mean(mono_upper), 100 * mean(mono_lower), 100 * mean(mono_upper)))
say(sprintf("draws-based interval (endpoint-wise)     : [%.6f, %.6f]",
            quantile(mono_lower, N_Q, type = 7, names = FALSE),
            quantile(mono_upper, 1 - N_Q, type = 7, names = FALSE)))

# --------------------------------------------------------- 6. comparison block
sep(); say("6. MODEL ANSWER vs IDENTIFIED SET"); sep()

model_E   <- 114.975
model_lo  <- 101
model_hi  <- 130
model_w   <- model_hi - model_lo
id_lo     <- as.numeric(qC[1])
id_hi     <- as.numeric(qC[3]) + n_un
id_w      <- id_hi - id_lo
say(sprintf("model            : E[C] = %.3f, 95%% interval [%d, %d], width %d",
            model_E, model_lo, model_hi, model_w))
say(sprintf("identified (draws): interval [%.1f, %.1f], width %.1f", id_lo, id_hi, id_w))
say(sprintf("of that width, %d LGAs (%.1f%%) is pure assumption about unobserved LGAs",
            n_un, 100 * n_un / id_w))
say(sprintf("model interval inside identified interval : %s",
            ifelse(model_lo >= id_lo && model_hi <= id_hi, "yes", "NO")))
say(sprintf("assumption amplifies the upper bound by a factor of %.2f over the model",
            id_hi / model_hi))

# --------------------------------------------------------------- 7. write out
sep(); say("7. WRITING OUTPUTS"); sep()

# ---- 7a. the 120 unobserved LGAs, sortable evidence ------------------------
out_lga <- data.frame(
  lga_id         = est$lga_id[U],
  lga_name       = est$lga_name[U],
  state_iso      = est$state_iso[U],
  lga_population = pop_s[U],
  posterior_mean = est$posterior_mean[U],
  P_exceed_050   = est$P_exceed_050[U]
)
out_lga <- out_lga[order(-out_lga$P_exceed_050), ]
write.csv(out_lga, "data/derived/identif_bounds_lga.csv", row.names = FALSE)
say("wrote data/derived/identif_bounds_lga.csv : ", nrow(out_lga), " rows")
say(sprintf("  P_exceed_050 among unobserved: min %.4f  median %.4f  max %.4f  sum %.3f",
            min(out_lga$P_exceed_050), median(out_lga$P_exceed_050),
            max(out_lga$P_exceed_050), sum(out_lga$P_exceed_050)))
say(sprintf("  unobserved LGAs with P_exceed_050 > 0.5 : %d of %d",
            sum(out_lga$P_exceed_050 > 0.5), nrow(out_lga)))
say(sprintf("  population held by unobserved LGAs : %.0f  (%.4f%% of national)",
            sum(pop_s[U], na.rm = TRUE), 100 * sum(pop_s[U], na.rm = TRUE) / sum(pop_s[valid])))

# ---- 7b. JSON, no external package -----------------------------------------
to_json <- function(x, indent = 0) {
  sp <- strrep("  ", indent)
  if (is.null(x)) return("null")
  if (is.list(x)) {
    nm <- names(x)
    if (is.null(nm) || all(nm == "")) {
      if (length(x) == 0) return("[]")
      items <- vapply(x, to_json, character(1), indent = indent + 1)
      return(paste0("[\n", paste0(strrep("  ", indent + 1), items, collapse = ",\n"),
                    "\n", sp, "]"))
    }
    if (length(x) == 0) return("{}")
    vals <- mapply(function(v, k) {
      paste0(strrep("  ", indent + 1), '"', k, '": ', to_json(v, indent + 1))
    }, x, nm, SIMPLIFY = TRUE, USE.NAMES = FALSE)
    return(paste0("{\n", paste(vals, collapse = ",\n"), "\n", sp, "}"))
  }
  if (is.character(x)) {
    if (length(x) == 1) return(paste0('"', gsub('"', '\\\\"', x), '"'))
    return(to_json(as.list(x), indent))
  }
  if (is.logical(x)) {
    if (length(x) == 1) {
      if (is.na(x)) return("null")
      return(ifelse(x, "true", "false"))
    }
    return(to_json(as.list(x), indent))
  }
  if (is.numeric(x) || is.integer(x)) {
    fmt1 <- function(v) {
      if (is.na(v)) return("null")
      if (!is.finite(v)) return("null")
      if (v == round(v) && abs(v) < 1e15) return(sprintf("%.0f", v))
      sprintf("%.10g", v)
    }
    if (length(x) == 1) return(fmt1(x))
    return(paste0("[", paste(vapply(x, fmt1, character(1)), collapse = ", "), "]"))
  }
  to_json(as.character(x), indent)
}

res <- list(
  generated_by = "scripts/identif_bounds.R",
  command      = "Rscript scripts/identif_bounds.R",
  ticket       = "T11",
  generated_at = format(t_start, "%Y-%m-%dT%H:%M:%S"),
  r_version    = R.version.string,
  threshold    = C_LINE,
  n_areas      = n_areas,
  n_draws      = n_draws,
  draws_source = list(
    file   = "data/derived/lga_posterior_draws.rds",
    method = as.character(draws$method),
    seed   = as.integer(draws$seed),
    object = "theta: 20000 x 774 matrix of per-LGA prevalence draws, joint across areas",
    note   = paste("joint draws, so the spatial dependence between areas is preserved;",
                   "no independence approximation was needed")
  ),
  quantities = list(
    n_observed       = n_obs,
    n_unobserved     = n_un,
    p_population     = p_population,
    p_area           = p_area,
    n_areas_with_population_denominator = sum(valid),
    lgas_without_denominator = if (length(no_denom) == 0) character(0) else no_denom,
    national_population = sum(pop_s[valid]),
    unobserved_population = sum(pop_s[U], na.rm = TRUE),
    unobserved_population_share = 1 - p_population
  ),
  estimand_a_count_of_lgas = list(
    estimand        = "C = #{s : theta_s > 0.50}, all 774 LGAs",
    construction    = paste("identified set [C_O, C_O + 120] given one realisation of the",
                            "654 observed-LGA statuses, C_O = #{s in O : theta_s > 0.50}"),
    observed_only_estimate = mean_C_O,
    observed_only_sd       = sd(C_O),
    bound_width            = n_un,
    bound_lower_at_mean    = mean(lower_C),
    bound_upper_at_mean    = mean(upper_C),
    lower_bound            = as.numeric(qC[1]),
    upper_bound            = as.numeric(qC[3]) + n_un,
    draws_interval         = c(lower = as.numeric(qC[1]), upper = as.numeric(qC[3]) + n_un),
    interval_on_identified_set = c(lower = as.numeric(qC[1]), upper = as.numeric(qC[3]) + n_un),
    interval_width         = id_w,
    lower_bound_share_of_all_lgas = as.numeric(qC[1]) / n_areas,
    upper_bound_share_of_all_lgas = (as.numeric(qC[3]) + n_un) / n_areas,
    model_implied_count_in_unobserved = mean(C_all) - mean_C_O,
    C_O_quantiles          = list(q025 = as.numeric(qC[1]), q50 = as.numeric(qC[2]),
                                  q975 = as.numeric(qC[3])),
    C_O_range              = c(min = min(C_O), max = max(C_O)),
    assumption_share_of_interval_width = n_un / id_w
  ),
  estimand_b_population_share = list(
    estimand        = "population share living in an LGA with theta > 0.50",
    construction    = paste("Manski bounds [p*pi_O, p*pi_O + (1-p)] at each draw, p the",
                            "population share held by observed LGAs, pi_O the observed-population",
                            "weighted share above the line; no assumption on unobserved LGAs"),
    observed_only_estimate = mean_pi_O,
    bound_width            = 1 - p_population,
    bound_lower_at_mean    = mean(lower_pi),
    bound_upper_at_mean    = mean(upper_pi),
    lower_bound            = as.numeric(quantile(lower_pi, N_Q, type = 7, names = FALSE)),
    upper_bound            = as.numeric(quantile(upper_pi, 1 - N_Q, type = 7, names = FALSE)),
    draws_interval         = c(
      lower = as.numeric(quantile(lower_pi, N_Q, type = 7, names = FALSE)),
      upper = as.numeric(quantile(upper_pi, 1 - N_Q, type = 7, names = FALSE))),
    interval_on_identified_set = c(
      lower = as.numeric(quantile(lower_pi, N_Q, type = 7, names = FALSE)),
      upper = as.numeric(quantile(upper_pi, 1 - N_Q, type = 7, names = FALSE))),
    interval_width         = as.numeric(quantile(upper_pi, 1 - N_Q, type = 7, names = FALSE)) -
                             as.numeric(quantile(lower_pi, N_Q, type = 7, names = FALSE)),
    pi_O_quantiles         = list(q025 = as.numeric(qp[1]), q50 = as.numeric(qp[2]),
                                  q975 = as.numeric(qp[3])),
    pi_O_sd                = sd(pi_O),
    assumption_share_of_interval_width = (1 - p_population) /
      (as.numeric(quantile(upper_pi, 1 - N_Q, type = 7, names = FALSE)) -
       as.numeric(quantile(lower_pi, N_Q, type = 7, names = FALSE)))
  ),
  monotonicity_variant = list(
    status      = "variant, NOT the headline",
    assumption  = paste("unclustered LGAs are assumed no better than observed ones,",
                        "pi_U >= pi_O; this is an assumption about Nigeria that these data",
                        "cannot test"),
    construction = "identified set [pi_O, p*pi_O + (1-p)], width (1-p)(1-pi_O)",
    lower_bound_mean = mean(mono_lower),
    upper_bound_mean = mean(mono_upper),
    lower_bound      = as.numeric(quantile(mono_lower, N_Q, type = 7, names = FALSE)),
    upper_bound      = as.numeric(quantile(mono_upper, 1 - N_Q, type = 7, names = FALSE)),
    interval_width   = as.numeric(quantile(mono_upper, 1 - N_Q, type = 7, names = FALSE)) -
                       as.numeric(quantile(mono_lower, N_Q, type = 7, names = FALSE)),
    mean_width       = mean(mono_upper) - mean(mono_lower)
  ),
  interval_interpretation = list(
    object = "a 95% posterior interval for the sample-analogue identified set",
    is_imbens_manski_confidence_set = FALSE,
    note = paste("This is NOT an Imbens-Manski (2004) confidence set. That object controls",
                 "frequentist coverage of the identified set under moment inequalities for a",
                 "consistent set estimator. What is computed here is the 2.5th percentile of",
                 "the lower bound and the 97.5th percentile of the upper bound across 20,000",
                 "posterior draws. In all three cases reported, both bounds are non-decreasing",
                 "functions of one draw-level quantity (C_O, or pi_O), so the identified set",
                 "lies inside the reported interval exactly when that quantity lies in its own",
                 "central 95% interval: the containment statement carries 95% posterior mass.",
                 "It carries no frequentist coverage guarantee, and it conditions on the model",
                 "for theta in the observed LGAs being right, which is what the paper is",
                 "arguing about; it also treats p as known and the observed/unobserved split",
                 "as exact, so cluster-to-LGA assignment error is not in these bounds.")
  ),
  model_answer = list(
    E_C = model_E, q025 = model_lo, q975 = model_hi,
    sd_C = 7.38300077, width = model_w,
    source = "data/derived/count_functional.json (unchanged, T10)"
  ),
  comparison_to_model = list(
    model_interval            = c(model_lo, model_hi),
    identified_interval       = c(id_lo, id_hi),
    model_interval_width      = model_w,
    identified_interval_width = id_w,
    assumption_width          = n_un,
    assumption_share_of_identified_width = n_un / id_w,
    model_inside_identified   = (model_lo >= id_lo && model_hi <= id_hi),
    upper_bound_ratio_identified_over_model = id_hi / model_hi
  ),
  checks = list(
    check_1_sum_P_equals_mean_C_O = list(value = sum_P_obs_rds, mean_C_O = mean_C_O,
                                         abs_diff = chk1_diff_rds, tol = 1e-6, passed = chk1_diff_rds <= 1e-6),
    check_1c_observed_sum_99_127  = list(value = mean_C_O, target = 99.127,
                                         abs_diff = chk_99127, tol = 1e-3, passed = chk_99127 <= 1e-3),
    check_2_p_population_0_88963  = list(value = p_population, target = chk2_target,
                                         abs_diff = chk2_diff, tol = 1e-5, passed = chk2_diff <= 1e-5),
    check_0_exceed_matches_theta  = list(max_abs_diff = d_ex, passed = (d_ex == 0)),
    check_0_colmeans_match_csv    = list(max_abs_diff = d_pm),
    check_0_P050_matches_means    = list(max_abs_diff = d_p50)
  ),
  console_log = as.list(log_lines)
)

writeLines(to_json(res), "data/derived/identif_bounds.json", useBytes = TRUE)
say("wrote data/derived/identif_bounds.json")

sep()
say("DONE in ", round(as.numeric(difftime(Sys.time(), t_start, units = "secs")), 1), " s")
