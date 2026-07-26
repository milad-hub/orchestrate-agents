"""Negative cases for orchestrator-spec/verify-install.py.

A green verify run only proves the verifier did not complain -- not that it
would. Each case corrupts one thing in a throwaway COPY of a real install,
asserts the verifier fails with the expected message, and moves on. The
original install is never touched.

    python verify-install-negative.py <install-dir>

<install-dir> is a directory the smoke suite just installed into, e.g.
$SCRATCH/claude-only/.claude. Platform is autodetected, same as the verifier.
"""
import glob
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERIFIER = os.path.join(ROOT, "templates", "orchestrator-spec",
                        "verify-install.py")


def edit(path, old, new):
    """Replace `old` once in `path`, asserting it was actually there."""
    def mutate(root):
        target = os.path.join(root, path)
        text = io.open(target, encoding="utf-8", newline="").read()
        if text.count(old) < 1:
            raise AssertionError("fixture drifted: %r not in %s" % (old, path))
        text = text.replace(old, new, 1)
        io.open(target, "w", encoding="utf-8", newline="").write(text)
    return mutate


CLAUDE_CASES = [
    ("worker model disagrees between json and frontmatter",
     edit("orchestration.json", '"model": "sonnet"', '"model": "haiku"'),
     "model disagrees"),
    ("read-only researcher granted Write",
     edit("agents/codebase-researcher.md", "tools: Read,", "tools: Write, Read,"),
     "must not have Edit/Write"),
    ("worker loses its capability packet block",
     edit("agents/implementation-worker.md",
          "## Capability packet (mandatory)", "## Capabilities"),
     "lost its"),
    ("bypassPermissions turned on",
     edit("orchestration.json", '"allowBypassPermissions": false',
          '"allowBypassPermissions": true'),
     "allowBypassPermissions"),
    ("unsubstituted installer token left behind",
     edit("README-orchestration.md", "## 1. Architecture",
          "## 1. Architecture {{CLAUDE_DIR}}"),
     "unsubstituted installer token"),
]

CODEX_CASES = [
    ("read-only researcher given workspace-write",
     edit("agents/codebase-researcher.toml", 'sandbox_mode = "read-only"',
          'sandbox_mode = "workspace-write"'),
     "sandbox_mode"),
    ("judge effort disagrees between toml and json",
     edit("agents/result-judge.toml", 'model_reasoning_effort = "high"',
          'model_reasoning_effort = "low"'),
     "reasoning effort disagrees"),
    ("worker loses its instruction hierarchy block",
     edit("agents/implementation-worker.toml",
          "## Instruction hierarchy (mandatory)", "## Instructions"),
     "lost its"),
]


def verify(root):
    result = subprocess.run([sys.executable, VERIFIER, root],
                            capture_output=True, text=True)
    return result.returncode, (result.stdout + result.stderr).strip()


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip())
        return 2
    source = os.path.abspath(argv[1])
    is_codex = bool(glob.glob(os.path.join(source, "agents", "*.toml")))
    cases = CODEX_CASES if is_codex else CLAUDE_CASES

    code, out = verify(source)
    ok = code == 0
    print(("PASS: " if ok else "FAIL: ") + "baseline install verifies clean")
    if not ok:
        print("      " + out)
    results = [ok]

    tmp = tempfile.mkdtemp()
    try:
        for label, mutate, expected in cases:
            work = os.path.join(tmp, re.sub(r"\W+", "-", label))
            shutil.copytree(source, work)
            mutate(work)
            code, out = verify(work)
            ok = code != 0 and expected in out
            print(("PASS: " if ok else "FAIL: ") + label)
            if not ok:
                print("      expected %r in: %s" % (expected, out or "<no output>"))
            results.append(ok)
            shutil.rmtree(work, ignore_errors=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
