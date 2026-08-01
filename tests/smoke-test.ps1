#Requires -Version 5.1
<#
.SYNOPSIS
  Smoke-test matrix for install.ps1. Never touches the real ~/.claude or
  ~/.codex -- everything runs against a scratch directory.
#>

$ErrorActionPreference = "Stop"
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

function Get-Python {
    $py = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $py) { $py = (Get-Command python3 -ErrorAction SilentlyContinue).Source }
    return $py
}

# The install's standing invariants live in orchestrator-spec/verify-install.py
# -- one executable list, shared with /orchestrate-sync. What stays here is
# what only a FRESH install can assert: the shipped default values, which the
# user (or /orchestrate-sync) is free to change afterwards.
function Test-Json {
    param([string]$File, [string]$Label)
    try {
        $d = Get-Content -Raw $File | ConvertFrom-Json
        if ($d.capabilities.explicitDeny.Count -ne 0) { throw "deny list should ship empty" }
        if ($d.workflow.waitSliceSeconds -ne 60) { throw "waitSliceSeconds != 60" }
        if ($d.workflow.agentTimeoutSeconds.codebaseResearcher -ne 180) { throw "researcher timeout != 180" }
        if ($d.workflow.agentTimeoutSeconds.implementationWorker -ne 900) { throw "worker timeout != 900" }
        if ($d.workflow.agentTimeoutSeconds.testValidator -ne 300) { throw "validator timeout != 300" }
        if ($d.workflow.agentTimeoutSeconds.resultJudge -ne 180) { throw "judge timeout != 180" }
        if ($d.workflow.agentTimeoutSeconds.correctionWorker -ne 300) { throw "correction timeout != 300" }
        if ($d.workflow.judgePolicy -ne "auto") { throw "judgePolicy should ship as auto" }
        if ($d.workflow.validationPolicy -ne "auto") { throw "validationPolicy should ship as auto" }
        if ($d.workflow.researchPolicy -ne "auto") { throw "researchPolicy should ship as auto" }
        foreach ($gone in @("requireIndependentJudge", "requireValidation")) {
            if ($d.workflow.PSObject.Properties.Name -contains $gone) {
                throw "$gone still shipped alongside the policy that replaced it"
            }
        }
        # Pruned in schema 2: they were all-true restatements of the prompt prose.
        if ($d.PSObject.Properties.Name -contains "instructionGovernance") { throw "instructionGovernance should be pruned" }
        if ($d.PSObject.Properties.Name -contains "capabilityRouting") { throw "capabilityRouting should be pruned" }
        Test-Pass "$Label`: orchestration.json ships the documented defaults"
    } catch {
        Test-Fail "$Label`: orchestration.json check failed: $_"
    }
}

function Test-Verify {
    param([string]$Dir, [string]$Label)
    $py = Get-Python
    if (-not $py) { Test-Fail "$Label`: no python on PATH -- verify-install.py cannot run"; return }
    $out = & $py (Join-Path $RepoRoot "templates\orchestrator-spec\verify-install.py") $Dir
    if ($LASTEXITCODE -eq 0) {
        Test-Pass "$Label`: verify-install.py clean"
    } else {
        Test-Fail "$Label`: verify-install.py: $out"
    }
}

# Proves verify-install.py would fail if the install were broken. Without this
# a green verify only means it did not complain.
function Test-VerifyNegative {
    param([string]$Dir, [string]$Label)
    $py = Get-Python
    if (-not $py) { Test-Fail "$Label`: no python on PATH -- negative cases cannot run"; return }
    $out = & $py (Join-Path $RepoRoot "tests\verify-install-negative.py") $Dir
    if ($LASTEXITCODE -eq 0) {
        Test-Pass "$Label`: verify-install.py rejects every corrupted variant"
    } else {
        Test-Fail "$Label`: verify-install negative cases: $out"
    }
}

function Test-WorkerModel {
    # The worker authors production code; a weak default is paid back in
    # correction cycles, so pin the rendered default.
    param([string]$File, [string]$Label)
    $line = (Get-Content $File | Where-Object { $_ -like "model:*" } | Select-Object -First 1)
    if ($line -match "sonnet") {
        Test-Pass "$Label`: worker renders model: sonnet (default)"
    } else {
        Test-Fail "$Label`: worker model is not sonnet: $line"
    }
}

