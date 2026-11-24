# ---------------------------------------------------------------------------
# make_figures.R -- the four manuscript figures, drawn from saved artefacts.
#
#   Rscript scripts/make_figures.R
#
# Inputs (read only, never written):
#   data/derived/lga_estimates.csv        per-LGA posterior summaries + marginals
#   data/derived/count_functional.json    fitted count variance, independence value
#   data/derived/identif_bounds.json      identified interval, observed-only interval
#   data/derived/calibration_exact.json   four_design_curve: coverage + exposure
#
# Outputs: docs/manuscript/figures/fig_{estimates,calibration,identified,feasible}.pdf
#
# No model is fitted, nothing is random, and no number is typed in by hand that
# is not first recomputed from an artefact and asserted below. The PDF Info
# dates are overwritten with a fixed stamp after writing, so two runs give
# byte-identical files.
#
# Palette: Okabe-Ito (colour-blind safe) plus black and neutral greys. Every
# pair that is compared is separated by shape and/or linetype as well as
# colour, so the figures survive greyscale printing.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages(library(jsonlite))

dir_fig <- "docs/manuscript/figures"
dir.create(dir_fig, showWarnings = FALSE, recursive = TRUE)

W    <- 145 / 25.4          # 145 mm, the width the figures are drawn for
PT   <- 9                   # base point size; every cex below keeps text >= 7 pt

COL_OBS   <- "#56B4E9"      # light blue  -- LGA with a sampled cluster
COL_UNOBS <- "#000000"      # black       -- LGA with no sampled cluster
COL_MODEL <- "#0072B2"      # blue        -- fitted model
COL_GREY  <- "#D9D9D9"      # light grey  -- identified set / band
COL_DARK  <- "#333333"      # dark grey   -- observed-only part

# ---- deterministic PDF dates ----------------------------------------------
# cairo and the base pdf device both stamp /CreationDate and /ModDate from the
# clock. Both strings are fixed width ("D:" + 14 digits), so replacing them in
# place leaves every byte offset unchanged.
stamp_pdf_dates <- function(path, stamp = "D:20260101000000") {
  stopifnot(nchar(stamp) == 16L)
  bytes <- readBin(path, what = "raw", n = file.size(path))
  n <- length(bytes)
  for (key in c("CreationDate (D:", "ModDate (D:")) {
    pat  <- charToRaw(key)
    k    <- length(pat)
    cand <- which(bytes[seq_len(n - k + 1L)] == pat[1L])
    for (i in cand) {
      if (i + k - 1L > n) next
      if (all(bytes[i:(i + k - 1L)] == pat)) {
        # the pattern already ends in "D:", so the stamp starts two bytes back
        from <- i + k - 2L
        to   <- from + nchar(stamp) - 1L
        if (to <= n) bytes[from:to] <- charToRaw(stamp)
      }
    }
  }
  writeBin(bytes, path)
}

open_pdf <- function(file, height) {
  pdf(file.path(dir_fig, file), width = W, height = height,
      pointsize = PT, useDingbats = FALSE, bg = "white")
}

close_pdf <- function() {
  dev.off()
  invisible(NULL)
}

# greyscale luminance of a hex colour, printed as a legibility check
lum <- function(hex) {
  v <- col2rgb(hex) / 255
  round(100 * (0.2126 * v[1] + 0.7152 * v[2] + 0.0722 * v[3]), 1)
}

# ===========================================================================
# INPUTS
# ===========================================================================
est <- read.csv("data/derived/lga_estimates.csv", stringsAsFactors = FALSE,
                check.names = FALSE)
cf  <- fromJSON("data/derived/count_functional.json", simplifyVector = FALSE)
ib  <- fromJSON("data/derived/identif_bounds.json",  simplifyVector = FALSE)
ce  <- fromJSON("data/derived/calibration_exact.json", simplifyVector = FALSE)

