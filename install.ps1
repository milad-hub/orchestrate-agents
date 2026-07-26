#Requires -Version 5.1
<#
.SYNOPSIS
  Installer for the orchestrate-agents bundle (manager/researcher/worker/
  validator/judge multi-agent system) -- Claude Code and/or Codex CLI.

.DESCRIPTION
  Run with no arguments for the interactive installer.

  Non-interactive testing (never used for a real install -- for smoke tests
  only): set $env:ORCH_NONINTERACTIVE = "1" and optionally override any of:
    ORCH_PLATFORM=claude|codex|both      (default claude)
    ORCH_SCOPE=global|project
    ORCH_PROJECT_DIR=<path>              (required if ORCH_SCOPE=project)
    ORCH_OVERWRITE=y|n
    ORCH_CODEX_CONFIG_PATH_OVERRIDE=<path>  (test-only; overrides
                                              ~/.codex/config.toml target)

  Permission defaults. Both ship OFF and are NOT asked interactively --
  widening them is a deliberate decision, not a question to answer while
  skimming an installer. Honoured in interactive installs too:
    ORCH_ALLOW_TEST_WRITES=y|n           (default n)
    ORCH_ALLOW_BUILD_SERVE=y|n           (default n)
#>

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
$Templates = Join-Path $RepoRoot "templates"
$NonInteractive = ($env:ORCH_NONINTERACTIVE -eq "1")

function Get-Prompt {
    param([string]$EnvVar, [string]$Text, [string]$Default)
    if ($NonInteractive) {
        $val = [Environment]::GetEnvironmentVariable($EnvVar)
        if ([string]::IsNullOrEmpty($val)) { return $Default } else { return $val }
    }
    $reply = Read-Host "$Text [$Default]"
    if ([string]::IsNullOrEmpty($reply)) { return $Default } else { return $reply }
}

# Redraws rewind a fixed number of rows, so a line that wraps would desync the
# cursor and leave a trail of half-drawn menus. Clip instead.
function Get-ClipWidth {
    try { $w = [Console]::WindowWidth } catch { $w = 80 }
    if ($w -lt 20) { $w = 80 }
    return $w - 1
}

function Format-Clipped {
    param([string]$Text, [int]$Width)
    if ($Text.Length -le $Width) { return $Text }
    return $Text.Substring(0, $Width)
}

function Get-Radio {
    param([string[]]$Options, [int]$DefaultIndex, [string]$Prompt)
    $cursor = $DefaultIndex
    $menuLines = $Options.Length + 2
    $width = Get-ClipWidth
    Write-Host (Format-Clipped $Prompt $width)
    for ($i = 0; $i -lt $Options.Length; $i++) { Write-Host "" }
    Write-Host ""
    while ($true) {
        [Console]::SetCursorPosition(0, [Console]::CursorTop - $menuLines)
        Write-Host (Format-Clipped $Prompt $width)
        for ($i = 0; $i -lt $Options.Length; $i++) {
            $mark = if ($i -eq $cursor) { "x" } else { " " }
            $pointer = if ($i -eq $cursor) { ">" } else { " " }
            Write-Host (Format-Clipped "  $pointer ($mark) $($Options[$i])                    " $width)
        }
        Write-Host ""
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($key.VirtualKeyCode -eq 13) { break }
        elseif ($key.VirtualKeyCode -eq 38) { $cursor = ($cursor - 1 + $Options.Length) % $Options.Length }
        elseif ($key.VirtualKeyCode -eq 40) { $cursor = ($cursor + 1) % $Options.Length }
    }
    return $cursor
}

# Env-var only: for settings that are never asked interactively.
function Get-EnvBool {
    param([string]$EnvVar, [string]$Default)
    $val = [Environment]::GetEnvironmentVariable($EnvVar)
    if ([string]::IsNullOrEmpty($val)) { $val = $Default }
    if ($val -match '^(y|yes|true)$') { return "true" } else { return "false" }
}

function Get-PromptBool {
    param([string]$EnvVar, [string]$Text, [string]$Default)
    if ($NonInteractive) { return (Get-EnvBool -EnvVar $EnvVar -Default $Default) }
    $defaultIdx = if ($Default -match '^(y|yes|true)$') { 0 } else { 1 }
    $idx = Get-Radio -Options @("Yes", "No") -DefaultIndex $defaultIdx -Prompt "$Text (Up/Down move, Enter confirm):"
    if ($idx -eq 0) { return "true" } else { return "false" }
}

# ---- 1. platform choice ---------------------------------------------------

