# Smoke test: fit a BYM2 binomial model on the real 37-state adjacency graph.
# Synthetic outcome on purpose — this proves the toolchain, it is not a result.
suppressPackageStartupMessages({
  library(INLA)
  library(spdep)
})

edges <- read.csv("data/derived/neighbours.csv", stringsAsFactors = FALSE)
ids <- sort(unique(edges$geography))
cat("nodes:", length(ids), "| directed links:", nrow(edges), "\n")

nb <- lapply(ids, function(g) as.integer(which(ids %in% edges$neighbour[edges$geography == g])))
names(nb) <- ids
class(nb) <- "nb"

# connectivity: a BYM2 model needs one component or extra constraints
library(igraph, quietly = TRUE, warn.conflicts = FALSE)
A <- matrix(0, length(ids), length(ids), dimnames = list(ids, ids))
for (i in seq_len(nrow(edges))) A[edges$geography[i], edges$neighbour[i]] <- 1
g <- graph_from_adjacency_matrix(A, mode = "undirected")
cat("connected components:", components(g)$no, "\n")
cat("degree range:", range(igraph::degree(g)), "\n")

tmp <- tempfile(fileext = ".adj")
nb2INLA(tmp, nb)
graph <- inla.read.graph(tmp)
cat("INLA graph read: nodes", graph$n, "| edges", sum(graph$nnbs) / 2, "\n")

set.seed(11)
n <- length(ids)
spatial <- rnorm(n, 0, 0.6)
trials <- rep(70, n)
y <- rbinom(n, trials, plogis(-2.2 + spatial))
dat <- data.frame(id = seq_len(n), y = y, N = trials)

t0 <- Sys.time()
fit <- inla(
  y ~ 1 + f(id, model = "bym2", graph = graph),
  family = "binomial", Ntrials = N, data = dat,
  control.compute = list(waic = TRUE, dic = TRUE),
  control.predictor = list(compute = TRUE)
)
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

cat("\nmodel fitted in", round(elapsed, 1), "seconds\n")
cat("WAIC:", round(fit$waic$waic, 2), "| DIC:", round(fit$dic$dic, 2), "\n")
cat("fixed effect (intercept):", round(fit$summary.fixed$mean[1], 4),
    " 95% CI", round(fit$summary.fixed$`0.025quant`[1], 3), "to",
    round(fit$summary.fixed$`0.975quant`[1], 3), "\n")
cat("hyperparameters:\n")
print(fit$summary.hyperpar[, c("mean", "0.025quant", "0.975quant")])
cat("\nrhat range:", round(range(fit$summary.hyperpar$mean, na.rm = TRUE), 3),
    "(diagnostic exists:", !is.null(fit$summary.hyperpar), ")\n")
