# Spike: {slug}

**Bead**: {bead-id}
**Branch**: spike/{slug}
**Date**: {YYYY-MM-DD}

<!--
A spike answers one question that talking could not settle ("I need to see it").
Copy this file to grimoires/loa/spikes/{slug}.md, the path the open DEC row names as
its source. The prototype lives on spike/{slug} in its own worktree: pushed, never
merged into another branch, no PR. This report and the verdict row (dec-write-lib.sh
decide) are committed on the working branch, never on spike/{slug}.
Check it with: .claude/scripts/validate-artifact.sh --type spike --file <this file>
-->

## Question
{The one question the prototype answers, as the interview or map ticket asked it.}

## What was built
{What the prototype does and leaves out, in a few lines, and what the operator looked at.}

## Verdict
{One line: the answer to the question.}

## Pointer
Branch spike/{slug} at commit {sha}, or the path of what was built.

## Decided by
{operator or agent}, recorded as {DEC-NNNN}; an agent verdict stays proposed until the operator runs /decisions confirm.
