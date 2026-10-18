# s4-f3 report: suite v2 swap round 1, refactor-v2-05 … 08 (author F3, Claude Opus 5.5)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s4f3` at `b5cf34cf`. Patch: `~/.cache/loa/cycle-130/patches/s4-f3.patch`, sha256 `94ef7d7d…43eae3`. It has 76 files and +13,562 lines, touches only `tasks/refactor-v2-0{5,6,7,8}/`, and applies cleanly at `b5cf34cf`.

**Headline: all four tasks are fair and proven, but they are too easy, and will very likely fail the a0_bare ≤ 0.5 bar.** I ran blind self-solves with fresh Opus 5.5 subagents. Each saw only TASK.md and a copy of the fixture, with a 10-minute / 45-call box. They scored 1.0, 1.0, 0.975 and 0.975 in about four minutes each. A hardening experiment on task 08 added three rules that force rewrites and eight behaviour classes, and it stayed at 0.975. The lead had an early warning by message.

## Survey
I did not run a seeder. Every task is synthetic, as round 1 was, because the Sprint 259 survey found no clean refactor commit.

## Tasks
Every task has the same shape:
- **The brief.** A tangled Python package with 8–10 modules is rebuilt into a stated layer table with 12–15 modules. The brief states the data model, the error classes, the exports and 24–27 numbered rules. Behaviour must be unchanged for every input.
- **The structural check.** `hidden/structural/<x>_layout_test.py` runs 40 cases, overlaid at `tests/structure/`.
- **The rule cases.** Each rule case checks one rule across the whole package: the layer DAG, import form, top-level imports only, no private imports, `__init__` re-exports only, module, function, complexity, nesting and parameter limits, no module or class state, no global or cache, full annotations, PEP 585/604 annotation forms, exact sorted `__all__`, docstrings, naming, one definition, classes only in `errors`/`model`, raises only package errors, no broad except, output only in `cli`, frozen slotted dataclasses, fixed signatures and exhaustive enum `match`.
- **The conformance cases.** These compare the new layer functions and the exports with a flattened reference, `hidden/structural/_oracle_<x>.py` (dest `tests/structure/`). Inputs are seeded and generated, 400–2,000 per case. Each oracle is the reference's modules concatenated in layer order. I checked each oracle against the base package through the public API with zero diffs.
- **Oracle checks.**

| Task | Scenarios | Functions per scenario |
|---|---|---|
| 05 | 20,000 | 9 |
| 06 | 6,000 | 5 |
| 07 | 20,000 | 8 |
| 08 | 15,000 | 8 |

| id | component | fixture (lines / src modules) | reference (files, +/−) | hidden cases (rule / conformance) | limits: module / fn / complexity / nesting / params |
|---|---|---|---|---|---|
| refactor-v2-05 | semver 2.0.0 + npm ranges (`^ ~ ~> x-ranges hyphen ||`, prerelease rule, bump) | 843 / 9 | 17, +737/−586 | 35 / 5 | 150 / 25 / 8 / 2 / 4 |
| refactor-v2-06 | five-field cron (names, steps, `?`, macros, `L LW L-n nW dL d#n`, Vixie OR/AND rule, 5-year horizon) | 633 / 10 | 21, +643/−454 | 35 / 5 | 120 / 20 / 7 / 2 / 3 |
| refactor-v2-07 | RFC 6901 pointer + RFC 6902 patch (atomic, validate-all-first), diff, explain, pointer list, type counts | 636 / 9 | 21, +632/−407 | 35 / 5 | 110 / 22 / 7 / 2 / 3 |
| refactor-v2-08 | task-manifest scheduler (cycle report, Kahn with priority ties, levels, critical path, slack, list scheduling, dot) | 629 / 8 | 21, +623/−406 | 32 / 8 | 100 / 18 / 8 / 2 / 3, plus no recursion, single exit, no in-place mutation |

## Proofs
Host proofs ran on Python 3.13.5 and Python 3.11.14 (uv) with the same counts. Each run used a fresh copy, the manifest overlay, `patch -p1 --batch --forward`, `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider` and `timeout 300`. No `.orig` or `.rej` files were left.
```
05 [base] tests --ignore=tests/structure => 64 passed | tests/structure => 40 failed
05 [ref]  tests --ignore=tests/structure => 64 passed | tests/structure => 40 passed
06 [base] 39 passed | 39 failed, 1 passed      06 [ref] 39 passed | 40 passed
07 [base] 49 passed | 39 failed, 1 passed      07 [ref] 49 passed | 40 passed
08 [base] 40 passed | 39 failed, 1 passed      08 [ref] 40 passed | 40 passed
```
- **The base passes.** The one base pass in 06, 07 and 08 is the exported-behaviour conformance case, which the base meets by construction. In 05 that case fails at base because the brief renames the error classes.
- **Grader-style runs.** A run in the style of `-I --rootdir <tree> -o addopts=` gave 40/40 for every reference.
- **Suite checks.** The staging-root validator with review-01…04 plus the four tasks gave: `validate-suite: OK — 8 task(s) valid … (partial: type counts not enforced)`. `no-secrets.sh` exited 0 on every fixture. There are no caches, no `hidden` token in TASK.md or the fixtures, and `ast.parse(feature_version=(3, 11))` passes on all 60 `.py` files.