stopifnot(nrow(est) == 774L)
est$has_cluster <- est$n_clusters > 0L
n_obs <- sum(est$has_cluster); n_unobs <- sum(!est$has_cluster)
stopifnot(n_obs == 654L, n_unobs == 120L)
stopifnot(all(est$ci_low <= est$posterior_mean),
          all(est$posterior_mean <= est$ci_high))

# the marginals, and the sharp bounds they imply (Prop. 2 of the theory annex)
p      <- est$P_exceed_050
S      <- sum(p)
ps     <- sort(p)
f_frac <- S - floor(S)
var_min   <- f_frac * (1 - f_frac)
var_comon <- sum(ps * (2 * (774 - seq_len(774)) + 1)) - S^2
sd_min    <- sqrt(var_min)
sd_comon  <- sqrt(var_comon)
var_ind   <- sum(p * (1 - p))
sd_ind    <- sqrt(var_ind)
var_fit   <- as.numeric(cf$primary$variance_from_the_draws)
sd_fit    <- as.numeric(cf$primary$sd)
pos_fit   <- (var_fit - var_min) / (var_comon - var_min)

# every one of these is already published in results.tex or count_functional.json
stopifnot(abs(S - as.numeric(cf$primary$expectation)) < 1e-6,
          abs(sd_fit - 7.383) < 1e-3,
          abs(sd_ind - 6.345) < 1e-3,
          abs(sd_min - 0.156) < 1e-3,
          abs(sd_comon - 74.11) < 5e-3)

cat(sprintf("marginals  : S = %.3f   n = 774   observed %d / unobserved %d\n",
            S, n_obs, n_unobs))
cat(sprintf("bounds     : Var in [%.4f, %.2f]  ->  sd in [%.4f, %.4f]\n",
            var_min, var_comon, sd_min, sd_comon))
cat(sprintf("values     : independence sd %.4f   fitted sd %.4f   fitted Var %.4f\n",
            sd_ind, sd_fit, var_fit))
cat(sprintf("position   : fitted variance at %.2f%% of the feasible variance range\n",
            100 * pos_fit))
cat(sprintf("greyscale  : observed %s = %.1f%%   unobserved %s = %.1f%%   model %s = %.1f%%\n",
            COL_OBS, lum(COL_OBS), COL_UNOBS, lum(COL_UNOBS),
            COL_MODEL, lum(COL_MODEL)))

# ===========================================================================
# 1. fig:estimates -- 774 areas, sorted by posterior mean, coverage marked
# ===========================================================================
o   <- order(est$posterior_mean)
d   <- est[o, ]
x   <- seq_len(nrow(d))
obs <- d$has_cluster

open_pdf("fig_estimates.pdf", height = 3.5)
par(mar = c(3.6, 4.8, 0.6, 0.6), mgp = c(2.4, 0.55, 0), las = 1,
    cex.axis = 0.95, tcl = -0.25)

plot(NA, xlim = c(0.5, nrow(d) + 0.5), ylim = c(0, 1),
     xlab = "", ylab = "", axes = FALSE)

# intervals: observed areas solid and light, unobserved dashed and black
segments(x[obs],  d$ci_low[obs],  x[obs],  d$ci_high[obs],
         col = COL_OBS, lwd = 0.5, lty = 1)
segments(x[!obs], d$ci_low[!obs], x[!obs], d$ci_high[!obs],
         col = COL_UNOBS, lwd = 0.6, lty = 2)

# crisis line, drawn under the points
abline(h = 0.50, lty = 3, lwd = 0.8, col = "grey35")

points(x[obs],  d$posterior_mean[obs],  pch = 16, cex = 0.30, col = COL_OBS)
points(x[!obs], d$posterior_mean[!obs], pch = 17, cex = 0.42, col = COL_UNOBS)

axis(1, at = c(1, 100, 200, 300, 400, 500, 600, 700, 774), cex.axis = 0.95)
axis(2, at = seq(0, 1, 0.2), cex.axis = 0.95)
box(col = "grey30", lwd = 0.6)

