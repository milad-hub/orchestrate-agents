"""Negative cases for check-drift.py.

A green drift run only proves the checker did not complain -- not that it
would. Each case here breaks one invariant, asserts check-drift.py fails
with the expected message, restores the file, and asserts it passes again.

Run: python tests/check-drift-negative.py
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANAGER = ROOT / "templates/agents/task-orchestrator.md"
VALIDATOR = ROOT / "templates/agents/test-validator.md"
REPORTING = ROOT / "templates/orchestrator-spec/policies/reporting.md"
CODEX_UPDATE_SKILL = ROOT / ("templates/codex/skills/orchestrate-update/"
                             "references/orchestrate-update-body.md")


def drift():
    result = subprocess.run([sys.executable, "tests/check-drift.py"], cwd=ROOT,
                            capture_output=True, text=True)
    return result.returncode, result.stdout.strip()


def case(label, path, mutate, expected):
    original = path.read_text(encoding="utf-8", newline="")
    try:
        path.write_text(mutate(original), encoding="utf-8", newline="")
        code, out = drift()
        ok = code != 0 and expected in out
        print(("PASS: " if ok else "FAIL: ") + label)
        if not ok:
            print("      expected %r in: %s" % (expected, out or "<no output>"))
        return ok
    finally:
        path.write_text(original, encoding="utf-8", newline="")


def move_triage_after_discovery(text):
    """Swap the triage step's body with the instruction-discovery step's."""
    bodies = {int(n): b for n, b in re.findall(
        r"(?ms)^(\d+)\.\s+(.*?)(?=^\d+\.\s+|^## |\Z)", text)}
    triage = min(n for n, b in bodies.items() if "provisional class" in b)
    discovery = min(n for n, b in bodies.items()
                    if "Discover applicable instructions" in b)
    out = text.replace("%d. %s" % (triage, bodies[triage]), "%d. @@HOLD@@" % triage)
    out = out.replace("%d. %s" % (discovery, bodies[discovery]),
                      "%d. %s" % (discovery, bodies[triage]))
    return out.replace("@@HOLD@@", bodies[discovery])


results = [
    case("triage moved below discovery is rejected",
         MANAGER, move_triage_after_discovery, "must precede step"),
    case("prompt dropping a status token is rejected",
         VALIDATOR,
         # target the Readiness line, not the description -- status_vocab
         # only reads Status:/Readiness:/Final verdict: lines
         lambda t: t.replace("Readiness: PASS / PASS_WITH_GAPS / FAIL / BLOCKED / TIMEOUT",
                             "Readiness: PASS / PASS_WITH_GAPS / FAIL / BLOCKED", 1),
         "status vocabulary"),
    case("canonical source dropping a role is rejected",
         REPORTING,
         lambda t: re.sub(r"(?m)^- test-validator:.*$\n", "", t),
         "no canonical status line"),
    # The two orchestrate-update bodies drifted for a whole round while only
    # the agents were compared. Prove the pair is actually in the comparison.
    case("the two orchestrate-update bodies diverging is rejected",
         CODEX_UPDATE_SKILL,
         lambda t: t.replace("### 5. Report", "### 5. Summary", 1),
         "orchestrate-update heading"),
]

code, out = drift()
print(("PASS: " if code == 0 else "FAIL: ") + "clean after restore")
if code != 0:
    print("      " + out)
results.append(code == 0)

sys.exit(0 if all(results) else 1)