function Test-Drift {
    $py = Get-Python
    if (-not $py) { Test-Fail "drift check cannot run: no python on PATH"; return }
    $out = & $py (Join-Path $RepoRoot "tests\check-drift.py")
    if ($LASTEXITCODE -eq 0) {
        Test-Pass "templates: structure and step references valid"
    } else {
        Test-Fail "templates: Claude/Codex drift: $out"
    }
}

function Invoke-Install {
    param([string]$Platform, [string]$ProjDir, [string]$CodexConfigOverride = "", [string]$AllowTestWrites = "n")
    New-Item -ItemType Directory -Force -Path $ProjDir | Out-Null
    $env:ORCH_NONINTERACTIVE = "1"
    $env:ORCH_ALLOW_TEST_WRITES = $AllowTestWrites
    $env:ORCH_PLATFORM = $Platform
    $env:ORCH_SCOPE = "project"
    $env:ORCH_PROJECT_DIR = $ProjDir
    if ($CodexConfigOverride) { $env:ORCH_CODEX_CONFIG_PATH_OVERRIDE = $CodexConfigOverride }
    else { Remove-Item Env:\ORCH_CODEX_CONFIG_PATH_OVERRIDE -ErrorAction SilentlyContinue }
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $Install 2>&1
    $out | Out-File -FilePath (Join-Path $env:TEMP "orch_smoke_install_out.txt") -Encoding utf8
    return $LASTEXITCODE
}

Write-Host "=== 0/11: template drift (Claude vs Codex) ==="
Test-Drift

Write-Host "=== 1/11: claude-only ==="
$proj = Join-Path $Scratch "claude-only"
if ((Invoke-Install "claude" $proj) -eq 0) {
    Test-Pass "claude-only: install.ps1 exited 0"
    Test-NoTokens (Join-Path $proj ".claude") "claude-only"
    Test-Json (Join-Path $proj ".claude\orchestration.json") "claude-only"
    Test-Verify (Join-Path $proj ".claude") "claude-only"
    Test-VerifyNegative (Join-Path $proj ".claude") "claude-only"
    Test-WorkerModel (Join-Path $proj ".claude\agents\implementation-worker.md") "claude-only"
} else {
    Test-Fail "claude-only: install.ps1 failed"
}

Write-Host "=== 2/11: codex-only ==="
$proj = Join-Path $Scratch "codex-only"
$cfg = Join-Path $proj ".codex\config.toml"
if ((Invoke-Install "codex" $proj $cfg) -eq 0) {
    Test-Pass "codex-only: install.ps1 exited 0"
    Test-NoTokens (Join-Path $proj ".codex") "codex-only"
    Test-NoMcpLeak (Join-Path $proj ".codex") "codex-only"
    Test-Json (Join-Path $proj ".codex\orchestration.json") "codex-only"
    Test-Verify (Join-Path $proj ".codex") "codex-only"
    Test-VerifyNegative (Join-Path $proj ".codex") "codex-only"
} else {
    Test-Fail "codex-only: install.ps1 failed"
}

Write-Host "=== 3/11: both ==="
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

Write-Host "=== 4/11: config.toml -- absent (created) ==="
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

Write-Host "=== 5/11: config.toml -- present, no [agents] (appended) ==="
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

Write-Host "=== 6/11: config.toml -- has [agents], value is fine (untouched, quiet) ==="
$cfg = Join-Path $Scratch "cfg-hasagents\config.toml"
New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
[System.IO.File]::WriteAllText($cfg, "[agents]`nmax_concurrent_threads_per_session = 8`n")
$beforeHash = (Get-FileHash $cfg -Algorithm SHA256).Hash
$proj = Join-Path $Scratch "cfg-hasagents-proj"
if ((Invoke-Install "codex" $proj $cfg) -eq 0) {
    $afterHash = (Get-FileHash $cfg -Algorithm SHA256).Hash
    $installOut = Get-Content (Join-Path $env:TEMP "orch_smoke_install_out.txt") -Raw
    if ($beforeHash -ne $afterHash) {
        Test-Fail "config.toml has-agents-case: an existing [agents] table was modified"
    } elseif ($installOut -match "WARNING") {
        Test-Fail "config.toml has-agents-case: warned about a value that is already >= 4"
    } else {
        Test-Pass "config.toml has-agents-case: untouched, no needless warning"
    }
} else {
    Test-Fail "config.toml has-agents-case: install failed"
}

