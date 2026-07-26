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

function Get-Radio {
    param([string[]]$Options, [int]$DefaultIndex, [string]$Prompt)
    $cursor = $DefaultIndex
    $menuLines = $Options.Length + 2
    Write-Host $Prompt
    for ($i = 0; $i -lt $Options.Length; $i++) { Write-Host "" }
    Write-Host ""
    while ($true) {
        [Console]::SetCursorPosition(0, [Console]::CursorTop - $menuLines)
        Write-Host $Prompt
        for ($i = 0; $i -lt $Options.Length; $i++) {
            $mark = if ($i -eq $cursor) { "x" } else { " " }
            $pointer = if ($i -eq $cursor) { ">" } else { " " }
            Write-Host "  $pointer ($mark) $($Options[$i])                    "
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
            Write-Host "  $pointer [$box] $($options[$i])                    "
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
    $userProfile = [Environment]::GetFolderPath('UserProfile')
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
    $overwrite = Get-PromptBool -EnvVar "ORCH_OVERWRITE" -Text "Existing orchestration install found at: $($existing -join ', '). Overwrite" -Default "n"
    if ($overwrite -ne "true") {
        Write-Host "Aborted -- nothing was changed."
        exit 0
    }
}

# ---- 4. workflow toggles -----------------------------------------------------

# Not asked. Both default OFF -- the safe setting -- and stay a permission
# decision the user makes deliberately. /orchestrate-update flips them (and
# the validator's tool allowlist with them) on request.
$AllowTestWrites = Get-EnvBool -EnvVar "ORCH_ALLOW_TEST_WRITES" -Default "n"
$AllowBuildServe = Get-EnvBool -EnvVar "ORCH_ALLOW_BUILD_SERVE" -Default "n"

# The validator only gets Edit/Write in its Claude tools allowlist when test
# writes are on -- with the default off the harness keeps it read-only, so the
# rule doesn't depend on the prompt being obeyed.
if ($AllowTestWrites -eq "true") { $ValidatorWriteTools = ", Edit, Write" } else { $ValidatorWriteTools = "" }

# ---- 5. misc tokens -----------------------------------------------------------

$InstallDate = Get-Date -Format "yyyy-MM-dd"
$ClaudeVersion = "unknown - run /orchestrate-update"
$CodexVersion = "unknown - run /orchestrate-update"
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

function Merge-CodexConfig {
    $codexConfig = if ($env:ORCH_CODEX_CONFIG_PATH_OVERRIDE) {
        $env:ORCH_CODEX_CONFIG_PATH_OVERRIDE
    } else {
        Join-Path ([Environment]::GetFolderPath('UserProfile')) ".codex\config.toml"
    }
    if (-not (Test-Path $codexConfig)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $codexConfig) | Out-Null
        [System.IO.File]::WriteAllText($codexConfig, "[agents]`nmax_concurrent_threads_per_session = 4`n", $Utf8NoBom)
        Write-Host "Created $codexConfig with a default [agents] table."
    } elseif ((Get-Content -Raw $codexConfig) -match '(?m)^\[agents\]') {
        Write-Host "WARNING: $codexConfig already has an [agents] section - not modified. Verify max_concurrent_threads_per_session yourself (should be >= workflow.maximumParallelWorkers in orchestration.json, default 4)."
    } else {
        Add-Content -Path $codexConfig -Value "`n[agents]`nmax_concurrent_threads_per_session = 4" -Encoding UTF8
        Write-Host "Appended [agents] table to $codexConfig."
    }
}

# ---- 7. generate -------------------------------------------------------------

if ($WantClaude) {
    New-Item -ItemType Directory -Force -Path $TargetClaudeDir | Out-Null
    $tokenMap = Get-TokenMap -AgentHomeDir $TargetClaudeDir -Platform "claude"
    Copy-Tree -SrcRoot (Join-Path $Templates "orchestrator-spec") -DstRoot (Join-Path $TargetClaudeDir "orchestrator-spec") -TokenMap $tokenMap
    Copy-Tree -SrcRoot (Join-Path $Templates "agents") -DstRoot (Join-Path $TargetClaudeDir "agents") -TokenMap $tokenMap
    Copy-Tree -SrcRoot (Join-Path $Templates "skills") -DstRoot (Join-Path $TargetClaudeDir "skills") -TokenMap $tokenMap
    Copy-Substituted -SrcFile (Join-Path $Templates "README-orchestration.template.md") -DstFile (Join-Path $TargetClaudeDir "README-orchestration.md") -TokenMap $tokenMap
    Copy-Item -Path (Join-Path $TargetClaudeDir "orchestrator-spec\orchestration.template.json") -Destination (Join-Path $TargetClaudeDir "orchestration.json") -Force
}

if ($WantCodex) {
    New-Item -ItemType Directory -Force -Path $TargetCodexDir | Out-Null
    $tokenMap = Get-TokenMap -AgentHomeDir $TargetCodexDir -Platform "codex"
    Copy-Tree -SrcRoot (Join-Path $Templates "orchestrator-spec") -DstRoot (Join-Path $TargetCodexDir "orchestrator-spec") -TokenMap $tokenMap
    Copy-Tree -SrcRoot (Join-Path $Templates "codex\agents") -DstRoot (Join-Path $TargetCodexDir "agents") -TokenMap $tokenMap
    Copy-Tree -SrcRoot (Join-Path $Templates "codex\skills") -DstRoot (Join-Path $TargetCodexDir "skills") -TokenMap $tokenMap
    Copy-Substituted -SrcFile (Join-Path $Templates "codex\README-orchestration.template.md") -DstFile (Join-Path $TargetCodexDir "README-orchestration.md") -TokenMap $tokenMap
    Copy-Item -Path (Join-Path $TargetCodexDir "orchestrator-spec\orchestration.template.json") -Destination (Join-Path $TargetCodexDir "orchestration.json") -Force
    Merge-CodexConfig
}

Write-Host ""
if ($WantClaude) { Write-Host "Installed to $TargetClaudeDir." }
if ($WantCodex) { Write-Host "Installed to $TargetCodexDir." }
Write-Host ""
if ($WantClaude) {
    Write-Host "Next (Claude Code): open a session and run /orchestrate-update to"
    Write-Host "reconcile MCP tool allowlists and the capability denylist against"
    Write-Host "THIS machine's installed plugins/MCP servers."
}
if ($WantCodex) {
    Write-Host "Next (Codex CLI): open a session and run /orchestrate-update to"
    Write-Host "reconcile MCP server routing and the capability denylist against"
    Write-Host "THIS machine's installed MCP servers."
}
Write-Host "Required before your first real /orchestrate run for full capability"
Write-Host "coverage - the bundle works without it too, just conservatively."
