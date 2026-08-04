---
id: architecture
category: rule
title: Architectural rules for changes to this bundle and to target repositories
applies: *
precedence: 45
---

# Architecture rules

## Respect the boundary you found

A change belongs in the layer that owns the concern. Reaching across a boundary because
it is shorter converts a local change into a structural one.

## Evolve rather than replace

Extend what exists before introducing a parallel structure. Two mechanisms doing one job
is worse than the imperfect mechanism that was already there.

## One responsibility per unit

A file, module or document answers one question. When it starts answering two, split it
along the seam that already exists rather than inventing one.

## Open to extension

Adding a case should mean adding a file or a descriptor, not editing a core one. When
adding the second instance of something requires touching shared code, the seam is in
the wrong place.

## Depend on declarations, not locations

Resolve things through a manifest, registry or interface rather than a hardcoded path.
Anything that names a path directly breaks when the layout moves.

## No hidden dependencies

What a component needs is declared where it is defined. A dependency discovered only at
run time is a defect waiting for an unusual environment.

## No global mutable state

State that anything can change from anywhere makes every failure non-local. This
includes knowledge that is true only on the machine that authored it.

## Justify structural change

A change to the architecture states what it enables and what it costs. An unexplained
structural change cannot be reviewed, only accepted or rejected.

## Prefer composition

Build behavior by combining pieces in a documented order rather than by inheritance or
transclusion. Composition is inspectable; inheritance chains are not.
