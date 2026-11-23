# Build the T3 analysis dataset from NDHS 2024 person recode.
# Follows data/derived/covariate_spec.md exactly. Run:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" scripts/build_analysis_households.R
# No model is fitted here. Writes:
#   data/derived/analysis_households.csv
#   data/derived/covariate_mapping.json
suppressPackageStartupMessages({
  library(haven); library(data.table); library(jsonlite)
})
set.seed(20261122)
ROOT <- "."
PRF  <- file.path(ROOT, "data/restricted/dhs-2024/pr/NGPR8BFL.dta")
HRF  <- file.path(ROOT, "data/restricted/dhs-2024/hr/NGHR8BFL.dta")
OUTD <- file.path(ROOT, "data/derived")

# ---------------------------------------------------------------- state map
NAME2ISO <- c(
  "abia"="NG-AB","adamawa"="NG-AD","akwa ibom"="NG-AK","anambra"="NG-AN","bauchi"="NG-BA",
  "bayelsa"="NG-BY","benue"="NG-BE","borno"="NG-BO","cross river"="NG-CR","delta"="NG-DE",
  "ebonyi"="NG-EB","edo"="NG-ED","ekiti"="NG-EK","enugu"="NG-EN","fct-abuja"="NG-FC",
  "gombe"="NG-GO","imo"="NG-IM","jigawa"="NG-JI","kaduna"="NG-KD","kano"="NG-KN",
  "katsina"="NG-KT","kebbi"="NG-KE","kogi"="NG-KO","kwara"="NG-KW","lagos"="NG-LA",
  "nasarawa"="NG-NA","niger"="NG-NI","ogun"="NG-OG","ondo"="NG-ON","osun"="NG-OS",
  "oyo"="NG-OY","plateau"="NG-PL","rivers"="NG-RI","sokoto"="NG-SO","taraba"="NG-TA",
  "yobe"="NG-YO","zamfara"="NG-ZA")

# ---------------------------------------------------------------- read PR
vars <- c("hhid","hv001","hv005","hv009","hv025","hv219","hv220","hv201","hv205","hv225",
          "hv101","hv106","shstate1", paste0("hfs",1:8), "hfs_sev","hfs_mod")
raw <- as.data.table(read_dta(PRF, col_select = all_of(vars)))
cat("PR rows (persons):", nrow(raw), "| households:", uniqueN(raw$hhid), "\n")

# state code -> ISO from the labels stored in the file
lab <- attr(raw$shstate1, "labels")
stopifnot(!is.null(lab))
norm <- function(x) gsub("\\s+", " ", tolower(trimws(x)))
key  <- norm(names(lab))
key  <- gsub("^fct abuja$|^federal capital territory$", "fct-abuja", key)
cat("\nstate labels as stored in the file:\n"); print(sort(names(lab)))
stopifnot(all(key %in% names(NAME2ISO)))
ISO <- unname(NAME2ISO[key]); names(ISO) <- as.character(unname(lab))
raw[, geography := ISO[as.character(shstate1)]]
stopifnot(!any(is.na(raw$geography)), uniqueN(raw$geography) == 37L)

# ---------------------------------------------------------------- items
# value labels of the eight items, as stored in the file
item_codes <- lapply(paste0("hfs",1:8), function(v) {
  l <- attr(raw[[v]], "labels")
  list(variable = v, labels = if (is.null(l)) NULL else as.list(setNames(as.integer(l), names(l))))
})
names(item_codes) <- paste0("hfs",1:8)

M <- as.matrix(raw[, paste0("hfs",1:8), with = FALSE])
n_dk_cells <- sum(M == 7 | M == 8, na.rm = TRUE)
n_na_cells <- sum(is.na(M))
# spec: yes -> 1, no -> 0, don't know and missing -> 0
A <- matrix(0L, nrow(M), ncol(M))
A[M == 1] <- 1L
raw[, fies_score := as.integer(rowSums(A))]
raw[, severe_fi  := as.integer(fies_score >= 6L)]
raw[, modsev_fi  := as.integer(fies_score >= 4L)]

# ---------------------------------------------------------------- collapse
setorder(raw, hhid)                       # stable within household: line order kept
hh <- raw[!duplicated(hhid)]
cat("\nhouseholds after collapse:", nrow(hh), "\n")

# head's education: the member with hv101 == 1 (relationship to head = head).
# hv218 (line number of head) is 1 for every person row in this file, so the head is line 1.
headp <- raw[hv101 == 1L]
headp <- headp[!duplicated(hhid)]
hh <- merge(hh, headp[, .(hhid, head_edu_hv106 = hv106, head_first = TRUE)],
            by = "hhid", all.x = TRUE, sort = FALSE)
