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
    # The manager is the only role that derives a profile, because it is the
    # only one that resolves knowledge; losing the block leaves applicability
    # matching with nothing to match against. Claude only: the Codex manager is
    # prose the session reads rather than a registered subagent, so the
    # mandatory-block check does not cover it there.
    ("manager loses its repository profile block",
     "agents/task-orchestrator.md", "## Repository profile (mandatory)",
     "## Repository notes", "lost its"),
    # The declaration is what dispatch routes on. A role claiming it writes
    # nothing while the harness grants writes is a guarantee nobody holds.
    ("worker declares it writes nothing while holding Edit/Write",
     "agents/implementation-worker.md", "- **Writes**: assigned source files.",
     "- **Writes**: none.", "declaration is what dispatch trusts"),
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
    # Codex grants writes through the sandbox rather than a tool allowlist, but
    # the declaration must agree with it just the same.
    ("worker declares it writes nothing while sandboxed for writes",
     "agents/implementation-worker.toml", "- **Writes**: assigned source files.",
     "- **Writes**: none.", "declaration is what dispatch trusts"),
]

# The knowledge tree, its manifest and its configuration are identical on both
# platforms -- they ship with the spec and carry no platform syntax -- so these
# run against either install.
SHARED_CASES = [
    ("knowledge document loses a required frontmatter field",
     "orchestrator-spec/knowledge/rules/security.md", "\nprecedence: 90", "",
     "frontmatter is missing precedence"),
    ("knowledge precedence outside its band",
     "orchestrator-spec/knowledge/rules/security.md", "precedence: 90",
     "precedence: 900", "outside 0-100"),
    ("knowledge id no longer matches its filename",
     "orchestrator-spec/knowledge/rules/git.md", "id: git", "id: gitt",
     "does not match the filename"),
    ("knowledge category outside the schema",
     "orchestrator-spec/knowledge/memory/glossary.md", "category: memory",
     "category: notes", "is not one of"),
    # The failure that looks like nothing: a document on disk that no agent can
    # select, because the manifest it is found through never learned about it.
    ("manifest no longer matches the tree",
     "orchestrator-spec/knowledge/index.json", '"id": "security"',
     '"id": "securite"', "out of date"),
    # An applicability token is matched against the repository profile by
    # equality. A malformed one cannot match anything, so it silently excludes
    # its own document -- the rule stops applying and nothing says so.
    ("applicability token that can never match a profile",
     "orchestrator-spec/knowledge/rules/coding.md", "applies: *",
     "applies: Angular 17", "can never match"),
    ("applicability mixes everywhere with named technologies",
     "orchestrator-spec/knowledge/rules/testing.md", "applies: *",
     "applies: *, angular", "mixes"),
    # The knowledge block is what makes selection bounded. Losing the budget
    # would not fail anything at run time -- it would just quietly inject the
    # whole tree into every packet.
    ("knowledge document budget outside its range",
     "orchestration.json", '"maximumDocuments": 12',
     '"maximumDocuments": 0', "knowledge.maximumDocuments"),
    ("knowledge ranking policy is not a policy name",
     "orchestration.json", '"rankingPolicy": "applicability-precedence"',
     '"rankingPolicy": ""', "knowledge.rankingPolicy"),
    # The packet slicing table decides which documents reach which delegate.
    # A stale id there is the quietest failure in the system: the rule stays
    # in the manifest, the install stays green, and one role silently stops
    # receiving it. The manager is a plain .md on both platforms, so unlike
    # the mandatory-block cases these do cover Codex.
    ("slicing table names a document that is not in the manifest",
     "agents/task-orchestrator.md", "`rule/testing`, `rule/security`",
     "`rule/nonexistent`, `rule/security`", "manifest has no such document"),
    # Narrowing a slice is a budget decision; narrowing away a security-band
    # document is a security decision wearing a budget's clothes. The narrowed
    # roles are the ones reading untrusted repository content.
    ("slicing table drops a security-band document from a narrowed slice",
     "agents/task-orchestrator.md",
     "| `test-validator` | `rule/testing`, `rule/security`, `rule/git`, "
     "`memory/conventions` |",
     "| `test-validator` | `rule/testing`, `rule/git`, `memory/conventions` |",
     "reaches every delegate, never only some"),
    ("slicing table removed entirely",
     "agents/task-orchestrator.md", "Packet slicing:", "Removed:",
     "nothing says which documents reach which delegate"),
    # A role the table forgets has no defined slice -- not a narrow one, an
    # undefined one. A misspelled role name produces the same hole while the
    # table still looks complete, which is why this checks by role rather
    # than by row count.
    ("slicing table forgets a delegate",
     "agents/task-orchestrator.md",
     "| `result-judge` | the full selected set |", "",
     "no row for result-judge"),
    ("config kept from an older bundle",
     "orchestration.json", '"schemaVersion": 4', '"schemaVersion": 3',
     "Migrate it"),
    # A skill is invoked by name and reported against. A descriptor missing a
    # section is a skill nothing can be finished against.
    ("skill descriptor loses a required section",
     "orchestrator-spec/knowledge/skills/bug-fixing.md",
     "## Completion criteria", "## Done when", "missing Completion criteria"),
    ("skill descriptor loses its prerequisites",
     "orchestrator-spec/knowledge/skills/code-review.md",
     "## Prerequisites", "## Preconditions", "missing Prerequisites"),
    # Whole-tree defects: the ones no per-file check can see.
    ("two documents claiming the same title",
     "orchestrator-spec/knowledge/rules/git.md",
     "title: Version control rules",
     "title: Coding rules that hold in every repository", "duplicate title"),
    ("a document filed outside its category's directory",
     "orchestrator-spec/knowledge/memory/glossary.md", "category: memory",
     "category: rule", "belongs under rules/"),
    # The security band is what "never overridden by convenience" means. A
    # template sitting in it would outrank the security rules while carrying
    # none of their authority.
    ("a template promoted into the security band",
     "orchestrator-spec/knowledge/templates/adr.md", "precedence: 30",
     "precedence: 90", "security band"),
    ("a cross-reference that resolves to nothing",
     "orchestrator-spec/knowledge/rules/git.md", "# Git rules",
     "# Git rules\n\nSee [[nonexistent-doc]].", "resolves to nothing"),
    ("a cross-reference that is ambiguous",
     "orchestrator-spec/knowledge/rules/git.md", "# Git rules",
     "# Git rules\n\nSee [[security]].", "ambiguous"),
    # The shortest possible cycle, because a case here may edit one file. The
    # general graph walk catches longer ones.
    ("a document that references itself",
     "orchestrator-spec/knowledge/rules/git.md", "# Git rules",
     "# Git rules\n\nSee [[rule/git]].", "circular reference"),
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
    cases = (CODEX_CASES if is_codex else CLAUDE_CASES) + SHARED_CASES

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
