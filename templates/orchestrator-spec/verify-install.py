#!/usr/bin/env python3
"""Verify an installed orchestrate bundle.

This file IS the definition of the install's invariants. /orchestrate-sync
runs it instead of re-deriving the list in prose, and the smoke suites run it
against every test install so the list is exercised on every commit.

    python3 verify-install.py <install-dir>
    python3 verify-install.py --bless <install-dir>

<install-dir> is the directory holding orchestration.json, agents/ and
orchestrator-spec/ -- i.e. ~/.claude or ~/.codex (or a project-scoped
.claude / .codex). Platform is autodetected from the presence of
agents/*.toml.

--bless records a SHA-256 of each role's prompt BODY in
orchestrator-spec/prompt-hashes.json. Later runs check the bodies against it,
so /orchestrate-sync cannot reword a delegate's prompt while it is in there
editing frontmatter. Fields the skill is allowed to change (tools/model/effort
on Claude; everything outside developer_instructions on Codex) are excluded
from the hash. Re-bless after a deliberate prompt edit.

Only files this bundle installed are ever read -- never the rest of the home
directory. Prints one line per failure and exits non-zero.
Stdlib only, no third-party imports, so it runs wherever python3 does.
"""
import glob
import hashlib
import json
import os
import re
import sys

try:
    import tomllib
except ImportError:  # py < 3.11
    tomllib = None

FAILURES = []


def fail(msg):
    FAILURES.append(msg)


# agent file stem -> orchestration.json key
ROLES = {
    "task-orchestrator": "orchestrator",
    "codebase-researcher": "researcher",
    "implementation-worker": "worker",
    "test-validator": "validator",
    "result-judge": "judge",
}
READ_ONLY_ROLES = ("codebase-researcher", "result-judge")
CODEX_SANDBOX = {
    "codebase-researcher": "read-only",
    "result-judge": "read-only",
    "implementation-worker": "workspace-write",
    "test-validator": "workspace-write",
}
# Blocks whose loss would silently remove a role's guardrails. Named headings,
# not a count -- a count cannot be checked against anything.
MANDATORY_BLOCKS = {
    "task-orchestrator": ("## Instruction hierarchy (mandatory)",
                          "## Hard limits"),
    "codebase-researcher": ("## Instruction hierarchy (mandatory)",
                            "## Capability packet (mandatory)"),
    "implementation-worker": ("## Instruction hierarchy (mandatory)",
                              "## Capability packet (mandatory)"),
    "test-validator": ("## Instruction hierarchy (mandatory)",
                       "## Capability packet (mandatory)"),
    "result-judge": ("## Instruction hierarchy (mandatory)",
                     "## Capability packet (mandatory)",
                     "## Independence (mandatory)"),
}
HASHES = "orchestrator-spec/prompt-hashes.json"
# Frontmatter fields /orchestrate-sync may legitimately rewrite, so they are
# excluded from the prompt-body hash.
MUTABLE_FRONTMATTER = ("tools", "model", "effort")


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


# ---------------------------------------------------------------- files ----

def bundle_files(root):
    """Only what this bundle installed.

    A global install lives in ~/.claude, which also holds session transcripts,
    credentials and plugin trees -- hundreds of thousands of files that are
    none of this script's business. Walking the root would be slow and would
    read secrets that belong to other tools.
    """
    found = []
    for rel in ("orchestration.json", "README-orchestration.md"):
        path = os.path.join(root, rel)
        if os.path.isfile(path):
            found.append(path)
    for sub in ("agents", "orchestrator-spec"):
        for dirpath, dirnames, filenames in os.walk(os.path.join(root, sub)):
            found.extend(os.path.join(dirpath, f) for f in sorted(filenames))
    skills = os.path.join(root, "skills")
    if os.path.isdir(skills):
        for name in sorted(os.listdir(skills)):
            if not name.startswith("orchestrate"):
                continue
            for dirpath, dirnames, filenames in os.walk(
                    os.path.join(skills, name)):
                found.extend(os.path.join(dirpath, f) for f in sorted(filenames))
    return found


# ---------------------------------------------------------------- json ----