if ($NonInteractive) {
    $platformAns = if ($env:ORCH_PLATFORM) { $env:ORCH_PLATFORM } else { "claude" }
} else {
    $options = @("Claude Code", "Codex CLI")
    $checked = @($true, $false)
    $cursor = 0
    $menuLines = $options.Length + 2
    Write-Host "Install for: (Up/Down move, Space toggle, Enter confirm)"
    for ($i = 0; $i -lt $options.Length; $i++) { Write-Host "" }
    Write-Host ""
    while ($true) {
        [Console]::SetCursorPosition(0, [Console]::CursorTop - $menuLines)
        Write-Host "Install for: (Up/Down move, Space toggle, Enter confirm)"
        for ($i = 0; $i -lt $options.Length; $i++) {
            $box = if ($checked[$i]) { "x" } else { " " }
            $pointer = if ($i -eq $cursor) { ">" } else { " " }
            Write-Host (Format-Clipped "  $pointer [$box] $($options[$i])                    " (Get-ClipWidth))
        }
        Write-Host ""
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($key.VirtualKeyCode -eq 13) { break }
        elseif ($key.VirtualKeyCode -eq 38) { $cursor = ($cursor - 1 + $options.Length) % $options.Length }
        elseif ($key.VirtualKeyCode -eq 40) { $cursor = ($cursor + 1) % $options.Length }
        elseif ($key.VirtualKeyCode -eq 32) { $checked[$cursor] = -not $checked[$cursor] }
    }
    if (-not $checked[0] -and -not $checked[1]) { $checked[0] = $true }
    if ($checked[0] -and $checked[1]) { $platformAns = "both" }
    elseif ($checked[1]) { $platformAns = "codex" }
    else { $platformAns = "claude" }
}
if ($platformAns -notin @("claude", "codex", "both")) {
    Write-Error "Unrecognized platform '$platformAns' (expected claude, codex, or both)."
    exit 1
}
$WantClaude = ($platformAns -eq "claude" -or $platformAns -eq "both")
$WantCodex = ($platformAns -eq "codex" -or $platformAns -eq "both")
Write-Host "Platform(s): $platformAns"

# ---- 2. scope --------------------------------------------------------------

if ($NonInteractive) {
    $scopeAns = if ($env:ORCH_SCOPE) { $env:ORCH_SCOPE } else { "global" }
} else {
    $globalDirs = @()
    if ($WantClaude) { $globalDirs += "~/.claude" }
    if ($WantCodex) { $globalDirs += "~/.codex" }
    $projectDirs = @()
    if ($WantClaude) { $projectDirs += ".claude/" }
    if ($WantCodex) { $projectDirs += ".codex/" }
    $idx = Get-Radio -Options @("Install globally ($($globalDirs -join ', '))", "Install into a project ($($projectDirs -join ', '))") -DefaultIndex 0 -Prompt "Install scope (Up/Down move, Enter confirm):"
    if ($idx -eq 1) { $scopeAns = "project" } else { $scopeAns = "global" }
}

if ($scopeAns -eq "project") {
    if ($NonInteractive) {
        $projectDir = $env:ORCH_PROJECT_DIR
        if ([string]::IsNullOrEmpty($projectDir)) {
            throw "ORCH_PROJECT_DIR is required when ORCH_SCOPE=project"
        }
    } else {
        $projectDir = Read-Host "Project directory path"
    }
    if ($projectDir -like '~*') {
        $projectDir = [Environment]::GetFolderPath('UserProfile') + $projectDir.Substring(1)
    }
    if (-not (Test-Path -Path $projectDir -PathType Container)) {
        Write-Error "'$projectDir' is not a directory."
        exit 1
    }
    $projectDir = (Resolve-Path $projectDir).Path
    $TargetClaudeDir = Join-Path $projectDir ".claude"
    $TargetCodexDir = Join-Path $projectDir ".codex"
} else {
    # $env:USERPROFILE first so a redirected profile (and the smoke suite's
    # fake home) is honoured; GetFolderPath cannot be redirected.
    $userProfile = $env:USERPROFILE
    if ([string]::IsNullOrEmpty($userProfile)) {
        $userProfile = [Environment]::GetFolderPath('UserProfile')
    }
    $TargetClaudeDir = Join-Path $userProfile ".claude"
    $TargetCodexDir = Join-Path $userProfile ".codex"
}

if ($WantClaude) { Write-Host "Claude Code target: $TargetClaudeDir" }
if ($WantCodex) { Write-Host "Codex CLI target: $TargetCodexDir" }

