---
id: performance
category: skill
title: Make something measurably faster
applies: *
precedence: 40
---

# Performance

## Purpose

Reduce a measured cost — time, memory, queries, payload — without changing what
the code does.

Wrong choice without a measurement. Optimizing what was never measured changes
code with no evidence it helped, and usually costs readability for nothing.
Also wrong when the real problem is correctness: a fast wrong answer is worse
than a slow one.

## Prerequisites

- A measurement of the current cost, taken the same way it will be taken
  afterwards.
- A target, or at minimum a statement of what would count as better.
- A passing suite, so a behavior change is detectable.

## Required context

`coding`, `architecture`, `testing`; the repository profile, because what is
expensive depends on the stack.

## Execution steps

1. Measure first, and record the method exactly — the number is meaningless
   without it.
2. Find where the cost actually is. Profile or instrument; do not assume. The
   expensive line is routinely not the suspected one.
3. Check for the structural causes before the micro ones: repeated work in a
   loop, N+1 queries, work done per item that could be done per batch, data
   fetched and discarded.
4. Change one thing, then re-measure with the same method.
5. Confirm behavior is unchanged: same tests, same results.
6. Record what the change cost in readability, and whether that is worth it.

## Expected outputs

- Before and after measurements, with the method stated.
- The change, scoped to what the measurement justified.
- Suite results proving behavior did not move.
- What was tried and did not help.

## Validation checklist

- Both measurements used the same method, environment and input.
- The improvement is outside measurement noise — state the variance, not one
  sample.
- The full suite passes, identical to before.
- No correctness traded for speed: no dropped validation, no weakened error
  handling, no cache without an invalidation story.

## Quality checklist

- Was the bottleneck measured or guessed?
- Is the gain worth the complexity added?
- Does the change hold for realistic input sizes, not just the benchmark's?
- Would a reader understand why this code is shaped oddly, or does it need a
  comment naming the constraint?

## Completion criteria

- Improvement demonstrated by comparable before-and-after measurements.
- Behavior unchanged, evidenced by the suite.
- Method recorded so the measurement can be repeated.
- Rejected approaches named, so the next person does not retry them.
