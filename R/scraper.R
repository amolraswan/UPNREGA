library(httr)
library(rvest)
library(xml2)
library(dplyr)
library(curl)

NREGA_HOME_URL <- "https://nrega.dord.gov.in/MGNREGA_new/Nrega_home.aspx"
NREGA_PORTAL_ORIGIN <- "https://mnregaweb4.dord.gov.in"
BASE_URL <- paste0(NREGA_PORTAL_ORIGIN, "/netnrega/")

UA_STRING <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
UA <- user_agent(UA_STRING)
PORTAL_HEADERS <- add_headers(
  "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
  "Accept-Language" = "en-US,en;q=0.9",
  "Upgrade-Insecure-Requests" = "1"
)

UP_DISTRICTS <- c(
  "AGRA", "ALIGARH", "AMBEDKAR NAGAR", "AMETHI", "AMROHA",
  "AURAIYA", "AYODHYA", "AZAMGARH", "BAGHPAT", "BAHRAICH",
  "BALLIA", "BALRAMPUR", "BANDA", "BARABANKI", "BAREILLY",
  "BASTI", "BIJNOR", "BUDAUN", "BULANDSHAHR", "CHANDAULI",
  "CHITRAKOOT", "DEORIA", "ETAH", "ETAWAH", "FARRUKHABAD",
  "FATEHPUR", "FIROZABAD", "GHAZIPUR", "GONDA", "GORAKHPUR",
  "HAMIRPUR", "HAPUR", "HARDOI", "HATHRAS", "JALAUN", "JAUNPUR",
  "JHANSI", "KANNAUJ", "KANPUR DEHAT", "KANPUR NAGAR",
  "KASHGANJ", "KAUSHAMBI", "KHERI", "KUSHI NAGAR", "LALITPUR",
  "LUCKNOW", "MAHARAJGANJ", "MAHOBA", "MAINPURI", "MATHURA",
  "MAU", "MEERUT", "MIRZAPUR", "MORADABAD", "MUZAFFARNAGAR",
  "PILIBHIT", "PRATAPGARH", "PRAYAGRAJ", "RAE BARELI", "RAMPUR",
  "SAHARANPUR", "SAMBHAL", "SANT KABEER NAGAR",
  "SANT RAVIDAS NAGAR", "SHAHJAHANPUR", "SHAMLI", "SHRAVASTI",
  "SIDDHARTH NAGAR", "SITAPUR", "SONBHADRA", "SULTANPUR",
  "UNNAO", "VARANASI"
)

DISTRICT_MATCH_ALIASES <- list(
  "AMROHA" = c("JYOTIBA PHULE NAGAR", "J P NAGAR", "JP NAGAR"),
  "AYODHYA" = "FAIZABAD",
  "HAPUR" = "PANCHSHEEL NAGAR",
  "KASHGANJ" = "KASGANJ",
  "KUSHI NAGAR" = "KUSHINAGAR",
  "PRAYAGRAJ" = "ALLAHABAD",
  "RAE BARELI" = c("RAEBARELI", "RAIBAREILLY", "RAEBAREILLY"),
  "SANT KABEER NAGAR" = "SANT KABIR NAGAR",
  "SANT RAVIDAS NAGAR" = "BHADOHI"
)

normalize_district_text <- function(x) {
  x <- URLdecode(as.character(x))
  x <- toupper(trimws(x))
  x <- gsub("[[:space:]_+-]+", " ", x)
  x <- gsub("[^A-Z0-9 ]", " ", x)
  gsub("\\s+", " ", trimws(x))
}

canonicalize_district <- function(district) {
  if (length(district) != 1 || is.na(district) || !nzchar(trimws(district))) {
    stop("Please choose a district.", call. = FALSE)
  }

  district_key <- normalize_district_text(district)
  district_keys <- normalize_district_text(UP_DISTRICTS)
  idx <- match(district_key, district_keys)
  if (is.na(idx)) {
    stop("Unknown UP district: ", district, call. = FALSE)
  }

  UP_DISTRICTS[idx]
}

validate_district <- function(district) {
  tryCatch({
    canonicalize_district(district)
    NULL
  }, error = function(e) e$message)
}

district_slug <- function(district) {
  district <- canonicalize_district(district)
  slug <- gsub("[^A-Z0-9]+", "_", district)
  gsub("^_|_$", "", slug)
}