# ---- 3. overwrite check -----------------------------------------------------

$existing = @()
if ($WantClaude -and (Test-Path (Join-Path $TargetClaudeDir "agents\task-orchestrator.md"))) { $existing += $TargetClaudeDir }
if ($WantCodex -and (Test-Path (Join-Path $TargetCodexDir "agents\task-orchestrator.md"))) { $existing += $TargetCodexDir }
if ($existing.Count -gt 0) {
    if (-not $NonInteractive) {
        Write-Host "Existing orchestration install found at: $($existing -join ', ')"
    }
    $overwrite = Get-PromptBool -EnvVar "ORCH_OVERWRITE" -Text "Overwrite it" -Default "n"
    if ($overwrite -ne "true") {
        Write-Host "Aborted -- nothing was changed."
        exit 0
    }
}

# ---- 4. workflow toggles -----------------------------------------------------

# Not asked. Both default OFF -- the safe setting -- and stay a permission
# decision the user makes deliberately. /orchestrate-sync flips them (and
# the validator's tool allowlist with them) on request.
$AllowTestWrites = Get-EnvBool -EnvVar "ORCH_ALLOW_TEST_WRITES" -Default "n"
$AllowBuildServe = Get-EnvBool -EnvVar "ORCH_ALLOW_BUILD_SERVE" -Default "n"

# The validator only gets Edit/Write in its Claude tools allowlist when test
# writes are on -- with the default off the harness keeps it read-only, so the
# rule doesn't depend on the prompt being obeyed.
if ($AllowTestWrites -eq "true") { $ValidatorWriteTools = ", Edit, Write" } else { $ValidatorWriteTools = "" }

# ---- 5. misc tokens -----------------------------------------------------------

$InstallDate = Get-Date -Format "yyyy-MM-dd"
$ClaudeVersion = "unknown - run /orchestrate-sync"
$CodexVersion = "unknown - run /orchestrate-sync"
if ($WantClaude) {
    try {
        $v = (& claude --version 2>$null | Select-Object -First 1)
        if ($v) { $ClaudeVersion = $v }
    } catch {}
}
if ($WantCodex) {
    try {
        $v = (& codex --version 2>$null | Select-Object -First 1)
        if ($v) { $CodexVersion = $v }
    } catch {}
}

# ---- substitution -----------------------------------------------------------

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-TokenMap {
    param([string]$AgentHomeDir, [string]$Platform)
    return @{
        '{{AGENT_HOME_DIR}}'                   = ($AgentHomeDir -replace '\\', '/')
        '{{CLAUDE_DIR}}'                       = ($TargetClaudeDir -replace '\\', '/')
        '{{CODEX_DIR}}'                        = ($TargetCodexDir -replace '\\', '/')
        '{{ALLOW_WORKER_TEST_WRITES}}'         = $AllowTestWrites
        '{{ALLOW_VALIDATOR_TEST_WRITES}}'      = $AllowTestWrites
        '{{ALLOW_TEST_FILE_CREATION}}'         = $AllowTestWrites
        '{{ALLOW_BUILD_COMMANDS}}'             = $AllowBuildServe
        '{{ALLOW_SERVE_COMMANDS}}'             = $AllowBuildServe
        '{{ALLOW_VALIDATOR_BUILD_COMMANDS}}'   = $AllowBuildServe
        '{{ALLOW_VALIDATOR_SERVE_COMMANDS}}'   = $AllowBuildServe
        '{{VALIDATOR_WRITE_TOOLS}}'            = $ValidatorWriteTools
        '{{INSTALL_DATE}}'                     = $InstallDate
        '{{CLAUDE_VERSION}}'                   = $ClaudeVersion
        '{{CODEX_VERSION}}'                    = $CodexVersion
    }
}

function Copy-Substituted {
    param([string]$SrcFile, [string]$DstFile, [hashtable]$TokenMap)
    $content = Get-Content -Raw -Path $SrcFile
    foreach ($key in $TokenMap.Keys) {
        $content = $content.Replace($key, $TokenMap[$key])
    }
    $dstDir = Split-Path -Parent $DstFile
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
    # Windows PowerShell 5.1's Set-Content -Encoding utf8 writes a BOM, which
    # breaks strict JSON parsers (orchestration.json) -- write via .NET instead.
    [System.IO.File]::WriteAllText($DstFile, $content, $Utf8NoBom)
}