def check_json(root):
    """Policy invariants that must hold for the life of the install."""
    rel = "orchestration.json"
    path = os.path.join(root, rel)
    if not os.path.isfile(path):
        fail("%s: missing" % rel)
        return {}
    try:
        d = json.loads(read(path))
    except ValueError as exc:
        fail("%s: does not parse: %s" % (rel, exc))
        return {}

    def want(value, expected, label):
        if value != expected:
            fail("%s: %s is %r, expected %r" % (rel, label, value, expected))

    want(d.get("schemaVersion"), 2, "schemaVersion")
    want(d.get("defaultGlobalAgent"), False, "defaultGlobalAgent")
    wf = d.get("workflow", {})
    want(wf.get("maximumParallelWorkers"), 4, "workflow.maximumParallelWorkers")
    want(wf.get("maximumCorrectionCycles"), 2, "workflow.maximumCorrectionCycles")
    want(wf.get("maximumAgentRetries"), 0, "workflow.maximumAgentRetries")
    perm = d.get("permissions", {})
    want(perm.get("allowBypassPermissions"), False,
         "permissions.allowBypassPermissions")
    want(perm.get("allowDestructiveGit"), False,
         "permissions.allowDestructiveGit")
    mem = d.get("memory", {})
    want(mem.get("persistentAgentMemory"), False, "memory.persistentAgentMemory")
    want(mem.get("allowRepositoryMemoryWrites"), False,
         "memory.allowRepositoryMemoryWrites")

    for key in ("codebaseResearcher", "implementationWorker", "testValidator",
                "resultJudge", "correctionWorker"):
        if key not in wf.get("agentTimeoutSeconds", {}):
            fail("%s: workflow.agentTimeoutSeconds.%s missing" % (rel, key))
    for key in ("allowBuildCommands", "allowServeCommands",
                "allowTestFileCreation"):
        if key not in d.get("commands", {}):
            fail("%s: commands.%s missing" % (rel, key))
    if "allowTestWrites" not in d.get("worker", {}):
        fail("%s: worker.allowTestWrites missing" % rel)
    for key in ("allowTestWrites", "allowBuildCommands", "allowServeCommands"):
        if key not in d.get("validator", {}):
            fail("%s: validator.%s missing" % (rel, key))

    check_flag_agreement(rel, d)
    return d


def check_flag_agreement(rel, d):
    """One installer answer fans out to several flags; a half-applied edit
    splits them, and the split is silent -- the worker would write tests the
    validator is still forbidden to touch."""
    groups = (
        ("test writes", (("worker", "allowTestWrites"),
                         ("validator", "allowTestWrites"),
                         ("commands", "allowTestFileCreation"))),
        ("build commands", (("commands", "allowBuildCommands"),
                            ("validator", "allowBuildCommands"))),
        ("serve commands", (("commands", "allowServeCommands"),
                            ("validator", "allowServeCommands"))),
    )
    for label, keys in groups:
        seen = {}
        for section, key in keys:
            if key in d.get(section, {}):
                seen["%s.%s" % (section, key)] = d[section][key]
        if len(set(seen.values())) > 1:
            fail("%s: %s flags disagree: %s" % (
                rel, label,
                ", ".join("%s=%s" % kv for kv in sorted(seen.items()))))


# ------------------------------------------------------------- readme ----

def readme_table(root):
    """role -> [cell, ...] from the README-orchestration configuration table."""
    path = os.path.join(root, "README-orchestration.md")
    if not os.path.isfile(path):
        fail("README-orchestration.md: missing")
        return {}
    rows = {}
    for line in read(path).splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells and cells[0] in ROLES:
            rows[cells[0]] = cells
    missing = [r for r in ROLES if r not in rows]
    if missing:
        fail("README-orchestration.md: configuration table has no row for %s"
             % ", ".join(sorted(missing)))
    return rows


# ------------------------------------------------------- prompt bodies ----

