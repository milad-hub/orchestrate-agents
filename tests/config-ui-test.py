#!/usr/bin/env python3
"""Check that config-ui.py's writes leave a verifiable install.

    python3 tests/config-ui-test.py <install-dir> [<install-dir> ...]

The UI edits settings that live in up to three files at once. Writing only
orchestration.json would look right in the browser and fail verify-install.py
on the next run, so every case here changes a value and then re-runs the
verifier -- that is the whole point of the test.

Run against a throwaway install: it changes settings and does not put them
back.
"""
import importlib.util
import json
import os
import re
import subprocess
import sys

# This suite imports config-ui.py from templates/, which the installer copies
# verbatim; a __pycache__ written there would be installed onto every machine.
sys.dont_write_bytecode = True

FAILURES = []


def fail(msg):
    print("FAIL: %s" % msg)
    FAILURES.append(msg)


def ok(msg):
    print("PASS: %s" % msg)


def load_ui_from(path):
    spec = importlib.util.spec_from_file_location("orch_config_ui_src", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_ui(root):
    path = os.path.join(root, "orchestrator-spec", "config-ui.py")
    spec = importlib.util.spec_from_file_location("orch_config_ui", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def verify(root):
    proc = subprocess.run(
        [sys.executable, os.path.join(root, "orchestrator-spec",
                                      "verify-install.py"), root],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return proc.returncode == 0, proc.stdout.decode("utf-8", "replace").strip()


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def cfg(root):
    return json.loads(read(os.path.join(root, "orchestration.json")))


def readme_row(root, stem):
    for line in read(os.path.join(root, "README-orchestration.md")).splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells and cells[0] == stem:
            return cells
    return []


def check(root):
    label = os.path.basename(root)
    is_codex = bool([f for f in os.listdir(os.path.join(root, "agents"))
                     if f.endswith(".toml")])
    ui = load_ui(root)

    passing, out = verify(root)
    if not passing:
        fail("%s: install does not verify before any change: %s" % (label, out))
        return

    # --- the three-way one: model/effort must move in every copy ----------
    if is_codex:
        ui.apply_setting(root, True, "role.worker.desiredEffort", "high")
        toml = read(os.path.join(root, "agents", "implementation-worker.toml"))
        row = readme_row(root, "implementation-worker")
        if cfg(root)["worker"]["desiredEffort"] != "high":
            fail("%s: orchestration.json effort not written" % label)
        elif not re.search(r'(?m)^model_reasoning_effort\s*=\s*"high"', toml):
            fail("%s: .toml model_reasoning_effort not written" % label)
        elif len(row) < 2 or row[1] != "high":
            fail("%s: README table effort not written (row=%s)" % (label, row))
        else:
            ok("%s: effort written to json, .toml and README together" % label)
    else:
        ui.apply_setting(root, False, "role.worker.model", "opus")
        fm = read(os.path.join(root, "agents", "implementation-worker.md"))
        row = readme_row(root, "implementation-worker")
        if cfg(root)["worker"]["model"] != "opus":
            fail("%s: orchestration.json model not written" % label)
        elif not re.search(r"(?m)^model:\s*opus\s*$", fm):
            fail("%s: frontmatter model not written" % label)
        elif len(row) < 2 or row[1] != "opus":
            fail("%s: README table model not written (row=%s)" % (label, row))
        else:
            ok("%s: model written to json, frontmatter and README together"
               % label)

        ui.apply_setting(root, False, "role.judge.desiredEffort", "medium")
        if (cfg(root)["judge"]["desiredEffort"] == "medium"
                and re.search(r"(?m)^effort:\s*medium\s*$",
                              read(os.path.join(root, "agents",
                                                "result-judge.md")))
                and readme_row(root, "result-judge")[2] == "medium"):
            ok("%s: effort written to json, frontmatter and README together"
               % label)
        else:
            fail("%s: effort did not reach all three copies" % label)

    passing, out = verify(root)
    if passing:
        ok("%s: still verifies after a model/effort change" % label)
    else:
        fail("%s: model/effort change broke the install: %s" % (label, out))

    # --- the fanned-out one: one toggle, several flags --------------------
    ui.apply_setting(root, is_codex, "group.testWrites", True)
    d = cfg(root)
    flags = {"worker.allowTestWrites": d["worker"]["allowTestWrites"],
             "validator.allowTestWrites": d["validator"]["allowTestWrites"],
             "commands.allowTestFileCreation":
                 d["commands"]["allowTestFileCreation"]}
    if set(flags.values()) == {True}:
        ok("%s: test-writes toggle set all three flags" % label)
    else:
        fail("%s: test-writes flags disagree: %s" % (label, flags))

    if not is_codex:
        tools = re.search(r"(?m)^tools:\s*(.*)$",
                          read(os.path.join(root, "agents",
                                            "test-validator.md"))).group(1)
        if (re.search(r"\bEdit\b", tools)
                and re.search(r"\bWrite\b", tools)):
            ok("%s: validator gained Edit/Write with the flag" % label)
        else:
            fail("%s: validator allowlist still withholds Edit/Write: %s"
                 % (label, tools))

    passing, out = verify(root)
    if passing:
        ok("%s: still verifies with test writes on" % label)
    else:
        fail("%s: enabling test writes broke the install: %s" % (label, out))

    # Turning it back off must withdraw the tools again -- a one-way grant
    # would leave the validator able to write for the rest of the install.
    ui.apply_setting(root, is_codex, "group.testWrites", False)
    if not is_codex:
        tools = re.search(r"(?m)^tools:\s*(.*)$",
                          read(os.path.join(root, "agents",
                                            "test-validator.md"))).group(1)
        if (re.search(r"\bEdit\b", tools)
                or re.search(r"\bWrite\b", tools)):
            fail("%s: validator kept Edit/Write after the flag went off: %s"
                 % (label, tools))
        else:
            ok("%s: validator lost Edit/Write with the flag" % label)
    passing, out = verify(root)
    if passing:
        ok("%s: still verifies with test writes back off" % label)
    else:
        fail("%s: disabling test writes broke the install: %s" % (label, out))

    # --- plain json settings ----------------------------------------------
    ui.apply_setting(root, is_codex, "workflow.judgePolicy", "always")
    ui.apply_setting(root, is_codex,
                     "workflow.agentTimeoutSeconds.resultJudge", 240)
    ui.apply_setting(root, is_codex, "capabilities.explicitDeny",
                     "some-server\nother-server")
    d = cfg(root)
    if (d["workflow"]["judgePolicy"] == "always"
            and d["workflow"]["agentTimeoutSeconds"]["resultJudge"] == 240
            and d["capabilities"]["explicitDeny"] == ["some-server",
                                                      "other-server"]):
        ok("%s: toggle, number and list settings written" % label)
    else:
        fail("%s: plain settings not written: %s" % (label, d["workflow"]))

    # --- the values that used to be locked --------------------------------
    # They were pinned only because check_json asserted the shipped default.
    # Now they are bounded, so the edit has to work AND stay verifiable.
    for fid, value in (("workflow.maximumParallelWorkers", 8),
                       ("workflow.maximumCorrectionCycles", 0),
                       ("workflow.maximumAgentRetries", 3),
                       ("memory.persistentAgentMemory", True),
                       ("memory.allowRepositoryMemoryWrites", True)):
        ui.apply_setting(root, is_codex, fid, value)
    d = cfg(root)
    if (d["workflow"]["maximumParallelWorkers"] == 8
            and d["workflow"]["maximumCorrectionCycles"] == 0
            and d["workflow"]["maximumAgentRetries"] == 3
            and d["memory"]["persistentAgentMemory"] is True
            and d["memory"]["allowRepositoryMemoryWrites"] is True):
        ok("%s: the unlocked values are writable at their bounds" % label)
    else:
        fail("%s: an unlocked value did not stick: %s" % (label, d["workflow"]))

    passing, out = verify(root)
    if passing:
        ok("%s: still verifies at the edge of every bound" % label)
    else:
        fail("%s: a bounded value broke the install: %s" % (label, out))

    # Out of range must fail in both places, or the UI and the verifier
    # disagree about what is allowed and one of them is wrong.
    for fid, value in (("workflow.maximumParallelWorkers", 9),
                       ("workflow.maximumCorrectionCycles", 6),
                       ("workflow.maximumAgentRetries", 4),
                       ("workflow.maximumParallelWorkers", 0)):
        try:
            ui.apply_setting(root, is_codex, fid, value)
        except ValueError:
            ok("%s: refused %s = %s (out of range)" % (label, fid, value))
        else:
            fail("%s: accepted %s = %s" % (label, fid, value))

    raw = json.loads(read(os.path.join(root, "orchestration.json")))
    raw["workflow"]["maximumParallelWorkers"] = 99
    with open(os.path.join(root, "orchestration.json"), "w",
              encoding="utf-8") as fh:
        json.dump(raw, fh, indent=2)
    passing, out = verify(root)
    if not passing and "maximumParallelWorkers" in out:
        ok("%s: the verifier catches an out-of-range value edited by hand"
           % label)
    else:
        fail("%s: verifier accepted maximumParallelWorkers=99" % label)
    ui.apply_setting(root, is_codex, "workflow.maximumParallelWorkers", 4)

    # The two rails are the reason the UI has a locked section at all, and
    # defaultGlobalAgent is a launch-time fact no file can change.
    for fid in ("locked.permissions.allowBypassPermissions",
                "locked.permissions.allowDestructiveGit",
                "defaultGlobalAgent"):
        try:
            ui.apply_setting(root, is_codex, fid, True)
        except (KeyError, ValueError):
            ok("%s: refused %s" % (label, fid.replace("locked.", "")))
        else:
            fail("%s: a browser tab switched off %s" % (label, fid))

    raw = json.loads(read(os.path.join(root, "orchestration.json")))
    raw["permissions"]["allowBypassPermissions"] = True
    with open(os.path.join(root, "orchestration.json"), "w",
              encoding="utf-8") as fh:
        json.dump(raw, fh, indent=2)
    passing, out = verify(root)
    if not passing and "allowBypassPermissions" in out:
        ok("%s: the verifier still pins allowBypassPermissions" % label)
    else:
        fail("%s: allowBypassPermissions is no longer enforced" % label)
    raw["permissions"]["allowBypassPermissions"] = False
    with open(os.path.join(root, "orchestration.json"), "w",
              encoding="utf-8") as fh:
        json.dump(raw, fh, indent=2)

    # --- refusals ----------------------------------------------------------
    for fid, value, why in (
            ("locked.schemaVersion", 3, "the schema version"),
            ("workflow.waitSliceSeconds", 0, "a non-positive timeout"),
            ("role.worker.model", "gpt-4", "a model outside the list"),
            ("no.such.setting", 1, "an unknown setting")):
        try:
            ui.apply_setting(root, is_codex, fid, value)
        except (KeyError, ValueError, TypeError):
            ok("%s: refused %s" % (label, why))
        else:
            fail("%s: accepted %s (%s)" % (label, why, fid))

    if is_codex:
        # The manager is the top-level session on Codex, so no .toml carries
        # its effort. The row is gone from the page; the writer must refuse it
        # too, or the API stays a way in.
        for fid in ("role.orchestrator.desiredEffort", "role.worker.model"):
            try:
                ui.apply_setting(root, True, fid, "high")
            except (KeyError, ValueError):
                ok("%s: refused %s -- Codex has nowhere to write it"
                   % (label, fid))
            else:
                fail("%s: accepted %s, which Codex cannot honour" % (label, fid))

    passing, out = verify(root)
    if passing:
        ok("%s: verifies after every change in this run" % label)
    else:
        fail("%s: install left failing: %s" % (label, out))

    # --- the platform offers only controls it can honour ------------------
    ids = [f["id"] for f in ui.build_fields(is_codex)]
    models = [i for i in ids if i.endswith(".model")]
    if is_codex:
        if models:
            fail("%s: offers a per-agent model picker Codex cannot honour: %s"
                 % (label, ", ".join(models)))
        else:
            ok("%s: no model rows -- Codex runs subagents on the session model"
               % label)
        if "role.orchestrator.desiredEffort" in ids:
            fail("%s: offers an effort for the manager, which has no .toml"
                 % label)
        else:
            ok("%s: no manager effort row (top-level session)" % label)
        if [i for i in ids if i.startswith("note.")]:
            ok("%s: explains why models are absent" % label)
        else:
            fail("%s: drops the model rows without saying why" % label)
    elif len(models) == 5:
        ok("%s: a model row per role" % label)
    else:
        fail("%s: expected 5 model rows, got %d" % (label, len(models)))

    # --- sync status ------------------------------------------------------
    hashes = os.path.join(root, "orchestrator-spec", "prompt-hashes.json")
    if os.path.isfile(hashes):
        os.remove(hashes)
    state_path = os.path.join(root, "orchestrator-spec", "install-state.json")
    state = json.loads(read(state_path))
    state["lastCheckedAt"] = None
    with open(state_path, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2)
    if ui.sync_status(root)["synced"]:
        fail("%s: a fresh install claims /orchestrate-sync has run" % label)
    else:
        ok("%s: fresh install reports /orchestrate-sync has not run" % label)

    # Either proof is enough: the skill blesses the hashes on its first step
    # and writes lastCheckedAt at the end, and a run can be seen mid-flight.
    subprocess.run([sys.executable,
                    os.path.join(root, "orchestrator-spec", "verify-install.py"),
                    "--bless", root], stdout=subprocess.DEVNULL)
    if ui.sync_status(root)["synced"]:
        ok("%s: blessed prompt hashes count as synced" % label)
    else:
        fail("%s: blessed hashes still report unsynced" % label)

    os.remove(hashes)
    state["lastCheckedAt"] = "2026-07-27"
    with open(state_path, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2)
    if ui.sync_status(root)["synced"]:
        ok("%s: a recorded lastCheckedAt counts as synced" % label)
    else:
        fail("%s: lastCheckedAt ignored" % label)

    # --- what the UI would show -------------------------------------------
    values = ui.current_values(root, is_codex)
    missing = [f["id"] for f in ui.build_fields(is_codex)
               if f["kind"] != "note" and f["id"] not in values]
    if missing:
        fail("%s: no value for %s" % (label, ", ".join(missing)))
    else:
        ok("%s: every field has a value to display" % label)

    if [t for t in ui.find_targets(root) if t[2] == root]:
        ok("%s: finds its own install" % label)
    else:
        fail("%s: find_targets missed its own directory" % label)


def check_server(root):
    """The endpoint's own guards, which no amount of client code can supply.

    The page hides settings until /orchestrate-sync has run; if the endpoint
    does not refuse them too, that is a rendering decision rather than a
    guarantee.
    """
    import http.server
    import threading
    import urllib.error
    import urllib.request

    label = os.path.basename(root)
    ui = load_ui(root)
    hashes = os.path.join(root, "orchestrator-spec", "prompt-hashes.json")
    if os.path.isfile(hashes):
        os.remove(hashes)
    state_path = os.path.join(root, "orchestrator-spec", "install-state.json")
    state = json.loads(read(state_path))
    state["lastCheckedAt"] = None
    with open(state_path, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2)

    ui.Handler.token = "test-token"
    ui.Handler.root = root
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), ui.Handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    base = "http://127.0.0.1:%d" % httpd.server_address[1]
    platform = "codex" if root.endswith(".codex") else "claude"

    def call(path, data=None):
        req = urllib.request.Request(
            base + path, data=data,
            headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                return r.status, r.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            return exc.code, exc.read().decode("utf-8", "replace")

    try:
        code, _ = call("/")
        if code == 403:
            ok("%s: server refuses a request with no token" % label)
        else:
            fail("%s: served the page without a token (%d)" % (label, code))

        body = json.dumps({"platform": platform,
                           "id": "workflow.validationPolicy",
                           "value": "always"}).encode("utf-8")
        code, out = call("/api/set?t=test-token", body)
        if code == 409 and "orchestrate-sync" in out:
            ok("%s: server refuses writes before /orchestrate-sync" % label)
        else:
            fail("%s: wrote a setting before sync (%d %s)" % (label, code, out))

        subprocess.run(
            [sys.executable, os.path.join(root, "orchestrator-spec",
                                          "verify-install.py"),
             "--bless", root], stdout=subprocess.DEVNULL)
        code, out = call("/api/set?t=test-token", body)
        if code == 200:
            ok("%s: server accepts writes once synced" % label)
        else:
            fail("%s: still refusing writes after sync (%d %s)"
                 % (label, code, out))
    finally:
        httpd.shutdown()
        httpd.server_close()


def check_profiles(root):
    """The dial: every stop lands, derives back, and touches nothing else."""
    label = os.path.basename(root)
    is_codex = root.endswith(".codex")
    ui = load_ui(root)

    if ui.derive_profile(ui.current_values(root, is_codex), is_codex) == "balanced":
        ok("%s: a fresh install reads as the Balanced profile" % label)
    else:
        fail("%s: fresh install does not match any profile -- the table and "
             "the shipped defaults disagree" % label)

    # What a profile must never be able to reach. Snapshotting the raw JSON
    # sections means a new permission key added later is covered for free.
    def guarded():
        d = json.loads(read(os.path.join(root, "orchestration.json")))
        return json.dumps({"permissions": d.get("permissions"),
                           "capabilities": d.get("capabilities"),
                           "memory": d.get("memory"),
                           "commands": d.get("commands"),
                           "worker.allowTestWrites":
                               d.get("worker", {}).get("allowTestWrites"),
                           "validator": dict(
                               (k, v) for k, v in d.get("validator", {}).items()
                               if k.startswith("allow"))}, sort_keys=True)

    before_guarded = guarded()
    for profile in ui.PROFILE_IDS:
        outcome = ui.apply_profile(root, is_codex, profile)
        got = ui.derive_profile(ui.current_values(root, is_codex), is_codex)
        if got != profile:
            fail("%s: applied %s but it reads back as %s" % (label, profile, got))
        elif outcome["verify"]["ok"] is not True:
            fail("%s: %s left the install failing: %s"
                 % (label, profile, outcome["verify"]["output"]))
        else:
            ok("%s: %s applied (%d settings) and reads back"
               % (label, profile, len(outcome["changed"])))

    if guarded() == before_guarded:
        ok("%s: no profile touched permissions, capabilities, memory or the "
           "write flags" % label)
    else:
        fail("%s: a profile changed a permission -- profiles must never widen "
             "what agents may do" % label)

    # No profile may ask for /orchestrate-sync. It writes models, effort,
    # deadlines and policy -- never a tool allowlist or an MCP map -- so a
    # prompt to re-sync could only ever be a false alarm. The first version of
    # this feature had one, and it fired on every synced Codex install.
    nagging = [p for p in ui.PROFILE_IDS
               if "resync" in ui.apply_profile(root, is_codex, p)]
    if nagging:
        fail("%s: %s asked for /orchestrate-sync; profiles never change "
             "routing" % (label, ", ".join(nagging)))
    else:
        ok("%s: no profile asks for a re-sync" % label)

    # One hand edit is enough to stop calling it a profile.
    ui.apply_setting(root, is_codex, "workflow.maximumCorrectionCycles", 4)
    if ui.derive_profile(ui.current_values(root, is_codex), is_codex) == "custom":
        ok("%s: one edit away from a profile reads as Custom" % label)
    else:
        fail("%s: still claims a profile after an edit that left it" % label)

    # Restore is what makes instant apply reversible.
    surface = ui.profile_surface(is_codex)
    snapshot = dict((k, ui.current_values(root, is_codex)[k]) for k in surface)
    ui.apply_profile(root, is_codex, "exhaustive")
    ui.restore_surface(root, is_codex, snapshot)
    restored = ui.current_values(root, is_codex)
    if all(restored[k] == v for k, v in snapshot.items()):
        ok("%s: restore puts every surface key back" % label)
    else:
        fail("%s: restore did not round-trip" % label)

    try:
        ui.restore_surface(root, is_codex,
                           {"permissions.allowExternalMutations": True})
    except ValueError:
        ok("%s: restore refuses keys outside the profile surface" % label)
    else:
        fail("%s: restore wrote a key no profile owns" % label)

    try:
        ui.apply_profile(root, is_codex, "nonsense")
    except ValueError:
        ok("%s: refuses an unknown profile" % label)
    else:
        fail("%s: accepted an unknown profile" % label)

    passing, out = verify(root)
    if passing:
        ok("%s: verifies after every profile in this run" % label)
    else:
        fail("%s: profiles left the install failing: %s" % (label, out))

    ui.apply_profile(root, is_codex, "balanced")


def check_profile_rollback(root):
    """A profile that would break the install must change nothing at all.

    Instant apply is only defensible if a bad apply undoes itself, so this
    forces one: a poisoned table entry that the verifier rejects.
    """
    label = os.path.basename(root)
    is_codex = root.endswith(".codex")
    ui = load_ui(root)
    ui.apply_profile(root, is_codex, "balanced")
    before = read(os.path.join(root, "orchestration.json"))

    original = ui.PROFILE_WORKFLOW["thorough"]["workflow.maximumParallelWorkers"]
    ui.PROFILE_WORKFLOW["thorough"]["workflow.maximumParallelWorkers"] = 4
    ui.apply_setting = ui.apply_setting  # unchanged; we poison via the verifier
    try:
        # schemaVersion is pinned, so writing it is a guaranteed verify failure
        # without needing an out-of-range value the writer would reject first.
        ui.PROFILE_WORKFLOW["thorough"]["schemaVersion"] = 99
        try:
            ui.apply_profile(root, is_codex, "thorough")
        except (ValueError, KeyError):
            after = read(os.path.join(root, "orchestration.json"))
            if after == before:
                ok("%s: a failing profile left the file byte-identical" % label)
            else:
                fail("%s: a failing profile still changed the config" % label)
        else:
            fail("%s: a profile the verifier rejects was applied anyway" % label)
    finally:
        ui.PROFILE_WORKFLOW["thorough"].pop("schemaVersion", None)
        ui.PROFILE_WORKFLOW["thorough"]["workflow.maximumParallelWorkers"] = original

    passing, _ = verify(root)
    if passing:
        ok("%s: still verifies after the rollback" % label)
    else:
        fail("%s: rollback left the install broken" % label)


def check_sync_modes(root):
    """--sync-start / --sync-finish carry the mechanical half of the skill.

    They exist so a small model does not have to sequence migrate, bless,
    verify and record itself, or judge from prose whether the fast path
    applies. Each printed NEXT: line is an instruction, so each one is worth
    a test.
    """
    label = os.path.basename(root)
    verifier = os.path.join(root, "orchestrator-spec", "verify-install.py")
    hashes = os.path.join(root, "orchestrator-spec", "prompt-hashes.json")
    state_path = os.path.join(root, "orchestrator-spec", "install-state.json")

    def run(*extra):
        proc = subprocess.run([sys.executable, verifier] + list(extra),
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        return proc.returncode, proc.stdout.decode("utf-8", "replace")

    if os.path.isfile(hashes):
        os.remove(hashes)
    state = json.loads(read(state_path))
    state["cliVersion"] = None
    state["lastCheckedAt"] = None
    with open(state_path, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2)

    # First run: blesses, and cannot claim the fast path with nothing recorded.
    code, out = run("--sync-start", root, "--cli-version", "cli 1.0")
    if code == 0 and "FULL-PASS" in out and "first run" in out:
        ok("%s: first --sync-start blesses and asks for a full pass" % label)
    else:
        fail("%s: first --sync-start said %r" % (label, out.strip()[-160:]))
    if os.path.isfile(hashes):
        ok("%s: prompt hashes recorded before any edit could happen" % label)
    else:
        fail("%s: --sync-start did not record the prompt hashes" % label)

    code, out = run("--sync-finish", root, "--cli-version", "cli 1.0")
    recorded = json.loads(read(state_path))
    if code == 0 and recorded.get("cliVersion") == "cli 1.0" \
            and recorded.get("lastCheckedAt"):
        ok("%s: --sync-finish records the version and the date" % label)
    else:
        fail("%s: --sync-finish left %s" % (label, recorded))

    # Same version -> the model is told to stop early.
    code, out = run("--sync-start", root, "--cli-version", "cli 1.0")
    if code == 0 and "FAST-PATH" in out:
        ok("%s: an unchanged CLI version takes the fast path" % label)
    else:
        fail("%s: unchanged version did not take the fast path: %r"
             % (label, out.strip()[-160:]))

    code, out = run("--sync-start", root, "--cli-version", "cli 2.0")
    if code == 0 and "FULL-PASS" in out:
        ok("%s: a changed CLI version forces a full pass" % label)
    else:
        fail("%s: changed version did not force a full pass" % label)

    # No version supplied must never be read as "nothing moved".
    code, out = run("--sync-start", root)
    if code == 0 and "FULL-PASS" in out:
        ok("%s: a missing version is not treated as unchanged" % label)
    else:
        fail("%s: missing version was not handled conservatively" % label)

    # A broken install must stop the run and must not update the state file.
    is_codex = root.endswith(".codex")
    stem = "result-judge" + (".toml" if is_codex else ".md")
    victim = os.path.join(root, "agents", stem)
    original = read(victim)
    with open(victim, "w", encoding="utf-8") as fh:
        fh.write(original.replace("## Independence (mandatory)",
                                  "## Independence (mandatory)\nBe nice.", 1))
    before_state = read(state_path)
    code, out = run("--sync-start", root, "--cli-version", "cli 2.0")
    if code == 1 and "NEXT: STOP" in out and "prompt body changed" in out:
        ok("%s: --sync-start stops on a reworded prompt body" % label)
    else:
        fail("%s: --sync-start missed a reworded prompt body (%d)" % (label, code))
    code, out = run("--sync-finish", root, "--cli-version", "cli 9.9")
    if code == 1 and read(state_path) == before_state:
        ok("%s: --sync-finish refuses to record a run that did not verify"
           % label)
    else:
        fail("%s: --sync-finish recorded state for a broken install" % label)

    with open(victim, "w", encoding="utf-8") as fh:
        fh.write(original)
    code, _ = run("--sync-finish", root, "--cli-version", "cli 2.0")
    if code == 0:
        ok("%s: verifies again once the prompt is restored" % label)
    else:
        fail("%s: still failing after restoring the prompt" % label)


def check_backup(root):
    """Export/import carries settings and refuses everything else.

    The point of the feature is that settings are portable and capabilities
    are not, so the tests that matter are the ones proving what does NOT
    travel: pinned flags, another platform's rows, and anything that would
    leave the install half-written.
    """
    label = os.path.basename(root)
    is_codex = root.endswith(".codex")
    ui = load_ui(root)

    bundle = ui.export_bundle(root)
    entry = None
    for item in bundle["installs"]:
        if item["platform"] == ("codex" if is_codex else "claude"):
            entry = item
    if entry is None:
        fail("%s: export did not include this install" % label)
        return
    if bundle["kind"] == "orchestrate-settings" and bundle["formatVersion"] == 1:
        ok("%s: export is tagged so a wrong file can be refused" % label)
    else:
        fail("%s: export is missing its kind/format tag" % label)

    # Capability data is derived per machine; carrying it would describe
    # servers that are not on the machine importing it.
    leaked = [k for k in entry["values"]
              if "tools" in k.lower() or "mcp" in k.lower()]
    if not leaked:
        ok("%s: export carries no tool allowlist or MCP routing" % label)
    else:
        fail("%s: export leaked capability data: %s" % (label, leaked))

    # Pinned permission flags must not travel either.
    pinned = [k for k in entry["values"] if k.startswith("locked.")]
    if not pinned:
        ok("%s: export carries no pinned permission flags" % label)
    else:
        fail("%s: export leaked pinned flags: %s" % (label, pinned))

    # One file covers every installed platform, from either tab -- the whole
    # point of a backup being one file.
    seen = sorted(i["platform"] for i in bundle["installs"])
    expected = sorted(t[0] for t in ui.find_targets(root)
                      if ui.sync_status(t[2])["synced"])
    if seen == expected and len(seen) > 1:
        ok("%s: one export covers both installed platforms" % label)
    elif seen == expected:
        ok("%s: the export covers every synced install (%s)"
           % (label, ", ".join(seen)))
    else:
        fail("%s: export covered %s, expected %s" % (label, seen, expected))

    # A platform in the file that is not installed here is skipped, not a
    # reason to refuse the rest.
    mixed = dict(bundle)
    mixed["installs"] = list(bundle["installs"]) + [
        {"platform": "some-other-cli", "label": "Some Other CLI",
         "values": {"workflow.maximumParallelWorkers": 2}}]
    outcome = ui.import_bundle(root, mixed)
    if "some-other-cli" in outcome["notInstalled"]:
        ok("%s: an uninstalled platform in the file is reported as skipped"
           % label)
    else:
        fail("%s: uninstalled platform was not reported: %s"
             % (label, outcome["notInstalled"]))
    if [i["platform"] for i in outcome["installs"]] == expected:
        ok("%s: the installed platforms still import alongside it" % label)
    else:
        fail("%s: a missing platform blocked the installed ones" % label)

    # But a file with nothing installable is an error, not a silent no-op.
    only_absent = dict(bundle)
    only_absent["installs"] = [{"platform": "some-other-cli",
                                "values": {}}]
    try:
        ui.import_bundle(root, only_absent)
        fail("%s: an export for no installed platform was accepted" % label)
    except ValueError:
        ok("%s: an export naming no installed platform is refused" % label)

    # --- round trip ---------------------------------------------------
    before = ui.current_values(root, is_codex)
    ui.apply_setting(root, is_codex, "workflow.maximumParallelWorkers", 7)
    ui.apply_setting(root, is_codex, "workflow.maximumCorrectionCycles", 1)
    moved = ui.current_values(root, is_codex)
    if moved["workflow.maximumParallelWorkers"] == 7:
        ok("%s: a setting changed so the restore has something to undo" % label)
    else:
        fail("%s: could not change a setting" % label)

    outcome = ui.import_bundle(root, bundle)
    restored = ui.current_values(root, is_codex)
    same = [k for k in entry["values"] if restored.get(k) != before.get(k)]
    if not same:
        ok("%s: importing the export restores every exported setting" % label)
    else:
        fail("%s: import did not restore %s" % (label, same))
    if outcome["installs"][0]["verify"]["ok"] is True:
        ok("%s: the install still verifies after an import" % label)
    else:
        fail("%s: import left the install failing verification" % label)

    # --- what must not be written -------------------------------------
    hostile = dict(bundle)
    hostile["installs"] = [dict(entry, values=dict(
        entry["values"],
        **{"locked.permissions.allowBypassPermissions": True,
           "role.orchestrator.model" if is_codex else "nonsense.key": "opus",
           "totally.made.up": 5}))]
    outcome = ui.import_bundle(root, hostile)
    notes = " ".join(outcome["installs"][0]["notes"])
    after = ui.current_values(root, is_codex)
    if after.get("locked.permissions.allowBypassPermissions") in (False, None):
        ok("%s: an import cannot flip a pinned permission flag" % label)
    else:
        fail("%s: an import flipped a pinned permission flag" % label)
    if "pinned or read-only" in notes:
        ok("%s: the pinned flag is reported as refused, not as a typo" % label)
    else:
        fail("%s: pinned flag was not reported: %s" % (label, notes))
    if "totally.made.up: unknown setting" in notes:
        ok("%s: an unknown key is reported rather than silently dropped" % label)
    else:
        fail("%s: unknown key was not reported: %s" % (label, notes))
    if is_codex and "not a setting on this platform" in notes:
        ok("%s: a Claude-only row is refused on Codex" % label)
    elif not is_codex:
        ok("%s: (platform-mismatch note is exercised on the Codex install)"
           % label)
    else:
        fail("%s: Codex accepted a Claude-only row: %s" % (label, notes))

    # --- atomicity ----------------------------------------------------
    snapshot = read(os.path.join(root, "orchestration.json"))
    broken = dict(bundle)
    broken["installs"] = [dict(entry, values=dict(
        entry["values"], **{"workflow.maximumParallelWorkers": 9999}))]
    try:
        ui.import_bundle(root, broken)
        fail("%s: an out-of-range value was accepted" % label)
    except (ValueError, TypeError):
        if read(os.path.join(root, "orchestration.json")) == snapshot:
            ok("%s: a refused import writes nothing at all" % label)
        else:
            fail("%s: a refused import still changed orchestration.json" % label)

    # A file that is not ours, and one that is corrupt.
    for bad, why in (({"kind": "something-else"}, "a foreign file"),
                     ({"kind": "orchestrate-settings", "formatVersion": 99,
                       "installs": []}, "a newer format"),
                     ({"kind": "orchestrate-settings", "formatVersion": 1,
                       "installs": []}, "an empty export")):
        try:
            ui.import_bundle(root, bad)
            fail("%s: %s was accepted" % (label, why))
        except (ValueError, TypeError):
            ok("%s: %s is refused" % (label, why))

    # --- rollback when the install itself is broken -------------------
    stem = "result-judge" + (".toml" if is_codex else ".md")
    victim = os.path.join(root, "agents", stem)
    original = read(victim)
    with open(victim, "w", encoding="utf-8") as fh:
        fh.write(original.replace("## Independence (mandatory)",
                                  "## Independence (mandatory)\nBe nice.", 1))
    ui.apply_setting(root, is_codex, "workflow.maximumParallelWorkers", 3)
    guard = read(os.path.join(root, "orchestration.json"))
    try:
        ui.import_bundle(root, bundle)
        fail("%s: imported into an install that does not verify" % label)
    except ValueError:
        if read(os.path.join(root, "orchestration.json")) == guard:
            ok("%s: a failing verify rolls the import back" % label)
        else:
            fail("%s: import left settings behind after a failed verify" % label)
    with open(victim, "w", encoding="utf-8") as fh:
        fh.write(original)

    ui.import_bundle(root, bundle)
    good, out = verify(root)
    if good:
        ok("%s: the install is back to the exported state and verifies" % label)
    else:
        fail("%s: could not restore the install: %s" % (label, out[-160:]))

    # --- a machine that has never synced ------------------------------
    # The restore case that matters: fresh install, nothing reconciled yet.
    # Settings and capabilities are disjoint, so this must be allowed --
    # gating it would refuse the only situation an export is really for.
    hashes = os.path.join(root, "orchestrator-spec", "prompt-hashes.json")
    state_path = os.path.join(root, "orchestrator-spec", "install-state.json")
    keep_hashes = read(hashes) if os.path.isfile(hashes) else None
    keep_state = read(state_path)
    os.remove(hashes)
    state = json.loads(keep_state)
    state["lastCheckedAt"] = None
    with open(state_path, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2)

    if not ui.sync_status(root)["synced"]:
        ok("%s: the install reads as never-synced for this check" % label)
    else:
        fail("%s: could not make the install look unsynced" % label)

    ui.apply_setting(root, is_codex, "workflow.maximumParallelWorkers", 5)
    try:
        outcome = ui.import_bundle(root, bundle)
        after = ui.current_values(root, is_codex)
        want = entry["values"]["workflow.maximumParallelWorkers"]
        if after["workflow.maximumParallelWorkers"] == want:
            ok("%s: settings can be restored before /orchestrate-sync has run"
               % label)
        else:
            fail("%s: pre-sync import did not write the settings" % label)
    except ValueError as exc:
        fail("%s: pre-sync import was refused: %s" % (label, exc))

    # Importing must not fake having been synced.
    if not ui.sync_status(root)["synced"]:
        ok("%s: an import does not make an unsynced install look synced" % label)
    else:
        fail("%s: an import marked the install as synced" % label)

    if keep_hashes is not None:
        with open(hashes, "w", encoding="utf-8") as fh:
            fh.write(keep_hashes)
    with open(state_path, "w", encoding="utf-8") as fh:
        fh.write(keep_state)
    ui.import_bundle(root, bundle)


def check_migration(root):
    """An upgrade keeps your orchestration.json, so something has to move it
    forward. Neither installer can parse JSON, so verify-install.py does it."""
    label = os.path.basename(root)
    path = os.path.join(root, "orchestration.json")
    verifier = os.path.join(root, "orchestrator-spec", "verify-install.py")

    d = json.loads(read(path))
    d["schemaVersion"] = 2
    for key in ("researchPolicy", "judgePolicy", "validationPolicy"):
        d["workflow"].pop(key, None)
    d["workflow"]["requireIndependentJudge"] = True
    d["workflow"]["requireValidation"] = False
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(d, fh, indent=2)

    passing, out = verify(root)
    if not passing and "--migrate" in out:
        ok("%s: a v2 config fails with the migrate command in the message"
           % label)
    else:
        fail("%s: v2 config was not reported as needing migration: %s"
             % (label, out))

    proc = subprocess.run([sys.executable, verifier, "--migrate", root],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    first = proc.stdout.decode("utf-8", "replace").strip()
    d = json.loads(read(path))
    wf = d["workflow"]
    kn = d.get("knowledge", {})
    if (proc.returncode == 0 and d["schemaVersion"] == 4
            and wf["judgePolicy"] == "always"      # was requireIndependentJudge
            and wf["validationPolicy"] == "auto"   # false meant "manager decides"
            and wf["researchPolicy"] == "auto"
            # 3 -> 4 backfills the knowledge block, with proposals off: a
            # migration must never hand an old install a new write.
            and kn.get("enabled") is True
            and kn.get("allowProposals") is False):
        ok("%s: migrated to v4 with policies derived from the old booleans "
           "and the knowledge block backfilled" % label)
    else:
        fail("%s: migration produced %s (%s)" % (label, wf, first))

    passing, out = verify(root)
    if passing:
        ok("%s: verifies after migrating" % label)
    else:
        fail("%s: still fails after migrating: %s" % (label, out))

    before = read(path)
    subprocess.run([sys.executable, verifier, "--migrate", root],
                   stdout=subprocess.DEVNULL)
    if read(path) == before:
        ok("%s: migrating twice changes nothing" % label)
    else:
        fail("%s: a second migration rewrote the file" % label)


# A field may be absent from the prompts only for a reason written down here.
# Anything else that writes cleanly and is never read is the bug this test
# exists for -- the state the bundle was in before profiles, when half the
# page moved keys nothing consulted.
BINDING_EXEMPT = {
    "role.": "model and effort are frontmatter/TOML, not prompt text",
}

# The JSON keys a field writes, where the id is not the key.
BINDING_ALIASES = {
    "group.testWrites": ("allowTestWrites", "allowTestFileCreation"),
    "group.buildCommands": ("allowBuildCommands",),
    "group.serveCommands": ("allowServeCommands",),
    "workflow.agentTimeoutSeconds.": ("agentTimeoutSeconds",),
}


def binding_names(fid):
    for prefix, names in BINDING_ALIASES.items():
        if fid == prefix or fid.startswith(prefix) and prefix.endswith("."):
            return names
    return (fid.split(".")[-1],)


def check_page_script(repo_root):
    """node --check on the page's JavaScript, when node is on PATH.

    Skipped rather than failed without node: the bundle does not need node,
    and a check that cannot run is not a reason to fail an install test.
    """
    import shutil
    import tempfile

    node = shutil.which("node")
    if not node:
        print("SKIP: node not on PATH -- page script not syntax-checked")
        return
    ui = load_ui_from(os.path.join(repo_root, "templates", "orchestrator-spec",
                                   "config-ui.py"))
    path = os.path.join(tempfile.gettempdir(), "orch_ui_script_check.js")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(ui.SCRIPT)
    proc = subprocess.run([node, "--check", path],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    os.remove(path)
    if proc.returncode == 0:
        ok("page script parses as JavaScript")
    else:
        fail("page script has a syntax error: %s"
             % proc.stdout.decode("utf-8", "replace").strip().splitlines()[:4])


def check_page_styles(repo_root):
    """A class the page emits with no CSS rule behind it.

    That is how the re-sync banner ended up as a bare exclamation mark: the
    markup kept its class after the stylesheet lost the rule, and every other
    check still passed.
    """
    ui = load_ui_from(os.path.join(repo_root, "templates", "orchestrator-spec",
                                   "config-ui.py"))
    used = set()
    for m in re.finditer(r'el\("[a-z]+",\s*"([^"]+)"', ui.SCRIPT):
        used.update(m.group(1).split())
    for m in re.finditer(r'classList\.(?:add|toggle)\("([^"]+)"', ui.SCRIPT):
        used.add(m.group(1))
    missing = sorted(c for c in used if ("." + c) not in ui.STYLE)
    if missing:
        fail("page emits classes with no CSS rule: %s" % ", ".join(missing))
    else:
        ok("every class the page emits has a style (%d)" % len(used))


def check_binding(repo_root):
    """Every editable setting must be named by a prompt, or be read-only.

    Read-only rows state a fact the prompts enforce unconditionally; editable
    rows promise the value is consulted. This test holds the page to that
    promise for both platforms.
    """
    prompt_sets = {}
    for label, paths in (
        ("claude", ["templates/agents/task-orchestrator.md",
                    "templates/agents/implementation-worker.md",
                    "templates/agents/test-validator.md",
                    "templates/agents/result-judge.md",
                    "templates/agents/codebase-researcher.md"]),
        ("codex", ["templates/codex/agents/task-orchestrator.md",
                   "templates/codex/agents/implementation-worker.toml",
                   "templates/codex/agents/test-validator.toml",
                   "templates/codex/agents/result-judge.toml",
                   "templates/codex/agents/codebase-researcher.toml"]),
    ):
        missing_file = [q for q in paths
                        if not os.path.isfile(os.path.join(repo_root, q))]
        if missing_file:
            fail("binding: missing %s" % ", ".join(missing_file))
            return
        prompt_sets[label] = "\n".join(
            read(os.path.join(repo_root, q)) for q in paths)

    ui = load_ui_from(os.path.join(repo_root, "templates", "orchestrator-spec",
                                   "config-ui.py"))
    for is_codex, label in ((False, "claude"), (True, "codex")):
        unread = []
        for f in ui.build_fields(is_codex):
            fid = f["id"]
            if f["kind"] in ("note", "readonly") or fid.startswith("locked."):
                continue
            if any(fid.startswith(k) for k in BINDING_EXEMPT):
                continue
            if not any(n in prompt_sets[label] for n in binding_names(fid)):
                unread.append(fid)
        if unread:
            fail("%s: %d editable setting(s) no prompt reads, so changing them "
                 "does nothing: %s" % (label, len(unread), ", ".join(unread)))
        else:
            ok("%s: every editable setting is named by a prompt" % label)


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    # Profiles first: they assert what a FRESH install reads as, and every
    # later check deliberately changes settings.
    for root in argv:
        check_profiles(os.path.abspath(root))
        check_profile_rollback(os.path.abspath(root))
    for root in argv:
        check(os.path.abspath(root))
    check_server(os.path.abspath(argv[0]))
    check_migration(os.path.abspath(argv[0]))
    for root in argv:
        check_sync_modes(os.path.abspath(root))
    for root in argv:
        check_backup(os.path.abspath(root))
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    check_binding(repo)
    check_page_script(repo)
    check_page_styles(repo)
    print("")
    if FAILURES:
        print("%d CHECK(S) FAILED" % len(FAILURES))
        return 1
    print("config-ui: ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
