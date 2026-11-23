# Install R-INLA from its own repository.
# R-INLA is not on CRAN, so it needs the INLA repository added explicitly.
options(repos = c(
  CRAN = "https://cloud.r-project.org",
  INLA = "https://inla.r-inla-download.org/R/stable"
))

cat("R version:", R.version.string, "\n")
cat("libPaths:\n"); print(.libPaths())

install.packages("INLA", dep = TRUE)

cat("\n--- verify ---\n")
ok <- requireNamespace("INLA", quietly = TRUE)
cat("INLA loadable:", ok, "\n")
if (ok) cat("INLA version:", as.character(packageVersion("INLA")), "\n")