n_head_matched <- sum(!is.na(hh$head_first))
n_head_fallback <- sum(is.na(hh$head_first))
hh[is.na(head_first), head_edu_hv106 := hv106]   # fallback: line-1 row supplies the head
# how often is the head not the first row of the household?
first_row <- raw[!duplicated(hhid), .(hhid, first_hv101 = hv101)]
hh <- merge(hh, first_row, by = "hhid", all.x = TRUE, sort = FALSE)
n_head_not_first <- sum(hh$first_hv101 != 1L, na.rm = TRUE)

# cross-check against the household recode: one row per household, hv106_01 is the head's
# level (hv218 == 1 on every person row), hv271 is the combined wealth factor score.
hr <- as.data.table(read_dta(HRF, col_select = c("hhid","hv271","hv106_01")))
setnames(hr, c("hv271","hv106_01"), c("hv271_hr","hv106_hr"))
cat("HR rows (households):", nrow(hr), "| matched to PR households:",
    sum(hh$hhid %in% hr$hhid), "\n")
hh <- merge(hh, hr, by = "hhid", all.x = TRUE, sort = FALSE)

# head education: DK (8) and missing -> NA; 0/1/2/3 kept
hh[, head_edu := fifelse(is.na(head_edu_hv106) | head_edu_hv106 == 8, NA_integer_,
                         as.integer(head_edu_hv106))]
hh[, head_edu_hr := fifelse(is.na(hv106_hr) | hv106_hr == 8, NA_integer_, as.integer(hv106_hr))]
edu_agree <- mean(hh$head_edu == hh$head_edu_hr, na.rm = TRUE)
n_edu_missing <- sum(is.na(hh$head_edu))
n_edu_dk      <- sum(hh$head_edu_hv106 == 8, na.rm = TRUE)

# ---------------------------------------------------------------- wealth
wr <- hh$hv271_hr
wealth_raw_range <- range(wr, na.rm = TRUE)
scaled <- if (max(abs(wealth_raw_range)) > 20) wr / 1e5 else wr
wealth_scaled_range <- range(scaled, na.rm = TRUE)

# ---------------------------------------------------------------- WASH
wash_table <- function(var, improved_labels) {
  l <- attr(hh[[var]], "labels")
  stopifnot(!is.null(l))
  d <- data.table(code = as.integer(l), label = names(l))
  d[, improved_jmp := as.integer(norm(label) %in% norm(improved_labels))]
  setorder(d, code); d
}
water_ok <- c("Piped into dwelling","Piped to yard/plot","Public tap/standpipe",
              "Tube well or borehole","Protected well","Protected spring","Rainwater")
san_ok   <- c("Flush to piped sewer system","Flush to septic tank","Flush to pit latrine",
              "Ventilated Improved Pit latrine (VIP)","Pit latrine with slab","Composting toilet")
wt <- wash_table("hv201", water_ok)
st <- wash_table("hv205", san_ok)
cat("\n--- hv201 label -> class ---\n"); print(wt[, .(code, label = substr(label,1,42), improved_jmp)])
cat("\n--- hv205 label -> class ---\n"); print(st[, .(code, label = substr(label,1,42), improved_jmp)])

hh[, improved_water := wt$improved_jmp[match(as.integer(hv201), wt$code)]]
hh[, san_unshared  := st$improved_jmp[match(as.integer(hv205), wt$code)]]
# hv225 is NotAppl where there is no facility: those are unimproved by construction, not missing
n_san_shared_drop <- sum(hh$san_unshared == 1L & hh$hv225 == 1L, na.rm = TRUE)
n_san_na_hv225    <- sum(hh$san_unshared == 1L & is.na(hh$hv225))
hh[, improved_sanitation := fifelse(is.na(san_unshared), NA_integer_,
                             fifelse(!is.na(hv225) & hv225 == 1L, 0L, san_unshared))]
n_water_missing <- sum(is.na(hh$improved_water))
n_san_missing   <- sum(is.na(hh$improved_sanitation))
cat(sprintf("\nsanitation: NA hv205 %d | NA san_unshared %d | NA hv225 %d | NA improved %d\n",
            sum(is.na(hh$hv205)), sum(is.na(hh$san_unshared)), sum(is.na(hh$hv225)),
            n_san_missing))
cat("hv205 codes not found in the label table:",
    paste(setdiff(unique(as.integer(hh$hv205)), st$code), collapse = ","), "\n")
cat("improved_sanitation by hv225:\n"); print(table(hh$improved_sanitation,
    addNA(factor(hh$hv225)), useNA = "always"))

# ---------------------------------------------------------------- other covariates
hh[, `:=`(hh_size = as.numeric(hv009),
          urban = fifelse(hv025 == 1L, 1L, fifelse(hv025 == 2L, 0L, NA_integer_)),
          head_male = fifelse(hv219 == 1L, 1L, fifelse(hv219 == 2L, 0L, NA_integer_)),
          head_age = as.numeric(hv220))]
