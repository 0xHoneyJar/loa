# Agent Ergonomics (cycle-119)

Mechanical rules for agent tool use. Tables/snippets only — no theory.

## 1. Wait-for-condition

Never bare `sleep N` then check.

```bash
until <check>; do sleep 2; done   # bounded poll
```

Or use the Monitor tool for a background process / one-shot "wait until done".

## 2. Directory changes

Never a bare relative `cd` after a resume/clear — the cwd may not be what you assume.

```bash
cd "$(git rev-parse --show-toplevel)/<subdir>"
```

## 3. Before any edit phase

List artifacts-to-touch, batch-Read them all, THEN edit.

Note: the harness still hard-errors un-Read writes — this removes the retry
round-trip, it does not replace the harness gate.

## 4. Edit-anchor freshness

If the target file was touched by any earlier tool call in this session,
re-check the anchor immediately before Edit:

```bash
grep -n "<anchor>" <file>
```

## 5. Parallel Bash

| Call type | Rule |
|---|---|
| Read-only, independent (`git status`, `git diff`, `git log`) | May run in parallel |
| State-mutating (`git commit`, `git push`, `gh pr create`) | Sequence — never parallel |

## 6. Fan-out budgets

Any adversarial/verification fan-out MUST declare, per lens:

| Budget | Value |
|---|---|
| Tool-use cap | ≤15 per lens |
| Short-circuit rule | Stop on high-confidence zero-findings |
| Total token target | Stated explicitly before dispatch |

This bounds the E10 892K-token fan-out class (unbudgeted adversarial fan-outs
that balloon past any single skill's cost profile).

Destructive-idiom substitutions (e.g. `rm -rf` → `trash`) are intentionally
NOT here — their canonical home is the safety-hook BLOCK texts.

## Reference

Full context-management protocol: `.claude/protocols/tool-result-clearing.md`.
Karpathy principles: `.claude/protocols/karpathy-principles.md`.
