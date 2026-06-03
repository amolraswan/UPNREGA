# PhotoMatch

Standalone R analysis for comparing first NMMS group photos for common muster
rolls across two dates.

## Install Dependencies

Run once before using the analysis:

```sh
Rscript PhotoMatch/install_dependencies.R
```

## Run

Set these values at the top of `PhotoMatch/photo_match.R`:

```r
district_name <- ""
first_date <- ""  # DD/MM/YYYY
second_date <- ""  # DD/MM/YYYY
match_threshold <- 85
```

Then run:

```sh
Rscript PhotoMatch/photo_match.R
```

Command-line values can also be supplied:

```sh
Rscript PhotoMatch/photo_match.R \
  --district "<DISTRICT>" \
  --date1 <DD/MM/YYYY> \
  --date2 <DD/MM/YYYY> \
  --threshold 85
```

Dates can be supplied as `DD/MM/YYYY`, `DD-MM-YYYY`, or `DDMMYYYY`.
Photo downloads and comparisons use an internal 4-worker setup.
The comparison crops out the bottom text area, then checks structural similarity
and two perceptual image hashes. A final match requires structural similarity
and at least one hash score to meet the threshold.

## Output

Results are written under:

```text
PhotoMatch/<DISTRICT>_<DATE1>_<DATE2>/
```

The workflow saves first-photo JPEGs under `photos/<DATE>/` and writes an Excel
file named:

```text
photo_match_<DISTRICT>_<DATE1>_<DATE2>.xlsx
```

The `Matches` sheet contains only final matches and embeds the two photo
thumbnails. The `All_Compared` sheet keeps every common muster roll, including
local photo paths, source photo URLs, statuses, component scores, photo taken
time, photo uploaded time, taken-by names, and the final match decision. Both
sheets keep the separate first-date and second-date photo filenames at the far
right.

Dependencies installed by `install_dependencies.R` are kept in
the normal global R package library by default. If `PhotoMatch/library/` exists,
the analysis script will also search it before global package locations.
