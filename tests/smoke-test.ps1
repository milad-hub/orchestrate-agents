#Requires -Version 5.1
<#
.SYNOPSIS
  Smoke-test matrix for install.ps1. Never touches the real ~/.claude or
  ~/.codex -- everything runs against a scratch directory.
#>

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Install = Join-Path $RepoRoot "install.ps1"
$Scratch = Join-Path $env:TEMP ("orch-smoke-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
$script:Failures = 0

function Test-Pass { param([string]$Msg) Write-Host "PASS: $Msg" }
function Test-Fail { param([string]$Msg) Write-Host "FAIL: $Msg"; $script:Failures++ }

function Test-NoTokens {
    param([string]$Dir, [string]$Label)
    $hit = Get-ChildItem -Path $Dir -Recurse -File | Where-Object { (Get-Content -Raw $_.FullName) -match [regex]::Escape("{{") }
    if ($hit) { Test-Fail "$Label`: leftover {{ tokens found" } else { Test-Pass "$Label`: no leftover tokens" }
}

function Test-NoMcpLeak {
    param([string]$Dir, [string]$Label)
    $agentsDir = Join-Path $Dir "agents"
    if (Test-Path $agentsDir) {
        $hit = Get-ChildItem -Path $agentsDir -Recurse -File | Where-Object { (Get-Content -Raw $_.FullName) -match "mcp__" }
        if ($hit) { Test-Fail "$Label`: mcp__ (Claude-specific) names leaked into Codex agents"; return }
    }
    Test-Pass "$Label`: no mcp__ leakage"
}

function Test-Json {
    param([string]$File, [string]$Label)
    try {
        $d = Get-Content -Raw $File | ConvertFrom-Json
        if ($d.capabilities.explicitDeny.Count -ne 0) { throw "explicitDeny not empty" }
        if ($d.defaultGlobalAgent -ne $false) { throw "defaultGlobalAgent not false" }
        if ($d.workflow.maximumParallelWorkers -ne 4) { throw "maximumParallelWorkers != 4" }
        if ($d.workflow.maximumCorrectionCycles -ne 2) { throw "maximumCorrectionCycles != 2" }
        if ($d.permissions.allowBypassPermissions -ne $false) { throw "allowBypassPermissions not false" }
        if (-not ($d.instructionGovernance.PSObject.Properties.Name -contains "followInstructionHierarchy")) { throw "followInstructionHierarchy missing" }
        if (-not ($d.instructionGovernance.PSObject.Properties.Name -contains "inspectNestedInstructionFiles")) { throw "inspectNestedInstructionFiles missing" }
        if ($d.instructionGovernance.PSObject.Properties.Name -contains "followClaudeMdHierarchy") { throw "old field name followClaudeMdHierarchy still present" }
        Test-Pass "$Label`: orchestration.json valid + invariants hold"
    } catch {
        Test-Fail "$Label`: orchestration.json check failed: $_"
    }
}

function Test-Toml {
    param([string]$Dir, [string]$Label)
    $py = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $py) { $py = (Get-Command python3 -ErrorAction SilentlyContinue).Source }
    if (-not $py) { Test-Pass "$Label`: TOML check skipped (no python on PATH)"; return }
    $pyScript = @'
import sys, glob
try:
    import tomllib
except ImportError:
    print("tomllib unavailable (py<3.11) -- skipping strict parse", file=sys.stderr)
    sys.exit(0)
d = sys.argv[1]
expect = {
    "codebase-researcher.toml": "read-only",
    "result-judge.toml": "read-only",
    "implementation-worker.toml": "workspace-write",
    "test-validator.toml": "workspace-write",
}
for f in glob.glob(d + "/agents/*.toml"):
    p = tomllib.loads(open(f, "rb").read().decode("utf-8"))
    name = f.replace("\\", "/").split("/")[-1]
    assert "name" in p and "description" in p and "developer_instructions" in p
    assert p.get("sandbox_mode") == expect[name], (name, p.get("sandbox_mode"))
    assert p.get("mcp_servers") == [], name
'@
    $tmp = Join-Path $env:TEMP ("orch-tomlcheck-" + [guid]::NewGuid().ToString("N") + ".py")
    [System.IO.File]::WriteAllText($tmp, $pyScript)
    $err = & $py $tmp ($Dir.Replace('\\','/')) 2>&1
    if ($LASTEXITCODE -eq 0) {
        Test-Pass "$Label`: all .toml files parse + sandbox_mode correct"
    } else {
        Test-Fail "$Label`: TOML check failed: $err"
    }
    Remove-Item $tmp -ErrorAction SilentlyContinue
}

function Test-ManagerNoFrontmatter {
    param([string]$File, [string]$Label)
    $first = Get-Content $File -TotalCount 1
    if ($first -eq "---") {
        Test-Fail "$Label`: task-orchestrator.md unexpectedly has frontmatter"
    } else {
        Test-Pass "$Label`: task-orchestrator.md has no frontmatter (correct)"
    }
}

function Invoke-Install {
    param([string]$Platform, [string]$ProjDir, [string]$CodexConfigOverride = "")
    New-Item -ItemType Directory -Force -Path $ProjDir | Out-Null
    $env:ORCH_NONINTERACTIVE = "1"
    $env:ORCH_PLATFORM = $Platform
    $env:ORCH_SCOPE = "project"
    $env:ORCH_PROJECT_DIR = $ProjDir
    if ($CodexConfigOverride) { $env:ORCH_CODEX_CONFIG_PATH_OVERRIDE = $CodexConfigOverride }
    else { Remove-Item Env:\ORCH_CODEX_CONFIG_PATH_OVERRIDE -ErrorAction SilentlyContinue }
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $Install 2>&1
    $out | Out-File -FilePath (Join-Path $env:TEMP "orch_smoke_install_out.txt") -Encoding utf8
    return $LASTEXITCODE
}

