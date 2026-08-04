"""The learning loop must never write knowledge, only propose it.

    python proposal-gate-test.py <install-dir> [<install-dir> ...]

Proposals are the one place an agent is invited to author knowledge, which
makes them the one place a bad rule can install itself permanently. Three
things hold that shut, and this asserts all three from the shipped files
rather than from the prose that describes them:

  1. `knowledge.allowProposals` ships false.
  2. Every prompt that mentions proposals routes them to
     `.orchestrate/proposals/` -- never into the knowledge tree.
  3. No prompt tells anyone to merge, apply or install one.

A grep-shaped test for a grep-shaped guarantee: the gate is a prompt contract
plus the absence of a write instruction, so absence is what has to be checked.
"""
import io
import json
import os
import re
import sys

FAILURES = []


def ok(msg):
    print("PASS: " + msg)


def fail(msg):
    print("FAIL: " + msg)
    FAILURES.append(msg)


def read(path):
    return io.open(path, encoding="utf-8", newline="").read()


def prompt_files(root):
    out = []
    agents = os.path.join(root, "agents")
    for name in sorted(os.listdir(agents)):
        if name.endswith((".md", ".toml")):
            out.append(os.path.join(agents, name))
    return out


# "merge this proposal", "apply the proposal", "install a proposal" -- the
# instruction that would turn a suggestion into a rule without a human.
MERGE = re.compile(
    r"(?i)\b(merge|apply|install|accept|commit)\b[^.\n]{0,40}\bproposals?\b")
# ... and the same idea the other way round.
MERGE_REVERSED = re.compile(
    r"(?i)\bproposals?\b[^.\n]{0,30}\b(are|is|be)\s+(merged|applied|installed)\b"
    r"(?!\s*(?:automatically|by a human|-- a human))")


def check_install(root):
    label = os.path.basename(root) or root

    config = os.path.join(root, "orchestration.json")
    try:
        data = json.loads(read(config))
    except (IOError, OSError, ValueError) as exc:
        fail("%s: orchestration.json unreadable: %s" % (label, exc))
        return
    if data.get("knowledge", {}).get("allowProposals") is False:
        ok("%s: proposals ship off" % label)
    else:
        fail("%s: knowledge.allowProposals is %r, expected false"
             % (label, data.get("knowledge", {}).get("allowProposals")))

    mentions = 0
    for path in prompt_files(root):
        text = read(path)
        rel = os.path.relpath(path, root).replace("\\", "/")
        if "proposal" not in text.lower():
            continue
        mentions += 1

        # Every proposal destination named must be the quarantine directory.
        for match in re.finditer(r"(?i)write[^.\n]{0,60}proposals?[^.\n]{0,60}",
                                 text):
            window = match.group(0)
            if "knowledge/" in window and ".orchestrate/proposals" not in window:
                fail("%s: %s names the knowledge tree as a proposal "
                     "destination: %r" % (label, rel, window.strip()))

        found = MERGE.search(text) or MERGE_REVERSED.search(text)
        if found:
            fail("%s: %s instructs merging a proposal: %r"
                 % (label, rel, found.group(0).strip()))

    if mentions:
        ok("%s: %d prompt(s) mention proposals, none instructs a merge or a "
           "write into the knowledge tree" % (label, mentions))
    else:
        fail("%s: no prompt mentions proposals -- the gate is not stated "
             "anywhere, so nothing holds it" % label)

    # The quarantine directory is in the repository under work, never in the
    # bundle: a proposal that landed beside the knowledge it proposes is one
    # accidental copy away from being installed.
    stray = os.path.join(root, "orchestrator-spec", "knowledge", "proposals")
    if os.path.exists(stray):
        fail("%s: proposals directory exists inside the knowledge tree" % label)
    else:
        ok("%s: no proposals directory inside the knowledge tree" % label)


def main(argv):
    if not argv:
        print(__doc__.strip())
        return 2
    for root in argv:
        check_install(os.path.abspath(root))
    if FAILURES:
        print("%d problem(s)" % len(FAILURES))
        return 1
    print("proposal gate holds")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
