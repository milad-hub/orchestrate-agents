#!/usr/bin/env python3
"""Browser UI for an installed orchestrate bundle's settings.

    python3 config-ui.py [--port N] [--no-browser] [--dir <install-dir>]

Serves one page on 127.0.0.1 with a tab per installed platform. Both tabs are
found from this file's own location: config-ui.py lives in <target>/
orchestrator-spec/, and the sibling target is the .claude/.codex next to it,
so a single copy manages both.

Every setting here is one of three kinds:

  json only    -- lives in orchestration.json and nowhere else.
  fanned out   -- one answer, several keys. The installer writes them
                  together; so does this UI, because verify-install.py fails
                  an install whose copies disagree.
  three-way    -- model and effort must match in orchestration.json, the
                  agent file's frontmatter (or TOML), and the README config
                  table. All three are written, or none.

Saving re-runs verify-install.py and shows what it says, so a setting that
breaks the install says so immediately instead of at the next /orchestrate.

Stdlib only, no third-party imports, so it runs wherever python3 does.
"""
import argparse
import datetime
import http.server
import json
import os
import re
import secrets
import subprocess
import sys
import threading
import webbrowser

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.dirname(HERE)

MODELS = ("opus", "sonnet", "haiku", "inherit")
EFFORTS = ("low", "medium", "high")

# orchestration.json key -> agent file stem
ROLE_STEMS = {
    "orchestrator": "task-orchestrator",
    "researcher": "codebase-researcher",
    "worker": "implementation-worker",
    "validator": "test-validator",
    "judge": "result-judge",
}
ROLE_LABELS = {
    "orchestrator": "Manager",
    "researcher": "Researcher",
    "worker": "Worker",
    "validator": "Validator",
    "judge": "Judge",
}

# Values verify-install.py asserts outright. Shown, never editable: they are
# the bundle's safety rails, and changing one here would just hand you an
# install that fails its own verifier on the next run.
# Three values verify-install.py pins outright, for two different reasons.
# schemaVersion is not a setting -- it says which layout the file is parsed
# against. The other two are the harness guardrails the whole design rests on:
# delegates are held back by the permission system rather than by their
# prompts, so these stay a deliberate hand edit, not something a browser tab
# can switch off. Everything else that used to sit here is now editable and
# merely bounded.
LOCKED = (
    ("schemaVersion", "Schema version",
     "Which orchestration.json layout this is. Bumped by an upgrade, not by you."),
    ("permissions.allowBypassPermissions", "Allow permission bypass",
     "Off, and not switchable here. Delegates never run with the permission "
     "prompt disabled -- that is what stops a prompt being the only thing "
     "between an agent and your machine."),
    ("permissions.allowDestructiveGit", "Allow destructive git",
     "Off, and not switchable here. No reset --hard, no force push, no "
     "history rewriting."),
)


def field(fid, cat, title, sub, kind, **kw):
    f = {"id": fid, "category": cat, "title": title, "subtitle": sub,
         "kind": kind}
    f.update(kw)
    return f


def build_fields(is_codex):
    """The settings this UI offers, in display order."""
    out = []

    if is_codex:
        # No model rows. Codex runs every subagent on the session's model, so
        # a per-agent model picker here would be a control that changes
        # nothing but a line in a JSON file.
        cat = "Reasoning effort"
        out.append(field(
            "note.codexModels", cat, "Models are a session setting on Codex.",
            "Every subagent runs on the model of the session that spawned it, "
            "so there is no per-agent model to pick. Reasoning effort is "
            "per-agent, and that is what this bundle sets.", "note"))
        for key, label in ROLE_LABELS.items():
            # The Codex manager is the top-level session, not a subagent:
            # there is no .toml to carry an effort setting for it.
            if key == "orchestrator":
                continue
            out.append(field(
                "role.%s.desiredEffort" % key, cat, "%s reasoning effort" % label,
                "Written to orchestration.json, the agent's .toml "
                "(model_reasoning_effort) and the README table together.",
                "enum", options=list(EFFORTS)))
    else:
        cat = "Models & effort"
        for key, label in ROLE_LABELS.items():
            out.append(field(
                "role.%s.model" % key, cat, "%s model" % label,
                "Written to orchestration.json, the agent's frontmatter and "
                "the README table together.",
                "enum", options=list(MODELS)))
            out.append(field(
                "role.%s.desiredEffort" % key, cat, "%s effort" % label,
                "How hard this role thinks. Higher costs more and takes longer.",
                "enum", options=list(EFFORTS)))

    cat = "Permissions & writes"
    tw_sub = ("Off by default. Turning it on sets worker.allowTestWrites, "
              "validator.allowTestWrites and commands.allowTestFileCreation "
              "together")
    if not is_codex:
        tw_sub += (", and grants the validator Edit and Write in its tools "
                   "allowlist -- the harness enforces it, not the prompt")
    out.append(field("group.testWrites", cat, "Allow test-file writes",
                     tw_sub + ".", "toggle"))
    out.append(field("group.buildCommands", cat, "Allow build commands",
                     "Off by default. Sets commands.allowBuildCommands and "
                     "validator.allowBuildCommands together.", "toggle"))
    out.append(field("group.serveCommands", cat, "Allow serve / dev-server commands",
                     "Off by default. A dev server that never exits is the "
                     "usual cause of a delegate burning its whole timeout.",
                     "toggle"))
    out.append(field("validator.allowProductionWrites", cat,
                     "Validator may write production source",
                     "Always off, and not a switch: the validator's prompt "
                     "forbids production edits and its tool allowlist "
                     "withholds Edit/Write unless test writes are on.",
                     "readonly"))
    out.append(field(
        "worker.worktreeIsolation", cat, "Worker worktree isolation",
        "Always on. Codex isolates spawned agents natively; on Claude the "
        "manager spawns workers with isolation: worktree unconditionally."
        if is_codex else
        "Always on. The manager spawns every worker with "
        "isolation: worktree, so parallel workers cannot collide.",
        "readonly"))
    out.append(field("permissions.policy", cat, "Permission policy",
                     "Balanced is the only posture this bundle defines -- "
                     "policies/permissions.md and the delegate prompts are "
                     "written against it, so another value would name nothing.",
                     "readonly"))
    out.append(field("permissions.allowExternalMutations", cat,
                     "Allow external mutations",
                     "Writes that leave the repository: pushing, posting, "
                     "calling a live API.", "toggle"))
    out.append(field("permissions.requireApprovalForExternalMutations", cat,
                     "Approve external mutations",
                     "Ask before each one, even when the above is on. The "
                     "manager gates every mutation on this.", "toggle"))

    cat = "Workflow & review"
    # The floor the design rests on. The prompts make these mandatory whatever
    # the config says, and no profile touches them -- so they are shown as
    # facts rather than as switches that would silently do nothing.
    for key, title, sub in (
        ("requireAcceptanceCriteria", "Require acceptance criteria",
         "Always on. No work starts until the task states what done means."),
        ("requireManagerReview", "Require manager review",
         "Always on. The manager reads every delegate's diff itself; this is "
         "what stands in for the judge when no judge is warranted."),
        ("requireFinalDiffReview", "Require final diff review",
         "Always on. One review of the whole change at the end, not just "
         "per delegate."),
        ("avoidOverlappingEdits", "Avoid overlapping edits",
         "Always on. Two workers are never given the same file in one round."),
    ):
        out.append(field("workflow." + key, cat, title, sub, "readonly"))
    for key, title, sub in (
        ("researchPolicy", "Researcher",
         "never skips research entirely; auto lets the manager decide from "
         "the task class; always researches before touching anything."),
        ("judgePolicy", "Independent judge",
         "never means the manager's own compliance gate is the only review; "
         "auto judges complex or risky work; always judges every run."),
        ("validationPolicy", "Validation",
         "never skips tests, lint and type-checks; auto decides per task; "
         "always validates before returning a result."),
    ):
        out.append(field("workflow." + key, cat, title, sub, "enum",
                         options=["never", "auto", "always"]))
    for key, title, sub in (
        ("delegateOnlyWhenUseful", "Delegate only when useful",
         "Small tasks run in the manager instead of paying for a delegate round trip."),
    ):
        out.append(field("workflow." + key, cat, title, sub, "toggle"))
    out.append(field("workflow.maximumParallelWorkers", cat,
                     "Max parallel workers",
                     "Delegates the manager may run at once. On Codex, "
                     "max_concurrent_threads_per_session in ~/.codex/config.toml "
                     "must be at least this or they queue.",
                     "int", min=1, max=8))
    out.append(field("workflow.maximumCorrectionCycles", cat,
                     "Max correction cycles",
                     "How many times work may bounce back after a rejection "
                     "before the run stops and reports. Zero means one shot.",
                     "int", min=0, max=5))
    out.append(field("workflow.maximumAgentRetries", cat, "Max agent retries",
                     "Retries for a delegate that failed outright. Zero "
                     "reports the failure instead of quietly running it again "
                     "and paying twice.", "int", min=0, max=3))
    out.append(field("defaultGlobalAgent", cat, "Default global agent",
                     "Off. Whether the manager is your session's default agent "
                     "is decided by how you launch the CLI, not by this file, "
                     "so nothing here can change it.", "readonly"))

    cat = "Timeouts"
    if is_codex:
        # Claude's manager is told not to poll at all -- it waits on the
        # delegate -- so offering a polling interval there described nothing.
        out.append(field("workflow.waitSliceSeconds", cat, "Wait slice",
                         "How long the manager waits between checks on running "
                         "subagents. Seconds.", "int"))
    for key, label, sub in (
        ("codebaseResearcher", "Researcher timeout",
         "Research is reading, not building; a long one usually means a bad question."),
        ("implementationWorker", "Worker timeout",
         "The longest of the five -- this is the one doing the editing."),
        ("testValidator", "Validator timeout",
         "Long enough for the suite, short enough that a hung dev server is caught."),
        ("resultJudge", "Judge timeout",
         "The judge reads and rules; it never edits."),
        ("correctionWorker", "Correction worker timeout",
         "A correction round is narrower than the original task."),
    ):
        out.append(field("workflow.agentTimeoutSeconds." + key, cat, label,
                         sub + " Seconds.", "int"))

    cat = "Memory"
    out.append(field("memory.allowRepositoryMemoryLookup", cat,
                     "Repository memory lookup",
                     "Delegates may read an indexed memory of the repo when "
                     "one exists.", "toggle"))
    out.append(field("memory.persistentAgentMemory", cat,
                     "Persistent agent memory",
                     "Off, delegates start every run cold. On, they carry "
                     "state between runs -- which also means a wrong idea "
                     "survives the run that formed it.", "toggle"))
    out.append(field("memory.allowRepositoryMemoryWrites", cat,
                     "Repository memory writes",
                     "Let agents write back to the repository's memory index, "
                     "not just read it.", "toggle"))

    cat = "Capabilities"
    out.append(field("capabilities.explicitAllow", cat, "Explicit allow list",
                     "Capabilities always offered to delegates, whatever the "
                     "policy says. One per line.", "list"))
    out.append(field("capabilities.explicitDeny", cat, "Explicit deny list",
                     "Capabilities never offered. /orchestrate-sync adds "
                     "servers it finds are gone. One per line.", "list"))

    cat = "Enforced by verify-install.py"
    for path, title, sub in LOCKED:
        out.append(field("locked." + path, cat, title, sub, "readonly"))
    return out