district_match_terms <- function(district) {
  district <- canonicalize_district(district)
  unique(normalize_district_text(c(district, DISTRICT_MATCH_ALIASES[[district]])))
}

contains_normalized_term <- function(haystack, term) {
  pattern <- paste0("(^| )", gsub(" ", "\\\\s+", term), "($| )")
  grepl(pattern, haystack)
}

is_nonempty_string <- function(x) {
  length(x) == 1 && !is.na(x) && nzchar(trimws(x))
}

normalize_portal_href <- function(href) {
  if (!is_nonempty_string(href)) return(NA_character_)

  href <- trimws(href)
  href <- gsub("&amp;", "&", href, fixed = TRUE)
  href <- gsub("&amp", "&", href, fixed = TRUE)
  href <- gsub("&+", "&", href)
  href <- sub("^http://", "https://", href)
  gsub(" ", "%20", href, fixed = TRUE)
}

absolute_portal_url <- function(href, base_url) {
  href <- normalize_portal_href(href)
  if (!is_nonempty_string(href)) return(NA_character_)
  if (grepl("^https?://", href)) return(href)
  xml2::url_absolute(href, base_url)
}

portal_get <- function(url, handle, referer = NULL, timeout_seconds = 60) {
  configs <- list(UA, PORTAL_HEADERS, timeout(timeout_seconds))
  if (is_nonempty_string(referer)) {
    configs <- c(configs, list(add_headers("Referer" = referer)))
  }

  tryCatch(
    do.call(GET, c(list(url = url, handle = handle), configs)),
    error = function(e) NULL
  )
}

portal_post <- function(url, handle, body, referer = NULL, timeout_seconds = 60) {
  configs <- list(UA, PORTAL_HEADERS, timeout(timeout_seconds))
  if (is_nonempty_string(referer)) {
    configs <- c(configs, list(add_headers("Referer" = referer)))
  }

  tryCatch(
    do.call(POST, c(
      list(url = url, handle = handle, body = body, encode = "form"),
      configs
    )),
    error = function(e) NULL
  )
}

response_text <- function(resp) {
  content(resp, "text", encoding = "UTF-8")
}

is_access_denied_html <- function(html_text) {
  grepl("Access Denied", html_text, fixed = TRUE) &&
    grepl("cannot access this page", html_text, fixed = TRUE)
}

clean_cell_text <- function(x) {
  trimws(gsub("\\s+", " ", html_text2(x)))
}

safe_number <- function(x) {
  x <- gsub(",", "", trimws(as.character(x)))
  suppressWarnings(as.numeric(x))
}

find_district_href <- function(state_html, district) {
  terms <- district_match_terms(district)
  district_nodes <- html_nodes(state_html, "a")

  for (node in district_nodes) {
    href <- html_attr(node, "href")
    if (is.na(href) ||
        !grepl("NMMS_DailyAttendance.aspx", href, fixed = TRUE) ||
        !grepl("page=D", href, fixed = TRUE) ||
        grepl("Summary", href, fixed = TRUE)) {
      next
    }

    candidate_text <- normalize_district_text(paste(href, html_text2(node)))
    if (any(vapply(terms, contains_normalized_term,
                   logical(1), haystack = candidate_text))) {
      return(href)
    }
  }

  NULL
}

get_financial_year <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  if (m >= 4) {
    paste0(y, "-", y + 1)
  } else {
    paste0(y - 1, "-", y)
  }
}

extract_asp_fields <- function(html) {
  form <- html_node(html, "form#aspnetForm")
  if (is.na(form)) form <- html_node(html, "form")
  fields <- list()
  for (inp in html_nodes(form, "input[type='hidden']")) {
    nm  <- html_attr(inp, "name")
    val <- html_attr(inp, "value")
    if (!is.na(nm)) fields[[nm]] <- if (is.na(val)) "" else val
  }
  for (sel in html_nodes(form, "select")) {
    nm <- html_attr(sel, "name")
    if (is.na(nm)) next
    opt <- html_node(sel, "option[selected]")
    if (is.na(opt)) opt <- html_node(sel, "option")
    if (!is.na(opt)) {
      val <- html_attr(opt, "value")
      fields[[nm]] <- if (is.na(val)) "" else val
    }
  }
  fields
}

