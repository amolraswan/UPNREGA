district_name <- "AMROHA"
first_date <- "01/06/2026"  # DD/MM/YYYY
second_date <- "02/06/2026"  # DD/MM/YYYY
match_threshold <- 85

show_usage <- function() {
  cat(
    "Usage:\n",
    "  Rscript PhotoMatch/photo_match.R\n",
    "  Rscript PhotoMatch/photo_match.R --district <district> --date1 <DD/MM/YYYY> --date2 <DD/MM/YYYY> [options]\n\n",
    "Options:\n",
    "  --district <district>   Uttar Pradesh district name.\n",
    "  --date1 <DD/MM/YYYY>   First attendance date. DD-MM-YYYY and DDMMYYYY also work.\n",
    "  --date2 <DD/MM/YYYY>   Second attendance date. DD-MM-YYYY and DDMMYYYY also work.\n",
    "  --threshold <number>   Match threshold from 0 to 100.\n",
    "  --help                 Show this help text.\n",
    sep = ""
  )
}

parse_args <- function(args) {
  opts <- list(help = FALSE)

  i <- 1
  while (i <= length(args)) {
    arg <- args[[i]]

    if (arg %in% c("--help", "-h")) {
      opts$help <- TRUE
      i <- i + 1
      next
    }

    if (!startsWith(arg, "--")) {
      stop("Unexpected argument: ", arg, call. = FALSE)
    }

    if (grepl("=", arg, fixed = TRUE)) {
      parts <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1]]
      key <- parts[[1]]
      value <- paste(parts[-1], collapse = "=")
    } else {
      key <- sub("^--", "", arg)
      if (i == length(args) || startsWith(args[[i + 1]], "--")) {
        stop("Missing value for --", key, call. = FALSE)
      }
      value <- args[[i + 1]]
      i <- i + 1
    }

    key <- gsub("-", "_", key)
    if (!key %in% c("district", "date1", "date2", "threshold")) {
      stop("Unknown option: --", gsub("_", "-", key), call. = FALSE)
    }
    opts[[key]] <- value
    i <- i + 1
  }

  opts
}

apply_top_level_defaults <- function(opts) {
  if (is.null(opts$district)) opts$district <- district_name
  if (is.null(opts$date1)) opts$date1 <- first_date
  if (is.null(opts$date2)) opts$date2 <- second_date
  if (is.null(opts$threshold)) opts$threshold <- match_threshold
  opts
}

script_path <- function() {
  args_all <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args_all, value = TRUE)
  candidates <- character(0)
  if (length(file_arg) > 0) {
    candidates <- c(candidates, sub("^--file=", "", file_arg[[1]]))
  }
  candidates <- c(candidates, "photo_match.R", file.path("PhotoMatch", "photo_match.R"))
  candidates <- unique(candidates[nzchar(candidates)])
  existing <- candidates[file.exists(candidates)]
  if (length(existing) > 0) {
    return(normalizePath(existing[[1]], winslash = "/", mustWork = TRUE))
  }
  normalizePath(candidates[[1]], winslash = "/", mustWork = FALSE)
}

parent_dirs <- function(path, levels = 8) {
  path <- if (dir.exists(path)) path else dirname(path)
  if (dir.exists(path)) {
    path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  }
  dirs <- character(0)
  current <- path
  for (i in seq_len(levels)) {
    dirs <- c(dirs, current)
    next_dir <- dirname(current)
    if (identical(next_dir, current)) break
    current <- next_dir
  }
  unique(dirs)
}

find_repo_root <- function(script_dir_value) {
  candidates <- unique(c(parent_dirs(script_dir_value), parent_dirs(getwd())))
  matches <- candidates[file.exists(file.path(candidates, "R", "scraper.R"))]
  if (length(matches) == 0) {
    stop("Could not find R/scraper.R. Run the script from inside the repository or keep PhotoMatch inside the repository.", call. = FALSE)
  }
  normalizePath(matches[[1]], winslash = "/", mustWork = TRUE)
}

script_dir <- dirname(script_path())
repo_root <- find_repo_root(script_dir)
if (file.exists(file.path(repo_root, "PhotoMatch", "photo_match.R"))) {
  script_dir <- normalizePath(file.path(repo_root, "PhotoMatch"), winslash = "/", mustWork = TRUE)
}
local_library_dir <- file.path(script_dir, "library")
if (dir.exists(local_library_dir)) {
  .libPaths(c(local_library_dir, .libPaths()))
}

opts <- parse_args(commandArgs(trailingOnly = TRUE))
if (isTRUE(opts$help)) {
  show_usage()
  quit(status = 0, save = "no")
}
opts <- apply_top_level_defaults(opts)

