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
    ORCH_ROLE_ORCHESTRATOR=model/effort  (default opus/high)
    ORCH_ROLE_RESEARCHER=model/effort    (default haiku/medium)
    ORCH_ROLE_WORKER=model/effort        (default haiku/medium)
    ORCH_ROLE_VALIDATOR=model/effort     (default haiku/medium)
    ORCH_ROLE_JUDGE=model/effort         (default sonnet/high)
    ORCH_ALLOW_TEST_WRITES=y|n           (default n)
    ORCH_ALLOW_BUILD_SERVE=y|n           (default n)
    ORCH_CODEX_MODEL_RESEARCHER=<id>     (default blank = inherit session model)
    ORCH_CODEX_MODEL_WORKER=<id>
    ORCH_CODEX_MODEL_VALIDATOR=<id>
    ORCH_CODEX_MODEL_JUDGE=<id>
    ORCH_CODEX_CONFIG_PATH_OVERRIDE=<path>  (test-only; overrides
                                              ~/.codex/config.toml target)
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

function Get-PromptBool {
    param([string]$EnvVar, [string]$Text, [string]$Default)
    if ($NonInteractive) {
        $val = [Environment]::GetEnvironmentVariable($EnvVar)
        if ([string]::IsNullOrEmpty($val)) { $val = $Default }
        if ($val -match '^(y|yes|true)$') { return "true" } else { return "false" }
    }
    $defaultIdx = if ($Default -match '^(y|yes|true)$') { 0 } else { 1 }
    $idx = Get-Radio -Options @("Yes", "No") -DefaultIndex $defaultIdx -Prompt "$Text (Up/Down move, Enter confirm):"
    if ($idx -eq 0) { return "true" } else { return "false" }
}

