install_to_local_library <- FALSE

script_path <- function() {
  args_all <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args_all, value = TRUE)
  if (length(file_arg) > 0) {
    sub("^--file=", "", file_arg[[1]])
  } else {
    "PhotoMatch/install_dependencies.R"
  }
}

script_dir <- dirname(normalizePath(script_path(), winslash = "/", mustWork = FALSE))
library_dir <- file.path(script_dir, "library")
if (dir.exists(library_dir)) {
  .libPaths(c(library_dir, .libPaths()))
}

required_packages <- c(
  "httr",
  "rvest",
  "xml2",
  "dplyr",
  "curl",
  "jpeg",
  "openxlsx"
)

missing_packages <- required_packages[!vapply(
  required_packages,
  requireNamespace,
  logical(1),
  quietly = TRUE
)]

if (length(missing_packages) == 0) {
  cat("All PhotoMatch dependencies are already installed.\n")
  quit(status = 0, save = "no")
}

cat("Installing PhotoMatch package(s): ", paste(missing_packages, collapse = ", "), "\n", sep = "")
install_lib <- NULL
if (isTRUE(install_to_local_library)) {
  dir.create(library_dir, showWarnings = FALSE, recursive = TRUE)
  .libPaths(c(library_dir, .libPaths()))
  install_lib <- library_dir
} else {
  global_lib <- .libPaths()[1]
  if (file.access(global_lib, mode = 2) != 0) {
    stop(
      "Missing package(s): ", paste(missing_packages, collapse = ", "),
      "\nThe global R package library is not writable: ", global_lib,
      "\nInstall these packages globally using a writable R setup, or set install_to_local_library <- TRUE.",
      call. = FALSE
    )
  }
}

install.packages(
  missing_packages,
  lib = install_lib,
  repos = "https://cloud.r-project.org",
  dependencies = c("Depends", "Imports", "LinkingTo")
)

still_missing <- required_packages[!vapply(
  required_packages,
  requireNamespace,
  logical(1),
  quietly = TRUE
)]

if (length(still_missing) > 0) {
  stop("Could not install package(s): ", paste(still_missing, collapse = ", "), call. = FALSE)
}

cat("PhotoMatch dependencies are ready.\n")