extract_form_action <- function(html, base_url) {
  form <- html_node(html, "form#aspnetForm")
  if (is.na(form)) form <- html_node(html, "form")
  action <- html_attr(form, "action")
  if (is.na(action) || !nzchar(action)) return(base_url)
  absolute_portal_url(action, base_url)
}

validate_date <- function(dd, mm, yyyy) {
  tryCatch({
    d <- as.Date(paste(yyyy, mm, dd, sep = "-"))
    if (is.na(d)) return("Invalid date.")
    if (d > Sys.Date()) return("Date is in the future.")
    if (as.numeric(Sys.Date() - d) > 14) return("Date must be within the past 14 days.")
    return(NULL)
  }, error = function(e) "Invalid date.")
}

save_data <- function(df, district, dd, mm, yyyy) {
  dir.create("data", showWarnings = FALSE, recursive = TRUE)
  dist_slug <- district_slug(district)
  fname <- file.path("data", paste0("data_", dist_slug, "_", dd, mm, yyyy, ".csv"))
  write.csv(df, fname, row.names = FALSE)
  fname
}

empty_muster_records <- function() {
  data.frame(
    District = character(0),
    Block = character(0),
    Panchayat = character(0),
    Work_Code = character(0),
    Mustroll_No = character(0),
    Mustroll_Link = character(0),
    Mustroll_Referer = character(0),
    Persondays = numeric(0),
    stringsAsFactors = FALSE
  )
}

table_data_rows <- function(html) {
  tbl <- html_element(html, "table.table-bordered")
  if (is.na(tbl)) return(list())

  rows <- html_elements(tbl, "tr")
  if (length(rows) <= 2) return(list())
  as.list(rows[-(1:2)])
}

is_total_row <- function(tds) {
  if (length(tds) == 0) return(TRUE)
  any(toupper(vapply(tds, clean_cell_text, character(1))) == "TOTAL")
}

href_matches <- function(hrefs, include, exclude = character(0)) {
  ok <- !is.na(hrefs)
  for (pattern in include) {
    ok <- ok & grepl(pattern, hrefs, fixed = TRUE)
  }
  for (pattern in exclude) {
    ok <- ok & !grepl(pattern, hrefs, fixed = TRUE)
  }
  ok
}

extract_table_links <- function(html, page_url, include, exclude = character(0),
                                name_col = 2) {
  records <- lapply(table_data_rows(html), function(row) {
    tds <- html_elements(row, "td")
    if (length(tds) < name_col || is_total_row(tds)) return(NULL)

    anchors <- html_elements(row, "a")
    hrefs <- html_attr(anchors, "href")
    keep <- which(href_matches(hrefs, include, exclude))
    if (length(keep) == 0) return(NULL)

    data.frame(
      Name = clean_cell_text(tds[name_col]),
      URL = absolute_portal_url(hrefs[keep[1]], page_url),
      stringsAsFactors = FALSE
    )
  })

  records <- records[!vapply(records, is.null, logical(1))]
  if (length(records) == 0) {
    return(data.frame(Name = character(0), URL = character(0),
                      stringsAsFactors = FALSE))
  }
  bind_rows(records)
}

parse_muster_summary_page <- function(summary_html, summary_url) {
  records <- lapply(table_data_rows(summary_html), function(row) {
    tds <- html_elements(row, "td")
    if (length(tds) < 7 || is_total_row(tds)) return(NULL)

    link_node <- html_element(tds[6], "a")
    if (is.na(link_node)) {
      link_node <- html_element(row, xpath = ".//a[contains(@href, 'NMMS_DailyAttendance_Summary_Details.aspx')]")
    }

    mustroll_href <- if (!is.na(link_node)) html_attr(link_node, "href") else NA_character_
    mustroll_link <- if (is_nonempty_string(mustroll_href)) {
      absolute_portal_url(mustroll_href, summary_url)
    } else {
      NA_character_
    }

    data.frame(
      District = clean_cell_text(tds[2]),
      Block = clean_cell_text(tds[3]),
      Panchayat = clean_cell_text(tds[4]),
      Work_Code = clean_cell_text(tds[5]),
      Mustroll_No = clean_cell_text(tds[6]),
      Mustroll_Link = mustroll_link,
      Mustroll_Referer = summary_url,
      Persondays = safe_number(clean_cell_text(tds[7])),
      stringsAsFactors = FALSE
    )
  })

  records <- records[!vapply(records, is.null, logical(1))]
  if (length(records) == 0) return(empty_muster_records())
  bind_rows(records)
}

