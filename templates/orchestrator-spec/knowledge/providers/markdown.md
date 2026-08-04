---
id: markdown
category: provider
title: The knowledge tree itself
applies: *
precedence: 50
---

# Markdown provider

**Source:** every document under `knowledge/`, as listed in `knowledge/index.json`.
**Trust level:** curated.
**Refresh:** at install, and whenever the manifest is regenerated.

## What it provides

Memory, rules, skills and templates. This is the only provider that
ships with content rather than deriving it.

## How it is read

Through the manifest. An agent selects by category and applicability, then reads the
paths it selected. Walking the tree is not a supported access path: it makes selection
unbounded and unreportable, and it silently picks up files that were never meant to be
knowledge.

## Excluded

`README.md` files and anything under `rules/examples/`. Both are documentation about the
tree rather than knowledge in it, which is why neither carries frontmatter or appears in
the manifest.

## Failure behavior

A document that does not parse fails the install rather than being skipped. Silently
skipping malformed knowledge is how a rule stops applying without anyone noticing.

## Staleness

None to manage. The content is versioned with the bundle, so it is exactly as current as
the installed release.
