param(
    [string]$Configuration = "Release",
    [string]$RuntimeIdentifier = "win-x64",
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$DistRoot = Join-Path $RepoRoot "dist"
$StageRoot = Join-Path $DistRoot "MusterRollDownloader"
$PublishRoot = Join-Path $DistRoot "publish"
$ProjectPath = Join-Path $RepoRoot "src\MusterRollDownloader\MusterRollDownloader.csproj"

function Resolve-ToolPath {
    param(
        [string[]]$Names,
        [string[]]$FallbackPaths
    )

    foreach ($Name in $Names) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($Command) {
            return $Command.Source
        }
    }

    foreach ($Path in $FallbackPaths) {
        if (Test-Path -LiteralPath $Path) {
            return $Path
        }
    }

    return $null
}

$Dotnet = Resolve-ToolPath `
    -Names @("dotnet.exe", "dotnet") `
    -FallbackPaths @("C:\Program Files\dotnet\dotnet.exe")
if (-not $Dotnet) {
    throw "dotnet was not found. Install the .NET SDK or add dotnet.exe to PATH."
}

if (Test-Path $StageRoot) {
    Remove-Item -LiteralPath $StageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $StageRoot | Out-Null

& $Dotnet publish $ProjectPath `
    -c $Configuration `
    -r $RuntimeIdentifier `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $PublishRoot

Copy-Item -LiteralPath (Join-Path $PublishRoot "MusterRollDownloader.exe") -Destination $StageRoot

$RscriptFallbacks = @()
$RRoot = "C:\Program Files\R"
if (Test-Path -LiteralPath $RRoot) {
    $RscriptFallbacks = Get-ChildItem -LiteralPath $RRoot -Directory |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName "bin\Rscript.exe" }
}

$BuildRscript = Resolve-ToolPath `
    -Names @("Rscript.exe", "Rscript") `
    -FallbackPaths $RscriptFallbacks
if (-not $BuildRscript) {
    throw "Rscript was not found on the build machine PATH."
}

$RHome = & $BuildRscript -e "cat(normalizePath(R.home(), winslash='\\'))"
if (-not (Test-Path $RHome)) {
    throw "R.home() did not resolve to an existing folder: $RHome"
}

Copy-Item -LiteralPath $RHome -Destination (Join-Path $StageRoot "R") -Recurse

$LibraryDir = Join-Path $StageRoot "library"
& $BuildRscript (Join-Path $PSScriptRoot "build_r_library.R") $LibraryDir

$AppDir = Join-Path $StageRoot "app"
New-Item -ItemType Directory -Path $AppDir | Out-Null
Copy-Item -LiteralPath (Join-Path $RepoRoot "app\run.R") -Destination $AppDir
Copy-Item -LiteralPath (Join-Path $RepoRoot "download_pdfs_parallel.R") -Destination (Join-Path $AppDir "download_pdfs_parallel.R")
Copy-Item -LiteralPath (Join-Path $RepoRoot "R\scraper.R") -Destination (Join-Path $AppDir "scraper.R")
& $BuildRscript (Join-Path $PSScriptRoot "export_districts.R") (Join-Path $RepoRoot "R\scraper.R") (Join-Path $AppDir "districts.json") $LibraryDir

if (-not $SkipInstaller) {
    $Iscc = Resolve-ToolPath `
        -Names @("ISCC.exe", "ISCC") `
        -FallbackPaths @(
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
        )
    if (-not $Iscc) {
        throw "Inno Setup compiler ISCC.exe was not found. Install Inno Setup or rerun with -SkipInstaller."
    }

    & $Iscc (Join-Path $RepoRoot "installer\MusterRollDownloader.iss")
}

Write-Host "Staged app at $StageRoot"