extract_work_name <- function(html) {
  detail_node <- html_node(
    html,
    xpath = "//*[@id='ContentPlaceHolder1_lbl_dtl' or contains(@id, '_lbl_dtl')]"
  )

  detail_text <- if (!is.na(detail_node)) html_text2(detail_node) else html_text2(html)
  if (!grepl("Work\\s+Name\\s*:", detail_text, ignore.case = TRUE, perl = TRUE)) {
    return(NA_character_)
  }

  work_name <- sub("(?is).*Work\\s+Name\\s*:\\s*", "", detail_text, perl = TRUE)
  work_name <- sub("(?is)\\s+S\\.?\\s*No\\.?\\b.*$", "", work_name, perl = TRUE)
  work_name <- trimws(gsub("\\s+", " ", work_name))
  if (nzchar(work_name)) work_name else NA_character_
}

set_portal_curl_headers <- function(handle, referer = NULL) {
  headers <- c(
    "User-Agent" = UA_STRING,
    "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language" = "en-US,en;q=0.9"
  )
  if (is_nonempty_string(referer)) {
    headers["Referer"] <- referer
  }
  do.call(handle_setheaders, c(list(handle = handle), as.list(headers)))
}

fetch_muster_summary_pages <- function(summary_tasks, progress_callback = NULL) {
  n <- nrow(summary_tasks)
  if (n == 0) return(empty_muster_records())

  batch_size <- 20
  total_batches <- ceiling(n / batch_size)
  record_batches <- list()

  for (b in seq_len(total_batches)) {
    idx_start <- (b - 1) * batch_size + 1
    idx_end <- min(b * batch_size, n)
    batch_idx <- idx_start:idx_end

    pool <- new_pool(total_con = 20, host_con = 20)

    for (i in batch_idx) {
      summary_url <- summary_tasks$URL[i]
      referer <- summary_tasks$Referer[i]
      if (!is_nonempty_string(summary_url)) next

      local({
        ii <- i
        url <- summary_url
        ref <- referer
        h <- new_handle()
        set_portal_curl_headers(h, ref)
        handle_setopt(h, timeout = 60)

        curl_fetch_multi(url, done = function(resp) {
          tryCatch({
            summary_text <- rawToChar(resp$content)
            if (is_access_denied_html(summary_text)) return(NULL)

            summary_html <- read_html(summary_text)
            records <- parse_muster_summary_page(summary_html, url)
            if (nrow(records) > 0) {
              record_batches[[as.character(ii)]] <<- records
            }
          }, error = function(e) {
            # leave this summary page out on parse errors
          })
        }, fail = function(msg) {
          # leave this summary page out on network errors
        }, pool = pool, handle = h)
      })
    }

    multi_run(pool = pool)

    if (!is.null(progress_callback)) {
      progress_callback(b, total_batches)
    }
  }

  if (length(record_batches) == 0) return(empty_muster_records())
  record_batches <- record_batches[order(as.integer(names(record_batches)))]
  bind_rows(record_batches)
}

scrape_muster_details <- function(df, progress_callback = NULL) {
  n <- nrow(df)
  batch_size <- 20
  total_batches <- ceiling(n / batch_size)

  work_names <- rep(NA_character_, n)

  for (b in seq_len(total_batches)) {
    idx_start <- (b - 1) * batch_size + 1
    idx_end <- min(b * batch_size, n)
    batch_idx <- idx_start:idx_end

    pool <- new_pool(total_con = 20, host_con = 20)

    for (i in batch_idx) {
      url <- df$Mustroll_Link[i]
      if (is.na(url) || url == "") next
      referer <- if ("Mustroll_Referer" %in% names(df)) df$Mustroll_Referer[i] else NA_character_

      local({
        ii <- i
        ref <- referer
        h <- new_handle()
        set_portal_curl_headers(h, ref)
        handle_setopt(h, timeout = 30)

        curl_fetch_multi(url, done = function(resp) {
          tryCatch({
            html <- read_html(rawToChar(resp$content))
            work_names[ii] <<- extract_work_name(html)
          }, error = function(e) {
            # leave as NA on parse error
          })
        }, fail = function(msg) {
          # leave as NA on network error
        }, pool = pool, handle = h)
      })
    }

    multi_run(pool = pool)

    if (!is.null(progress_callback)) {
      progress_callback(b, total_batches)
    }
  }

  df$Work_Name <- work_names
  df
}

