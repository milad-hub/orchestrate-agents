"""Check cross-platform prompt structure and numbered-step references."""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENT_PAIRS = {
    name: ("templates/agents/%s.md" % name,
           "templates/codex/agents/%s%s" % (
               name, ".md" if name == "task-orchestrator" else ".toml"))
    for name in ("task-orchestrator", "codebase-researcher",
                 "implementation-worker", "test-validator", "result-judge")
}
# The skills are hand-maintained in parallel too, and drifted unnoticed while
# only the agents were compared. They carry no status vocabulary and no
# ordered steps, so they get the structural comparison and nothing else.
SKILL_PAIRS = {
    "orchestrate-sync": (
        "templates/skills/orchestrate-sync/SKILL.md",
        "templates/codex/skills/orchestrate-sync/references/"
        "orchestrate-sync-body.md"),
    "orchestrate": ("templates/skills/orchestrate/SKILL.md",
                    "templates/codex/skills/orchestrate/SKILL.md"),
}
PAIRS = dict(AGENT_PAIRS, **SKILL_PAIRS)
STOP_WORDS = {
    "about", "after", "before", "current", "discover", "every", "from",
    "manager", "only", "read", "repository", "session", "step", "these",
    "those", "through", "under", "where", "which", "while", "with", "your",
}


# Structural comparison cannot express a DELIBERATE divergence between the
# two platforms, and it cannot see a rule both platforms drop together.
# Keep this list tiny -- it is a safety net for the few invariants that are
# expensive to lose, not a return to phrase-matching whole prompts.
# (needle, path, must_be_present)
INVARIANTS = [
    # Claude subagents push a completion notification when they finish;
    # polling in slices is a Codex concept and costs manager turns at
    # manager rates. The divergence is deliberate and must stay.
    ("waitSliceSeconds", "templates/agents/task-orchestrator.md", False),
    ("waitSliceSeconds", "templates/codex/agents/task-orchestrator.md", True),
]

# Triage must come before discovery on both platforms, or every trivial run
# pays for discovery it never uses. Bound by ORDER, not by step number --
# the numbers have already shifted twice, and a number-bound assert would
# false-fail on the next legitimate insertion above triage.
ORDERED_STEPS = [("provisional class", "Discover applicable instructions")]

# Canonical status vocabularies live in policies/reporting.md; the prompts
# must match. Derived, never duplicated here.
REPORTING = "templates/orchestrator-spec/policies/reporting.md"


def read(relative_path):
    return (ROOT / relative_path).read_text(encoding="utf-8")


def prompt_body(relative_path):
    """The comparable prompt text.

    For a Codex .toml only the developer_instructions block is the prompt;
    the surrounding TOML keys are platform plumbing, and a commented-out
    key like `# model = ""` would otherwise parse as a markdown heading.
    """
    text = read(relative_path)
    if relative_path.endswith(".toml"):
        _, _, rest = text.partition('developer_instructions = """')
        body, _, _ = rest.partition('"""')
        return body or text
    return text


def layout(text):
    result = []
    for section in re.split(r"(?=^#{1,6}\s+)", text, flags=re.MULTILINE)[1:]:
        heading = re.match(r"^(#+)\s+(.+)$", section, re.MULTILINE)
        result.append((len(heading.group(1)), heading.group(2).strip(),
                       len(re.findall(r"^\d+\.\s+", section, re.MULTILINE))))
    return result


def status_vocab(text):
    lines = re.findall(
        r"^(?:\d+\.\s+)?(?:Status|Readiness|Final verdict):.*$",
        text, re.MULTILINE | re.IGNORECASE)
    return sorted(set(re.findall(r"\b[A-Z][A-Z_]{2,}\b", "\n".join(lines))))


def words(text):
    return {word for word in re.findall(r"[a-z][a-z-]{3,}", text.lower())
            if word not in STOP_WORDS}


def numbered_steps(text):
    return {int(number): body for number, body in re.findall(
        r"(?ms)^(\d+)\.\s+(.*?)(?=^\d+\.\s+|^## |\Z)", text)}


