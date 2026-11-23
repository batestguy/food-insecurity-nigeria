# Global Moran's I for severe food insecurity at state level, on the project's own adjacency graph.
suppressPackageStartupMessages({ library(spdep) })

fi <- read.csv("data/derived/fi_state_direct.csv", stringsAsFactors = FALSE)
nb <- read.csv("data/derived/neighbours.csv", stringsAsFactors = FALSE)
ids <- sort(unique(nb$geography))
nb_list <- lapply(ids, function(g) as.integer(which(ids %in% nb$neighbour[nb$geography == g])))
class(nb_list) <- "nb"
lw <- nb2listw(nb_list, style = "W")

stopifnot(identical(sort(fi$geography), ids))
x <- fi$severe_fi[match(ids, fi$geography)]
y <- fi$modsev_fi[match(ids, fi$geography)]

set.seed(20261028)
for (nm in c("severe", "moderate_or_severe")) {
  v <- if (nm == "severe") x else y
  mt <- moran.mc(v, lw, nsim = 9999, alternative = "greater")
  cat(sprintf("%-18s Moran I = %6.4f   expected = %6.4f   p = %.4f   (%d permutations)\n",
              nm, mt$statistic, -1/(length(v) - 1), mt$p.value, 9999))
}

cat("\nstate estimates, sorted:\n")
print(fi[order(-fi$severe_fi), c("geography", "n_hh", "severe_fi", "modsev_fi")], row.names = FALSE)

# neighbours sanity: how many states share a high-high pattern by eye
cat("\nrange severe:", sprintf("%.3f to %.3f", min(x), max(x)), "\n")