function Copy-Tree {
    param([string]$SrcRoot, [string]$DstRoot, [hashtable]$TokenMap)
    Get-ChildItem -Path $SrcRoot -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($SrcRoot.Length).TrimStart('\', '/')
        $dst = Join-Path $DstRoot $rel
        Copy-Substituted -SrcFile $_.FullName -DstFile $dst -TokenMap $TokenMap
    }
}

# ---- 6. config.toml [agents] merge (Codex only, always global) -------------

# Must be >= workflow.maximumParallelWorkers in orchestration.template.json.
$RequiredThreads = 4

# The value of max_concurrent_threads_per_session inside the [agents] table, or
# $null if absent. Scoped to that table so an identically named key under
# another section cannot be mistaken for it.
function Get-CodexThreadLimit {
    param([string]$Raw)
    $block = [regex]::Match($Raw, '(?ms)^[ \t]*\[agents\][ \t]*\r?$(.*?)(?=^[ \t]*\[|\z)')
    if (-not $block.Success) { return $null }
    $key = [regex]::Match($block.Groups[1].Value,
        '(?m)^[ \t]*max_concurrent_threads_per_session[ \t]*=[ \t]*(\d+)')
    if (-not $key.Success) { return $null }
    return [int]$key.Groups[1].Value
}

function Merge-CodexConfig {
    $codexConfig = if ($env:ORCH_CODEX_CONFIG_PATH_OVERRIDE) {
        $env:ORCH_CODEX_CONFIG_PATH_OVERRIDE
    } else {
        $profileDir = $env:USERPROFILE
        if ([string]::IsNullOrEmpty($profileDir)) {
            $profileDir = [Environment]::GetFolderPath('UserProfile')
        }
        Join-Path $profileDir ".codex\config.toml"
    }
    if (-not (Test-Path $codexConfig)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $codexConfig) | Out-Null
        [System.IO.File]::WriteAllText($codexConfig, "[agents]`nmax_concurrent_threads_per_session = $RequiredThreads`n", $Utf8NoBom)
        Write-Host "Created $codexConfig with a default [agents] table."
    } elseif ((Get-Content -Raw $codexConfig) -match '(?m)^[ \t]*\[agents\][ \t]*$') {
        # Never modified - an existing [agents] table is the user's. But there
        # is no reason to make them go read a number the installer can read.
        $limit = Get-CodexThreadLimit -Raw (Get-Content -Raw $codexConfig)
        if ($null -eq $limit) {
            Write-Host "WARNING: $codexConfig has an [agents] table with no"
            Write-Host "max_concurrent_threads_per_session. Add"
            Write-Host "'max_concurrent_threads_per_session = $RequiredThreads' to it, or the"
            Write-Host "manager may not get the $RequiredThreads parallel delegates it plans for."
        } elseif ($limit -lt $RequiredThreads) {
            Write-Host "WARNING: $codexConfig sets"
            Write-Host "max_concurrent_threads_per_session = $limit, below the $RequiredThreads parallel"
            Write-Host "delegates the manager plans for. Raise it to $RequiredThreads or delegates will"
            Write-Host "queue. Your config was not modified."
        }
    } else {
        Add-Content -Path $codexConfig -Value "`n[agents]`nmax_concurrent_threads_per_session = $RequiredThreads" -Encoding UTF8
        Write-Host "Appended [agents] table to $codexConfig."
    }
}

# ---- 7. generate -------------------------------------------------------------

$BundleVersion = 7
$script:KeptConfig = @()
$script:RemovedSkills = @()

# Skill directories this bundle shipped under a previous name. Copy-Tree only
# writes files, so without this a rename leaves the old skill installed
# alongside the new one -- both register, and the stale copy describes a
# procedure that no longer matches the verifier it calls.
$RetiredSkills = @("orchestrate-update")

function Remove-RetiredSkills {
    param([string]$Dir)
    foreach ($name in $RetiredSkills) {
        $path = Join-Path $Dir "skills\$name"
        if (Test-Path $path) {
            Remove-Item -Recurse -Force $path
            $script:RemovedSkills += $path
        }
    }
}

# Reinstalling replaces the generated tree -- that is what upgrading means --
# but orchestration.json is not generated content. It carries the models,
# effort, permission flags and reconciled deny list that /orchestrate-sync
# wrote for THIS machine, so keep it and let the user reconcile.
# A stale prompt-hashes.json would mismatch the new prompts on every upgrade,
# so drop it; the next /orchestrate-sync re-blesses.
function Install-Config {
    param([string]$Dir)
    $hashes = Join-Path $Dir "orchestrator-spec\prompt-hashes.json"
    if (Test-Path $hashes) { Remove-Item $hashes -Force }
    $config = Join-Path $Dir "orchestration.json"
    if (Test-Path $config) {
        $script:KeptConfig += $Dir
    } else {
        Copy-Item -Path (Join-Path $Dir "orchestrator-spec\orchestration.template.json") -Destination $config -Force
    }
}