function Get-RolePrompt {
    param([string]$EnvVar, [string]$Label, [string]$DefaultModel, [string]$DefaultEffort, [bool]$ShowModel)
    if ($NonInteractive) {
        $val = [Environment]::GetEnvironmentVariable($EnvVar)
        if ([string]::IsNullOrEmpty($val)) { return "$DefaultModel/$DefaultEffort" } else { return $val }
    }
    $model = $DefaultModel
    if ($ShowModel) {
        $models = @("opus", "sonnet", "haiku")
        $modelIdx = [array]::IndexOf($models, $DefaultModel)
        if ($modelIdx -lt 0) { $modelIdx = 0 }
        $mi = Get-Radio -Options $models -DefaultIndex $modelIdx -Prompt "$($Label): model (Up/Down move, Enter confirm):"
        $model = $models[$mi]
    }
    $efforts = @("low", "medium", "high")
    $effortIdx = [array]::IndexOf($efforts, $DefaultEffort)
    if ($effortIdx -lt 0) { $effortIdx = 1 }
    $ei = Get-Radio -Options $efforts -DefaultIndex $effortIdx -Prompt "$($Label): effort (Up/Down move, Enter confirm):"
    return "$model/$($efforts[$ei])"
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

# ---- 4. per-role model/effort (always asked; Codex reuses the effort) ------

$roleOrchestrator = Get-RolePrompt -EnvVar "ORCH_ROLE_ORCHESTRATOR" -Label "Manager (task-orchestrator)" -DefaultModel "opus" -DefaultEffort "high" -ShowModel $WantClaude
$roleResearcher   = Get-RolePrompt -EnvVar "ORCH_ROLE_RESEARCHER"   -Label "Researcher (codebase-researcher)" -DefaultModel "haiku" -DefaultEffort "medium" -ShowModel $WantClaude
$roleWorker       = Get-RolePrompt -EnvVar "ORCH_ROLE_WORKER"       -Label "Worker (implementation-worker)" -DefaultModel "haiku" -DefaultEffort "medium" -ShowModel $WantClaude
$roleValidator    = Get-RolePrompt -EnvVar "ORCH_ROLE_VALIDATOR"    -Label "Validator (test-validator)" -DefaultModel "haiku" -DefaultEffort "medium" -ShowModel $WantClaude
$roleJudge        = Get-RolePrompt -EnvVar "ORCH_ROLE_JUDGE"        -Label "Judge (result-judge)" -DefaultModel "sonnet" -DefaultEffort "high" -ShowModel $WantClaude

function Split-Role {
    param([string]$Role)
    $parts = $Role -split '/', 2
    return @{ Model = $parts[0]; Effort = $parts[1] }
}

$ro = Split-Role $roleOrchestrator
$rr = Split-Role $roleResearcher
$rw = Split-Role $roleWorker
$rv = Split-Role $roleValidator
$rj = Split-Role $roleJudge

# ---- 5. Codex model overrides (only if Codex is a target) ------------------

$ReasoningEffortResearcher = $rr.Effort
$ReasoningEffortWorker = $rw.Effort
$ReasoningEffortValidator = $rv.Effort
$ReasoningEffortJudge = $rj.Effort

$ModelOverrideResearcher = ""; $ModelCommentResearcher = "# "
$ModelOverrideWorker = "";     $ModelCommentWorker = "# "
$ModelOverrideValidator = "";  $ModelCommentValidator = "# "
$ModelOverrideJudge = "";      $ModelCommentJudge = "# "

if ($WantCodex) {
    $ModelOverrideResearcher = Get-Prompt -EnvVar "ORCH_CODEX_MODEL_RESEARCHER" -Text "Codex model override for researcher (blank = inherit session default)" -Default ""
    $ModelOverrideWorker     = Get-Prompt -EnvVar "ORCH_CODEX_MODEL_WORKER"     -Text "Codex model override for worker (blank = inherit session default)" -Default ""
    $ModelOverrideValidator  = Get-Prompt -EnvVar "ORCH_CODEX_MODEL_VALIDATOR"  -Text "Codex model override for validator (blank = inherit session default)" -Default ""
    $ModelOverrideJudge      = Get-Prompt -EnvVar "ORCH_CODEX_MODEL_JUDGE"      -Text "Codex model override for judge (blank = inherit session default)" -Default ""

    if (-not [string]::IsNullOrEmpty($ModelOverrideResearcher)) { $ModelCommentResearcher = "" } else { $ModelOverrideResearcher = "not set -- inherits session default" }
    if (-not [string]::IsNullOrEmpty($ModelOverrideWorker)) { $ModelCommentWorker = "" } else { $ModelOverrideWorker = "not set -- inherits session default" }
    if (-not [string]::IsNullOrEmpty($ModelOverrideValidator)) { $ModelCommentValidator = "" } else { $ModelOverrideValidator = "not set -- inherits session default" }
    if (-not [string]::IsNullOrEmpty($ModelOverrideJudge)) { $ModelCommentJudge = "" } else { $ModelOverrideJudge = "not set -- inherits session default" }
}

# ---- 6. workflow toggles -----------------------------------------------------

$AllowTestWrites = Get-PromptBool -EnvVar "ORCH_ALLOW_TEST_WRITES" -Text "Allow workers/validator to create or modify test files by default" -Default "n"
$AllowBuildServe = Get-PromptBool -EnvVar "ORCH_ALLOW_BUILD_SERVE" -Text "Allow build and serve/dev-server commands by default" -Default "n"

# ---- 7. misc tokens -----------------------------------------------------------

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
    if ($Platform -eq "codex") {
        $modelOrchestrator = "inherits Codex session default"
        $modelResearcher = $ModelOverrideResearcher
        $modelWorker = $ModelOverrideWorker
        $modelValidator = $ModelOverrideValidator
        $modelJudge = $ModelOverrideJudge
    } else {
        $modelOrchestrator = $ro.Model
        $modelResearcher = $rr.Model
        $modelWorker = $rw.Model
        $modelValidator = $rv.Model
        $modelJudge = $rj.Model
    }
    return @{
        '{{AGENT_HOME_DIR}}'                   = ($AgentHomeDir -replace '\\', '/')
        '{{CLAUDE_DIR}}'                       = ($TargetClaudeDir -replace '\\', '/')
        '{{CODEX_DIR}}'                        = ($TargetCodexDir -replace '\\', '/')
        '{{MODEL_ORCHESTRATOR}}'               = $modelOrchestrator
        '{{EFFORT_ORCHESTRATOR}}'              = $ro.Effort
        '{{MODEL_RESEARCHER}}'                 = $modelResearcher
        '{{EFFORT_RESEARCHER}}'                = $rr.Effort
        '{{MODEL_WORKER}}'                     = $modelWorker
        '{{EFFORT_WORKER}}'                    = $rw.Effort
        '{{MODEL_VALIDATOR}}'                  = $modelValidator
        '{{EFFORT_VALIDATOR}}'                 = $rv.Effort
        '{{MODEL_JUDGE}}'                      = $modelJudge
        '{{EFFORT_JUDGE}}'                     = $rj.Effort
        '{{REASONING_EFFORT_RESEARCHER}}'      = $ReasoningEffortResearcher
        '{{REASONING_EFFORT_WORKER}}'          = $ReasoningEffortWorker
        '{{REASONING_EFFORT_VALIDATOR}}'       = $ReasoningEffortValidator
        '{{REASONING_EFFORT_JUDGE}}'           = $ReasoningEffortJudge
        '{{MODEL_OVERRIDE_RESEARCHER}}'        = $ModelOverrideResearcher
        '{{MODEL_OVERRIDE_WORKER}}'             = $ModelOverrideWorker
        '{{MODEL_OVERRIDE_VALIDATOR}}'          = $ModelOverrideValidator
        '{{MODEL_OVERRIDE_JUDGE}}'              = $ModelOverrideJudge
        '{{MODEL_COMMENT_RESEARCHER}}'          = $ModelCommentResearcher
        '{{MODEL_COMMENT_WORKER}}'              = $ModelCommentWorker
        '{{MODEL_COMMENT_VALIDATOR}}'           = $ModelCommentValidator
        '{{MODEL_COMMENT_JUDGE}}'               = $ModelCommentJudge
        '{{ALLOW_WORKER_TEST_WRITES}}'         = $AllowTestWrites
        '{{ALLOW_VALIDATOR_TEST_WRITES}}'      = $AllowTestWrites
        '{{ALLOW_TEST_FILE_CREATION}}'         = $AllowTestWrites
        '{{ALLOW_BUILD_COMMANDS}}'             = $AllowBuildServe
        '{{ALLOW_SERVE_COMMANDS}}'             = $AllowBuildServe
        '{{ALLOW_VALIDATOR_BUILD_COMMANDS}}'   = $AllowBuildServe
        '{{ALLOW_VALIDATOR_SERVE_COMMANDS}}'   = $AllowBuildServe
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

# ---- 8. config.toml [agents] merge (Codex only, always global) -------------

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

# ---- 9. generate -------------------------------------------------------------

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