Write-Host "=== 7/11: config.toml -- [agents] value too low (specific warning) ==="
$cfg = Join-Path $Scratch "cfg-lowagents\config.toml"
New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
[System.IO.File]::WriteAllText($cfg, "[agents]`nmax_concurrent_threads_per_session = 2`n")
$beforeHash = (Get-FileHash $cfg -Algorithm SHA256).Hash
$proj = Join-Path $Scratch "cfg-lowagents-proj"
if ((Invoke-Install "codex" $proj $cfg) -eq 0) {
    $afterHash = (Get-FileHash $cfg -Algorithm SHA256).Hash
    $installOut = Get-Content (Join-Path $env:TEMP "orch_smoke_install_out.txt") -Raw
    if ($beforeHash -ne $afterHash) {
        Test-Fail "config.toml low-agents-case: the file was modified"
    } elseif ($installOut -match "max_concurrent_threads_per_session = 2, below the 8") {
        Test-Pass "config.toml low-agents-case: warned with the actual value"
    } else {
        Test-Fail "config.toml low-agents-case: no specific warning"
    }
} else {
    Test-Fail "config.toml low-agents-case: install failed"
}

Write-Host "=== 8/11: test writes enabled -- validator gains Edit/Write ==="
$proj = Join-Path $Scratch "testwrites-on"
if ((Invoke-Install "claude" $proj "" "y") -eq 0) {
    Test-Pass "test-writes-on: install.ps1 exited 0"
    Test-NoTokens (Join-Path $proj ".claude") "test-writes-on"
    # verify-install.py ties the validator's Edit/Write allowlist to
    # validator.allowTestWrites, so this covers the "with" case too.
    Test-Verify (Join-Path $proj ".claude") "test-writes-on"
    if ((Get-Content -Raw (Join-Path $proj ".claude\orchestration.json")) -match '"allowTestWrites": true') {
        Test-Pass "test-writes-on: orchestration.json records allowTestWrites=true"
    } else {
        Test-Fail "test-writes-on: orchestration.json still has allowTestWrites=false"
    }
} else {
    Test-Fail "test-writes-on: install.ps1 failed"
}

# A global install lands in ~/.claude, which on a real machine also holds
# session transcripts, credentials and plugin trees. The verifier must read
# only this bundle's files -- every other case installs project-scoped, which
# is exactly why an earlier whole-root scan went unnoticed.
Write-Host "=== 9/11: global scope -- verifier must not read the rest of HOME ==="
$fakeHome = Join-Path $Scratch "fakehome"
$decoy = "sk-decoy-DEADBEEF0123456789"
$savedHome = $env:USERPROFILE
$env:USERPROFILE = $fakeHome
$env:HOME = $fakeHome
$env:ORCH_NONINTERACTIVE = "1"
$env:ORCH_PLATFORM = "claude"
$env:ORCH_SCOPE = "global"
Remove-Item Env:\ORCH_PROJECT_DIR -ErrorAction SilentlyContinue
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File $Install 2>&1
$installRc = $LASTEXITCODE
$env:USERPROFILE = $savedHome
Remove-Item Env:\HOME -ErrorAction SilentlyContinue
if ($installRc -eq 0) {
    Test-Pass "global: install.ps1 exited 0"
    # Seeded INSIDE the install root, because that is where the real ones are:
    # ~/.claude/projects/*.jsonl and ~/.claude/.credentials.json. Seeding them
    # beside it would leave this case passing against the whole-root walk it
    # exists to catch.
    $decoyDir = Join-Path $fakeHome ".claude\projects\junk"
    New-Item -ItemType Directory -Force -Path $decoyDir | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $fakeHome ".claude\.credentials.json"),
        "{""apiKey"": ""$decoy""}")
    foreach ($i in 0..299) {
        [System.IO.File]::WriteAllText((Join-Path $decoyDir "f$i.txt"),
            "token = ""$decoy""`nfiller $i`n")
    }
    $py = Get-Python
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $verifyOut = & $py (Join-Path $RepoRoot "templates\orchestrator-spec\verify-install.py") (Join-Path $fakeHome ".claude")
    $verifyRc = $LASTEXITCODE
    $sw.Stop()
    $joined = ($verifyOut -join "`n")
    if ($verifyRc -eq 0) {
        Test-Pass "global: verify-install.py clean"
    } else {
        Test-Fail "global: verify-install.py: $joined"
    }
    if ($joined.Contains($decoy)) {
        Test-Fail "global: verifier echoed a credential value"
    } else {
        Test-Pass "global: verifier never echoed a credential value"
    }
    if ($joined -match 'credentials\.json|projects[\\/]junk') {
        Test-Fail "global: verifier read files outside the bundle"
    } else {
        Test-Pass "global: verifier stayed inside the bundle's files"
    }
    if ($sw.Elapsed.TotalSeconds -le 15) {
        Test-Pass ("global: verify finished in {0:N1}s" -f $sw.Elapsed.TotalSeconds)
    } else {
        Test-Fail ("global: verify took {0:N1}s -- it is walking the whole home dir" -f $sw.Elapsed.TotalSeconds)
    }
} else {
    Test-Fail "global: install.ps1 failed"
}