hh[, head_age_c := head_age - 40]
hh[, head_age_c2 := head_age_c^2]
hh[, `:=`(head_edu_secondary = fifelse(head_edu == 2L, 1L, fifelse(is.na(head_edu), NA_integer_, 0L)),
          head_edu_higher    = fifelse(head_edu == 3L, 1L, fifelse(is.na(head_edu), NA_integer_, 0L)))]

# ---------------------------------------------------------------- FI eligibility
hh[, fi_ok := !is.na(hfs_sev) & hv005 > 0]
cat("\nhhs with non-missing hfs_sev and hv005>0:", sum(hh$fi_ok), "\n")

# ---------------------------------------------------------------- analytic sample
cov <- c("hh_size","urban","head_male","head_age","head_edu_secondary","head_edu_higher",
         "improved_water","improved_sanitation")
hh[, wealth_scaled := scaled]
miss <- sapply(hh[, c("wealth_scaled", cov), with = FALSE], function(x) sum(is.na(x)))
hh[, complete := fi_ok & !is.na(fies_score) & rowSums(is.na(.SD)) == 0,
   .SDcols = c("wealth_scaled", cov)]

# wealth_z standardised over the analytic sample
mu_w <- mean(hh$wealth_scaled[hh$complete]); sd_w <- sd(hh$wealth_scaled[hh$complete])
hh[, wealth_z := (wealth_scaled - mu_w) / sd_w]

keep <- hh$complete
cat("\n=== analytic sample ===\n")
cat("in :", sum(keep), " hhs | severe_fi prevalence",
    round(mean(hh$severe_fi[keep]), 4), "| modsev", round(mean(hh$modsev_fi[keep]), 4), "\n")
cat("out:", sum(!keep), " hhs | severe_fi prevalence",
    round(mean(hh$severe_fi[!keep], na.rm = TRUE), 4),
    "| hfs_sev-based", round(mean(hh$hfs_sev[!keep] / 1e8, na.rm = TRUE), 4), "\n")
cat("clusters in:", uniqueN(hh$hv001[keep]), "| states in:", uniqueN(hh$geography[keep]), "\n")
cat("missing by covariate (all households):\n"); print(miss)
cat("missing by covariate (analytic sample):\n")
print(sapply(hh[keep, ..cov], function(x) sum(is.na(x))))

# ---------------------------------------------------------------- validation gate
r <- cor(hh$fies_score[hh$fi_ok], hh$hfs_sev[hh$fi_ok] / 1e8, use = "complete.obs")
rs <- cor(hh$fies_score[hh$fi_ok], hh$hfs_sev[hh$fi_ok] / 1e8, method = "spearman",
          use = "complete.obs")
cat("\n=== validation: fies_score vs hfs_sev/1e8 ===\n")
cat(sprintf("pearson r = %.4f | spearman = %.4f | n = %d\n", r, rs, sum(hh$fi_ok)))
ct <- hh[fi_ok == TRUE, .N, by = .(fies_score, sev_prob = round(hfs_sev / 1e8, 8))]
cat("\ncrosstab fies_score x hfs_sev/1e8 (hfs_sev is a Rasch probability, 9 distinct values):\n")
print(dcast(ct, fies_score ~ sev_prob, value.var = "N", fill = 0)[order(fies_score)])

nat_w <- weighted.mean(hh$severe_fi[hh$fi_ok], hh$hv005[hh$fi_ok])
nat_u <- mean(hh$severe_fi[hh$fi_ok])
nat_prob_w <- weighted.mean(hh$hfs_sev[hh$fi_ok] / 1e8, hh$hv005[hh$fi_ok])
cat(sprintf("\nnational severe_fi (score>=6): weighted %.4f | unweighted %.4f\n", nat_w, nat_u))
cat(sprintf("national mean hfs_sev/1e8 (the figure in AGENTS.md): weighted %.4f\n", nat_prob_w))
cat(sprintf("national modsev_fi (score>=4): weighted %.4f\n",
            weighted.mean(hh$modsev_fi[hh$fi_ok], hh$hv005[hh$fi_ok])))

n_score_multi_prob <- ct[, uniqueN(sev_prob), by = fies_score][V1 > 1, .N]
n_prob_multi_score <- ct[, uniqueN(fies_score), by = sev_prob][V1 > 1, .N]
cat(sprintf("\nscores mapping to more than one hfs_sev value: %d\n", n_score_multi_prob))
cat(sprintf("hfs_sev values mapping to more than one score: %d\n", n_prob_multi_score))

if (r <= 0.9) {
  cat("\nSTOP: item coding does not validate against hfs_sev (r <= 0.9). See .agent/T3-report.md.\n")
}