required_opts <- c("district", "date1", "date2")
missing_opts <- required_opts[!vapply(required_opts, function(key) {
  value <- opts[[key]]
  !is.null(value) && nzchar(trimws(as.character(value)))
}, logical(1))]
if (length(missing_opts) > 0) {
  show_usage()
  stop("Missing required option(s): --", paste(missing_opts, collapse = ", --"), call. = FALSE)
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
if (length(missing_packages) > 0) {
  stop(
    "Missing R package(s): ", paste(missing_packages, collapse = ", "),
    "\nInstall these packages in the global R library before running PhotoMatch.",
    call. = FALSE
  )
}

scraper_path <- file.path(repo_root, "R", "scraper.R")
if (!file.exists(scraper_path)) {
  stop("Could not find scraper.R at: ", scraper_path, call. = FALSE)
}
suppressPackageStartupMessages(source(scraper_path, local = FALSE))

parse_input_date <- function(value, label) {
  value <- trimws(as.character(value))
  parsed <- NA

  if (grepl("^\\d{2}/\\d{2}/\\d{4}$", value)) {
    parsed <- as.Date(value, format = "%d/%m/%Y")
  } else if (grepl("^\\d{2}-\\d{2}-\\d{4}$", value)) {
    parsed <- as.Date(value, format = "%d-%m-%Y")
  } else if (grepl("^\\d{8}$", value)) {
    parsed <- as.Date(value, format = "%d%m%Y")
  }

  if (is.na(parsed)) {
    stop(label, " must be in DD/MM/YYYY format.", call. = FALSE)
  }

  list(
    date = parsed,
    dd = format(parsed, "%d"),
    mm = format(parsed, "%m"),
    yyyy = format(parsed, "%Y"),
    tag = format(parsed, "%d%m%Y"),
    display = format(parsed, "%d/%m/%Y")
  )
}

validate_photo_match_date <- function(date_info, label) {
  err <- validate_date(date_info$dd, date_info$mm, date_info$yyyy)
  if (!is.null(err)) {
    stop("Invalid ", label, " (", date_info$display, "): ", err, call. = FALSE)
  }
}

as_threshold <- function(value) {
  threshold <- suppressWarnings(as.numeric(value))
  if (is.na(threshold) || threshold < 0 || threshold > 100) {
    stop("--threshold must be a number from 0 to 100.", call. = FALSE)
  }
  threshold
}

sanitize_filename_part <- function(x) {
  x <- gsub("[^A-Za-z0-9_-]", "_", as.character(x))
  x <- gsub("_+", "_", x)
  gsub("^_|_$", "", x)
}

normalize_key_part <- function(x) {
  x <- toupper(trimws(as.character(x)))
  gsub("\\s+", " ", x)
}

make_identity_key <- function(df) {
  key_cols <- c("District", "Block", "Panchayat", "Work_Code", "Mustroll_No")
  missing_cols <- setdiff(key_cols, names(df))
  if (length(missing_cols) > 0) {
    stop("Scraped data is missing expected column(s): ", paste(missing_cols, collapse = ", "), call. = FALSE)
  }

  normalized <- lapply(key_cols, function(col) normalize_key_part(df[[col]]))
  do.call(paste, c(normalized, sep = "\034"))
}

dedupe_by_key <- function(df, label) {
  df$photo_match_key <- make_identity_key(df)
  duplicates <- duplicated(df$photo_match_key)
  if (any(duplicates)) {
    cat(sprintf(
      "  WARNING: %s has %d duplicate muster-roll key(s); keeping the first row for each key.\n",
      label,
      sum(duplicates)
    ))
    df <- df[!duplicates, , drop = FALSE]
  }
  df
}

find_common_musters <- function(df1, df2) {
  df1 <- dedupe_by_key(df1, "date1")
  df2 <- dedupe_by_key(df2, "date2")

  merged <- merge(
    df1,
    df2,
    by = "photo_match_key",
    suffixes = c("_date1", "_date2"),
    all = FALSE,
    sort = FALSE
  )

  if (nrow(merged) == 0) {
    return(data.frame(
      District = character(0),
      Block = character(0),
      Panchayat = character(0),
      Work_Code = character(0),
      Mustroll_No = character(0),
      Url_Date1 = character(0),
      Url_Date2 = character(0),
      stringsAsFactors = FALSE
    ))
  }

  data.frame(
    District = merged$District_date1,
    Block = merged$Block_date1,
    Panchayat = merged$Panchayat_date1,
    Work_Code = merged$Work_Code_date1,
    Mustroll_No = merged$Mustroll_No_date1,
    Url_Date1 = merged$Mustroll_Link_date1,
    Url_Date2 = merged$Mustroll_Link_date2,
    stringsAsFactors = FALSE
  )
}

photo_filename <- function(row, district_slug_value, date_tag) {
  paste0(
    district_slug_value, "_",
    sanitize_filename_part(row$Block), "_",
    sanitize_filename_part(row$Panchayat), "_",
    date_tag, "_",
    sanitize_filename_part(row$Work_Code), "_",
    sanitize_filename_part(row$Mustroll_No), ".jpg"
  )
}

make_absolute_url <- function(url, base_url) {
  if (is.na(url) || !nzchar(url)) return(NA_character_)
  url <- trimws(url)
  if (grepl("^https?://", url, ignore.case = TRUE)) return(url)
  if (startsWith(url, "//")) {
    scheme <- sub("^(https?)://.*$", "\\1", base_url, ignore.case = TRUE)
    return(paste0(scheme, ":", url))
  }
  origin <- sub("^(https?://[^/]+).*$", "\\1", base_url, ignore.case = TRUE)
  if (startsWith(url, "/")) return(paste0(origin, url))
  base_dir <- sub("/[^/?#]*([?#].*)?$", "/", base_url)
  paste0(base_dir, url)
}

extract_first_photo_url <- function(html, page_url) {
  img_node <- rvest::html_node(html, "img#ContentPlaceHolder1_img_groupPhoto")
  src <- if (!is.na(img_node)) rvest::html_attr(img_node, "src") else NA_character_

  if (is.na(src) || !nzchar(src)) {
    link_node <- rvest::html_node(html, "a#ContentPlaceHolder1_hyp_viewPhotos")
    src <- if (!is.na(link_node)) rvest::html_attr(link_node, "href") else NA_character_
  }

  if (is.na(src) || !nzchar(src)) {
    img_node <- rvest::html_node(html, xpath = "//*[@id='ContentPlaceHolder1_div_GroupPhotos']//img[1]")
    src <- if (!is.na(img_node)) rvest::html_attr(img_node, "src") else NA_character_
  }

  make_absolute_url(src, page_url)
}

extract_text_by_id <- function(html, id) {
  node <- rvest::html_node(html, paste0("#", id))
  value <- if (!is.na(node)) rvest::html_text2(node) else NA_character_
  if (is.na(value) || !nzchar(trimws(value))) NA_character_ else trimws(value)
}

clean_metadata_value <- function(value) {
  if (is.na(value) || !nzchar(trimws(value))) return(NA_character_)
  value <- gsub("\\s+", " ", trimws(value))
  if (nzchar(value)) value else NA_character_
}

photo1_metadata_text <- function(html) {
  text <- rvest::html_text2(html)
  if (is.na(text) || !nzchar(text)) return(NA_character_)
  start <- regexpr("Timestamp\\s+for\\s+Photo-?1", text, ignore.case = TRUE, perl = TRUE)
  if (start[[1]] > 0) {
    text <- substr(text, start[[1]], nchar(text))
  }
  text
}

extract_metadata_value <- function(text, label_pattern, stop_pattern) {
  if (is.na(text) || !nzchar(text)) return(NA_character_)
  pattern <- paste0(label_pattern, "\\s*([\\s\\S]*?)\\s*(?=", stop_pattern, ")")
  match <- regexec(pattern, text, ignore.case = TRUE, perl = TRUE)
  parts <- regmatches(text, match)[[1]]
  if (length(parts) < 2) return(NA_character_)
  clean_metadata_value(parts[[2]])
}

extract_first_photo_metadata <- function(html) {
  text <- photo1_metadata_text(html)
  photo_taken_time <- extract_text_by_id(html, "ContentPlaceHolder1_lbl_PhotoTakenTime")
  photo_uploaded_time <- extract_text_by_id(html, "ContentPlaceHolder1_lbl_PhotoUploadTime")
  photo_taken_by <- extract_text_by_id(html, "ContentPlaceHolder1_lbl_Taken_by")

  if (is.na(photo_taken_time)) {
    photo_taken_time <- extract_metadata_value(
      text,
      "Taken\\s*:",
      "Uploaded\\s*:|Geo\\s*Co-ordinates\\s*:|Taken\\s+by\\s*:|Designation\\s*:|Timestamp\\s+for\\s+Photo-?2|Second\\s+Photo|Group\\s+Photo\\s+2|English|$"
    )
  }
  if (is.na(photo_uploaded_time)) {
    photo_uploaded_time <- extract_metadata_value(
      text,
      "Uploaded\\s*:",
      "Geo\\s*Co-ordinates\\s*:|Taken\\s+by\\s*:|Designation\\s*:|Timestamp\\s+for\\s+Photo-?2|Second\\s+Photo|Group\\s+Photo\\s+2|English|$"
    )
  }
  if (is.na(photo_taken_by)) {
    photo_taken_by <- extract_metadata_value(
      text,
      "Taken\\s+by\\s*:",
      "Designation\\s*:|Timestamp\\s+for\\s+Photo-?2|Second\\s+Photo|Group\\s+Photo\\s+2|English|S\\.No|$"
    )
  }

  list(
    photo_taken_time = clean_metadata_value(photo_taken_time),
    photo_uploaded_time = clean_metadata_value(photo_uploaded_time),
    photo_taken_by = clean_metadata_value(photo_taken_by)
  )
}

empty_photo_metadata <- function() {
  list(
    photo_taken_time = NA_character_,
    photo_uploaded_time = NA_character_,
    photo_taken_by = NA_character_
  )
}

request_user_agent <- function() {
  if (exists("UA", inherits = TRUE)) {
    get("UA", inherits = TRUE)
  } else {
    httr::user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
  }
}

safe_get <- function(url, timeout_seconds = 60) {
  tryCatch(
    httr::GET(url, request_user_agent(), httr::timeout(timeout_seconds)),
    error = function(e) e
  )
}

response_ok <- function(resp) {
  !inherits(resp, "error") && httr::status_code(resp) >= 200 && httr::status_code(resp) < 300
}

valid_jpeg <- function(path) {
  if (!file.exists(path) || file.size(path) < 1024) return(FALSE)
  tryCatch({
    jpeg::readJPEG(path)
    TRUE
  }, error = function(e) FALSE)
}

download_image_candidates <- function(photo_url, output_path) {
  candidates <- photo_url
  if (grepl("^http://", photo_url, ignore.case = TRUE)) {
    candidates <- c(candidates, sub("^http://", "https://", photo_url, ignore.case = TRUE))
  } else if (grepl("^https://", photo_url, ignore.case = TRUE)) {
    candidates <- c(candidates, sub("^https://", "http://", photo_url, ignore.case = TRUE))
  }
  candidates <- unique(candidates)

  last_error <- "image download failed"
  for (candidate in candidates) {
    resp <- safe_get(candidate, timeout_seconds = 60)
    if (!response_ok(resp)) {
      last_error <- if (inherits(resp, "error")) {
        conditionMessage(resp)
      } else {
        paste0("HTTP ", httr::status_code(resp))
      }
      next
    }

    raw_body <- httr::content(resp, "raw")
    if (length(raw_body) < 1024) {
      last_error <- "downloaded image was too small"
      next
    }

    writeBin(raw_body, output_path)
    if (valid_jpeg(output_path)) {
      return(list(status = "saved", url = candidate, error = NA_character_))
    }

    last_error <- "downloaded file was not a readable JPEG"
  }

  list(status = "failed", url = photo_url, error = last_error)
}

download_first_photo <- function(page_url, output_path) {
  if (is.na(page_url) || !nzchar(page_url)) {
    metadata <- empty_photo_metadata()
    return(list(
      status = "missing_muster_url",
      path = output_path,
      photo_url = NA_character_,
      photo_taken_time = metadata$photo_taken_time,
      photo_uploaded_time = metadata$photo_uploaded_time,
      photo_taken_by = metadata$photo_taken_by,
      error = "muster-roll URL is missing"
    ))
  }

  existing_photo <- valid_jpeg(output_path)
  page_resp <- safe_get(page_url, timeout_seconds = 60)
  if (!response_ok(page_resp)) {
    err <- if (inherits(page_resp, "error")) {
      conditionMessage(page_resp)
    } else {
      paste0("HTTP ", httr::status_code(page_resp))
    }
    metadata <- empty_photo_metadata()
    return(list(
      status = if (existing_photo) "already_saved" else "page_fetch_failed",
      path = output_path,
      photo_url = NA_character_,
      photo_taken_time = metadata$photo_taken_time,
      photo_uploaded_time = metadata$photo_uploaded_time,
      photo_taken_by = metadata$photo_taken_by,
      error = err
    ))
  }

  html <- tryCatch(
    xml2::read_html(httr::content(page_resp, "text", encoding = "UTF-8")),
    error = function(e) e
  )
  if (inherits(html, "error")) {
    metadata <- empty_photo_metadata()
    return(list(
      status = if (existing_photo) "already_saved" else "page_parse_failed",
      path = output_path,
      photo_url = NA_character_,
      photo_taken_time = metadata$photo_taken_time,
      photo_uploaded_time = metadata$photo_uploaded_time,
      photo_taken_by = metadata$photo_taken_by,
      error = conditionMessage(html)
    ))
  }

  metadata <- extract_first_photo_metadata(html)
  photo_url <- extract_first_photo_url(html, page_url)
  if (is.na(photo_url) || !nzchar(photo_url)) {
    return(list(
      status = if (existing_photo) "already_saved" else "first_photo_missing",
      path = output_path,
      photo_url = NA_character_,
      photo_taken_time = metadata$photo_taken_time,
      photo_uploaded_time = metadata$photo_uploaded_time,
      photo_taken_by = metadata$photo_taken_by,
      error = if (existing_photo) NA_character_ else "first photo selector was not found"
    ))
  }

  if (existing_photo) {
    return(list(
      status = "already_saved",
      path = output_path,
      photo_url = photo_url,
      photo_taken_time = metadata$photo_taken_time,
      photo_uploaded_time = metadata$photo_uploaded_time,
      photo_taken_by = metadata$photo_taken_by,
      error = NA_character_
    ))
  }

  img_result <- download_image_candidates(photo_url, output_path)
  list(
    status = img_result$status,
    path = output_path,
    photo_url = img_result$url,
    photo_taken_time = metadata$photo_taken_time,
    photo_uploaded_time = metadata$photo_uploaded_time,
    photo_taken_by = metadata$photo_taken_by,
    error = img_result$error
  )
}

read_grayscale <- function(path, crop_ratio = 0.84) {
  img <- jpeg::readJPEG(path)
  dims <- dim(img)

  if (length(dims) == 2) {
    gray <- img
  } else if (dims[3] < 3) {
    gray <- img[, , 1]
  } else {
    gray <- 0.299 * img[, , 1] + 0.587 * img[, , 2] + 0.114 * img[, , 3]
  }

  crop_rows <- max(1, min(nrow(gray), floor(nrow(gray) * crop_ratio)))
  gray[seq_len(crop_rows), , drop = FALSE]
}

resize_nearest <- function(mat, target_height = 128, target_width = 128) {
  row_idx <- pmin(pmax(round(seq(1, nrow(mat), length.out = target_height)), 1), nrow(mat))
  col_idx <- pmin(pmax(round(seq(1, ncol(mat), length.out = target_width)), 1), ncol(mat))
  mat[row_idx, col_idx, drop = FALSE]
}

ssim_score <- function(img1, img2) {
  x <- as.numeric(img1)
  y <- as.numeric(img2)
  mean_x <- mean(x, na.rm = TRUE)
  mean_y <- mean(y, na.rm = TRUE)
  var_x <- mean((x - mean_x)^2, na.rm = TRUE)
  var_y <- mean((y - mean_y)^2, na.rm = TRUE)
  cov_xy <- mean((x - mean_x) * (y - mean_y), na.rm = TRUE)
  c1 <- 0.01^2
  c2 <- 0.03^2
  score <- ((2 * mean_x * mean_y + c1) * (2 * cov_xy + c2)) /
    ((mean_x^2 + mean_y^2 + c1) * (var_x + var_y + c2))
  round(max(0, min(100, 100 * score)), 2)
}

dct_matrix <- function(n) {
  rows <- seq_len(n) - 1
  cols <- seq_len(n) - 1
  mat <- cos(pi / n * outer(rows + 0.5, cols))
  mat[, 1] <- mat[, 1] / sqrt(n)
  if (n > 1) mat[, -1] <- mat[, -1] * sqrt(2 / n)
  mat
}

phash_bits <- function(img) {
  img <- resize_nearest(img, 32, 32)
  dct <- t(dct_matrix(32)) %*% img %*% dct_matrix(32)
  low <- dct[2:9, 2:9, drop = FALSE]
  low > median(low, na.rm = TRUE)
}

dhash_bits <- function(img) {
  img <- resize_nearest(img, 8, 9)
  img[, 2:9, drop = FALSE] > img[, 1:8, drop = FALSE]
}

hash_similarity <- function(bits1, bits2) {
  round(100 * (1 - mean(xor(as.logical(bits1), as.logical(bits2)), na.rm = TRUE)), 2)
}

photo_similarity <- function(path1, path2, threshold) {
  base1 <- read_grayscale(path1)
  base2 <- read_grayscale(path2)
  img1 <- resize_nearest(base1)
  img2 <- resize_nearest(base2)

  ssim <- ssim_score(img1, img2)
  phash <- hash_similarity(phash_bits(base1), phash_bits(base2))
  dhash <- hash_similarity(dhash_bits(base1), dhash_bits(base2))

  ssim_pass <- !is.na(ssim) && ssim >= threshold
  phash_pass <- !is.na(phash) && phash >= threshold
  dhash_pass <- !is.na(dhash) && dhash >= threshold
  final_match <- ssim_pass && sum(c(ssim_pass, phash_pass, dhash_pass)) >= 2
  final_score <- round(mean(c(ssim, phash, dhash), na.rm = TRUE), 2)

  list(
    score = final_score,
    ssim_score = ssim,
    phash_score = phash,
    dhash_score = dhash,
    is_match = final_match
  )
}

make_chunks <- function(row_indices, workers) {
  if (length(row_indices) == 0) return(list())
  workers <- min(max(1, as.integer(workers)), length(row_indices))
  chunk_size <- ceiling(length(row_indices) / workers)
  split(row_indices, ceiling(seq_along(row_indices) / chunk_size))
}

empty_download_log <- function() {
  data.frame(
    task_index = integer(0),
    row_index = integer(0),
    date_slot = character(0),
    status = character(0),
    path = character(0),
    photo_url = character(0),
    photo_taken_time = character(0),
    photo_uploaded_time = character(0),
    photo_taken_by = character(0),
    error = character(0),
    stringsAsFactors = FALSE
  )
}

build_photo_tasks <- function(common, district_slug_value, date1_tag, date2_tag, photo_dir1, photo_dir2) {
  if (nrow(common) == 0) return(empty_download_log())

  row_indices <- seq_len(nrow(common))
  paths1 <- vapply(row_indices, function(i) {
    photo_filename(common[i, , drop = FALSE], district_slug_value, date1_tag)
  }, character(1))
  paths2 <- vapply(row_indices, function(i) {
    photo_filename(common[i, , drop = FALSE], district_slug_value, date2_tag)
  }, character(1))

  tasks1 <- data.frame(
    task_index = seq(1, by = 2, length.out = nrow(common)),
    row_index = row_indices,
    date_slot = "date1",
    page_url = common$Url_Date1,
    output_path = file.path(photo_dir1, paths1),
    stringsAsFactors = FALSE
  )
  tasks2 <- data.frame(
    task_index = seq(2, by = 2, length.out = nrow(common)),
    row_index = row_indices,
    date_slot = "date2",
    page_url = common$Url_Date2,
    output_path = file.path(photo_dir2, paths2),
    stringsAsFactors = FALSE
  )

  tasks <- rbind(tasks1, tasks2)
  tasks[order(tasks$task_index), , drop = FALSE]
}

download_photo_task_rows <- function(row_idx, tasks) {
  messages <- character(0)
  logs <- vector("list", length(row_idx))

  for (pos in seq_along(row_idx)) {
    task <- tasks[row_idx[pos], , drop = FALSE]
    result <- download_first_photo(task$page_url, task$output_path)
    result_path <- normalizePath(result$path, winslash = "/", mustWork = FALSE)

    msg <- sprintf(
      "  row %d %s: %s - %s",
      task$row_index,
      task$date_slot,
      result$status,
      basename(result_path)
    )
    if (!is.na(result$error) && nzchar(result$error)) {
      msg <- paste0(msg, " (", result$error, ")")
    }
    messages <- c(messages, paste0(msg, "\n"))

    logs[[pos]] <- data.frame(
      task_index = task$task_index,
      row_index = task$row_index,
      date_slot = task$date_slot,
      status = result$status,
      path = result_path,
      photo_url = result$photo_url,
      photo_taken_time = result$photo_taken_time,
      photo_uploaded_time = result$photo_uploaded_time,
      photo_taken_by = result$photo_taken_by,
      error = result$error,
      stringsAsFactors = FALSE
    )
  }

  list(
    log = if (length(logs) == 0) empty_download_log() else do.call(rbind, logs),
    messages = messages
  )
}

run_parallel_downloads <- function(tasks, workers) {
  if (nrow(tasks) == 0) {
    return(list(log = empty_download_log(), messages = character(0), workers = 0))
  }

  workers <- min(max(1, as.integer(workers)), nrow(tasks))
  row_indices <- seq_len(nrow(tasks))
  chunks <- make_chunks(row_indices, workers)

  if (workers == 1) {
    worker_results <- list(download_photo_task_rows(row_indices, tasks))
  } else {
    cl <- parallel::makeCluster(workers)
    on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
    parallel::clusterCall(cl, function(paths) .libPaths(paths), .libPaths())
    parallel::clusterExport(
      cl,
      c(
        "request_user_agent",
        "safe_get",
        "response_ok",
        "valid_jpeg",
        "download_first_photo",
        "download_image_candidates",
        "extract_first_photo_url",
        "extract_text_by_id",
        "clean_metadata_value",
        "photo1_metadata_text",
        "extract_metadata_value",
        "extract_first_photo_metadata",
        "empty_photo_metadata",
        "make_absolute_url",
        "empty_download_log",
        "download_photo_task_rows"
      ),
      envir = globalenv()
    )

    worker_results <- parallel::parLapply(
      cl,
      chunks,
      function(rows, tasks) download_photo_task_rows(rows, tasks),
      tasks = tasks
    )
    parallel::stopCluster(cl)
  }

  log <- do.call(rbind, lapply(worker_results, `[[`, "log"))
  log <- log[order(log$task_index), , drop = FALSE]

  list(
    log = log,
    messages = unlist(lapply(worker_results, `[[`, "messages"), use.names = FALSE),
    workers = workers
  )
}

empty_compare_log <- function() {
  data.frame(
    row_index = integer(0),
    status = character(0),
    score = numeric(0),
    ssim_score = numeric(0),
    phash_score = numeric(0),
    dhash_score = numeric(0),
    is_match = logical(0),
    error = character(0),
    stringsAsFactors = FALSE
  )
}

compare_photo_pair_rows <- function(row_idx, results, threshold) {
  messages <- character(0)
  logs <- vector("list", length(row_idx))

  for (pos in seq_along(row_idx)) {
    i <- row_idx[pos]
    err <- NA_character_
    comparison <- tryCatch(
      photo_similarity(results$First_Photo_Path[i], results$Second_Photo_Path[i], threshold),
      error = function(e) {
        err <<- conditionMessage(e)
        NULL
      }
    )

    status <- if (is.null(comparison)) "compare_failed" else "compared"
    score <- if (is.null(comparison)) NA_real_ else comparison$score
    ssim <- if (is.null(comparison)) NA_real_ else comparison$ssim_score
    phash <- if (is.null(comparison)) NA_real_ else comparison$phash_score
    dhash <- if (is.null(comparison)) NA_real_ else comparison$dhash_score
    is_match <- if (is.null(comparison)) FALSE else comparison$is_match

    messages <- c(messages, sprintf(
      "  row %d: score=%s ssim=%s phash=%s dhash=%s match=%s\n",
      i,
      if (is.na(score)) "NA" else sprintf("%.2f", score),
      if (is.na(ssim)) "NA" else sprintf("%.2f", ssim),
      if (is.na(phash)) "NA" else sprintf("%.2f", phash),
      if (is.na(dhash)) "NA" else sprintf("%.2f", dhash),
      if (is_match) "yes" else "no"
    ))

    logs[[pos]] <- data.frame(
      row_index = i,
      status = status,
      score = score,
      ssim_score = ssim,
      phash_score = phash,
      dhash_score = dhash,
      is_match = is_match,
      error = err,
      stringsAsFactors = FALSE
    )
  }

  list(
    log = if (length(logs) == 0) empty_compare_log() else do.call(rbind, logs),
    messages = messages
  )
}

run_parallel_comparisons <- function(row_indices, results, threshold, workers) {
  if (length(row_indices) == 0) {
    return(list(log = empty_compare_log(), messages = character(0), workers = 0))
  }

  use_parallel <- workers > 1 && length(row_indices) >= max(8, workers * 2)
  workers <- if (use_parallel) min(workers, length(row_indices)) else 1
  chunks <- make_chunks(row_indices, workers)

  if (workers == 1) {
    worker_results <- list(compare_photo_pair_rows(row_indices, results, threshold))
  } else {
    cl <- parallel::makeCluster(workers)
    on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
    parallel::clusterCall(cl, function(paths) .libPaths(paths), .libPaths())
    parallel::clusterExport(
      cl,
      c(
        "read_grayscale",
        "resize_nearest",
        "ssim_score",
        "dct_matrix",
        "phash_bits",
        "dhash_bits",
        "hash_similarity",
        "photo_similarity",
        "empty_compare_log",
        "compare_photo_pair_rows"
      ),
      envir = globalenv()
    )

    worker_results <- parallel::parLapply(
      cl,
      chunks,
      function(rows, results, threshold) compare_photo_pair_rows(rows, results, threshold),
      results = results,
      threshold = threshold
    )
    parallel::stopCluster(cl)
  }

  log <- do.call(rbind, lapply(worker_results, `[[`, "log"))
  log <- log[order(log$row_index), , drop = FALSE]

  list(
    log = log,
    messages = unlist(lapply(worker_results, `[[`, "messages"), use.names = FALSE),
    workers = workers
  )
}

empty_results <- function() {
  data.frame(
    District = character(0),
    Block = character(0),
    Panchayat = character(0),
    Work_Code = character(0),
    Mustroll_No = character(0),
    First_Date = character(0),
    Second_Date = character(0),
    First_Photo_Path = character(0),
    Second_Photo_Path = character(0),
    First_Photo_URL = character(0),
    Second_Photo_URL = character(0),
    First_Photo_Taken_Time = character(0),
    First_Photo_Uploaded_Time = character(0),
    First_Photo_Taken_By = character(0),
    Second_Photo_Taken_Time = character(0),
    Second_Photo_Uploaded_Time = character(0),
    Second_Photo_Taken_By = character(0),
    Match_Score = numeric(0),
    SSIM_Score = numeric(0),
    PHash_Score = numeric(0),
    DHash_Score = numeric(0),
    Is_Match = logical(0),
    Status = character(0),
    Error = character(0),
    stringsAsFactors = FALSE
  )
}

combine_error_text <- function(...) {
  parts <- c(...)
  parts <- parts[!is.na(parts) & nzchar(parts)]
  if (length(parts) == 0) NA_character_ else paste(parts, collapse = "; ")
}

build_results_from_download_log <- function(common, download_log, date1_display, date2_display) {
  if (nrow(common) == 0) return(empty_results())

  first <- download_log[download_log$date_slot == "date1", , drop = FALSE]
  second <- download_log[download_log$date_slot == "date2", , drop = FALSE]
  first <- first[match(seq_len(nrow(common)), first$row_index), , drop = FALSE]
  second <- second[match(seq_len(nrow(common)), second$row_index), , drop = FALSE]

  first_ok <- !is.na(first$status) & first$status %in% c("saved", "already_saved")
  second_ok <- !is.na(second$status) & second$status %in% c("saved", "already_saved")

  errors <- vapply(seq_len(nrow(common)), function(i) {
    combine_error_text(first$error[i], second$error[i])
  }, character(1))

  data.frame(
    District = common$District,
    Block = common$Block,
    Panchayat = common$Panchayat,
    Work_Code = common$Work_Code,
    Mustroll_No = common$Mustroll_No,
    First_Date = date1_display,
    Second_Date = date2_display,
    First_Photo_Path = first$path,
    Second_Photo_Path = second$path,
    First_Photo_URL = first$photo_url,
    Second_Photo_URL = second$photo_url,
    First_Photo_Taken_Time = first$photo_taken_time,
    First_Photo_Uploaded_Time = first$photo_uploaded_time,
    First_Photo_Taken_By = first$photo_taken_by,
    Second_Photo_Taken_Time = second$photo_taken_time,
    Second_Photo_Uploaded_Time = second$photo_uploaded_time,
    Second_Photo_Taken_By = second$photo_taken_by,
    Match_Score = NA_real_,
    SSIM_Score = NA_real_,
    PHash_Score = NA_real_,
    DHash_Score = NA_real_,
    Is_Match = FALSE,
    Status = ifelse(first_ok & second_ok, "pending_compare", "download_failed"),
    Error = errors,
    stringsAsFactors = FALSE
  )
}

apply_compare_log <- function(results, compare_log) {
  if (nrow(compare_log) == 0) return(results)

  for (i in seq_len(nrow(compare_log))) {
    row_index <- compare_log$row_index[i]
    results$Match_Score[row_index] <- compare_log$score[i]
    results$SSIM_Score[row_index] <- compare_log$ssim_score[i]
    results$PHash_Score[row_index] <- compare_log$phash_score[i]
    results$DHash_Score[row_index] <- compare_log$dhash_score[i]
    results$Is_Match[row_index] <- compare_log$is_match[i]
    results$Status[row_index] <- compare_log$status[i]
    if (!is.na(compare_log$error[i]) && nzchar(compare_log$error[i])) {
      results$Error[row_index] <- combine_error_text(results$Error[row_index], compare_log$error[i])
    }
  }

  results
}

make_requested_columns <- function(results, thumbnail_labels = FALSE) {
  first_photo <- if (thumbnail_labels) "" else results$First_Photo_Path
  second_photo <- if (thumbnail_labels) "" else results$Second_Photo_Path

  data.frame(
    "District Name" = results$District,
    "Block Name" = results$Block,
    "Panchayat Name" = results$Panchayat,
    "Work Code" = results$Work_Code,
    "Muster Roll" = results$Mustroll_No,
    "First Date" = results$First_Date,
    "Second Date" = results$Second_Date,
    "First Date Photo" = first_photo,
    "Second Date Photo" = second_photo,
    "Match Score" = results$Match_Score,
    "SSIM Score" = results$SSIM_Score,
    "PHash Score" = results$PHash_Score,
    "DHash Score" = results$DHash_Score,
    "First Date Photo Taken Time" = results$First_Photo_Taken_Time,
    "First Date Photo Uploaded Time" = results$First_Photo_Uploaded_Time,
    "First Date Photo Taken By" = results$First_Photo_Taken_By,
    "Second Date Photo Taken Time" = results$Second_Photo_Taken_Time,
    "Second Date Photo Uploaded Time" = results$Second_Photo_Uploaded_Time,
    "Second Date Photo Taken By" = results$Second_Photo_Taken_By,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

append_file_name_columns <- function(sheet, results) {
  sheet$"First Date Photo File" <- basename(results$First_Photo_Path)
  sheet$"Second Date Photo File" <- basename(results$Second_Photo_Path)
  sheet
}

write_photo_match_workbook <- function(results, workbook_path) {
  wb <- openxlsx::createWorkbook()
  header_style <- openxlsx::createStyle(textDecoration = "bold", fgFill = "#D9EAF7")

  matches <- results[results$Status == "compared" & !is.na(results$Is_Match) & results$Is_Match, , drop = FALSE]
  matches_sheet <- make_requested_columns(matches, thumbnail_labels = TRUE)
  matches_sheet <- append_file_name_columns(matches_sheet, matches)

  openxlsx::addWorksheet(wb, "Matches")
  openxlsx::writeData(wb, "Matches", matches_sheet)
  if (ncol(matches_sheet) > 0) {
    openxlsx::addStyle(wb, "Matches", header_style, rows = 1, cols = seq_len(ncol(matches_sheet)), gridExpand = TRUE)
    openxlsx::setColWidths(wb, "Matches", cols = seq_len(ncol(matches_sheet)), widths = "auto")
    openxlsx::setColWidths(wb, "Matches", cols = c(8, 9), widths = 22)
    openxlsx::freezePane(wb, "Matches", firstActiveRow = 2)
  }

  if (nrow(matches) > 0) {
    openxlsx::setRowHeights(wb, "Matches", rows = 2:(nrow(matches) + 1), heights = 82)
    for (i in seq_len(nrow(matches))) {
      row_num <- i + 1
      if (file.exists(matches$First_Photo_Path[i])) {
        openxlsx::insertImage(
          wb,
          "Matches",
          matches$First_Photo_Path[i],
          startCol = 8,
          startRow = row_num,
          width = 1.05,
          height = 1.05
        )
      }
      if (file.exists(matches$Second_Photo_Path[i])) {
        openxlsx::insertImage(
          wb,
          "Matches",
          matches$Second_Photo_Path[i],
          startCol = 9,
          startRow = row_num,
          width = 1.05,
          height = 1.05
        )
      }
    }
  }

  audit_sheet <- make_requested_columns(results, thumbnail_labels = FALSE)
  audit_sheet$"Final Match" <- results$Is_Match
  audit_sheet$"Status" <- results$Status
  audit_sheet$"First Photo URL" <- results$First_Photo_URL
  audit_sheet$"Second Photo URL" <- results$Second_Photo_URL
  audit_sheet$"Error" <- results$Error
  audit_sheet <- append_file_name_columns(audit_sheet, results)

  openxlsx::addWorksheet(wb, "All_Compared")
  openxlsx::writeData(wb, "All_Compared", audit_sheet)
  if (ncol(audit_sheet) > 0) {
    openxlsx::addStyle(wb, "All_Compared", header_style, rows = 1, cols = seq_len(ncol(audit_sheet)), gridExpand = TRUE)
    openxlsx::setColWidths(wb, "All_Compared", cols = seq_len(ncol(audit_sheet)), widths = "auto")
    openxlsx::freezePane(wb, "All_Compared", firstActiveRow = 2)
  }

  dir.create(dirname(workbook_path), showWarnings = FALSE, recursive = TRUE)
  openxlsx::saveWorkbook(wb, workbook_path, overwrite = TRUE)
}

district <- canonicalize_district(opts$district)
district_slug_value <- district_slug(district)
date1 <- parse_input_date(opts$date1, "--date1")
date2 <- parse_input_date(opts$date2, "--date2")
threshold <- as_threshold(opts$threshold)
workers <- 4

if (date1$date == date2$date) {
  stop("--date1 and --date2 must be different dates.", call. = FALSE)
}

validate_photo_match_date(date1, "--date1")
validate_photo_match_date(date2, "--date2")

run_dir <- file.path(script_dir, paste0(district_slug_value, "_", date1$tag, "_", date2$tag))
photo_dir1 <- file.path(run_dir, "photos", date1$tag)
photo_dir2 <- file.path(run_dir, "photos", date2$tag)
dir.create(photo_dir1, recursive = TRUE, showWarnings = FALSE)
dir.create(photo_dir2, recursive = TRUE, showWarnings = FALSE)

cat("=== PhotoMatch ===\n")
cat("District: ", district, "\n", sep = "")
cat("Date 1:   ", date1$display, "\n", sep = "")
cat("Date 2:   ", date2$display, "\n", sep = "")
cat("Threshold:", threshold, "\n")
cat("Workers:  ", workers, "\n", sep = "")
cat("Output:   ", run_dir, "\n\n", sep = "")

cat("[1/6] Scraping first date...\n")
result1 <- scrape_up_data(
  district,
  date1$dd,
  date1$mm,
  date1$yyyy,
  scrape_musters = FALSE,
  progress_callback = function(val, msg) cat("  ", msg, "\n", sep = "")
)
if (!result1$success) stop("First-date scrape failed: ", result1$error, call. = FALSE)
cat("  Found ", nrow(result1$data), " muster roll(s)\n\n", sep = "")

cat("[2/6] Scraping second date...\n")
result2 <- scrape_up_data(
  district,
  date2$dd,
  date2$mm,
  date2$yyyy,
  scrape_musters = FALSE,
  progress_callback = function(val, msg) cat("  ", msg, "\n", sep = "")
)
if (!result2$success) stop("Second-date scrape failed: ", result2$error, call. = FALSE)
cat("  Found ", nrow(result2$data), " muster roll(s)\n\n", sep = "")

common <- find_common_musters(result1$data, result2$data)
cat("[3/6] Common muster rolls: ", nrow(common), "\n\n", sep = "")

tasks <- build_photo_tasks(
  common,
  district_slug_value,
  date1$tag,
  date2$tag,
  photo_dir1,
  photo_dir2
)

download_workers <- if (nrow(tasks) == 0) 0 else min(workers, nrow(tasks))
cat("[4/6] Downloading ", nrow(tasks), " first-photo task(s) with ", download_workers, " worker(s)...\n", sep = "")
download_result <- run_parallel_downloads(tasks, workers)
if (length(download_result$messages) > 0) cat(download_result$messages, sep = "")

results <- build_results_from_download_log(common, download_result$log, date1$display, date2$display)
ready_rows <- which(results$Status == "pending_compare")

cat("\n[5/6] Comparing ", length(ready_rows), " photo pair(s)", sep = "")
if (length(ready_rows) > 0) {
  compare_workers <- if (workers > 1 && length(ready_rows) >= max(8, workers * 2)) {
    min(workers, length(ready_rows))
  } else {
    1
  }
  cat(" with ", compare_workers, " worker(s)", sep = "")
}
cat("...\n")

compare_result <- run_parallel_comparisons(ready_rows, results, threshold, workers)
if (length(compare_result$messages) > 0) cat(compare_result$messages, sep = "")
results <- apply_compare_log(results, compare_result$log)

workbook_path <- file.path(
  run_dir,
  paste0("photo_match_", district_slug_value, "_", date1$tag, "_", date2$tag, ".xlsx")
)

cat("\n[6/6] Writing workbook...\n")
write_photo_match_workbook(results, workbook_path)

cat("\n=== Done ===\n")
cat("Compared: ", sum(results$Status == "compared", na.rm = TRUE), "\n", sep = "")
cat("Matches:  ", sum(results$Status == "compared" & results$Is_Match, na.rm = TRUE), "\n", sep = "")
cat("Failed:   ", sum(results$Status %in% c("download_failed", "compare_failed"), na.rm = TRUE), "\n", sep = "")
cat("Workbook: ", workbook_path, "\n", sep = "")