Write-Host "=== 10/11: uninstall -- bundle gone, user's own files kept ==="
$proj = Join-Path $Scratch "uninstall"
if ((Invoke-Install "both" $proj (Join-Path $proj ".codex\config.toml")) -eq 0) {
    # Decoys: the failure this case exists for is an uninstall that takes the
    # user's own agents and skills with it.
    Set-Content -Encoding utf8 (Join-Path $proj ".claude\agents\my-own-agent.md") "mine"
    New-Item -ItemType Directory -Force -Path (Join-Path $proj ".claude\skills\my-skill") | Out-Null
    Set-Content -Encoding utf8 (Join-Path $proj ".claude\skills\my-skill\SKILL.md") "x"
    $env:ORCH_UNINSTALL_CONFIRM = "y"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $Install -Uninstall | Out-Null
    $rc = $LASTEXITCODE
    Remove-Item Env:\ORCH_UNINSTALL_CONFIRM -ErrorAction SilentlyContinue
    $survived = @(".claude\agents\task-orchestrator.md", ".claude\orchestrator-spec",
                  ".claude\orchestration.json", ".claude\skills\orchestrate",
                  ".codex\agents") |
        Where-Object { Test-Path (Join-Path $proj $_) }
    if ($rc -ne 0) {
        Test-Fail "uninstall: install.ps1 -Uninstall failed"
    } elseif ($survived.Count -gt 0) {
        Test-Fail "uninstall: bundle files survived: $($survived -join ', ')"
    } elseif (-not (Test-Path (Join-Path $proj ".claude\agents\my-own-agent.md")) -or
              -not (Test-Path (Join-Path $proj ".claude\skills\my-skill\SKILL.md"))) {
        Test-Fail "uninstall: removed files this bundle did not install"
    } else {
        Test-Pass "uninstall: bundle removed, user's own agents and skills kept"
    }
} else {
    Test-Fail "uninstall: setup install failed"
}

Write-Host "=== 11/11: config UI -- fanned-out writes keep the install verifiable ==="
$proj = Join-Path $Scratch "config-ui"
if ((Invoke-Install "both" $proj (Join-Path $proj ".codex\config.toml")) -eq 0) {
    $py = Get-Python
    if (-not $py) {
        Test-Fail "config UI: no python on PATH -- the UI test cannot run"
    } else {
        $out = & $py (Join-Path $RepoRoot "tests\config-ui-test.py") `
            (Join-Path $proj ".claude") (Join-Path $proj ".codex")
        if ($LASTEXITCODE -eq 0) {
            Test-Pass "config UI: every setting reached all the files that must agree"
        } else {
            Test-Fail "config UI: $(($out | Select-String '^FAIL' | Select-Object -First 3) -join '; ')"
        }
    }
} else {
    Test-Fail "config UI: setup install failed"
}

Remove-Item -Recurse -Force $Scratch -ErrorAction SilentlyContinue
Remove-Item Env:\ORCH_NONINTERACTIVE, Env:\ORCH_PLATFORM, Env:\ORCH_SCOPE, Env:\ORCH_PROJECT_DIR, Env:\ORCH_CODEX_CONFIG_PATH_OVERRIDE, Env:\ORCH_ALLOW_TEST_WRITES -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "================================================"
if ($script:Failures -eq 0) {
    Write-Host "ALL CHECKS PASSED"
    exit 0
} else {
    Write-Host "$($script:Failures) CHECK(S) FAILED"
    exit 1
}