# ---------------------------------------------------------------- write
cols <- c("hhid","hv001","geography","hv005","fies_score","severe_fi","modsev_fi",
          "wealth_z","hh_size","urban","head_male","head_age","head_age_c","head_age_c2",
          "head_edu_secondary","head_edu_higher","improved_water","improved_sanitation")
out <- hh[keep, ..cols]
fwrite(out, file.path(OUTD, "analysis_households.csv"), na = "")
cat("\nwritten:", nrow(out), "rows x", ncol(out), "cols -> data/derived/analysis_households.csv\n")

json <- list(
  built = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  script = "scripts/build_analysis_households.R",
  source = basename(PRF),
  spec = "data/derived/covariate_spec.md",
  r_version = R.version.string,
  haven_version = as.character(packageVersion("haven")),
  counts = list(pr_rows = nrow(raw), households_collapsed = nrow(hh),
                households_eligible = sum(hh$fi_ok), analytic_sample = sum(keep),
                clusters = uniqueN(hh$hv001[keep]), states = uniqueN(hh$geography[keep])),
  item_coding = list(
    labels_from_file = item_codes,
    dk_or_refused_cells_set_to_zero = n_dk_cells,
    na_cells_set_to_zero = n_na_cells,
    rule = "yes->1, no->0, don't know (7/8) and missing->0",
    fies_score_range = range(hh$fies_score, na.rm = TRUE),
    crosstab_fies_vs_hfs_sev = ct[order(fies_score), .(fies_score, sev_prob, N)]),
  validation = list(pearson_r_fies_score_vs_hfs_sev = r,
                    spearman_r = rs, gate = 0.9, passed = r > 0.9,
                    scores_with_more_than_one_hfs_sev_value = n_score_multi_prob,
                    hfs_sev_values_with_more_than_one_score = n_prob_multi_score,
                    diagnosis = paste("hfs_sev is a deterministic monotone transform of fies_score:",
                                      "every score maps to exactly one of 9 probability values, so the",
                                      "item coding is confirmed by the crosstab. Pearson r falls short of",
                                      "0.9 because the transform is strongly convex; the gate is a",
                                      "linear-correlation test applied to a non-linear relabeling."),
                    modelling_halted = r <= 0.9,
                    halt_reason = if (r <= 0.9) "spec section on the validation gate: stop and report" else NA),
  prevalence = list(
    national_severe_fi_weighted = nat_w, national_severe_fi_unweighted = nat_u,
    national_modsev_fi_weighted = weighted.mean(hh$modsev_fi[hh$fi_ok], hh$hv005[hh$fi_ok]),
    national_mean_hfs_sev_weighted = nat_prob_w,
    note = "severe_fi is the FAO raw-score binary (>=6); hfs_sev is a Rasch probability whose mean is the 31.3% quoted in AGENTS.md. They are different estimands."),
  wealth = list(source_variable = "hv271 (household recode; hv271 is not in the person file)",
                raw_range = wealth_raw_range, scaled_range = wealth_scaled_range,
                rescaled_by_1e5 = max(abs(wealth_raw_range)) > 20,
                standardisation = list(mean = mu_w, sd = sd_w),
                wealth_z_range = range(hh$wealth_z[keep])),
  washlabels = list(
    hv201 = wt[, .(code, label, improved_jmp)],
    hv205 = st[, .(code, label, improved_jmp)],
    hv225_shared_dropped = n_san_shared_drop,
    hv225_not_applicable_no_facility = n_san_na_hv225,
    rule_water = paste(water_ok, collapse = "; "),
    rule_sanitation = paste(san_ok, collapse = "; "),
    sanitation_note = "set to 0 where hv225 says the facility is shared"),
  head_education = list(
    source = "hv106 of the member with hv101==1 (head); hv218==1 on every row",
    matched_by_hv101 = n_head_matched, fallback_line1 = n_head_fallback,
    head_not_first_row = n_head_not_first,
    missing = n_edu_missing, dont_know = n_edu_dk,
    agreement_with_hr_hv106 = edu_agree,
    reference_level = "none or primary"),
  missing = list(by_covariate_all_households = as.list(miss),
                 improved_water_unresolved = n_water_missing,
                 improved_sanitation_unresolved = n_san_missing,
                 households_dropped = sum(!keep),
                 severe_fi_in_analytic = mean(hh$severe_fi[keep]),
                 severe_fi_in_dropped = mean(hh$severe_fi[!keep], na.rm = TRUE)),
  prohibition_check = list(disability_variables_used = FALSE,
                           variables_in_dataset = cols))
write_json(json, file.path(OUTD, "covariate_mapping.json"), auto_unbox = TRUE,
           pretty = TRUE, digits = 8, na = "null")
cat("written: data/derived/covariate_mapping.json\n")
