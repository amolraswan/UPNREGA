# UPNREGA

Windows desktop app and R workflow for downloading Uttar Pradesh NREGA muster
roll PDFs.

## Desktop app

The Windows app is a C# WinForms launcher around the existing R scraper and PDF
downloader. End users install one Windows package, choose a date, district, and
output folder, then run the workflow without installing R, RStudio, R packages,
RTools, or command-line tools. The app uses the user's installed Google Chrome
through `chromote`; Chrome is not bundled.

Installed layout:

```text
MusterRollDownloader/
  MusterRollDownloader.exe
  R/
    bin/
      Rscript.exe
  library/
  app/
    run.R
    download_pdfs_parallel.R
    scraper.R
    districts.json
```

The launcher only uses bundled Rscript paths:

```text
R\bin\Rscript.exe
R\bin\x64\Rscript.exe
```

It does not search system PATH for R on the user's machine.

## Build on Windows

Build machine requirements:

```text
R for Windows
.NET SDK
Inno Setup
Google Chrome
PowerShell
RTools if your R package installation needs source compilation
```

Create the staged app and installer:

```powershell
.\build\Build-App.ps1
```

Create only the staged app without compiling the installer:

```powershell
.\build\Build-App.ps1 -SkipInstaller
```

The build script:

1. Publishes the WinForms launcher as a self-contained Windows executable.
2. Copies the build machine's Windows R runtime into `dist\MusterRollDownloader\R`.
3. Installs required R packages into `dist\MusterRollDownloader\library`.
4. Copies `run.R`, `download_pdfs_parallel.R`, and `scraper.R` into the app folder.
5. Exports `UP_DISTRICTS` from `R\scraper.R` into `app\districts.json`.
6. Builds `dist\installer\MusterRollDownloaderSetup.exe` with Inno Setup.

## R scripts

`download_pdfs_parallel.R` is now callable through:

```r
download_muster_roll_pdfs(
  district = "AMROHA",
  dd = "26",
  mm = "05",
  yyyy = "2026",
  output_root = "C:/Output",
  num_sessions = 4
)
```

It preserves the original scrape-then-download behavior, writes PDFs under
`<output_root>/MusterRollsPDF/<DDMMYYYY>/`, and writes a CSV download log in the
same folder. It does not call `install.packages()` at runtime.
