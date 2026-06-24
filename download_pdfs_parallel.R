# download_pdfs_parallel.R - callable PDF downloader for the desktop app.
#
# Dependencies must be available before this file runs. The packaged desktop app
# bundles its own R package library and must never install packages at runtime.

required_packages <- c("chromote", "jsonlite", "httr", "rvest", "xml2", "dplyr", "curl")

missing_packages <- required_packages[!vapply(
  required_packages,
  requireNamespace,
  logical(1),
  quietly = TRUE
)]
if (length(missing_packages) > 0) {
  stop(
    "Missing bundled R package(s): ",
    paste(missing_packages, collapse = ", "),
    ". Rebuild the app package library before distributing the app.",
    call. = FALSE
  )
}

library(chromote)
library(jsonlite)

ensure_scraper_loaded <- function() {
  if (exists("scrape_up_data", mode = "function") &&
      exists("UP_DISTRICTS", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  candidates <- c(
    file.path(getwd(), "scraper.R"),
    file.path(getwd(), "R", "scraper.R"),
    file.path(dirname(normalizePath(sys.frame(1)$ofile %||% ".", mustWork = FALSE)), "scraper.R")
  )
  candidates <- unique(candidates[file.exists(candidates)])
  if (length(candidates) == 0) {
    stop("Could not find scraper.R. Run through app/run.R or place scraper.R next to this script.", call. = FALSE)
  }

  source(candidates[[1]], local = FALSE)
  invisible(TRUE)
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

emit_line <- function(callback, ...) {
  msg <- sprintf(...)
  cat(msg)
  if (!grepl("\n$", msg)) cat("\n")
  flush.console()
  if (!is.null(callback)) callback(msg)
}

sanitize_filename_part <- function(x) {
  gsub("[^A-Za-z0-9_-]", "_", as.character(x))
}

make_pdf_names <- function(df, dist_slug, date_tag) {
  pdf_name <- paste0(
    dist_slug, "_",
    sanitize_filename_part(df$Block), "_",
    sanitize_filename_part(df$Panchayat), "_",
    date_tag, "_",
    sanitize_filename_part(df$Work_Code), "_",
    sanitize_filename_part(df$Mustroll_No), ".pdf"
  )

  dup_names <- duplicated(pdf_name)
  if (any(dup_names)) {
    counts <- ave(seq_along(pdf_name), pdf_name, FUN = seq_along)
    pdf_name <- ifelse(
      pdf_name %in% pdf_name[dup_names],
      sub("\\.pdf$", paste0("_", counts, ".pdf"), pdf_name),
      pdf_name
    )
  }

  pdf_name
}

download_pdf_rows <- function(row_idx, df, output_dir) {
  library(chromote)
  library(jsonlite)

  messages <- character(0)
  add_message <- function(...) {
    messages <<- c(messages, sprintf(...))
  }

  row_status <- character(length(row_idx))
  row_attempts <- integer(length(row_idx))

  b <- ChromoteSession$new()
  on.exit(try(b$close(), silent = TRUE), add = TRUE)

  try(b$Network$enable(), silent = TRUE)
  b$Emulation$setEmulatedMedia(media = "screen")

  for (pos in seq_along(row_idx)) {
    i <- row_idx[pos]
    url <- df$Mustroll_Link[i]
    pdf_path <- file.path(output_dir, df$pdf_name[i])

    if (is.na(url) || url == "") {
      add_message("  [%d/%d] SKIP (no URL): %s\n", i, nrow(df), df$pdf_name[i])
      row_status[pos] <- "skipped_no_url"
      row_attempts[pos] <- 0
      next
    }

    if (file.exists(pdf_path) && file.size(pdf_path) >= 51200) {
      add_message("  [%d/%d] ALREADY SAVED: %s\n", i, nrow(df), df$pdf_name[i])
      row_status[pos] <- "already_saved"
      row_attempts[pos] <- 0
      next
    }

    referer <- if ("Mustroll_Referer" %in% names(df)) df$Mustroll_Referer[i] else NA_character_
    extra_headers <- if (!is.na(referer) && nzchar(referer)) {
      list(Referer = referer)
    } else {
      list()
    }
    try(b$Network$setExtraHTTPHeaders(headers = extra_headers), silent = TRUE)

    saved <- FALSE
    for (attempt in 1:3) {
      tryCatch({
        nav_result <- b$Page$navigate(url)

        if (!is.null(nav_result$errorText) && nzchar(nav_result$errorText)) {
          add_message(
            "  [%d/%d] Attempt %d nav error: %s - %s\n",
            i, nrow(df), attempt, df$pdf_name[i], nav_result$errorText
          )
          if (attempt < 3) Sys.sleep(attempt * 2)
          next
        }

        tryCatch(
          b$Page$loadEventFired(timeout = 30),
          error = function(e) {
            add_message(
              "  [%d/%d] Attempt %d: page load timeout, proceeding anyway\n",
              i, nrow(df), attempt
            )
          }
        )
        Sys.sleep(3)

        pdf_data <- b$Page$printToPDF(
          landscape = FALSE,
          printBackground = TRUE,
          preferCSSPageSize = FALSE,
          paperWidth = 8.27,
          paperHeight = 11.69
        )

        raw_pdf <- base64_dec(pdf_data$data)
        writeBin(raw_pdf, pdf_path)

        if (file.size(pdf_path) < 51200) {
          add_message(
            "  [%d/%d] Attempt %d: PDF too small (likely blank): %s\n",
            i, nrow(df), attempt, df$pdf_name[i]
          )
          file.remove(pdf_path)
          if (attempt < 3) Sys.sleep(attempt * 2)
        } else {
          saved <- TRUE
          row_attempts[pos] <- attempt
          break
        }
      }, error = function(e) {
        add_message(
          "  [%d/%d] Attempt %d failed: %s - %s\n",
          i, nrow(df), attempt, df$pdf_name[i], e$message
        )
        if (attempt < 3) Sys.sleep(attempt * 2)
      })
    }

    if (saved) {
      row_status[pos] <- "saved"
      add_message("  [%d/%d] OK: %s\n", i, nrow(df), df$pdf_name[i])
    } else {
      row_status[pos] <- "failed"
      row_attempts[pos] <- 3
      add_message("  [%d/%d] FAILED after 3 attempts: %s\n", i, nrow(df), df$pdf_name[i])
    }
  }

  list(
    log = data.frame(
      row = row_idx,
      Status = row_status,
      Attempts = row_attempts,
      stringsAsFactors = FALSE
    ),
    messages = messages
  )
}

download_muster_roll_pdfs <- function(district,
                                      dd,
                                      mm,
                                      yyyy,
                                      output_root,
                                      num_sessions = 4,
                                      log_callback = NULL) {
  ensure_scraper_loaded()

  date_err <- validate_date(dd, mm, yyyy)
  if (!is.null(date_err)) {
    stop("Invalid date (", dd, "/", mm, "/", yyyy, "): ", date_err, call. = FALSE)
  }

  district_err <- validate_district(district)
  if (!is.null(district_err)) {
    stop("Invalid district: ", district_err, call. = FALSE)
  }
  district <- canonicalize_district(district)
  dist_slug <- district_slug(district)

  date_tag <- paste0(
    sprintf("%02d", as.integer(dd)),
    sprintf("%02d", as.integer(mm)),
    yyyy
  )

  output_root <- normalizePath(output_root, winslash = "\\", mustWork = FALSE)
  output_dir <- file.path(output_root, "MusterRollsPDF", date_tag)
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  emit_line(log_callback, "=== Muster Roll PDF Downloader ===\n")
  emit_line(log_callback, "District: %s\n", district)
  emit_line(log_callback, "Date: %s/%s/%s\n\n", dd, mm, yyyy)

  emit_line(log_callback, "[1/4] Scraping NREGA data to get muster roll URLs...\n")
  result <- scrape_up_data(
    district,
    dd,
    mm,
    yyyy,
    scrape_musters = FALSE,
    progress_callback = function(val, msg) emit_line(log_callback, "  %s\n", msg)
  )

  if (!result$success) stop("Scrape failed: ", result$error, call. = FALSE)
  df <- result$data
  emit_line(log_callback, "  Found %d muster rolls\n\n", nrow(df))

  df$pdf_name <- make_pdf_names(df, dist_slug, date_tag)

  num_sessions <- max(1, as.integer(num_sessions))
  num_sessions <- min(num_sessions, max(1, nrow(df)))

  emit_line(log_callback, "[2/4] Launching %d parallel headless Chrome sessions...\n", num_sessions)
  cl <- parallel::makeCluster(num_sessions)
  on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
  parallel::clusterCall(cl, function(path) setwd(path), getwd())
  parallel::clusterCall(cl, function(paths) .libPaths(paths), .libPaths())
  parallel::clusterExport(cl, "download_pdf_rows", envir = environment())

  emit_line(log_callback, "[3/4] Found %d pages to save\n", nrow(df))
  emit_line(log_callback, "[4/4] Saving in progress\n")
  row_indices <- seq_len(nrow(df))
  chunk_size <- ceiling(length(row_indices) / num_sessions)
  chunks <- split(row_indices, ceiling(seq_along(row_indices) / chunk_size))

  worker_results <- parallel::parLapply(
    cl,
    chunks,
    function(rows, df, output_dir) download_pdf_rows(rows, df, output_dir),
    df = df,
    output_dir = output_dir
  )

  parallel::stopCluster(cl)

  for (res in worker_results) {
    cat(res$messages, sep = "")
  }

  combined_log <- do.call(rbind, lapply(worker_results, `[[`, "log"))
  combined_log <- combined_log[order(combined_log$row), ]

  log_status <- combined_log$Status
  log_attempts <- combined_log$Attempts

  success <- sum(log_status == "saved")
  failed <- sum(log_status == "failed")
  skipped <- sum(log_status == "skipped_no_url")
  already <- sum(log_status == "already_saved")
  failed_names <- df$pdf_name[log_status == "failed"]
  skipped_names <- df$pdf_name[log_status == "skipped_no_url"]

  emit_line(log_callback, "\n=== Done ===\n")
  emit_line(log_callback, "Saved:          %d PDFs\n", success)
  if (already > 0) {
    emit_line(log_callback, "Already saved:  %d (skipped on resume)\n", already)
  }
  if (skipped > 0) {
    emit_line(log_callback, "Skipped (no URL): %d\n", skipped)
  }
  emit_line(log_callback, "Failed:         %d\n", failed)

  if (length(skipped_names) > 0) {
    emit_line(log_callback, "\nSkipped muster rolls (no URL):\n")
    for (fn in skipped_names) emit_line(log_callback, "  - %s\n", fn)
  }
  if (length(failed_names) > 0) {
    emit_line(log_callback, "\nFailed muster rolls:\n")
    for (fn in failed_names) emit_line(log_callback, "  - %s\n", fn)
  }

  log_df <- data.frame(
    District = district,
    Block = df$Block,
    Panchayat = df$Panchayat,
    Work_Code = df$Work_Code,
    Mustroll_No = df$Mustroll_No,
    URL = df$Mustroll_Link,
    Referer = if ("Mustroll_Referer" %in% names(df)) df$Mustroll_Referer else NA_character_,
    PDF_File = df$pdf_name,
    Status = log_status,
    Attempts = log_attempts,
    stringsAsFactors = FALSE
  )
  log_path <- file.path(output_dir, paste0("download_log_", dist_slug, "_", date_tag, ".csv"))
  write.csv(log_df, log_path, row.names = FALSE)

  emit_line(log_callback, "Output: %s\n", output_dir)
  emit_line(log_callback, "Log: %s\n", log_path)

  list(
    output_dir = output_dir,
    log_path = log_path,
    saved = success,
    already_saved = already,
    skipped = skipped,
    failed = failed
  )
}

# This file intentionally defines functions only. The desktop app calls
# download_muster_roll_pdfs() through app/run.R with user-provided settings.