def check_step_order(path, text):
    steps = numbered_steps(text)
    for earlier, later in ORDERED_STEPS:
        first = [n for n, body in steps.items() if earlier in body]
        second = [n for n, body in steps.items() if later in body]
        if not first:
            failures.append("%s has no step containing %r" % (path, earlier))
        elif not second:
            failures.append("%s has no step containing %r" % (path, later))
        elif min(first) > min(second):
            failures.append("%s: step %d (%r) must precede step %d (%r)"
                            % (path, min(first), earlier, min(second), later))


def canonical_vocab():
    """Role -> status tokens, parsed from the canonical reporting policy."""
    return {role.strip(): sorted(set(re.findall(r"\b[A-Z][A-Z_]{2,}\b", tokens)))
            for role, tokens in re.findall(
                r"(?m)^-\s+([a-z-]+):\s+(.+)$", read(REPORTING))}


def check_step_references(path, text):
    steps = {int(number): body for number, body in re.findall(
        r"(?ms)^(\d+)\.\s+(.*?)(?=^\d+\.\s+|^## |\Z)", text)}
    for match in re.finditer(r"\(step (\d+)\)", text, re.IGNORECASE):
        number = int(match.group(1))
        if number not in steps:
            failures.append("%s references missing step %d" % (path, number))
        elif not words(text[max(0, match.start() - 120):match.start()]) & words(steps[number]):
            failures.append("%s step %d reference no longer matches its target"
                            % (path, number))


failures = []
for name, (claude_path, codex_path) in PAIRS.items():
    claude, codex = prompt_body(claude_path), prompt_body(codex_path)
    if layout(claude) != layout(codex):
        failures.append("%s heading/numbered-section structure differs" % name)
    if status_vocab(claude) != status_vocab(codex):
        failures.append("%s status vocabularies differ: %s != %s"
                        % (name, status_vocab(claude), status_vocab(codex)))
    check_step_references(claude_path, claude)
    check_step_references(codex_path, codex)
    if name == "task-orchestrator":
        check_step_order(claude_path, claude)
        check_step_order(codex_path, codex)

vocab = canonical_vocab()
for name, (claude_path, codex_path) in AGENT_PAIRS.items():
    if name not in vocab:
        if name != "task-orchestrator":
            failures.append("%s has no canonical status line in %s"
                            % (name, REPORTING))
        continue
    for path in (claude_path, codex_path):
        found = status_vocab(prompt_body(path))
        if found and found != vocab[name]:
            failures.append("%s status vocabulary %s != canonical %s (%s)"
                            % (path, found, vocab[name], REPORTING))

for needle, path, must_be_present in INVARIANTS:
    if (needle in read(path)) != must_be_present:
        failures.append("%s: %r must be %s" % (
            path, needle, "present" if must_be_present else "absent"))

# docs/ explains the spec rather than restating it, so every page names the
# spec files that own its subject. A page pointing at a file that no longer
# exists is documentation that has silently stopped describing anything --
# which is the failure mode a doc tree has, since nothing else fails when it
# goes stale.
DOC_LINK = re.compile(r"\]\((\.\./[^)#]+)\)")
docs_dir = ROOT / "docs"
if not docs_dir.is_dir():
    failures.append("docs/ is missing")
else:
    pages = sorted(docs_dir.glob("*.md"))
    if len(pages) < 2:
        failures.append("docs/ has no pages")
    for page in pages:
        rel = "docs/" + page.name
        text = page.read_text(encoding="utf-8")
        targets = DOC_LINK.findall(text)
        for target in targets:
            if not (docs_dir / target).resolve().exists():
                failures.append("%s links to missing %s" % (rel, target))
        # The index is a table of contents; every other page must anchor to
        # something outside docs/, or it is prose with no source.
        if page.name != "README.md" and not any(
                not t.startswith("../docs/") for t in targets):
            failures.append("%s cites no file outside docs/" % rel)

for f in failures:
    print("DRIFT: " + f)
sys.exit(1 if failures else 0)
