args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) {
  stop("Usage: build_r_library.R <library_dir>", call. = FALSE)
}

library_dir <- normalizePath(args[[1]], winslash = "\\", mustWork = FALSE)
dir.create(library_dir, showWarnings = FALSE, recursive = TRUE)
.libPaths(c(library_dir, .libPaths()))

required_packages <- c(
  "chromote",
  "jsonlite",
  "httr",
  "rvest",
  "xml2",
  "dplyr",
  "curl"
)

is_installed_in_target <- function(package) {
  length(find.package(package, lib.loc = library_dir, quiet = TRUE)) > 0
}

missing_packages <- required_packages[!vapply(required_packages, is_installed_in_target, logical(1))]

if (length(missing_packages) > 0) {
  install.packages(
    missing_packages,
    lib = library_dir,
    repos = "https://cloud.r-project.org",
    dependencies = c("Depends", "Imports", "LinkingTo")
  )
}

still_missing <- required_packages[!vapply(required_packages, is_installed_in_target, logical(1))]

if (length(still_missing) > 0) {
  stop("Could not install required packages: ", paste(still_missing, collapse = ", "), call. = FALSE)
}

cat("Bundled package library ready:", library_dir, "\n")
