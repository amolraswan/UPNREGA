args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2 || length(args) > 3) {
  stop("Usage: export_districts.R <scraper_path> <output_json> [library_dir]", call. = FALSE)
}

scraper_path <- normalizePath(args[[1]], winslash = "\\", mustWork = TRUE)
output_json <- normalizePath(args[[2]], winslash = "\\", mustWork = FALSE)
if (length(args) == 3) {
  library_dir <- normalizePath(args[[3]], winslash = "\\", mustWork = TRUE)
  .libPaths(c(library_dir, .libPaths()))
}

source(scraper_path, local = TRUE)
if (!exists("UP_DISTRICTS")) {
  stop("UP_DISTRICTS was not found in scraper.R", call. = FALSE)
}

dir.create(dirname(output_json), showWarnings = FALSE, recursive = TRUE)
jsonlite::write_json(UP_DISTRICTS, output_json, pretty = TRUE, auto_unbox = TRUE)
cat("Wrote districts:", output_json, "\n")