# Machine-readable install facts. /orchestrate-sync's fast path compares
# cliVersion against `claude --version` / `codex --version` and writes back
# what it saw -- parsing prose out of a README was the previous design and it
# referred to a line that did not exist.
function Write-InstallState {
    param([string]$Dir, [string]$Platform)
    $json = @"
{
  "platform": "$Platform",
  "bundleVersion": $BundleVersion,
  "installedAt": "$(Get-Date -Format 'yyyy-MM-dd')",
  "cliVersion": null,
  "lastCheckedAt": null
}
"@
    [System.IO.File]::WriteAllText(
        (Join-Path $Dir "orchestrator-spec\install-state.json"), $json)
}

if ($WantClaude) {
    New-Item -ItemType Directory -Force -Path $TargetClaudeDir | Out-Null
    $tokenMap = Get-TokenMap -AgentHomeDir $TargetClaudeDir -Platform "claude"
    Copy-Tree -SrcRoot (Join-Path $Templates "orchestrator-spec") -DstRoot (Join-Path $TargetClaudeDir "orchestrator-spec") -TokenMap $tokenMap
    Copy-Tree -SrcRoot (Join-Path $Templates "agents") -DstRoot (Join-Path $TargetClaudeDir "agents") -TokenMap $tokenMap
    Copy-Tree -SrcRoot (Join-Path $Templates "skills") -DstRoot (Join-Path $TargetClaudeDir "skills") -TokenMap $tokenMap
    Copy-Substituted -SrcFile (Join-Path $Templates "README-orchestration.template.md") -DstFile (Join-Path $TargetClaudeDir "README-orchestration.md") -TokenMap $tokenMap
    Remove-RetiredSkills -Dir $TargetClaudeDir
    Install-Config -Dir $TargetClaudeDir
    Write-InstallState -Dir $TargetClaudeDir -Platform "claude"
}

if ($WantCodex) {
    New-Item -ItemType Directory -Force -Path $TargetCodexDir | Out-Null
    $tokenMap = Get-TokenMap -AgentHomeDir $TargetCodexDir -Platform "codex"
    Copy-Tree -SrcRoot (Join-Path $Templates "orchestrator-spec") -DstRoot (Join-Path $TargetCodexDir "orchestrator-spec") -TokenMap $tokenMap
    Copy-Tree -SrcRoot (Join-Path $Templates "codex\agents") -DstRoot (Join-Path $TargetCodexDir "agents") -TokenMap $tokenMap
    Copy-Tree -SrcRoot (Join-Path $Templates "codex\skills") -DstRoot (Join-Path $TargetCodexDir "skills") -TokenMap $tokenMap
    Copy-Substituted -SrcFile (Join-Path $Templates "codex\README-orchestration.template.md") -DstFile (Join-Path $TargetCodexDir "README-orchestration.md") -TokenMap $tokenMap
    Remove-RetiredSkills -Dir $TargetCodexDir
    Install-Config -Dir $TargetCodexDir
    Write-InstallState -Dir $TargetCodexDir -Platform "codex"
    Merge-CodexConfig
}

# One closing message. The next step is identical on both platforms, so
# saying it twice in different words only makes it easier to skip.
$targets = @()
if ($WantClaude) { $targets += $TargetClaudeDir }
if ($WantCodex) { $targets += $TargetCodexDir }

Write-Host ""
Write-Host "Installed to $($targets -join ', ')."
if ($script:RemovedSkills.Count -gt 0) {
    Write-Host "Removed skills renamed in this bundle: $($script:RemovedSkills -join ', ')"
}
if ($script:KeptConfig.Count -gt 0) {
    Write-Host "Kept your existing orchestration.json (models, effort, permission"
    Write-Host "flags, capability deny list). Tool allowlists and MCP routing were"
    Write-Host "reset to the bundle defaults."
}
Write-Host ""
Write-Host "Next: open a session and run /orchestrate-sync - once per platform you"
Write-Host "installed. It reconciles tool allowlists, MCP routing and the capability"
Write-Host "deny list against THIS machine, and records the prompt hashes it checks"
Write-Host "against later. Recommended before your first real /orchestrate run; the"
Write-Host "bundle works without it, just conservatively."