mtext("LGAs ordered by posterior mean", side = 1, line = 2.2, cex = 0.95)
# las = 0 here is not decoration: par(las = 1) above applies to mtext() as
# well, which drew this axis title horizontally so that it ran off the page.
mtext("Posterior mean prevalence", side = 2, line = 2.3, cex = 0.95, las = 0)

# placed at the left, above the line: at the right it sat on top of the
# intervals it is meant to be read against.
text(nrow(d) * 0.015, 0.50 + 0.045, "crisis line, c = 0.50",
     adj = c(0, 0), cex = 0.85, col = "grey25")

legend("topleft",
       legend = c(sprintf("Sampled cluster present (n = %d)", n_obs),
                  sprintf("No sampled cluster (n = %d)", n_unobs)),
       col = c(COL_OBS, COL_UNOBS), lty = c(1, 2), lwd = c(0.9, 0.9),
       pch = c(16, 17), pt.cex = c(0.55, 0.75), seg.len = 1.6,
       bty = "n", cex = 0.85, inset = 0.015)
close_pdf()

# ===========================================================================
# 2. fig:calibration -- four designs, measured against nominal. No line.
# ===========================================================================
cal <- ce$four_design_curve$table
cal <- data.frame(
  design   = vapply(cal, function(z) z$design,   ""),
  exposure = vapply(cal, function(z) z$exposure, 0),
  coverage = vapply(cal, function(z) z$coverage, 0),
  mean_z   = vapply(cal, function(z) z$mean_z,   0),
  sd_z     = vapply(cal, function(z) z$sd_z,     0),
  n        = vapply(cal, function(z) z$n,        0L),
  stringsAsFactors = FALSE)
stopifnot(nrow(cal) == 4L)
cal <- cal[order(cal$exposure), ]           # bottom row = least exposure
stopifnot(max(cal$coverage) < 1.0, all(cal$coverage > 0.7))

# Verdicts are computed from all three pre-declared criteria, not from coverage
# alone.  An earlier version keyed the "fails all three" label off coverage and
# so printed a false statement beside the exact-exposure design, which passes
# the mean check.  Order after sorting is least to most exposure.
fail_mean <- cal$mean_z < -0.15 | cal$mean_z > 0.15
fail_sd   <- cal$sd_z   <  0.85 | cal$sd_z   > 1.15
fail_cov  <- cal$coverage < 0.90 | cal$coverage > 0.98
nfail     <- fail_mean + fail_sd + fail_cov
# must agree with Table tab:calibration in results.tex
stopifnot(identical(as.integer(nfail), c(0L, 2L, 1L, 3L)))

row_lab <- c("Single area,\nneighbours kept",
             "Exact exposure\nof the 120",
             "Matched\nover-exposure",
             "Whole region\nremoved")
fails   <- fail_cov        # symbol shows the coverage verdict only

open_pdf("fig_calibration.pdf", height = 2.6)
par(mar = c(3.6, 7.0, 0.7, 0.7), mgp = c(2.3, 0.55, 0), las = 1,
    cex.axis = 0.95, tcl = -0.25)

plot(NA, xlim = c(0.74, 1.02), ylim = c(0.45, 4.55),
     xlab = "", ylab = "", axes = FALSE)

# pre-declared acceptable band and the nominal line
rect(0.90, 0.45, 0.98, 4.55, col = COL_GREY, border = NA)
segments(c(0.90, 0.98), 0.45, c(0.90, 0.98), 4.55, lty = 3, lwd = 0.7,
         col = "grey30")
segments(0.95, 0.45, 0.95, 4.55, lty = 1, lwd = 1.0, col = "black")

# points: open circle = met the coverage criterion, filled square = failed.
# No segments join them: the text refuses a coverage curve.
y <- seq_len(nrow(cal))
points(cal$coverage[!fails], y[!fails], pch = 1, cex = 1.25, lwd = 1.2,
       col = COL_MODEL)
