---
id: documentation
category: skill
title: Write or update documentation that stays true
applies: *
precedence: 35
---

# Documentation

## Purpose

Record what someone needs and cannot get from the code, in a form that will
still be correct after the next change.

Wrong choice for restating what the code says. A stale line is worse than a
missing one: it gets trusted and acted on, and nothing fails when it lies.

## Prerequisites

- The behavior being documented exists and was observed, not planned.
- The repository's documentation conventions are known — where docs live, how
  they are structured, what is generated.

## Required context

`conventions`, `project-overview`, and the repository's own instruction files.

## Execution steps

1. Establish the reader and what they cannot derive themselves. Documentation
   that answers a question nobody has is cost with no return.
2. Find the existing document that owns this subject; extend it rather than
   adding a competing one.
3. Verify every command, path, flag and version by running or reading it. A
   documented command that was never executed is a guess with formatting.
4. Write the reason, not the narration — why something is done this way, not
   what the next line does.
5. Name what is deliberately excluded, where its absence would read as an
   oversight.
6. Check cross-references and links resolve.

## Expected outputs

- The document, or the edit to an existing one.
- Verified commands and paths.
- A note of anything that could not be verified, marked as such.

## Validation checklist

- Every command in the document was run, and its output matched what is
  claimed.
- Every path and file reference exists.
- Every link resolves.
- Nothing is documented that the code already states plainly.
- No aspiration written as fact: planned behavior is marked as planned.

## Quality checklist

- Will this still be true after a routine refactor, or is it coupled to
  details that move?
- Does it answer the question a reader actually arrives with?
- Is it shorter than the thing it explains?
- Does it duplicate a document that already exists?

## Completion criteria

- Content verified against the repository, with unverifiable parts marked.
- Placed in the document that owns the subject.
- Links and references resolve.
- No claim about behavior that was not observed.