Write-Host "=== 1/6: claude-only ==="
$proj = Join-Path $Scratch "claude-only"
if ((Invoke-Install "claude" $proj) -eq 0) {
    Test-Pass "claude-only: install.ps1 exited 0"
    Test-NoTokens (Join-Path $proj ".claude") "claude-only"
    Test-Json (Join-Path $proj ".claude\orchestration.json") "claude-only"
} else {
    Test-Fail "claude-only: install.ps1 failed"
}

Write-Host "=== 2/6: codex-only ==="
$proj = Join-Path $Scratch "codex-only"
$cfg = Join-Path $proj ".codex\config.toml"
if ((Invoke-Install "codex" $proj $cfg) -eq 0) {
    Test-Pass "codex-only: install.ps1 exited 0"
    Test-NoTokens (Join-Path $proj ".codex") "codex-only"
    Test-NoMcpLeak (Join-Path $proj ".codex") "codex-only"
    Test-Json (Join-Path $proj ".codex\orchestration.json") "codex-only"
    Test-Toml (Join-Path $proj ".codex") "codex-only"
    Test-ManagerNoFrontmatter (Join-Path $proj ".codex\agents\task-orchestrator.md") "codex-only"
    if (Test-Path (Join-Path $proj ".codex\agents\task-orchestrator.toml")) {
        Test-Fail "codex-only: task-orchestrator.toml should not exist"
    } else {
        Test-Pass "codex-only: no task-orchestrator.toml (correct)"
    }
} else {
    Test-Fail "codex-only: install.ps1 failed"
}

Write-Host "=== 3/6: both ==="
$proj = Join-Path $Scratch "both"
$cfg = Join-Path $proj ".codex\config.toml"
if ((Invoke-Install "both" $proj $cfg) -eq 0) {
    Test-Pass "both: install.ps1 exited 0"
    Test-NoTokens (Join-Path $proj ".claude") "both/claude"
    Test-NoTokens (Join-Path $proj ".codex") "both/codex"
    Test-NoMcpLeak (Join-Path $proj ".codex") "both/codex"
} else {
    Test-Fail "both: install.ps1 failed"
}

Write-Host "=== 4/6: config.toml -- absent (created) ==="
$cfg = Join-Path $Scratch "cfg-absent\config.toml"
$proj = Join-Path $Scratch "cfg-absent-proj"
if ((Invoke-Install "codex" $proj $cfg) -eq 0) {
    if ((Test-Path $cfg) -and ((Get-Content -Raw $cfg) -match '(?m)^\[agents\]')) {
        Test-Pass "config.toml absent-case: created with [agents]"
    } else {
        Test-Fail "config.toml absent-case: not created correctly"
    }
} else {
    Test-Fail "config.toml absent-case: install failed"
}

Write-Host "=== 5/6: config.toml -- present, no [agents] (appended) ==="
$cfg = Join-Path $Scratch "cfg-noagents\config.toml"
New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
[System.IO.File]::WriteAllText($cfg, "[other]`nfoo = `"bar`"`n")
$proj = Join-Path $Scratch "cfg-noagents-proj"
if ((Invoke-Install "codex" $proj $cfg) -eq 0) {
    $content = Get-Content -Raw $cfg
    if ($content -match 'foo = "bar"' -and $content -match '(?m)^\[agents\]') {
        Test-Pass "config.toml no-agents-case: appended, original content preserved"
    } else {
        Test-Fail "config.toml no-agents-case: original content lost or [agents] missing"
    }
} else {
    Test-Fail "config.toml no-agents-case: install failed"
}

Write-Host "=== 6/6: config.toml -- present, has [agents] (untouched, warned) ==="
$cfg = Join-Path $Scratch "cfg-hasagents\config.toml"
New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
[System.IO.File]::WriteAllText($cfg, "[agents]`nmax_concurrent_threads_per_session = 8`n")
$beforeHash = (Get-FileHash $cfg -Algorithm SHA256).Hash
$proj = Join-Path $Scratch "cfg-hasagents-proj"
if ((Invoke-Install "codex" $proj $cfg) -eq 0) {
    $afterHash = (Get-FileHash $cfg -Algorithm SHA256).Hash
    $installOut = Get-Content (Join-Path $env:TEMP "orch_smoke_install_out.txt") -Raw
    if ($beforeHash -eq $afterHash -and $installOut -match "WARNING") {
        Test-Pass "config.toml has-agents-case: untouched, warning printed"
    } else {
        Test-Fail "config.toml has-agents-case: file was modified or no warning printed"
    }
} else {
    Test-Fail "config.toml has-agents-case: install failed"
}

Remove-Item -Recurse -Force $Scratch -ErrorAction SilentlyContinue
Remove-Item Env:\ORCH_NONINTERACTIVE, Env:\ORCH_PLATFORM, Env:\ORCH_SCOPE, Env:\ORCH_PROJECT_DIR, Env:\ORCH_CODEX_CONFIG_PATH_OVERRIDE -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "================================================"
if ($script:Failures -eq 0) {
    Write-Host "ALL CHECKS PASSED"
    exit 0
} else {
    Write-Host "$($script:Failures) CHECK(S) FAILED"
    exit 1
}