## Self-solve
Each blind subagent saw only the brief and a copy of the fixture under `/tmp/f3-selfsolve/`. I graded its final tree with the fixture tests restored and the hidden check overlaid.

| task | structural | time | calls | missed |
|---|---|---|---|---|
| 05 | 40/40 (1.0) | 4.3 min | 19 | none; it differential-tested 40k inputs against the old code |
| 06 | 40/40 (1.0) | 3.6 min | 9 | none |
| 07 | 39/40 (0.975) | 3.3 min | 8 | the raise rule |
| 08, first version | 39/40 (0.975) | 3.7 min | 14 | nesting |
| 08, hardened (delivered) | 39/40 (0.975) | 3.8 min | 22 | nesting; it did not differential-test, yet all 8 behaviour classes passed |

All five solvers wrote their own AST checkers. The rules they missed were the ones they checked only by reading.

**What I hardened after the self-solve:**
1. Task 08 gained rules 25–27 (no recursion, nested or mutual; single exit; no in-place container mutation). Its behaviour check now covers eight edge classes: parsed fields, parse errors, unknown deps, cycles from a cyclic-graph generator, order and levels, critical path and slack, simulate, and exports. The reference was rewritten functionally, with an iterative DFS that keeps the old cycle order. It shows 0 diffs over 15,000×8 checks against the original oracle. The solver's score did not change.
2. Every brief now lists its exact export set. The base `__init__` files leak helper names (`simulate`, `check`, `compare_versions` and so on), so "keeps every name it exports today" was ambiguous.

## DECISION bullets
- DECISION: synthetic sources, `source.date` 2026-10-17, and `churn` recorded from the reference's numstat.
- DECISION: the oracle is the reference flattened into one file, not a separate implementation. Its fidelity to the spec is proven by zero diffs against the base, which defines the behaviour of a refactor.
- DECISION: conformance compares the class name and message of errors, so the brief's error-class mapping is part of the check.
- DECISION: the reference changes 1,029–1,323 lines (insertions plus deletions), above the 300–800 target. A full re-layering moves every function, and shrinking it would push the fixture below the 600-line floor. Insertions alone are 598–737.
- DECISION: rules are package-wide cases, one per rule, not per module. One module breaking a rule fails it, and the brief says so.
- DECISION: the exhaustive-match rule matches the `match` subject's source text (`kind`, `special.kind`, `op.kind`).
- DECISION: complexity limits are 8 for 05 and 08, because the brief requires exhaustive matches over 7-member enums, and 7 for 06 and 07.
- DECISION: I hardened only 08 with rules 25–27. Rewriting the 05–07 references for an expected gain of about zero, measured on 08, was not justified. 05–07 keep the 24-rule shape.
- DECISION: self-solve ran on blind Agent-tool subagents, not my own attempt, because an author cannot be blind to their own tests. These are in-session subagents, not a model CLI.
- DECISION: the patch stages only the four task directories, read as "your new directories only". The report copy at `grimoires/loa/a2a/sprint-261/reviewer-f3.md` is written but not staged.
- DECISION: `bounds` are `{IMPLEMENT: 80, BARE: 190}` / `{35, 80}` and `suite_version` is 2, as the brief says.

## Limitations
- **Hardness (the main one).** The evidence says a fair refactor at this scale cannot reach ≤ 0.5. Every rule is stated, so the agent writes a checker. The behaviour oracle is the old code in the tree, so it can differential-test, or simply move code. The first misses arrive only on rules it checked by reading. Getting below 0.5 would need more than 80 minutes of work, or semantics with no oracle. The second makes the task a feature build.
- **Proof environment.** Proofs ran on the host only, never in `loa-ablation:258`. Python 3.11.14 was run via uv with the host's pytest 9.0.2.
- **Fixture size.** The fixtures for 06, 07 and 08 sit near the 600-line floor, at 629–636 lines.

## Handoff notes for the fairness reviewer
- **What the oracle encodes.** It encodes the base's behaviour: messages, error order and quirks, listed in each brief's "Unchanged behaviour" paragraph. Spot-check that paragraph against the base code, not against an RFC. Two examples are semver's invalid-version-is-false in `satisfies` and npm-style `-0` ceilings, and cron's Vixie star rule, which treats a starred `*/2` as AND.
- **Possible misreadings.**
  - Rule 8 counts each comprehension `for` and `if`, and a lambda counts toward its enclosing function.
  - Rule 9 treats `else: if` as `elif`, because the AST cannot tell them apart. This is lenient.
  - Rule 11 accepts dotted names, adjacent string literals and `frozenset()`, and rejects f-strings, calls and compiled regexes.
  - Rule 15 makes `__init__.__all__` the sorted `as` names.
  - Rule 17 requires parameters to be snake_case as well as functions.
  - Rule 20 needs the bare imported class name, so `raise errors.X` fails.
  - In 08, rule 25 has two parts (nested self-calls, plus the top-level call graph), and rule 27 matches mutator method names on any object.
  - In 07, `not a JSON value` becomes a `PathError`, which the brief states; the base raises a plain `ValueError` there.
  - In 06, the normalised special-item order follows the `Special` member order, which the brief states.
- **Base-pass case.** The exported-behaviour conformance case passes at base in 06–08. It is a "don't break it" case.
