#!/usr/bin/env Rscript

args_all <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args_all, value = TRUE)
script_path <- if (length(file_arg) > 0) {
  sub("^--file=", "", file_arg[[1]])
} else {
  "run.R"
}
script_dir <- dirname(normalizePath(script_path, winslash = "\\", mustWork = FALSE))
install_root <- normalizePath(file.path(script_dir, ".."), winslash = "\\", mustWork = FALSE)

library_dir <- file.path(install_root, "library")
base_library_dir <- file.path(install_root, "R", "library")
bundled_library_paths <- character(0)
if (dir.exists(library_dir)) {
  bundled_library_paths <- c(bundled_library_paths, library_dir)
  Sys.setenv(R_LIBS_USER = library_dir, R_LIBS_SITE = "")
}
if (dir.exists(base_library_dir)) {
  bundled_library_paths <- c(bundled_library_paths, base_library_dir)
}
if (length(bundled_library_paths) > 0) {
  .libPaths(bundled_library_paths)
}

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite is missing from the bundled R package library.", call. = FALSE)
}

args <- commandArgs(trailingOnly = TRUE)
config_index <- match("--config", args)
if (is.na(config_index) || length(args) < config_index + 1) {
  stop("Usage: run.R --config <config_path>", call. = FALSE)
}
config_path <- normalizePath(args[[config_index + 1]], winslash = "\\", mustWork = TRUE)
config <- jsonlite::fromJSON(config_path)

required_config <- c("district", "dd", "mm", "yyyy", "output_folder")
missing_config <- required_config[!nzchar(vapply(required_config, function(k) {
  value <- config[[k]]
  if (is.null(value)) "" else as.character(value)
}, character(1)))]
if (length(missing_config) > 0) {
  stop("Config is missing: ", paste(missing_config, collapse = ", "), call. = FALSE)
}

output_folder <- normalizePath(config$output_folder, winslash = "\\", mustWork = FALSE)
dir.create(output_folder, showWarnings = FALSE, recursive = TRUE)

selected_date_tag <- paste0(
  sprintf("%02d", as.integer(config$dd)),
  sprintf("%02d", as.integer(config$mm)),
  config$yyyy
)

run_log_path <- if (!is.null(config$run_log_path) && nzchar(config$run_log_path)) {
  normalizePath(config$run_log_path, winslash = "\\", mustWork = FALSE)
} else {
  file.path(output_folder, paste0("muster_roll_downloader_", selected_date_tag, "_", format(Sys.time(), "%H%M%S"), ".log"))
}
dir.create(dirname(run_log_path), showWarnings = FALSE, recursive = TRUE)

log_con <- file(run_log_path, open = "wt", encoding = "UTF-8")
sink(log_con, split = TRUE)
on.exit({
  try(sink(), silent = TRUE)
  try(close(log_con), silent = TRUE)
}, add = TRUE)

exit_code <- tryCatch({
  cat("RUN_LOG:", run_log_path, "\n")

  scraper_path <- file.path(script_dir, "scraper.R")
  if (!file.exists(scraper_path)) {
    scraper_path <- file.path(install_root, "R", "scraper.R")
  }
  if (!file.exists(scraper_path)) {
    stop("Could not find scraper.R in the installed app files.", call. = FALSE)
  }

  downloader_path <- file.path(script_dir, "download_pdfs_parallel.R")
  if (!file.exists(downloader_path)) {
    downloader_path <- file.path(install_root, "download_pdfs_parallel.R")
  }
  if (!file.exists(downloader_path)) {
    stop("Could not find download_pdfs_parallel.R in the installed app files.", call. = FALSE)
  }

  suppressPackageStartupMessages(source(scraper_path, local = FALSE))
  suppressPackageStartupMessages(source(downloader_path, local = FALSE))

  result <- download_muster_roll_pdfs(
    district = config$district,
    dd = config$dd,
    mm = config$mm,
    yyyy = config$yyyy,
    output_root = output_folder,
    num_sessions = if (!is.null(config$num_sessions)) config$num_sessions else 4
  )

  cat("OUTPUT:", result$output_dir, "\n")
  cat("LOG:", result$log_path, "\n")
  cat("SUMMARY: saved=", result$saved,
      " already_saved=", result$already_saved,
      " skipped=", result$skipped,
      " failed=", result$failed, "\n", sep = "")

  if (result$failed > 0) {
    cat("Completed with PDF download failures. Review the CSV log for details.\n")
  }

  0
}, error = function(e) {
  cat("ERROR:", conditionMessage(e), "\n")
  1
})

quit(status = exit_code, save = "no")