def frontmatter(text):
    """{key: value} from a leading --- YAML block, or None if absent."""
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    out = {}
    for line in text[3:end].splitlines():
        m = re.match(r"^([A-Za-z_]+):\s*(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2).strip()
    return out


def prompt_body(path, root):
    """The part of a role file that /orchestrate-sync must not rewrite.

    Claude: everything except the frontmatter fields it may change.
    Codex: the developer_instructions block; the surrounding TOML keys are
    platform plumbing the skill is allowed to touch.
    Absolute paths are folded to a placeholder so a moved install still
    matches its manifest.
    """
    text = read(path)
    if path.endswith(".toml"):
        _, _, rest = text.partition('developer_instructions = """')
        body, _, _ = rest.partition('"""')
        text = body or text
    else:
        text = "\n".join(
            line for line in text.splitlines()
            if not any(line.startswith(f + ":") for f in MUTABLE_FRONTMATTER))
    return text.replace(root, "<DIR>").replace(root.replace("\\", "/"), "<DIR>")


def role_files(root, is_codex):
    """stem -> path for every role file that carries a prompt."""
    out = {}
    for stem in ROLES:
        if is_codex:
            name = stem + (".md" if stem == "task-orchestrator" else ".toml")
        else:
            name = stem + ".md"
        path = os.path.join(root, "agents", name)
        if os.path.isfile(path):
            out[stem] = path
    return out


def bless(root, is_codex):
    manifest = {"note": "SHA-256 of each role's prompt body; see "
                        "verify-install.py --bless",
                "bodies": {}}
    for stem, path in sorted(role_files(root, is_codex).items()):
        digest = hashlib.sha256(
            prompt_body(path, root).encode("utf-8")).hexdigest()
        manifest["bodies"][stem] = "sha256:" + digest
    out = os.path.join(root, HASHES)
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
        fh.write("\n")
    return out, len(manifest["bodies"])


def check_prompt_hashes(root, is_codex):
    """No manifest is not a failure -- the first /orchestrate-sync run
    creates one, before it edits anything."""
    path = os.path.join(root, HASHES)
    if not os.path.isfile(path):
        return
    try:
        bodies = json.loads(read(path)).get("bodies", {})
    except ValueError as exc:
        fail("%s: does not parse: %s" % (HASHES, exc))
        return
    for stem, path_ in sorted(role_files(root, is_codex).items()):
        expected = bodies.get(stem)
        if not expected:
            continue
        actual = "sha256:" + hashlib.sha256(
            prompt_body(path_, root).encode("utf-8")).hexdigest()
        if actual != expected:
            fail("agents/%s: prompt body changed since it was blessed "
                 "(expected %s, got %s). /orchestrate-sync may change "
                 "frontmatter only. If the edit was deliberate, re-bless: "
                 "verify-install.py --bless <dir>"
                 % (os.path.basename(path_), expected[:14], actual[:14]))


# ------------------------------------------------------------- claude ----

def check_claude(root, cfg, rows):
    for stem, key in ROLES.items():
        path = os.path.join(root, "agents", stem + ".md")
        if not os.path.isfile(path):
            fail("agents/%s.md: missing" % stem)
            continue
        text = read(path)
        fm = frontmatter(text)
        if fm is None:
            fail("agents/%s.md: no valid YAML frontmatter block" % stem)
            continue
        if fm.get("name") != stem:
            fail("agents/%s.md: frontmatter name is %r" % (stem, fm.get("name")))

        # three-way model/effort agreement
        role_cfg = cfg.get(key, {})
        row = rows.get(stem)
        for field, cfg_key, col in (("model", "model", 1),
                                    ("effort", "desiredEffort", 2)):
            seen = {"frontmatter": fm.get(field),
                    "orchestration.json": role_cfg.get(cfg_key)}
            if row and len(row) > col:
                seen["README table"] = row[col]
            values = set(v for v in seen.values() if v)
            if len(values) > 1:
                fail("%s %s disagrees: %s" % (
                    stem, field,
                    ", ".join("%s=%s" % kv for kv in sorted(seen.items()))))
            elif not values:
                fail("%s: %s is not recorded anywhere" % (stem, field))

        tools = fm.get("tools")
        if stem == "task-orchestrator":
            if tools:
                fail("agents/task-orchestrator.md: has a tools: allowlist; the "
                     "manager must keep the full toolset")
        else:
            if not tools:
                fail("agents/%s.md: delegate has no tools: allowlist" % stem)
                tools = ""
            if re.search(r"\bAgent\b", tools):
                fail("agents/%s.md: delegate may not have the Agent tool "
                     "(delegates never spawn)" % stem)
            writes = re.search(r"\bEdit\b|\bWrite\b", tools)
            if stem in READ_ONLY_ROLES and writes:
                fail("agents/%s.md: read-only role must not have Edit/Write: %s"
                     % (stem, tools))
            if stem == "test-validator":
                allowed = cfg.get("validator", {}).get("allowTestWrites")
                if allowed and not writes:
                    fail("agents/test-validator.md: allowTestWrites is true but "
                         "the allowlist withholds Edit/Write")
                if allowed is False and writes:
                    fail("agents/test-validator.md: allowTestWrites is false but "
                         "the allowlist grants Edit/Write: %s" % tools)

        for block in MANDATORY_BLOCKS[stem]:
            if block not in text:
                fail("agents/%s.md: lost its %r block" % (stem, block))


# -------------------------------------------------------------- codex ----

def toml_get(path, keys):
    """Values for `keys` from a .toml, via tomllib when available."""
    raw = read(path)
    if tomllib:
        try:
            parsed = tomllib.loads(raw)
        except Exception as exc:
            fail("%s: does not parse as TOML: %s" % (os.path.basename(path), exc))
            return None
        return dict((k, parsed.get(k)) for k in keys), parsed
    out = {}
    for k in keys:
        m = re.search(r'(?m)^%s\s*=\s*"([^"]*)"' % re.escape(k), raw)
        out[k] = m.group(1) if m else None
    return out, None


def check_codex(root, cfg, rows):
    manager = os.path.join(root, "agents", "task-orchestrator.md")
    if not os.path.isfile(manager):
        fail("agents/task-orchestrator.md: missing")
    elif read(manager).startswith("---"):
        fail("agents/task-orchestrator.md: has frontmatter; the manager is the "
             "top-level session, never a registered subagent")
    if os.path.isfile(os.path.join(root, "agents", "task-orchestrator.toml")):
        fail("agents/task-orchestrator.toml: must not exist (the manager is "
             "never a subagent)")

    seen_files = set(os.path.basename(p)
                     for p in glob.glob(os.path.join(root, "agents", "*.toml")))
    for stem, sandbox in CODEX_SANDBOX.items():
        name = stem + ".toml"
        path = os.path.join(root, "agents", name)
        if name not in seen_files:
            fail("agents/%s: missing" % name)
            continue
        got = toml_get(path, ("name", "description", "developer_instructions",
                              "sandbox_mode", "model_reasoning_effort"))
        if got is None:
            continue
        values, parsed = got
        for required in ("name", "description", "developer_instructions"):
            if not values.get(required):
                fail("agents/%s: %s missing" % (name, required))
        if values.get("sandbox_mode") != sandbox:
            fail("agents/%s: sandbox_mode is %r, expected %r"
                 % (name, values.get("sandbox_mode"), sandbox))
        if parsed is not None and parsed.get("mcp_servers") is not None:
            if not isinstance(parsed.get("mcp_servers"), dict):
                fail("agents/%s: mcp_servers must be a table, got %r"
                     % (name, parsed.get("mcp_servers")))

        instructions = values.get("developer_instructions") or ""
        for block in MANDATORY_BLOCKS[stem]:
            if block not in instructions:
                fail("agents/%s: lost its %r block" % (name, block))

        # three-way effort agreement (Codex pins no model by default)
        role_cfg = cfg.get(ROLES[stem], {})
        row = rows.get(stem)
        seen = {"toml": values.get("model_reasoning_effort"),
                "orchestration.json": role_cfg.get("desiredEffort")}
        if row and len(row) > 1:
            seen["README table"] = row[1]
        distinct = set(v for v in seen.values() if v)
        if len(distinct) > 1:
            fail("%s reasoning effort disagrees: %s" % (
                stem, ", ".join("%s=%s" % kv for kv in sorted(seen.items()))))
        elif not distinct:
            fail("%s: reasoning effort is not recorded anywhere" % stem)


# ---------------------------------------------------------------- tree ----

# Category only -- the matched VALUE is never printed. This runs over files
# that may legitimately contain examples, and echoing a match would put a live
# secret in the terminal and the transcript.
SECRET = re.compile(
    r"(?i)\b(api[_-]?key|secret|password|token)\b\s*[:=]\s*[\"']?[A-Za-z0-9/+_-]{16,}")
# Installer placeholder, e.g. {{CLAUDE_DIR}}. Matching the shape rather than a
# bare double-brace keeps this file from flagging itself.
TOKEN = re.compile(r"\{\{[A-Z][A-Z0-9_]*\}\}")


def check_tree(root):
    for path in bundle_files(root):
        try:
            text = read(path)
        except (UnicodeDecodeError, OSError):
            continue
        rel = os.path.relpath(path, root)
        token = TOKEN.search(text)
        if token:
            fail("%s: unsubstituted installer token %s" % (rel, token.group(0)))
        secret = SECRET.search(text)
        if secret:
            fail("%s: line %d looks like a credential (%s) -- value not shown"
                 % (rel, text.count("\n", 0, secret.start()) + 1,
                    secret.group(1).lower()))


# ---------------------------------------------------------------- main ----

def main(argv):
    args = [a for a in argv[1:] if a != "--bless"]
    blessing = "--bless" in argv[1:]
    if len(args) != 1:
        print(__doc__.strip())
        return 2
    root = os.path.abspath(args[0])
    if not os.path.isdir(os.path.join(root, "agents")):
        print("FAIL: %s has no agents/ directory -- not an install root" % root)
        return 2

    is_codex = bool(glob.glob(os.path.join(root, "agents", "*.toml")))
    platform = "codex" if is_codex else "claude"

    if blessing:
        out, count = bless(root, is_codex)
        print("Blessed %d prompt bodies -> %s" % (count, out))
        return 0

    cfg = check_json(root)
    rows = readme_table(root)
    (check_codex if is_codex else check_claude)(root, cfg, rows)
    check_prompt_hashes(root, is_codex)
    check_tree(root)

    if FAILURES:
        for msg in FAILURES:
            print("FAIL: " + msg)
        print("%d problem(s) in %s (%s)" % (len(FAILURES), root, platform))
        return 1
    print("OK: %s install verified (%s)" % (root, platform))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