# ------------------------------------------------------------ profiles ----

# One dial from cheap-and-quick to slow-and-certain. Discrete stops, not a
# continuous slider: these are policies and whole numbers, and interpolating
# them would invent configurations nobody chose.
#
# The surface below is the complete list of keys a profile writes. Permissions,
# capabilities, memory and the test-write/build/serve flags are deliberately
# absent -- a profile can never widen a permission, and there is a test that
# holds it to that.
PROFILE_IDS = ("swift", "balanced", "thorough", "exhaustive")
PROFILE_LABELS = {
    "swift": "Swift",
    "balanced": "Balanced",
    "thorough": "Thorough",
    "exhaustive": "Exhaustive",
}
PROFILE_BLURBS = {
    "swift": "One worker, no research, no judge, no validation gate. Cheapest "
             "and quickest; the manager's own review is the only check.",
    "balanced": "What the bundle ships. The manager decides who is involved "
                "from the task's class.",
    "thorough": "Judge and validation on every run, stronger models for "
                "review, more room to correct.",
    "exhaustive": "Everything on, best models, longest deadlines. For work you "
                  "would not ship without a second opinion.",
}

# Workflow half -- identical on both platforms.
PROFILE_WORKFLOW = {
    "swift": {
        "workflow.researchPolicy": "never",
        "workflow.judgePolicy": "never",
        "workflow.validationPolicy": "never",
        "workflow.maximumParallelWorkers": 1,
        "workflow.maximumCorrectionCycles": 0,
        "workflow.maximumAgentRetries": 0,
        "workflow.delegateOnlyWhenUseful": True,
    },
    "balanced": {
        "workflow.researchPolicy": "auto",
        "workflow.judgePolicy": "auto",
        "workflow.validationPolicy": "auto",
        "workflow.maximumParallelWorkers": 4,
        "workflow.maximumCorrectionCycles": 2,
        "workflow.maximumAgentRetries": 0,
        "workflow.delegateOnlyWhenUseful": True,
    },
    "thorough": {
        "workflow.researchPolicy": "auto",
        "workflow.judgePolicy": "always",
        "workflow.validationPolicy": "always",
        "workflow.maximumParallelWorkers": 4,
        "workflow.maximumCorrectionCycles": 3,
        "workflow.maximumAgentRetries": 1,
        "workflow.delegateOnlyWhenUseful": True,
    },
    "exhaustive": {
        "workflow.researchPolicy": "always",
        "workflow.judgePolicy": "always",
        "workflow.validationPolicy": "always",
        "workflow.maximumParallelWorkers": 6,
        "workflow.maximumCorrectionCycles": 5,
        "workflow.maximumAgentRetries": 1,
        "workflow.delegateOnlyWhenUseful": False,
    },
}

# Effort per role. Codex stops here: it runs subagents on the session model.
PROFILE_EFFORT = {
    "swift": {"orchestrator": "medium", "researcher": "low", "worker": "medium",
              "validator": "low", "judge": "medium"},
    "balanced": {"orchestrator": "high", "researcher": "medium",
                 "worker": "medium", "validator": "medium", "judge": "high"},
    "thorough": {"orchestrator": "high", "researcher": "medium",
                 "worker": "high", "validator": "medium", "judge": "high"},
    "exhaustive": {"orchestrator": "high", "researcher": "high",
                   "worker": "high", "validator": "high", "judge": "high"},
}
PROFILE_MODEL = {
    "swift": {"orchestrator": "sonnet", "researcher": "haiku",
              "worker": "haiku", "validator": "haiku", "judge": "sonnet"},
    "balanced": {"orchestrator": "opus", "researcher": "haiku",
                 "worker": "sonnet", "validator": "haiku", "judge": "sonnet"},
    "thorough": {"orchestrator": "opus", "researcher": "sonnet",
                 "worker": "sonnet", "validator": "haiku", "judge": "opus"},
    "exhaustive": {"orchestrator": "opus", "researcher": "sonnet",
                   "worker": "opus", "validator": "sonnet", "judge": "opus"},
}
# Deadlines scale with the profile: an exhaustive run that times out at the
# quick profile's limits is just an expensive failure.
PROFILE_TIMEOUT_SCALE = {"swift": 0.6, "balanced": 1.0,
                         "thorough": 1.5, "exhaustive": 2.0}
BASE_TIMEOUTS = {"codebaseResearcher": 180, "implementationWorker": 900,
                 "testValidator": 300, "resultJudge": 180,
                 "correctionWorker": 300}


def profile_values(profile, is_codex):
    """Every key a profile writes, and what it writes there."""
    out = dict(PROFILE_WORKFLOW[profile])
    for role, effort in PROFILE_EFFORT[profile].items():
        if is_codex and role == "orchestrator":
            continue  # top-level session: no .toml to carry an effort
        out["role.%s.desiredEffort" % role] = effort
    if not is_codex:
        for role, model in PROFILE_MODEL[profile].items():
            out["role.%s.model" % role] = model
    scale = PROFILE_TIMEOUT_SCALE[profile]
    for key, base in BASE_TIMEOUTS.items():
        out["workflow.agentTimeoutSeconds.%s" % key] = int(round(base * scale))
    return out


def profile_surface(is_codex):
    """The keys profiles own, so everything else is provably untouched."""
    return sorted(profile_values("balanced", is_codex))


def derive_profile(values, is_codex):
    """Which profile the current settings are, or 'custom'.

    Derived rather than stored: a recorded name goes stale the moment someone
    changes one toggle, and then the dial lies about what is configured.
    """
    for profile in PROFILE_IDS:
        wanted = profile_values(profile, is_codex)
        if all(values.get(k) == v for k, v in wanted.items()):
            return profile
    return "custom"


def profiles_for(is_codex):
    return [{"id": p, "label": PROFILE_LABELS[p], "blurb": PROFILE_BLURBS[p],
             "values": profile_values(p, is_codex)} for p in PROFILE_IDS]


# ------------------------------------------------------------- json io ----

def load_json(root):
    with open(os.path.join(root, "orchestration.json"), encoding="utf-8") as fh:
        return json.load(fh)


def save_json(root, data):
    path = os.path.join(root, "orchestration.json")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)


def dig(data, dotted):
    node = data
    for part in dotted.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def put(data, dotted, value):
    parts = dotted.split(".")
    node = data
    for part in parts[:-1]:
        node = node.setdefault(part, {})
    node[parts[-1]] = value