points(cal$coverage[fails],  y[fails],  pch = 15, cex = 1.05,
       col = "#D55E00")

# exposure beside each point: to the right where the point sits left of the
# band, to the left where it sits inside or right of the band, so that no
# label crosses the nominal line.
lab <- sprintf("exp %.2f", cal$exposure)
lab[nfail > 0] <- sprintf("exp %.2f - fails %d of 3 criteria",
                          cal$exposure[nfail > 0], nfail[nfail > 0])
# labels sit to the left of their point (the free part of the panel) except for
# the whole-region design, which sits too close to the axis to have room there.
right <- cal$coverage < 0.80
text(cal$coverage[right] + 0.008, y[right], lab[right], adj = c(0, 0.5),
     cex = 0.85)
text(cal$coverage[!right] - 0.008, y[!right], lab[!right], adj = c(1, 0.5),
     cex = 0.85)

axis(1, at = seq(0.75, 1.00, 0.05), cex.axis = 0.95)
axis(2, at = y, labels = row_lab, cex.axis = 0.80, tick = FALSE, las = 1)
box(col = "grey30", lwd = 0.6)

mtext("Observed coverage", side = 1, line = 2.2, cex = 0.95)
text(0.95, 4.55, "nominal 0.95", adj = c(0.5, 1.25), cex = 0.85)
text(0.94, 0.45, "pre-declared band 0.90–0.98", adj = c(1, -0.45),
     cex = 0.85, col = "grey25")
close_pdf()

# ===========================================================================
# 3. fig:identified -- what the design allows against what the model claims
# ===========================================================================
id_lo  <- as.numeric(ib$comparison_to_model$identified_interval[[1]])
id_hi  <- as.numeric(ib$comparison_to_model$identified_interval[[2]])
ob_lo  <- as.numeric(ib$estimand_a_count_of_lgas$C_O_quantiles$q025)
ob_hi  <- as.numeric(ib$estimand_a_count_of_lgas$C_O_quantiles$q975)
m_lo   <- as.numeric(cf$primary$quantiles$q025)
m_hi   <- as.numeric(cf$primary$quantiles$q975)
stopifnot(id_lo == 87, id_hi == 231, ob_lo == 87, ob_hi == 111,
          m_lo == 101, m_hi == 130)
gap <- ob_hi - id_lo + 120 - (ob_hi - id_lo)   # the 120 assumed counts

open_pdf("fig_identified.pdf", height = 2.3)
par(mar = c(3.6, 5.9, 0.6, 0.6), mgp = c(2.3, 0.55, 0), las = 1,
    cex.axis = 0.95, tcl = -0.25)

plot(NA, xlim = c(78, 240), ylim = c(0.05, 1.62),
     xlab = "", ylab = "", axes = FALSE)

# identified interval, and inside it the part the observed LGAs pin down
rect(id_lo, 0.87, id_hi, 1.13, col = COL_GREY, border = "grey35", lwd = 0.7)
rect(ob_lo, 0.87, ob_hi, 1.13, col = COL_DARK, border = NA)

# the fitted model's interval
rect(m_lo, 0.20, m_hi, 0.46, col = COL_MODEL, border = "grey20", lwd = 0.7)

# the width contributed by assumption, bracketed in the gap
segments(ob_hi, 1.26, id_hi, 1.26, lwd = 0.8, col = "grey25")
segments(c(ob_hi, id_hi), 1.21, c(ob_hi, id_hi), 1.31, lwd = 0.8, col = "grey25")
text((ob_hi + id_hi) / 2, 1.35,
     "width 120: assumption about the 120 unclustered LGAs",
     adj = c(0.5, 0), cex = 0.80, col = "grey15")