scrape_up_data <- function(district, dd, mm, yyyy, scrape_musters = FALSE, progress_callback = NULL) {

  notify <- function(val, msg) {
    if (!is.null(progress_callback)) progress_callback(val, msg)
  }

  district <- canonicalize_district(district)

  date_str <- paste0(
    sprintf("%02d", as.integer(dd)), "/",
    sprintf("%02d", as.integer(mm)), "/",
    yyyy
  )

  h <- handle(NREGA_PORTAL_ORIGIN)

  # ---- Step 1: Get NMMS link from homepage ----
  notify(0.05, "Fetching NREGA homepage...")
  home_resp <- tryCatch(
    GET(NREGA_HOME_URL, UA, PORTAL_HEADERS, timeout(60)),
    error = function(e) NULL
  )
  if (is.null(home_resp) || status_code(home_resp) != 200) {
    return(list(success = FALSE, error = "Could not reach NREGA homepage."))
  }

  home_html <- read_html(response_text(home_resp))
  att_node <- html_node(
    home_html,
    xpath = "//a[contains(translate(normalize-space(.), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'view daily attendance')]"
  )
  if (is.na(att_node)) {
    return(list(success = FALSE, error = "Could not find the NMMS attendance link on the homepage."))
  }
  nmms_url <- normalize_portal_href(html_attr(att_node, "href"))
  if (!is_nonempty_string(nmms_url)) {
    return(list(success = FALSE, error = "The NMMS attendance link on the homepage was empty."))
  }
  notify(0.10, "Found NMMS attendance link.")

  # ---- Step 2: GET the NMMS attendance page ----
  notify(0.15, "Loading attendance page...")
  page_resp <- portal_get(nmms_url, h, referer = NREGA_HOME_URL, timeout_seconds = 60)
  if (is.null(page_resp) || status_code(page_resp) != 200) {
    return(list(success = FALSE, error = "Could not load the NMMS attendance page."))
  }
  page_text <- response_text(page_resp)
  if (is_access_denied_html(page_text)) {
    return(list(success = FALSE, error = "The NMMS attendance page returned Access Denied."))
  }
  page_html <- read_html(page_text)
  if (length(html_nodes(page_html, "form")) == 0) {
    return(list(success = FALSE, error = "The NMMS attendance page did not contain the expected form."))
  }
  post_url  <- extract_form_action(page_html, nmms_url)
  fields    <- extract_asp_fields(page_html)

  # Override state and date, then submit directly — both dropdowns are already
  # populated on the initial page, so intermediate PostBacks are not needed.
  fields[["ctl00$ContentPlaceHolder1$ddlstate"]]       <- "31"
  fields[["ctl00$ContentPlaceHolder1$ddl_attendance"]] <- date_str
  fields[["__EVENTTARGET"]]   <- ""
  fields[["__EVENTARGUMENT"]] <- ""

  notify(0.35, paste0("Submitting form for ", date_str, "..."))
  post3_resp <- portal_post(
    post_url,
    h,
    body = c(fields, list(
      `ctl00$ContentPlaceHolder1$btn_showreport` = "Show Attendance"
    )),
    referer = nmms_url,
    timeout_seconds = 120
  )
  if (is.null(post3_resp) || status_code(post3_resp) != 200) {
    return(list(success = FALSE, error = "Failed to submit the attendance form."))
  }
  page4_text <- response_text(post3_resp)
  if (is_access_denied_html(page4_text)) {
    return(list(success = FALSE, error = "The attendance form response returned Access Denied."))
  }
  page4_html <- read_html(page4_text)

  # ---- Step 3: Find UTTAR PRADESH link ----
  notify(0.55, "Finding UTTAR PRADESH link...")
  up_node <- html_node(page4_html, xpath = "//a[contains(text(), 'UTTAR PRADESH')]")
  if (is.na(up_node)) {
    return(list(success = FALSE, error = "UTTAR PRADESH link not found in results. The date may not have data."))
  }
  up_href <- html_attr(up_node, "href")
  up_url <- absolute_portal_url(up_href, post_url)

  # ---- Step 4: GET state page, find district detail link ----
  notify(0.65, "Loading state page...")
  state_resp <- portal_get(up_url, h, referer = post_url, timeout_seconds = 120)
  if (is.null(state_resp) || status_code(state_resp) != 200) {
    return(list(success = FALSE, error = "Could not load the UTTAR PRADESH state page."))
  }
  state_text <- response_text(state_resp)
  if (is_access_denied_html(state_text)) {
    return(list(success = FALSE, error = "The UTTAR PRADESH state page returned Access Denied."))
  }
  state_html <- read_html(state_text)

  notify(0.70, paste0("Finding ", district, " link..."))
  district_href <- find_district_href(state_html, district)
  if (is.null(district_href)) {
    return(list(success = FALSE, error = paste0(district, " district link not found on the state page.")))
  }
  district_url <- absolute_portal_url(district_href, up_url)
  notify(0.75, paste0("Found ", district, " link. Loading block list..."))

  # ---- Step 5: GET district page, then walk blocks and panchayat summaries ----
  district_resp <- portal_get(district_url, h, referer = up_url, timeout_seconds = 120)
  if (is.null(district_resp) || status_code(district_resp) != 200) {
    return(list(success = FALSE, error = paste0("Could not load the ", district, " block page.")))
  }
  district_text <- response_text(district_resp)
  if (is_access_denied_html(district_text)) {
    return(list(success = FALSE, error = paste0("The ", district, " block page returned Access Denied.")))
  }
  district_html <- read_html(district_text)

  block_links <- extract_table_links(
    district_html,
    district_url,
    include = c("NMMS_DailyAttendance.aspx", "page=B"),
    exclude = "Summary"
  )
  if (nrow(block_links) == 0) {
    return(list(success = FALSE, error = paste0("No block links found on the ", district, " page.")))
  }

  summary_tasks <- list()
  for (i in seq_len(nrow(block_links))) {
    block_url <- block_links$URL[i]
    block_resp <- portal_get(block_url, h, referer = district_url, timeout_seconds = 120)
    if (!is.null(block_resp) && status_code(block_resp) == 200) {
      block_text <- response_text(block_resp)
      if (!is_access_denied_html(block_text)) {
        block_html <- read_html(block_text)
        links <- extract_table_links(
          block_html,
          block_url,
          include = "NMMS_DailyAttendance_Summary.aspx"
        )
        if (nrow(links) > 0) {
          links$Referer <- block_url
          summary_tasks[[length(summary_tasks) + 1]] <- links
        }
      }
    }

    frac <- 0.75 + 0.07 * (i / nrow(block_links))
    notify(frac, paste0("Fetching panchayat summary links... block ", i, "/", nrow(block_links)))
  }

  summary_tasks <- if (length(summary_tasks) == 0) {
    data.frame(Name = character(0), URL = character(0), Referer = character(0),
               stringsAsFactors = FALSE)
  } else {
    bind_rows(summary_tasks)
  }
  if (nrow(summary_tasks) == 0) {
    return(list(success = FALSE, error = paste0("No panchayat summary links found for ", district, ".")))
  }

  df <- fetch_muster_summary_pages(summary_tasks, progress_callback = function(batch_done, total_batches) {
    frac <- 0.82 + 0.08 * (batch_done / total_batches)
    notify(frac, paste0("Fetching muster roll summary pages... batch ", batch_done, "/", total_batches))
  })
  if (nrow(df) == 0) {
    return(list(success = FALSE, error = "Parsed table was empty."))
  }

  if (scrape_musters) {
    notify(0.90, "Fetching muster roll details (work names)...")
    df <- scrape_muster_details(df, progress_callback = function(batch_done, total_batches) {
      frac <- 0.90 + 0.09 * (batch_done / total_batches)
      notify(frac, paste0("Fetching muster details... batch ", batch_done, "/", total_batches))
    })
  } else {
    df$Work_Name <- NA_character_
  }

  notify(1.0, paste0("Done! ", nrow(df), " rows scraped."))
  list(success = TRUE, data = df)
}

scrape_basti_data <- function(dd, mm, yyyy, scrape_musters = FALSE, progress_callback = NULL) {
  scrape_up_data("BASTI", dd, mm, yyyy, scrape_musters, progress_callback)
}
