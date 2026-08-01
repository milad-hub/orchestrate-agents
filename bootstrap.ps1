#Requires -Version 5.1
<#
.SYNOPSIS
  Install orchestrate-agents without cloning.

.DESCRIPTION
  Fetches this branch's archive into a temp directory, runs the real installer
  from it, then deletes the directory.

    irm https://raw.githubusercontent.com/milad-hub/orchestrate-agents/main/bootstrap.ps1 | iex

  A piped script cannot take parameters, so to uninstall:

    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/milad-hub/orchestrate-agents/main/bootstrap.ps1))) -Uninstall

  Overrides (the second exists so the smoke suite can point at a local zip --
  it is the only reason the URL is not hardcoded):
    ORCH_REF=<branch|tag>       (default main)
    ORCH_ARCHIVE_URL=<url>      (default: this repo's zip for ORCH_REF)
#>

param([switch]$Uninstall)

$ErrorActionPreference = "Stop"

$repo = "milad-hub/orchestrate-agents"
$ref = if ($env:ORCH_REF) { $env:ORCH_REF } else { "main" }
$archive = if ($env:ORCH_ARCHIVE_URL) {
    $env:ORCH_ARCHIVE_URL
} else {
    # zip, not tar.gz: Expand-Archive in 5.1 reads only zip.
    "https://codeload.github.com/$repo/zip/refs/heads/$ref"
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("orchestrate-" + [guid]::NewGuid())
try {
    New-Item -ItemType Directory -Path $work | Out-Null
    $zip = Join-Path $work "bundle.zip"
    if (Test-Path -LiteralPath $archive -PathType Leaf) {
        # A local path is accepted as well as a URL: the smoke suite hands
        # this a zip it just built, and file:// URLs are a portability trap.
        Copy-Item -LiteralPath $archive -Destination $zip
    } else {
        # -UseBasicParsing: 5.1 otherwise wants Internet Explorer's engine.
        Invoke-WebRequest -Uri $archive -OutFile $zip -UseBasicParsing
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $work -Force

    # GitHub names the directory <repo>-<ref>, but a tag, a slash in a branch
    # name or a locally built zip all change that -- find it, don't assume it.
    $dir = Get-ChildItem -Directory -Path $work |
        Where-Object { Test-Path (Join-Path $_.FullName "install.ps1") } |
        Select-Object -First 1
    if (-not $dir) {
        Write-Error "The archive from $archive has no install.ps1 in it."
        exit 1
    }

    # No stdin problem to solve here: the installer's menus read the console
    # host (RawUI.ReadKey), not the pipeline, so `irm | iex` stays interactive.
    & (Join-Path $dir.FullName "install.ps1") @PSBoundParameters
    exit $LASTEXITCODE
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