def read_text(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write_text(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    os.replace(tmp, path)


# ------------------------------------------------------------- reading ----

def current_values(root, is_codex):
    """Every field's value, keyed by field id."""
    data = load_json(root)
    out = {}
    for key in ROLE_STEMS:
        out["role.%s.model" % key] = dig(data, "%s.model" % key)
        out["role.%s.desiredEffort" % key] = dig(data, "%s.desiredEffort" % key)
    out["group.testWrites"] = bool(dig(data, "worker.allowTestWrites"))
    out["group.buildCommands"] = bool(dig(data, "commands.allowBuildCommands"))
    out["group.serveCommands"] = bool(dig(data, "commands.allowServeCommands"))
    for f in build_fields(is_codex):
        fid = f["id"]
        if fid in out or f["kind"] == "note":
            continue
        if fid.startswith("locked."):
            out[fid] = dig(data, fid[len("locked."):])
        else:
            out[fid] = dig(data, fid)
    return out


def sync_status(root):
    """Has /orchestrate-sync run against this install yet?

    Until it has, the tool allowlists, MCP routing and capability deny list
    are the bundle's defaults rather than anything derived from this machine,
    so the page would be describing an install nobody has reconciled. The
    installer writes lastCheckedAt as null and ships no prompt-hashes.json;
    the skill fills in the first and writes the second on its opening step,
    so either one is proof it ran.
    """
    checked = None
    state = os.path.join(root, "orchestrator-spec", "install-state.json")
    if os.path.isfile(state):
        try:
            checked = json.loads(read_text(state)).get("lastCheckedAt")
        except ValueError:
            checked = None
    blessed = os.path.isfile(os.path.join(root, "orchestrator-spec",
                                          "prompt-hashes.json"))
    return {"synced": bool(checked) or blessed, "lastCheckedAt": checked}


# ------------------------------------------------------------- writing ----

class Batch(object):
    """Every edit of one logical change, held until all of it is ready.

    A profile moves a dozen settings across orchestration.json, five agent
    files and the README. Writing them one at a time leaves a window where
    some have moved and some have not, which is precisely the state the
    verifier reports as a broken install.
    """

    def __init__(self, root):
        self.root = root
        self.json = load_json(root)
        self.files = {}

    def read(self, path):
        if path not in self.files:
            self.files[path] = read_text(path)
        return self.files[path]

    def write(self, path, text):
        self.files[path] = text

    def flush(self):
        save_json(self.root, self.json)
        for path, text in sorted(self.files.items()):
            write_text(path, text)



def set_readme_cell(root, stem, column, value, batch=None):
    """Rewrite one cell of the README configuration table.

    verify-install.py reads that table as a third copy of model/effort; a row
    left stale is a failure, so it is written in the same breath as the JSON.
    """
    path = os.path.join(root, "README-orchestration.md")
    if not os.path.isfile(path):
        return
    source = batch.read(path) if batch else read_text(path)
    lines = source.splitlines(True)
    for i, line in enumerate(lines):
        if not line.startswith("|"):
            continue
        stripped = line.rstrip("\r\n")
        cells = [c.strip() for c in stripped.strip().strip("|").split("|")]
        if not cells or cells[0] != stem or len(cells) <= column:
            continue
        cells[column] = value
        ending = line[len(stripped):]
        lines[i] = "| " + " | ".join(cells) + " |" + ending
        if batch:
            batch.write(path, "".join(lines))
        else:
            write_text(path, "".join(lines))
        return


def set_frontmatter(path, key, value, batch=None):
    text = batch.read(path) if batch else read_text(path)
    pattern = re.compile(r"(?m)^%s:[ \t]*.*$" % re.escape(key))
    if pattern.search(text):
        updated = pattern.sub("%s: %s" % (key, value), text, count=1)
        if batch:
            batch.write(path, updated)
        else:
            write_text(path, updated)


def set_toml_key(path, key, value, batch=None):
    text = batch.read(path) if batch else read_text(path)
    pattern = re.compile(r'(?m)^%s[ \t]*=[ \t]*".*"[ \t]*$' % re.escape(key))
    if pattern.search(text):
        updated = pattern.sub('%s = "%s"' % (key, value), text, count=1)
        if batch:
            batch.write(path, updated)
        else:
            write_text(path, updated)


def set_validator_write_tools(root, allowed, batch=None):
    """Grant or withhold Edit/Write in the validator's Claude allowlist.

    The prompt says the validator must not touch production source; this is
    what makes it true when the prompt is ignored, so it moves with the flag
    rather than being a second thing to remember.
    """
    path = os.path.join(root, "agents", "test-validator.md")
    if not os.path.isfile(path):
        return
    text = batch.read(path) if batch else read_text(path)
    m = re.search(r"(?m)^tools:[ \t]*(.*)$", text)
    if not m:
        return
    tools = [t.strip() for t in m.group(1).split(",") if t.strip()]
    tools = [t for t in tools if t not in ("Edit", "Write")]
    if allowed:
        at = tools.index("Bash") + 1 if "Bash" in tools else len(tools)
        tools[at:at] = ["Edit", "Write"]
    updated = (text[:m.start()] + "tools: " + ", ".join(tools)
               + text[m.end():])
    if batch:
        batch.write(path, updated)
    else:
        write_text(path, updated)


def apply_setting(root, is_codex, fid, value, batch=None):
    """Write one setting everywhere it has to agree. Returns a note or ''.

    `batch` is an already-loaded orchestration.json to edit in place; the
    caller then writes it once. Without it each call is self-contained, which
    is what a single toggle wants.
    """
    fields = dict((f["id"], f) for f in build_fields(is_codex))
    f = fields.get(fid)
    if f is None:
        raise KeyError("unknown setting %r" % fid)
    if f["kind"] in ("readonly", "note") or f.get("locked"):
        raise ValueError("%s is not editable here" % fid)

    if f["kind"] == "toggle":
        value = bool(value)
    elif f["kind"] == "int":
        value = int(value)
        # Seconds default to "at least 1"; the bounded settings carry their
        # own range, and it is the same range verify-install.py accepts.
        low, high = f.get("min", 1), f.get("max")
        if high is None:
            if value < low:
                raise ValueError("%s must be %d or more" % (fid, low))
        elif not low <= value <= high:
            raise ValueError("%s must be between %d and %d" % (fid, low, high))
    elif f["kind"] == "enum":
        if value not in f["options"]:
            raise ValueError("%s must be one of %s"
                             % (fid, ", ".join(f["options"])))
    elif f["kind"] == "list":
        if isinstance(value, str):
            value = [v.strip() for v in value.splitlines() if v.strip()]
        value = list(value)

    data = batch.json if batch is not None else load_json(root)

    def commit():
        if batch is None:
            save_json(root, data)

    if fid.startswith("role."):
        _, key, attr = fid.split(".", 2)
        put(data, "%s.%s" % (key, attr), value)
        commit()
        stem = ROLE_STEMS[key]
        if is_codex:
            set_toml_key(os.path.join(root, "agents", stem + ".toml"),
                         "model_reasoning_effort", value, batch=batch)
            set_readme_cell(root, stem, 1, value, batch=batch)
            return "orchestration.json, agents/%s.toml, README table" % stem
        agent = os.path.join(root, "agents", stem + ".md")
        if attr == "model":
            set_frontmatter(agent, "model", value, batch=batch)
            set_readme_cell(root, stem, 1, value, batch=batch)
        else:
            set_frontmatter(agent, "effort", value, batch=batch)
            set_readme_cell(root, stem, 2, value, batch=batch)
        return "orchestration.json, agents/%s.md, README table" % stem

    if fid == "group.testWrites":
        for path in ("worker.allowTestWrites", "validator.allowTestWrites",
                     "commands.allowTestFileCreation"):
            put(data, path, value)
        commit()
        if not is_codex:
            set_validator_write_tools(root, value, batch=batch)
            return ("worker, validator and commands flags, and the validator's "
                    "tools allowlist")
        return "worker, validator and commands flags"

    if fid in ("group.buildCommands", "group.serveCommands"):
        which = "Build" if fid.endswith("buildCommands") else "Serve"
        put(data, "commands.allow%sCommands" % which, value)
        put(data, "validator.allow%sCommands" % which, value)
        commit()
        return "commands and validator flags"

    put(data, fid, value)
    commit()
    return "orchestration.json"


def apply_profile(root, is_codex, profile):
    """Write a whole profile, verify once, and undo it if that fails.

    Instant apply is only safe with an automatic undo: a profile moves a dozen
    settings, and finding out at the next /orchestrate that one of them broke
    the install is not a trade worth making.
    """
    if profile not in PROFILE_IDS:
        raise ValueError("unknown profile %r" % profile)
    wanted = profile_values(profile, is_codex)
    before = current_values(root, is_codex)
    snapshot = dict((k, before.get(k)) for k in wanted)
    changed = [k for k, v in sorted(wanted.items()) if before.get(k) != v]

    def write_all(mapping):
        # Nothing touches the disk until every file is ready, so a killed
        # process cannot leave half a profile behind.
        pending = Batch(root)
        for key, value in sorted(mapping.items()):
            apply_setting(root, is_codex, key, value, batch=pending)
        pending.flush()

    try:
        write_all(wanted)
        result = run_verify(root)
    except Exception:
        # A key that fails validation halfway through would otherwise leave
        # the profile half-applied -- worse than either end state.
        write_all(snapshot)
        raise
    if result["ok"] is False:
        write_all(snapshot)
        raise ValueError("%s would break the install, so nothing was changed: "
                         "%s" % (PROFILE_LABELS[profile], result["output"]))

    # No re-sync prompt: a profile writes models, effort, deadlines and
    # policy, and never a tool allowlist or an MCP map. Nothing it changes can
    # leave a delegate without the capabilities it had a moment ago.
    return {"profile": profile, "changed": changed, "verify": result}


def restore_surface(root, is_codex, values):
    """Put profile-surface keys back exactly as they were.

    What makes the slider safe to drag: applying is instant, so undoing has to
    be one click rather than a hunt through a dozen rows.
    """
    surface = set(profile_surface(is_codex))
    unknown = sorted(k for k in values if k not in surface)
    if unknown:
        raise ValueError("not profile settings: %s" % ", ".join(unknown))
    pending = Batch(root)
    for key, value in sorted(values.items()):
        apply_setting(root, is_codex, key, value, batch=pending)
    pending.flush()
    return {"changed": sorted(values), "verify": run_verify(root)}


# ------------------------------------------------------------- backup ----

EXPORT_KIND = "orchestrate-settings"
EXPORT_FORMAT = 1


def editable_ids(is_codex):
    """The field ids an import is allowed to write."""
    return [f["id"] for f in build_fields(is_codex)
            if f["kind"] not in ("readonly", "note") and not f.get("locked")]


def export_bundle(root):
    """Every synced install's settings, in one file worth keeping.

    Only the values somebody chose. The pinned permission flags are constants
    and the capability data -- tool allowlists, MCP maps, prompt hashes -- is
    derived against the machine that produced it, so carrying either to
    another machine would describe an install that does not exist there.
    """
    installs, unsynced = [], []
    for pid, label, directory in find_targets(root):
        if not sync_status(directory)["synced"]:
            unsynced.append(label)
            continue
        is_codex = pid == "codex"
        values = current_values(directory, is_codex)
        installs.append({
            "platform": pid,
            "label": label,
            "schemaVersion": load_json(directory).get("schemaVersion"),
            "profile": derive_profile(values, is_codex),
            "values": dict((k, values[k]) for k in editable_ids(is_codex)
                           if k in values),
        })
    return {"kind": EXPORT_KIND, "formatVersion": EXPORT_FORMAT,
            "exportedAt": datetime.date.today().isoformat(),
            "installs": installs, "skippedUnsynced": unsynced}


def import_install(root, is_codex, values):
    """Write one install's imported settings, or none of them.

    Same contract as a profile: all of it lands and verifies, or the install
    is exactly as it was. A half-applied import is worse than a refused one.
    """
    allowed = set(editable_ids(is_codex))
    here = set(f["id"] for f in build_fields(is_codex))
    anywhere = here | set(f["id"] for f in build_fields(not is_codex))
    wanted = dict((k, v) for k, v in values.items() if k in allowed)

    # Reported, never silently dropped: an import that quietly ignores half
    # its file looks exactly like an import that worked. A pinned flag is the
    # interesting one -- that is the safety rail refusing, not a typo.
    def why(key):
        if key in here:
            return "pinned or read-only, not importable"
        if key in anywhere:
            return "not a setting on this platform"
        return "unknown setting, ignored"

    notes = ["%s: %s" % (k, why(k)) for k in sorted(values)
             if k not in allowed]

    before = current_values(root, is_codex)
    snapshot = dict((k, before.get(k)) for k in wanted)
    changed = [k for k, v in sorted(wanted.items()) if before.get(k) != v]

    def write_all(mapping):
        pending = Batch(root)
        for key, value in sorted(mapping.items()):
            apply_setting(root, is_codex, key, value, batch=pending)
        pending.flush()

    if not changed:
        return {"changed": [], "notes": notes, "verify": run_verify(root)}
    try:
        write_all(wanted)
        result = run_verify(root)
    except Exception:
        write_all(snapshot)
        raise
    if result["ok"] is False:
        write_all(snapshot)
        raise ValueError("the imported settings would break this install, so "
                         "nothing was changed: %s" % result["output"])
    return {"changed": changed, "notes": notes, "verify": result}


def import_bundle(root, data):
    """Check the whole file before writing any of it."""
    if not isinstance(data, dict) or data.get("kind") != EXPORT_KIND:
        raise ValueError("that file is not an orchestrate settings export")
    if data.get("formatVersion") != EXPORT_FORMAT:
        raise ValueError("export format %r is not supported by this version"
                         % (data.get("formatVersion"),))
    entries = data.get("installs")
    if not isinstance(entries, list) or not entries:
        raise ValueError("the export contains no installs")

    targets = dict((t[0], t) for t in find_targets(root))
    planned, absent = [], []
    for entry in entries:
        pid = (entry or {}).get("platform")
        target = targets.get(pid)
        if target is None:
            absent.append(str(pid))
            continue
        directory = target[2]
        # Deliberately not gated on sync. A fresh machine has never synced, so
        # gating here would refuse exactly the restore this exists for, and an
        # import writes only settings -- never a tool allowlist or MCP map.
        values = entry.get("values")
        if not isinstance(values, dict):
            raise ValueError("%s has no settings in the export" % target[1])
        planned.append((pid, target[1], directory, pid == "codex", values))

    if not planned:
        raise ValueError("none of the installs in that export are installed "
                         "here (%s)" % ", ".join(absent))

    results = []
    for pid, label, directory, is_codex, values in planned:
        outcome = import_install(directory, is_codex, values)
        outcome.update({"platform": pid, "label": label})
        results.append(outcome)
    return {"installs": results, "notInstalled": absent}


# -------------------------------------------------------------- verify ----

def run_verify(root):
    script = os.path.join(root, "orchestrator-spec", "verify-install.py")
    if not os.path.isfile(script):
        return {"ok": None, "output": "verify-install.py is not installed"}
    try:
        proc = subprocess.run([sys.executable, script, root],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              timeout=120)
    except Exception as exc:  # pragma: no cover - environment dependent
        return {"ok": None, "output": "could not run verify-install.py: %s" % exc}
    text = proc.stdout.decode("utf-8", "replace").strip()
    return {"ok": proc.returncode == 0, "output": text}


# ------------------------------------------------------------- targets ----

def find_targets(root):
    """[(id, label, dir), ...] for every installed platform.

    The install this file belongs to, plus its sibling: a bundle installed for
    both platforms puts .claude and .codex next to each other, globally and
    project-scoped alike.
    """
    root = os.path.abspath(root)
    parent = os.path.dirname(root)
    found = []
    for pid, label, name in (("claude", "Claude Code", ".claude"),
                             ("codex", "Codex CLI", ".codex")):
        for candidate in (root, os.path.join(parent, name)):
            if (os.path.basename(candidate) == name
                    and os.path.isfile(os.path.join(candidate,
                                                    "orchestration.json"))):
                found.append((pid, label, candidate))
                break
    return found


def target_state(pid, label, directory):
    is_codex = pid == "codex"
    values = current_values(directory, is_codex)
    return {"id": pid, "label": label, "dir": directory,
            "fields": build_fields(is_codex),
            "values": values,
            "profiles": profiles_for(is_codex),
            "profile": derive_profile(values, is_codex),
            "surface": profile_surface(is_codex),
            "sync": sync_status(directory),
            "verify": run_verify(directory)}


# ---------------------------------------------------------------- page ----

SCRIPT = """
const TOKEN = new URLSearchParams(location.search).get("t") || "";
let STATE = null, ACTIVE = null;

function api(path, body) {
  const opt = {headers: {"Content-Type": "application/json"}};
  if (body) { opt.method = "POST"; opt.body = JSON.stringify(body); }
  return fetch(path + "?t=" + encodeURIComponent(TOKEN), opt).then(r => r.json());
}

function el(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined) n.textContent = text;
  return n;
}

function control(target, f, value) {
  const locked = f.kind === "readonly" || f.locked;
  if (f.kind === "toggle") {
    const w = el("label", "switch");
    const i = el("input"); i.type = "checkbox"; i.checked = !!value;
    i.disabled = locked;
    i.onchange = () => save(target, f, i.checked);
    w.appendChild(i); w.appendChild(el("span", "slider"));
    return w;
  }
  if (f.kind === "enum") {
    const s = el("select");
    (f.options || []).forEach(o => {
      const op = el("option", null, o); op.value = o;
      if (o === value) op.selected = true;
      s.appendChild(op);
    });
    s.disabled = locked;
    s.onchange = () => save(target, f, s.value);
    return s;
  }
  if (f.kind === "list") {
    const t = el("textarea");
    t.rows = 3;
    t.value = (value || []).join("\\n");
    t.disabled = locked;
    t.onchange = () => save(target, f, t.value);
    return t;
  }
  const i = el("input");
  i.type = f.kind === "int" ? "number" : "text";
  i.value = value === null || value === undefined ? "" : value;
  i.disabled = locked;
  i.onchange = () => save(target, f, f.kind === "int" ? Number(i.value) : i.value);
  return i;
}

// Write a value into an already-rendered row. Rebuilding the row would work
// too, and would throw away the user's scroll position and focus to do it.
function setControl(row, value) {
  const c = row.querySelector("input, select, textarea");
  if (!c) {
    const v = row.querySelector(".val");
    if (v) v.textContent = String(value);
    return;
  }
  if (c.type === "checkbox") c.checked = !!value;
  else if (c.tagName === "TEXTAREA") c.value = (value || []).join("\\n");
  else c.value = value === null || value === undefined ? "" : value;
}

function patchValues(target) {
  document.querySelectorAll("[data-fid]").forEach(row => {
    const fid = row.getAttribute("data-fid");
    if (fid in target.values) setControl(row, target.values[fid]);
  });
}

// The part worth keeping from the old rebuild: a visible sweep down the rows
// a profile changed, in the order they appear rather than alphabetically.
function cascade(changed) {
  if (!changed || !changed.length) return;
  const rows = Array.prototype.slice.call(
    document.querySelectorAll("[data-fid]"));
  rows.filter(r => changed.indexOf(r.getAttribute("data-fid")) !== -1)
      .forEach((row, i) => setTimeout(() => {
        row.classList.remove("tuned");
        void row.offsetWidth;   // restart the animation on a repeat apply
        row.classList.add("tuned");
        setTimeout(() => row.classList.remove("tuned"), 900);
      }, i * 45));
}

function refreshBadge(target) {
  const badge = document.querySelector(".strip .badge");
  if (!badge) return;
  const v = target.verify;
  badge.className = "badge " + (v.ok === true ? "good" : v.ok === false ? "bad" : "");
  badge.title = v.output || "";
  badge.textContent = "";
  badge.appendChild(el("span", "led"));
  badge.appendChild(document.createTextNode(
    v.ok === true ? "verify passing"
    : v.ok === false ? "verify failing" : "verify unknown"));
}

function flash(fid) {
  const row = document.querySelector('[data-fid="' + fid + '"]');
  if (!row) return;
  row.classList.add("saved");
  setTimeout(() => row.classList.remove("saved"), 1100);
}

function save(target, f, value) {
  status("writing " + f.title + " ...", "busy");
  api("/api/set", {platform: target.id, id: f.id, value: value})
    .then(res => {
      if (res.error) { status(res.error, "bad"); return; }
      const t = STATE.targets.find(x => x.id === target.id);
      t.values = res.values; t.verify = res.verify; t.sync = res.sync;
      if (res.verify.ok === false) {
        status("wrote " + res.wrote + " - verify-install.py now FAILS: "
               + res.verify.output, "bad");
      } else {
        status(f.title + "  ->  " + res.wrote, "good");
      }
      patchValues(t);
      syncBar(t);
      refreshBadge(t);
      flash(f.id);
    })
    .catch(e => status(String(e), "bad"));
}

function status(text, kind) {
  const bar = document.getElementById("status");
  bar.className = "status " + (kind || "");
  bar.querySelector(".msg").textContent = text;
}

function placeLine() {
  const on = document.querySelector(".tab.on");
  const line = document.querySelector(".tabline");
  if (!on || !line) return;
  line.style.left = on.offsetLeft + "px";
  line.style.width = on.offsetWidth + "px";
}

// Nothing is rendered behind this. Showing settings with a warning on top
// still asks you to trust the numbers underneath, and until the skill has
// reconciled the install against this machine they are the bundle's
// defaults -- not what these agents can actually reach.
function gate(target) {
  const g = el("div", "gate");
  g.appendChild(el("div", "gate-glyph", "\u2298"));
  g.appendChild(el("h3", null, "Run /orchestrate-sync first"));
  const p = el("p");
  p.appendChild(document.createTextNode("This install has not been "
    + "reconciled against this machine yet, so its tool allowlists, MCP "
    + "routing and capability deny list are still the bundle's defaults. "
    + "Settings are hidden rather than shown wrong."));
  g.appendChild(p);
  const steps = el("ol", "gate-steps");
  const one = el("li");
  one.appendChild(document.createTextNode("Open a "));
  one.appendChild(el("code", null, target.label));
  one.appendChild(document.createTextNode(" session."));
  steps.appendChild(one);
  const two = el("li");
  two.appendChild(document.createTextNode("Run "));
  two.appendChild(el("code", null, "/orchestrate-sync"));
  two.appendChild(document.createTextNode("."));
  steps.appendChild(two);
  steps.appendChild(el("li", null, "Come back and check again."));
  g.appendChild(steps);
  const b = el("button", "recheck", "Check again");
  b.onclick = () => {
    status("re-reading " + target.dir + " ...", "busy");
    api("/api/state").then(s => {
      STATE = s;
      render();
      const t = s.targets.find(x => x.id === ACTIVE);
      status(t && t.sync.synced ? "synced - settings unlocked"
             : "still not synced - /orchestrate-sync has not run yet",
             t && t.sync.synced ? "good" : "");
    });
  };
  g.appendChild(b);
  return g;
}

// The dial, and the undo that makes applying instantly a fair trade.
let UNDO = {};

function profileName(target, known) {
  return known === -1 ? "Custom" : target.profiles[known].label;
}

function profileBlurb(target, known) {
  return known === -1
    ? "These settings do not match a profile. Pick one to replace them, or "
      + "keep tuning by hand."
    : target.profiles[known].blurb;
}

function revertButton(target) {
  const undo = el("button", "revert", "Revert");
  undo.onclick = () => {
    const values = UNDO[target.id];
    status("restoring " + Object.keys(values).length + " settings ...", "busy");
    api("/api/profile", {platform: target.id, restore: values})
      .then(res => {
        if (res.error) { status(res.error, "bad"); return; }
        delete UNDO[target.id];
        absorb(target.id, res);
        patchValues(target);
        syncBar(target);
        refreshBadge(target);
        cascade(res.changed);
        status("reverted", "good");
      });
  };
  return undo;
}

// The bar is updated, never rebuilt: .profile carries the page's entrance
// animation, so replacing the node replays it and the box appears to reload.
function syncBar(target) {
  const wrap = document.querySelector(".profile");
  if (!wrap) return;
  const ids = target.profiles.map(p => p.id);
  const known = ids.indexOf(target.profile);
  wrap.querySelector(".profile-label").textContent = profileName(target, known);
  wrap.querySelector(".profile-blurb").textContent = profileBlurb(target, known);
  const slider = wrap.querySelector(".profile-slider");
  slider.value = known === -1 ? 1 : known;
  slider.classList.toggle("custom", known === -1);
  wrap.querySelectorAll(".tick").forEach((b, i) => {
    b.classList.toggle("on", i === known);
  });
  const head = wrap.querySelector(".profile-head");
  const existing = head.querySelector(".revert");
  if (UNDO[target.id] && !existing) head.appendChild(revertButton(target));
  else if (!UNDO[target.id] && existing) existing.remove();
}

function profileBar(target) {
  const wrap = el("div", "profile");
  const ids = target.profiles.map(p => p.id);
  const known = ids.indexOf(target.profile);

  const head = el("div", "profile-head");
  head.appendChild(el("span", "profile-label", profileName(target, known)));
  if (UNDO[target.id]) head.appendChild(revertButton(target));
  wrap.appendChild(head);

  const track = el("div", "profile-track");
  const slider = el("input", "profile-slider");
  slider.type = "range";
  slider.min = 0;
  slider.max = ids.length - 1;
  slider.step = 1;
  slider.value = known === -1 ? 1 : known;
  slider.setAttribute("aria-label", "Effort profile");
  if (known === -1) slider.classList.add("custom");
  // change, not input: dragging across four stops would otherwise apply four
  // profiles on the way past.
  slider.onchange = () => applyProfile(target, ids[Number(slider.value)]);
  track.appendChild(slider);

  const ticks = el("div", "profile-ticks");
  const last = ids.length - 1;
  target.profiles.forEach((p, i) => {
    const b = el("button", "tick" + (i === known ? " on" : ""), p.label);
    // Same fraction the thumb uses, in a box inset by half a thumb, so the
    // handle lands on the middle of the word rather than near it.
    b.style.left = (last > 0 ? (i * 100) / last : 50) + "%";
    b.onclick = () => applyProfile(target, p.id);
    ticks.appendChild(b);
  });
  track.appendChild(ticks);
  wrap.appendChild(track);

  wrap.appendChild(el("p", "profile-blurb", profileBlurb(target, known)));

  const scale = el("div", "profile-scale");
  scale.appendChild(el("span", null, "token-efficient / quick"));
  scale.appendChild(el("span", null, "precise / high effort"));
  wrap.appendChild(scale);
  return wrap;
}

function absorb(id, res) {
  const t = STATE.targets.find(x => x.id === id);
  t.values = res.values;
  t.verify = res.verify;
  t.sync = res.sync;
  if (res.profile !== undefined) t.profile = res.profile;
}

function applyProfile(target, id) {
  const before = {};
  target.surface.forEach(k => { before[k] = target.values[k]; });
  status("applying " + id + " ...", "busy");
  api("/api/profile", {platform: target.id, profile: id})
    .then(res => {
      if (res.error) { status(res.error, "bad"); syncBar(target); return; }
      UNDO[target.id] = before;
      absorb(target.id, res);
      patchValues(target);
      syncBar(target);
      refreshBadge(target);
      cascade(res.changed);
      status("applied " + id + " - " + (res.changed || []).length
             + " settings changed", "good");
    })
    .catch(e => status(String(e), "bad"));
}

// Settings travel between machines; capabilities do not. The export carries
// what somebody chose and nothing /orchestrate-sync derived, so restoring it
// on a new machine is a head start, not a substitute for reconciling.
function mountBackup(target) {
  const row = document.getElementById("backup");
  row.innerHTML = "";
  // Nothing to back up and nowhere to restore into until /orchestrate-sync
  // has reconciled this install: the page is showing the gate, not settings,
  // so both directions would act on values nobody has confirmed. Once it is
  // synced, both are offered together.
  if (!target || !target.sync.synced) return;

  const out = el("button", "ghost", "Export");
  out.onclick = () => {
    status("exporting ...", "busy");
    api("/api/export").then(data => {
      if (data.error) { status(data.error, "bad"); return; }
      if (!data.installs.length) {
        status("nothing to export - no install here is reconciled yet. "
               + "Run /orchestrate-sync first.", "warn");
        return;
      }
      const url = URL.createObjectURL(new Blob(
        [JSON.stringify(data, null, 2)], {type: "application/json"}));
      const a = el("a", "filepick");
      a.href = url;
      a.download = "orchestrate-settings-" + data.exportedAt + ".json";
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
      const skipped = data.skippedUnsynced || [];
      status("exported " + data.installs.length + " install(s)"
             + (skipped.length ? " - skipped " + skipped.join(", ")
                + " (not synced)" : ""),
             skipped.length ? "warn" : "good");
    }).catch(e => status(String(e), "bad"));
  };

  const pick = el("input", "filepick");
  pick.type = "file";
  pick.accept = "application/json,.json";
  pick.onchange = () => {
    const file = pick.files && pick.files[0];
    pick.value = "";
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      let data;
      try { data = JSON.parse(reader.result); }
      catch (err) { status("that file is not valid JSON", "bad"); return; }
      status("importing ...", "busy");
      api("/api/import", data).then(res => {
        if (res.error) { status(res.error, "bad"); return; }
        STATE = res.state;
        render();
        let n = 0;
        const notes = [], into = [];
        (res.installs || []).forEach(r => {
          n += r.changed.length;
          into.push(r.label + " (" + r.changed.length + ")");
          (r.notes || []).forEach(x => notes.push(r.label + " " + x));
        });
        // A platform in the file that is not installed here is skipped on
        // purpose, but silence would read as "restored everything".
        const absent = res.notInstalled || [];
        if (absent.length) {
          notes.push("not installed here: " + absent.join(", "));
        }
        status(n + " setting(s) restored into " + into.join(", ")
               + ". Run /orchestrate-sync if this machine has not been "
               + "reconciled yet."
               + (notes.length ? " Skipped: " + notes.join("; ") : ""),
               notes.length ? "warn" : "good");
      }).catch(e => status(String(e), "bad"));
    };
    reader.readAsText(file);
  };

  const into = el("button", "ghost", "Import");
  into.onclick = () => pick.click();
  out.title = "Write every synced install's settings to one JSON file.";
  into.title = "Restore settings from a file exported on another machine. "
             + "Tool allowlists and MCP routing are not carried -- "
             + "/orchestrate-sync derives those per machine.";
  row.appendChild(into);
  row.appendChild(out);
  row.appendChild(pick);   // the hidden input the Import button clicks
}

function render() {
  const app = document.getElementById("app");
  const target = STATE.targets.find(t => t.id === ACTIVE);
  document.body.className = ACTIVE === "codex" ? "codex" : "";
  app.innerHTML = "";

  const tabs = el("div", "tabs");
  STATE.targets.forEach(t => {
    const b = el("button", "tab" + (t.id === ACTIVE ? " on" : ""));
    b.appendChild(el("span", "dot"));
    b.appendChild(document.createTextNode(t.label));
    b.onclick = () => { ACTIVE = t.id; render(); };
    tabs.appendChild(b);
  });
  tabs.appendChild(el("span", "tabline"));
  app.appendChild(tabs);
  // Lives in the header, outside #app, so it survives the innerHTML reset --
  // and stays reachable while the sync gate is up, which is exactly when a
  // restore is the thing you came to do.
  mountBackup(target);
  if (!target) return;

  const strip = el("div", "strip");
  strip.appendChild(el("span", "path", target.dir));
  const v = target.verify;
  const badge = el("span", "badge " + (v.ok === true ? "good"
                   : v.ok === false ? "bad" : ""));
  badge.appendChild(el("span", "led"));
  badge.appendChild(document.createTextNode(
    v.ok === true ? "verify passing"
    : v.ok === false ? "verify failing" : "verify unknown"));
  badge.title = v.output || "";
  strip.appendChild(badge);
  app.appendChild(strip);

  if (!target.sync.synced) { app.appendChild(gate(target)); return; }

  app.appendChild(profileBar(target));

  let cat = null, section = null, i = 0;
  target.fields.forEach(f => {
    if (f.category !== cat) {
      cat = f.category;
      app.appendChild(el("h2", null, cat));
      section = el("div", "card");
      app.appendChild(section);
    }
    if (f.kind === "note") {
      const note = el("div", "row note");
      note.style.setProperty("--i", i++);
      note.appendChild(el("strong", null, f.title + " "));
      note.appendChild(document.createTextNode(f.subtitle));
      section.appendChild(note);
      return;
    }
    const locked = f.kind === "readonly" || f.locked;
    const row = el("div", "row" + (locked ? " locked" : ""));
    row.setAttribute("data-fid", f.id);
    row.style.setProperty("--i", i++);
    const label = el("div", "label");
    label.appendChild(el("div", "title", f.title));
    label.appendChild(el("div", "sub", f.subtitle));
    row.appendChild(label);
    const ctl = el("div", "ctl");
    if (f.kind === "readonly") {
      ctl.appendChild(el("span", "val", String(target.values[f.id])));
    } else {
      ctl.appendChild(control(target, f, target.values[f.id]));
    }
    row.appendChild(ctl);
    section.appendChild(row);
  });
  requestAnimationFrame(placeLine);
}

window.addEventListener("resize", placeLine);

api("/api/state").then(s => {
  STATE = s;
  if (!s.targets.length) {
    document.getElementById("app").textContent =
      "No installed orchestration config found next to this script.";
    return;
  }
  ACTIVE = s.targets[0].id;
  render();
  status("ready - every change is written as you make it", "");
});
"""

STYLE = """
/* An instrument panel, not a settings form: this configures five agents that
   spend money and edit code, so it reads like something with a power switch.
   Hairlines, monospace labels, one accent colour per platform, and no
   decoration that is not carrying information. */

:root {
  --ink: #e8eaed; --ink-dim: #939aa4; --ink-faint: #666d77;
  --bg: #0b0d10; --panel: #121519; --panel-2: #171b21;
  --line: #232830; --line-bright: #333a45;
  --accent: #f0a13c; --accent-soft: rgba(240, 161, 60, .13);
  --good: #55c98a; --bad: #f0625d; --radius: 3px;
  --mono: ui-monospace, "Cascadia Mono", "JetBrains Mono", "SF Mono",
          Menlo, Consolas, monospace;
  --sans: "Segoe UI Variable Text", "Segoe UI", -apple-system,
          "Helvetica Neue", sans-serif;
}
body.codex { --accent: #4fc7d4; --accent-soft: rgba(79, 199, 212, .13); }
@media (prefers-color-scheme: light) {
  :root {
    --ink: #14171c; --ink-dim: #5d646e; --ink-faint: #8b929c;
    --bg: #f4f2ee; --panel: #fffefc; --panel-2: #faf8f5;
    --line: #e4e0d8; --line-bright: #cfcabf;
    --accent: #b96f10; --accent-soft: rgba(185, 111, 16, .1);
    --good: #1d7a4c; --bad: #c0392f;
  }
}

* { box-sizing: border-box; }

body { margin: 0; padding: 0 0 6rem; background: var(--bg); color: var(--ink);
       font: 15px/1.55 var(--sans); -webkit-font-smoothing: antialiased; }

/* Two fixed layers: an accent wash that re-tints when the tab changes, and a
   faint grid for the panels to sit on. */
body::before {
  content: ""; position: fixed; inset: 0; pointer-events: none; z-index: 0;
  background:
    radial-gradient(90ch 45ch at 12% -12%, var(--accent-soft), transparent 70%),
    radial-gradient(70ch 40ch at 100% 0%, var(--accent-soft), transparent 65%);
  transition: background .45s ease;
}
body::after {
  content: ""; position: fixed; inset: 0; pointer-events: none; z-index: 0;
  opacity: .55;
  background-image:
    linear-gradient(var(--line) 1px, transparent 1px),
    linear-gradient(90deg, var(--line) 1px, transparent 1px);
  background-size: 64px 64px;
  mask-image: radial-gradient(120ch 70ch at 50% 0%, #000, transparent 75%);
  -webkit-mask-image: radial-gradient(120ch 70ch at 50% 0%, #000, transparent 75%);
}

.wrap { position: relative; z-index: 1; max-width: 900px; margin: 0 auto;
        padding: 3rem 1.25rem 0; }

.brand { display: flex; align-items: baseline; gap: .75rem; flex-wrap: wrap;
         animation: rise .5s cubic-bezier(.2,.7,.3,1) both; }
.brand h1 { font: 600 1.5rem/1.1 var(--sans); letter-spacing: -.02em; margin: 0; }
.brand .mark { font: 600 .66rem/1 var(--mono); letter-spacing: .22em;
               text-transform: uppercase; color: var(--accent);
               border: 1px solid currentColor; border-radius: 999px;
               padding: .3rem .55rem; transition: color .45s ease; }
.lede { color: var(--ink-dim); margin: .55rem 0 2rem; max-width: 64ch;
        font-size: .92rem;
        animation: rise .5s .06s cubic-bezier(.2,.7,.3,1) both; }
.lede code { font-family: var(--mono); font-size: .88em; }

.tabs { display: flex; gap: .25rem; position: relative;
        border-bottom: 1px solid var(--line);
        animation: rise .5s .1s cubic-bezier(.2,.7,.3,1) both; }
.tab { position: relative; background: none; border: 0; cursor: pointer;
       padding: .7rem 1rem .8rem; color: var(--ink-faint);
       font: 500 .8rem/1 var(--mono); letter-spacing: .08em;
       text-transform: uppercase; transition: color .18s ease; }
.tab:hover { color: var(--ink-dim); }
.tab.on { color: var(--ink); }
.tab .dot { display: inline-block; width: 6px; height: 6px; border-radius: 50%;
            margin-right: .5rem; background: var(--ink-faint);
            transition: background .2s ease, box-shadow .2s ease; }
.tab.on .dot { background: var(--accent);
               box-shadow: 0 0 0 3px var(--accent-soft);
               animation: pulse 2.6s ease-in-out infinite; }
.tabline { position: absolute; bottom: -1px; height: 2px; left: 0; width: 0;
           background: var(--accent); box-shadow: 0 0 12px var(--accent);
           transition: left .3s cubic-bezier(.4,.9,.3,1),
                       width .3s cubic-bezier(.4,.9,.3,1), background .45s ease; }

.strip { display: flex; align-items: center; gap: .8rem; flex-wrap: wrap;
         padding: 1rem 0 .25rem; font-family: var(--mono); font-size: .76rem; }
.strip .path { color: var(--ink-dim); word-break: break-all; }
.badge { display: inline-flex; align-items: center; gap: .4rem;
         padding: .22rem .55rem; border-radius: 999px;
         border: 1px solid var(--line-bright); color: var(--ink-dim);
         font-size: .68rem; letter-spacing: .06em; text-transform: uppercase; }
.badge .led { width: 6px; height: 6px; border-radius: 50%;
              background: currentColor; }
.badge.good { color: var(--good); border-color: var(--good); }
.badge.bad { color: var(--bad); border-color: var(--bad); }
.badge.good .led, .badge.bad .led { animation: pulse 2.6s ease-in-out infinite; }

.gate { margin: 2rem 0 0; padding: 2.25rem 2rem; text-align: center;
        border: 1px solid var(--accent); border-radius: var(--radius);
        background: var(--accent-soft);
        animation: rise .45s .14s cubic-bezier(.2,.7,.3,1) both; }
.gate-glyph { font-size: 2rem; line-height: 1; color: var(--accent);
              animation: pulse 2.6s ease-in-out infinite; }
.gate h3 { margin: .9rem 0 .4rem; font-size: 1.05rem; letter-spacing: -.01em; }
.gate p { margin: 0 auto; max-width: 58ch; color: var(--ink-dim);
          font-size: .9rem; }
.gate-steps { display: inline-block; margin: 1.2rem 0 0; padding: 0 0 0 1.2rem;
              text-align: left; color: var(--ink-dim); font-size: .9rem; }
.gate-steps li { margin: .2rem 0; }
.gate code { font-family: var(--mono); font-size: .88em; color: var(--accent); }
.recheck { display: block; margin: 1.5rem auto 0; cursor: pointer;
           background: none; color: var(--accent);
           border: 1px solid var(--accent); border-radius: var(--radius);
           padding: .5rem 1.1rem;
           font: 500 .74rem/1 var(--mono); letter-spacing: .12em;
           text-transform: uppercase;
           transition: background .18s ease, box-shadow .18s ease; }
.recheck:hover { background: var(--accent-soft);
                 box-shadow: 0 0 0 4px var(--accent-soft); }

.profile { margin: 1.4rem 0 0; padding: 1.1rem 1.2rem 1rem;
           border: 1px solid var(--line); border-radius: var(--radius);
           background: var(--panel);
           animation: rise .45s .14s cubic-bezier(.2,.7,.3,1) both; }
.profile-head { display: flex; align-items: center; justify-content: space-between;
                gap: 1rem; margin-bottom: .7rem; }
.profile-label { font: 600 1rem/1 var(--sans); letter-spacing: -.01em; }
.revert { cursor: pointer; background: none; color: var(--ink-dim);
          border: 1px solid var(--line-bright); border-radius: var(--radius);
          padding: .3rem .7rem; font: 500 .68rem/1 var(--mono);
          letter-spacing: .1em; text-transform: uppercase;
          transition: color .18s ease, border-color .18s ease; }
.revert:hover { color: var(--accent); border-color: var(--accent); }

/* Room for half of the outermost labels, which hang past the track's ends. */
.profile-track { position: relative; padding: 0 2.6rem; }
.profile-slider { -webkit-appearance: none; appearance: none; width: 100%;
                  display: block; height: 4px; margin: .2rem 0 .1rem;
                  background: var(--line-bright);
                  border: 0; border-radius: 999px; outline: 0; padding: 0; }
.profile-slider.custom { background: repeating-linear-gradient(90deg,
    var(--line-bright) 0 6px, transparent 6px 12px); }
.profile-slider::-webkit-slider-thumb {
  -webkit-appearance: none; width: 16px; height: 16px; border-radius: 50%;
  background: var(--accent); border: 3px solid var(--panel);
  box-shadow: 0 0 0 1px var(--accent), 0 0 12px var(--accent);
  cursor: pointer; transition: transform .18s cubic-bezier(.5,1.6,.5,1); }
.profile-slider::-webkit-slider-thumb:hover { transform: scale(1.15); }
.profile-slider::-moz-range-thumb {
  box-sizing: content-box; width: 16px; height: 16px; border-radius: 50%;
  background: var(--accent); border: 3px solid var(--panel);
  box-shadow: 0 0 0 1px var(--accent); cursor: pointer; }
.profile-slider:focus-visible { box-shadow: 0 0 0 4px var(--accent-soft); }

/* 11px = half the thumb (16px box + 3px border each side), so 0% and 100%
   here are exactly where the handle can reach. */
.profile-ticks { position: relative; height: 1.15rem; margin: .4rem 11px 0; }
.tick { position: absolute; top: 0; transform: translateX(-50%);
        white-space: nowrap; background: none; border: 0; cursor: pointer;
        padding: 0; color: var(--ink-faint); font: 500 .66rem/1.15rem var(--mono);
        letter-spacing: .1em; text-transform: uppercase;
        transition: color .18s ease; }
.tick:hover { color: var(--ink-dim); }
.tick.on { color: var(--accent); }
.tick { padding-right: .1em; }
.profile-blurb { margin: .7rem 0 0; color: var(--ink-dim); font-size: .87rem;
                 max-width: 62ch; }
.profile-scale { display: flex; justify-content: space-between;
                 margin-top: .5rem; color: var(--ink-faint);
                 font: .66rem/1 var(--mono); letter-spacing: .08em;
                 text-transform: uppercase; }

h2 { display: flex; align-items: center; gap: .8rem;
     font: 500 .68rem/1 var(--mono); letter-spacing: .2em;
     text-transform: uppercase; color: var(--ink-faint); margin: 2.4rem 0 .7rem; }
h2::after { content: ""; flex: 1; height: 1px;
            background: linear-gradient(90deg, var(--line), transparent); }

.card { border: 1px solid var(--line); border-radius: var(--radius);
        background: var(--panel); overflow: hidden; }

.row { display: flex; gap: 1.25rem; align-items: center; padding: .95rem 1.1rem;
       border-top: 1px solid var(--line); position: relative;
       transition: background .18s ease;
       animation: rise .42s cubic-bezier(.2,.7,.3,1) both;
       animation-delay: calc(var(--i) * 18ms + .12s); }
.row:first-child { border-top: 0; }
.row:hover { background: var(--panel-2); }
.row::before { content: ""; position: absolute; left: 0; top: 0; bottom: 0;
               width: 2px; background: var(--accent); transform: scaleY(0);
               transition: transform .2s ease; }
.row:hover::before { transform: scaleY(.5); }
.row.saved::before { transform: scaleY(1); }
.row.saved { background: var(--accent-soft); }
.row.locked { opacity: .55; }
.row.locked:hover::before { transform: scaleY(0); }
.row.note { display: block; color: var(--ink-dim); font-size: .87rem;
            background: var(--panel-2); }
.row.note strong { color: var(--ink); }

.label { flex: 1; min-width: 0; }
.title { font-weight: 600; letter-spacing: -.005em; }
.sub { color: var(--ink-dim); font-size: .845rem; margin-top: .12rem; }
.ctl { flex: 0 0 auto; display: flex; justify-content: flex-end;
       min-width: 8.5rem; }
.ctl .val { font-family: var(--mono); font-size: .8rem; color: var(--ink-dim);
            border: 1px dashed var(--line-bright); border-radius: var(--radius);
            padding: .25rem .55rem; }

select, input[type=number], input[type=text], textarea {
  font: inherit; color: var(--ink); background: var(--bg);
  border: 1px solid var(--line-bright); border-radius: var(--radius);
  padding: .38rem .55rem;
  transition: border-color .18s ease, box-shadow .18s ease; }
select { font-family: var(--mono); font-size: .84rem; }
input[type=number] { width: 6.5rem; font-family: var(--mono); }
textarea { width: 17rem; resize: vertical; font-family: var(--mono);
           font-size: .82rem; }
select:focus, input:focus, textarea:focus {
  outline: 0; border-color: var(--accent);
  box-shadow: 0 0 0 3px var(--accent-soft); }
select:disabled, input:disabled, textarea:disabled { cursor: not-allowed; }

.switch { position: relative; display: inline-block; width: 46px; height: 26px; }
.switch input { position: absolute; inset: 0; opacity: 0; width: 100%;
                height: 100%; margin: 0; cursor: pointer; z-index: 2; }
.slider { position: absolute; inset: 0; border-radius: 999px;
          background: var(--bg); border: 1px solid var(--line-bright);
          transition: background .22s ease, border-color .22s ease; }
.slider::before { content: ""; position: absolute; height: 16px; width: 16px;
                  left: 4px; top: 4px; border-radius: 50%;
                  background: var(--ink-faint);
                  transition: transform .26s cubic-bezier(.5,1.6,.5,1),
                              background .22s ease, box-shadow .22s ease; }
.switch input:checked + .slider { background: var(--accent-soft);
                                  border-color: var(--accent); }
.switch input:checked + .slider::before { transform: translateX(20px);
                                          background: var(--accent);
                                          box-shadow: 0 0 10px var(--accent); }
.switch input:focus-visible + .slider { box-shadow: 0 0 0 3px var(--accent-soft); }
.switch input:disabled { cursor: not-allowed; }

.status { position: fixed; left: 0; right: 0; bottom: 0; z-index: 5;
          display: flex; align-items: center; gap: .6rem; padding: .8rem 1.25rem;
          background: var(--panel); border-top: 1px solid var(--line);
          color: var(--ink-dim); font: .8rem/1.4 var(--mono);
          transition: color .2s ease; }
.status::before { content: ""; width: 6px; height: 6px; border-radius: 50%;
                  background: currentColor; flex: none; }
.backup { display: flex; align-items: center; gap: .5rem;
  margin-left: auto; align-self: center; }
.ghost { background: transparent; color: var(--ink-dim); font: inherit;
  font-size: .78rem; letter-spacing: .04em; text-transform: uppercase;
  border: 1px solid var(--line); border-radius: var(--radius);
  padding: .42rem .95rem; cursor: pointer;
  transition: color .18s ease, border-color .18s ease, background .18s ease; }
.ghost:hover { color: var(--accent); border-color: var(--accent);
  background: var(--accent-soft); }
.ghost:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.filepick { display: none; }
.status.warn { color: var(--accent); }
.status.good { color: var(--good); }
.status.bad { color: var(--bad); }
.status.busy::before { animation: pulse .8s ease-in-out infinite; }
.status .msg { flex: 1; min-width: 0; }

.loading { color: var(--ink-faint); font-family: var(--mono); }

@keyframes rise { from { opacity: 0; transform: translateY(9px); }
                  to { opacity: 1; transform: none; } }
/* The sweep a profile leaves behind: the row lights up and settles, without
   the page having been rebuilt underneath it. */
@keyframes tuned {
  0%   { background-color: var(--accent-soft); transform: translateX(4px); }
  60%  { background-color: var(--accent-soft); transform: none; }
  100% { background-color: transparent; transform: none; }
}
.row.tuned { animation: tuned .85s cubic-bezier(.2,.7,.3,1); }
.row.tuned::before { transform: scaleY(1); }
@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: .35; } }

@media (max-width: 620px) {
  .row { flex-direction: column; align-items: stretch; gap: .6rem; }
  .ctl { justify-content: flex-start; }
  textarea { width: 100%; }
}
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { animation-duration: .001ms !important;
    animation-delay: 0ms !important; transition-duration: .001ms !important; }
}
"""

PAGE = ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
        "<title>Orchestrate control panel</title>"
        "<style>%s</style></head><body>"
        "<div class=\"wrap\">"
        "<div class=\"brand\"><h1>Orchestrate</h1>"
        "<span class=\"mark\">control panel</span>"
        "<div id=\"backup\" class=\"backup\"></div></div>"
        "<p class=\"lede\">Five agents, their permissions and their limits. "
        "Every change is written to disk immediately, then re-checked with "
        "<code>verify-install.py</code>.</p>"
        "<div id=\"app\"><p class=\"loading\">reading install ...</p></div>"
        "</div>"
        "<div id=\"status\" class=\"status\"><span class=\"msg\"></span></div>"
        "<script>%s</script></body></html>")


def page():
    return PAGE % (STYLE, SCRIPT)


# ---------------------------------------------------------------- http ----

class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "orchestrate-config-ui"
    token = ""
    root = ""

    def log_message(self, fmt, *args):
        pass  # the terminal shows the URL and the errors, not every GET

    # A page on any other site can POST to 127.0.0.1. These settings include
    # permission flags, so every request carries the one-run token printed in
    # the terminal, and Host must be loopback (blocks DNS rebinding).
    def authorised(self):
        host = (self.headers.get("Host") or "").split(":")[0]
        if host not in ("127.0.0.1", "localhost", "[::1]", "::1"):
            return False
        _, _, query = self.path.partition("?")
        for pair in query.split("&"):
            key, _, value = pair.partition("=")
            if key == "t":
                return secrets.compare_digest(value, self.token)
        return False

    def send_json(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def state(self):
        return {"targets": [target_state(*t) for t in find_targets(self.root)]}

    def do_GET(self):
        path = self.path.split("?")[0]
        if not self.authorised():
            self.send_error(403, "bad or missing token")
            return
        if path == "/":
            body = page().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif path == "/api/state":
            self.send_json(self.state())
        elif path == "/api/export":
            self.send_json(export_bundle(self.root))
        else:
            self.send_error(404)

    def do_POST(self):
        route = self.path.split("?")[0]
        if not self.authorised() or route not in ("/api/set", "/api/profile",
                                                  "/api/import"):
            self.send_error(403, "bad or missing token")
            return
        length = int(self.headers.get("Content-Length") or 0)
        try:
            req = json.loads(self.rfile.read(length).decode("utf-8"))
        except ValueError:
            self.send_json({"error": "malformed request"}, 400)
            return
        if route == "/api/import":
            try:
                outcome = import_bundle(self.root, req)
            except (KeyError, ValueError, TypeError) as exc:
                self.send_json({"error": str(exc)}, 400)
                return
            outcome["state"] = self.state()
            self.send_json(outcome)
            return

        targets = dict((t[0], t) for t in find_targets(self.root))
        target = targets.get(req.get("platform"))
        if target is None:
            self.send_json({"error": "unknown platform"}, 400)
            return
        pid, label, directory = target
        if not sync_status(directory)["synced"]:
            self.send_json({"error": "/orchestrate-sync has not run for this "
                                     "install yet, so its settings are hidden"},
                           409)
            return
        is_codex = pid == "codex"
        try:
            if route == "/api/profile" and req.get("restore"):
                outcome = restore_surface(directory, is_codex,
                                          req["restore"])
                wrote = "%d setting(s) restored" % len(outcome["changed"])
            elif route == "/api/profile":
                outcome = apply_profile(directory, is_codex,
                                        req.get("profile"))
                wrote = "%d setting(s)" % len(outcome["changed"])
            else:
                outcome = {}
                wrote = apply_setting(directory, is_codex, req.get("id"),
                                      req.get("value"))
        except (KeyError, ValueError, TypeError) as exc:
            self.send_json({"error": str(exc)}, 400)
            return
        values = current_values(directory, is_codex)
        body = {"wrote": wrote,
                "values": values,
                "profile": derive_profile(values, is_codex),
                "sync": sync_status(directory),
                "verify": outcome.get("verify") or run_verify(directory)}
        body.update(dict((k, v) for k, v in outcome.items()
                         if k in ("changed",)))
        self.send_json(body)


def serve(root, port, open_browser):
    targets = find_targets(root)
    if not targets:
        print("No orchestration.json found in %s or beside it." % root)
        return 1
    Handler.token = secrets.token_urlsafe(18)
    Handler.root = root
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    url = "http://127.0.0.1:%d/?t=%s" % (httpd.server_address[1], Handler.token)
    print("Managing: %s" % ", ".join("%s (%s)" % (t[1], t[2]) for t in targets))
    unsynced = [t[1] for t in targets if not sync_status(t[2])["synced"]]
    if unsynced:
        print("Note: /orchestrate-sync has not run yet for %s, so the settings"
              % ", ".join(unsynced))
        print("      shown are the bundle's defaults, not this machine's.")
    print("Serving  %s" % url)
    print("Stop with Ctrl-C.")
    if open_browser:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        httpd.server_close()
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="Browser UI for orchestrate settings.")
    ap.add_argument("--dir", default=DEFAULT_ROOT,
                    help="install directory (default: the one holding this script)")
    ap.add_argument("--port", type=int, default=0,
                    help="port to serve on (default: any free port)")
    ap.add_argument("--no-browser", action="store_true",
                    help="do not open a browser")
    args = ap.parse_args(argv)
    return serve(os.path.abspath(args.dir), args.port, not args.no_browser)


if __name__ == "__main__":
    sys.exit(main())
