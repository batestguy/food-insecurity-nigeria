# Install R-INLA as a Windows binary (fast) rather than compiling from source.
options(repos = c(
  CRAN = "https://cloud.r-project.org",
  INLA = "https://inla.r-inla-download.org/R/stable"
))
cat("R:", R.version.string, "\n")
cat("library:", .libPaths()[1], "\n")

install.packages("INLA", type = "binary", dependencies = NA)

cat("\n--- verify ---\n")
ok <- requireNamespace("INLA", quietly = TRUE)
cat("INLA installed:", ok, "\n")
if (ok) {
  cat("INLA version:", as.character(packageVersion("INLA")), "\n")
  suppressMessages(library(INLA))
  cat("inla() callable:", is.function(inla), "\n")
  cat("fmesher present:", requireNamespace("fmesher", quietly = TRUE), "\n")
}