text(id_lo, 1.13, sprintf("%d", id_lo), adj = c(0.5, -0.45), cex = 0.85)
text(id_hi, 1.13, sprintf("%d", id_hi), adj = c(0.5, -0.45), cex = 0.85)
text((m_lo + m_hi) / 2, 0.33, sprintf("%d–%d", m_lo, m_hi),
     adj = c(0.5, 0.5), cex = 0.85, col = "white")

text(84, 0.76, "dark: 87–111, pinned down by the 654 observed LGAs",
     adj = c(0, 0.5), cex = 0.80, col = "grey15")

axis(1, at = seq(80, 240, 20), cex.axis = 0.95)
axis(2, at = c(1.00, 0.33), labels = c("identified set", "fitted model"),
     cex.axis = 0.80, tick = FALSE, las = 1)
box(col = "grey30", lwd = 0.6)

mtext("Number of LGAs above the threshold c = 0.50", side = 1, line = 2.2,
      cex = 0.95)
close_pdf()

# ===========================================================================
# 4. fig:feasible -- where the model sits in what the marginals permit
# ===========================================================================
open_pdf("fig_feasible.pdf", height = 2.3)
par(mar = c(3.6, 2.2, 0.6, 1.0), mgp = c(2.3, 0.55, 0), las = 1,
    cex.axis = 0.95, tcl = -0.25)

plot(NA, xlim = c(0.13, 95), ylim = c(0.45, 1.85), log = "x",
     xlab = "", ylab = "", axes = FALSE, yaxs = "i")

# the feasible range itself
segments(sd_min, 1.0, sd_comon, 1.0, lwd = 6, col = COL_GREY,
         lend = "butt")
segments(c(sd_min, sd_comon), 0.93, c(sd_min, sd_comon), 1.07,
         lwd = 1.0, col = "grey25")

# marks
points(sd_ind, 1.0, pch = 1, cex = 1.3, lwd = 1.2, col = COL_MODEL)
points(sd_fit, 1.0, pch = 17, cex = 1.45, col = "black")

text(sd_min, 0.86, sprintf("%.3f", sd_min), adj = c(0, 1), cex = 0.85)
text(sd_min, 0.74, "lower endpoint\n(cyclic coupling)", adj = c(0, 1),
     cex = 0.80, col = "grey15")

text(sd_ind, 0.86, sprintf("%.3f", sd_ind), adj = c(1.2, 1), cex = 0.85)
text(sd_ind, 0.74, "independence", adj = c(1.2, 1), cex = 0.80, col = "grey15")

text(sd_fit, 1.16, sprintf("%.3f", sd_fit), adj = c(-0.15, 0), cex = 0.85)
text(sd_fit, 1.28, "fitted model", adj = c(-0.15, 0), cex = 0.80,
     col = "grey15")

text(sd_comon, 1.16, sprintf("%.2f", sd_comon), adj = c(1.1, 0), cex = 0.85)
text(sd_comon, 1.28, "upper endpoint\n(comonotone coupling)",
     adj = c(1.1, 0), cex = 0.80, col = "grey15")

text(sd_min * 1.02, 1.62,
     sprintf("fitted Var(C) = %.3f lies %.2f%% of the way up the feasible variance range",
             var_fit, 100 * pos_fit),
     adj = c(0, 0.5), cex = 0.80, col = "grey15")

axis(1, at = c(0.2, 0.5, 1, 2, 5, 10, 20, 50), cex.axis = 0.95)
box(col = "grey30", lwd = 0.6)

mtext("Standard deviation of the count C, log scale", side = 1, line = 2.2,
      cex = 0.95)
close_pdf()

# ---- normalise the PDF dates so that two runs are byte-identical ----------
for (f in c("fig_estimates.pdf", "fig_calibration.pdf",
            "fig_identified.pdf", "fig_feasible.pdf")) {
  stamp_pdf_dates(file.path(dir_fig, f))
}

cat("wrote 4 PDFs to", dir_fig, "\n")
