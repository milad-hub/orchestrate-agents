"""Negative cases for orchestrator-spec/verify-install.py.

A green verify run only proves the verifier did not complain -- not that it
would. Each case corrupts one thing in the install, asserts the verifier
reacts as expected, then restores the file. Mutations happen in place (never
on a copy) because the prompt-body manifest folds the install path, and a
copied tree would false-fail every hash.

    python verify-install-negative.py <install-dir>

<install-dir> is a directory the smoke suite just installed into, e.g.
$SCRATCH/claude-only/.claude. Platform is autodetected, same as the verifier.

Half the cases assert the verifier does NOT fire: a prompt-hash check that
trips on a legitimate frontmatter edit would make /orchestrate-sync
unusable, which is worse than the drift it prevents.
"""
import glob
import io
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERIFIER = os.path.join(ROOT, "templates", "orchestrator-spec",
                        "verify-install.py")

# (label, file, find, replace, expected)
#   expected = substring the verifier must report
#   expected = None -> the prompt-body hash must NOT fire (other guards may)
CLAUDE_CASES = [
    ("worker model disagrees between json and frontmatter",
     "orchestration.json", '"model": "sonnet"', '"model": "haiku"',
     "model disagrees"),
    ("read-only researcher granted Write",
     "agents/codebase-researcher.md", "tools: Read,", "tools: Write, Read,",
     "must not have Edit/Write"),
    ("worker loses its capability packet block",
     "agents/implementation-worker.md", "## Capability packet (mandatory)",
     "## Capabilities", "lost its"),
    ("bypassPermissions turned on",
     "orchestration.json", '"allowBypassPermissions": false',
     '"allowBypassPermissions": true', "allowBypassPermissions"),
    ("unsubstituted installer token left behind",
     "README-orchestration.md", "## 1. Architecture",
     "## 1. Architecture {{CLAUDE_DIR}}", "unsubstituted installer token"),
    # One installer answer fans out to several flags; a half-applied edit
    # splits them silently.
    ("test-write flags split between worker and commands",
     "orchestration.json", '"allowTestFileCreation": false',
     '"allowTestFileCreation": true', "test writes flags disagree"),
    ("blessed prompt body edited",
     "agents/result-judge.md", "## Independence (mandatory)",
     "## Independence (mandatory) EDITED", "prompt body changed"),
    # ... and the other direction: the fields the skill IS allowed to change.
    ("changing tools: does not trip the hash",
     "agents/codebase-researcher.md", "tools: Read, Grep",
     "tools: Read, Grep, WebSearch", None),
    ("changing effort: does not trip the hash",
     "agents/result-judge.md", "effort: high", "effort: medium", None),
    ("changing model: does not trip the hash",
     "agents/result-judge.md", "model: sonnet", "model: opus", None),
]

CODEX_CASES = [
    ("read-only researcher given workspace-write",
     "agents/codebase-researcher.toml", 'sandbox_mode = "read-only"',
     'sandbox_mode = "workspace-write"', "sandbox_mode"),
    ("judge effort disagrees between toml and json",
     "agents/result-judge.toml", 'model_reasoning_effort = "high"',
     'model_reasoning_effort = "low"', "reasoning effort disagrees"),
    ("worker loses its instruction hierarchy block",
     "agents/implementation-worker.toml", "## Instruction hierarchy (mandatory)",
     "## Instructions", "lost its"),
    ("build/serve flags split between commands and validator",
     "orchestration.json", '"allowBuildCommands": false',
     '"allowBuildCommands": true', "build commands flags disagree"),
    ("blessed prompt body edited",
     "agents/test-validator.toml", "## Validation rules",
     "## Validation guidelines", "prompt body changed"),
    ("changing mcp_servers does not trip the hash",
     "agents/codebase-researcher.toml", "mcp_servers = {}",
     "mcp_servers = { placeholder = {} }", None),
]


def verify(root, extra=()):
    result = subprocess.run([sys.executable, VERIFIER] + list(extra) + [root],
                            capture_output=True, text=True)
    return result.returncode, (result.stdout + result.stderr).strip()


def run_case(root, label, rel, find, replace, expected):
    path = os.path.join(root, rel)
    original = io.open(path, encoding="utf-8", newline="").read()
    if original.count(find) < 1:
        print("FAIL: %s (fixture drifted: %r not in %s)" % (label, find, rel))
        return False
    try:
        io.open(path, "w", encoding="utf-8", newline="").write(
            original.replace(find, replace, 1))
        code, out = verify(root)
    finally:
        io.open(path, "w", encoding="utf-8", newline="").write(original)

    if expected is None:
        # Not "the run is clean" -- editing effort in one place legitimately
        # trips the three-way agreement check. Only the hash must stay quiet.
        ok = "prompt body changed" not in out
        note = "prompt-body hash must not fire"
    else:
        ok = code != 0 and expected in out
        note = "expected %r" % expected
    print(("PASS: " if ok else "FAIL: ") + label)
    if not ok:
        print("      %s, got: %s" % (note, out or "<no output>"))
    return ok


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip())
        return 2
    root = os.path.abspath(argv[1])
    is_codex = bool(glob.glob(os.path.join(root, "agents", "*.toml")))
    cases = CODEX_CASES if is_codex else CLAUDE_CASES

    # The prompt-body cases need a manifest; blessing is idempotent.
    code, out = verify(root, extra=["--bless"])
    if code != 0:
        print("FAIL: could not bless prompt bodies: " + out)
        return 1

    code, out = verify(root)
    ok = code == 0
    print(("PASS: " if ok else "FAIL: ") + "baseline install verifies clean")
    if not ok:
        print("      " + out)
    results = [ok]

    for case in cases:
        results.append(run_case(root, *case))

    code, out = verify(root)
    ok = code == 0
    print(("PASS: " if ok else "FAIL: ") + "clean after restore")
    if not ok:
        print("      " + out)
    results.append(ok)

    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
