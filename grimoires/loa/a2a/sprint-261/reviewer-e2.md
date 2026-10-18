# Sprint 261 (cycle-130 Sprint 4) — suite v2 author E2 report

Author: E2 (Claude Opus 5.5). Worktree `/home/merlin/Documents/thj/code/loa-wt-s4e` at `4c279606`, 2026-10-17. Owned: `grimoires/loa/evals/ablation-2.0/tasks/{refactor-v2-01..04,feature-v2-03,feature-v2-04}/`. Nothing else was touched. Each task was authored brief first, then the hidden tests, then the fixture and reference.

## Survey

`bash evals/harness/seed-refactor-tasks.sh --since 2026-06-01 --dry-run --out "$(mktemp -d)"`:

```
seed-refactor: 0 candidate(s), 85 refused, 3 skipped; dry run, nothing written
```

The refusals are commits touching `.claude/`, `grimoires/` or `.loa.config.yaml`. The skips are outside the allowed roots. With no real-history candidate, all six tasks are synthetic.

## Tasks authored

Proofs ran on the host (Python 3.13.5, pytest 9) with `/tmp/e2/prove.sh`. It copies a fresh fixture per side, overlays the manifest at each `dest`, and for the reference applies `patch -p1` after a clean dry run. It runs `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`. Every file also parses with `ast.parse(feature_version=(3, 11))`.

### refactor-v2-01 (refactor, synthetic)
Criterion: one order-line check, configured by keyword, in a module that imports nothing else from the package. The eight listed operations call it directly, and no copy is left.
Hard because the seven copies carry two drifts the suite pins: returns cleans the SKU, and bulk quotes allow 9999. Outside the new module the end state bans the `bool` name, the literals 999/9999 and the message prefixes, so a leftover constant or wrapper fails.
```
[base] tests --ignore=tests/structure => 26 passed | tests/structure => 15 failed
[ref]  tests --ignore=tests/structure => 26 passed | tests/structure => 15 passed
```
Reference: 92 lines (+29/−63) in 5 files. 15 structural cases.

### refactor-v2-02 (refactor, synthetic)
Criterion: parsing, pricing and rendering layers. Each name is defined once and imports go downward only. Pricing re-exports the parsing names as the same objects. Callers take each name from its own layer, and no layer function has more than 15 statements.
Hard because of two upward dependencies at base: parsing checks tax classes against pricing's `TAX_RATES`, and a pricing error uses rendering's `format_money`. Both must be untangled with the messages unchanged. The suite imports parsing names through `invoicer.pricing`, and two long functions must be split.
```
[base] tests --ignore=tests/structure => 21 passed | tests/structure => 12 failed
[ref]  tests --ignore=tests/structure => 21 passed | tests/structure => 12 passed
```
Reference: 341 lines (+190/−151) in 6 files, mostly moved code. 12 structural cases.

### refactor-v2-03 (refactor, synthetic)
Criterion: an explicit `Context`, which checks the settings, is passed first as `ctx` to every public function of six modules. No module or class state, `global`, function cache, `configure`, `set_clock` or `reset` is left, and two desks never interfere.
Hard because the state takes five forms: settings behind an `lru_cache`, a clock cell, a `global` counter, an event list and a dict that is never mutated. The rule covers class bodies too. Independence is checked through `Desk` and through explicit contexts.
```
[base] tests --ignore=tests/structure => 19 passed | tests/structure => 14 failed
[ref]  tests --ignore=tests/structure => 19 passed | tests/structure => 14 passed
```
Reference: 191 lines (+84/−107) in 8 files. 14 structural cases.

### refactor-v2-04 (refactor, synthetic)
Criterion: one six-member Enum, held by every shipment, with words only at the storage boundary and no vocabulary literal anywhere else. The three dispatch functions name every member, have no fallback, and raise `TypeError` for any non-member, including the old string.
Hard because the words sit in about 25 places across seven modules. `Status(value)` raises a different message from the pinned `unknown status: 'lost'`. The `TypeError` on `"pending"` defeats the `str`-mixin with `==` shortcut.
```
[base] tests --ignore=tests/structure => 23 passed | tests/structure => 14 failed
[ref]  tests --ignore=tests/structure => 23 passed | tests/structure => 14 passed
```
Reference: 119 lines (+75/−44) in 8 files. 14 structural cases.

### feature-v2-03 (feature-build, synthetic)
Criterion: a JSON checkpoint keyed by digests, rewritten atomically after each step. Resume reuses the leading matching steps and reruns from the first that does not match. A fresh run deletes the old file, each run reports ran or reused, errors are exact and ordered, and the CLI gains flags.
Hard because the cases sit on stated interactions. A rerun step forces every later step to run, even when a later input digest matches. An edited middle output invalidates only the steps after it. The seven-level error order treats `true` and `"1"` as bad versions and invalid UTF-8 as not JSON.
```
[base] tests => 12 failed, 16 passed | tests/acceptance => 12 failed | --ignore=tests/acceptance => 16 passed
[ref]  tests => 28 passed            | tests/acceptance => 12 passed | --ignore=tests/acceptance => 16 passed
```
Reference: 141 lines (+133/−8) in 4 files. 12 hidden cases.

### feature-v2-04 (feature-build, synthetic)
Criterion: deny rules, wildcards for principal, action and path, and an overrides source that wins whenever it matches. Then the most specific pattern, then deny over allow, then deny by default. Explain names the first deciding rule, the CLI gains overrides and explain, and rule errors are exact and ordered.
Hard because the three-part specificity order interacts with the rest. A `**` matches zero segments, a `**` is not a `*` segment, and principal and action never count. Overrides beat a more specific policy rule, and ties resolve by deny, then file order.
```
[base] tests => 13 failed, 21 passed | tests/acceptance => 13 failed | --ignore=tests/acceptance => 21 passed
[ref]  tests => 34 passed            | tests/acceptance => 13 passed | --ignore=tests/acceptance => 21 passed
```
Reference: 119 lines (+99/−20) in 4 files. 13 hidden cases.

### Checks (all six)
- `no-secrets.sh` exits 0 on every fixture.
- There are no caches, `.tmp` or binary files.
- Fixtures are 52–60 KB with 161–262 source lines in 5–8 modules.
- `grep -ril hidden` outside `hidden/` hits only the grader-facing `task.yaml` fields, as in v1. TASK.md and `criterion` are clean.
- `grader_protected` lists `tests/conftest.py` and the one fixture test file.
- Reference patches have no header timestamps, matching v1. They apply with the grader's exact `patch -p1 --batch --forward --no-backup-if-mismatch -s` with exit 0, no output and no `.orig` or `.rej` files.

## validate-suite (staging root: review-01…04 plus the six tasks and the README)

```
validate-suite.sh --root "$S" --allow-partial
  -> 6 violation(s) over 10 task(s), each "schema: suite_version 2 differs from the suite file's 1"
validate-suite.sh --root "$S" --allow-partial --suite-file <copy with suite_version: 2>   (staged review copies at 2)
  -> validate-suite: OK — 10 task(s) valid (partial: type counts not enforced)
```

## Decisions

- DECISION: Survey: the refactor seeder found 0 candidates since 2026-06-01 (85 refused, 3 skipped). All six tasks are synthetic with `source.date: "2026-10-17"`.
- DECISION: refactor-v2-01 uses smell 1, duplicated validation: seven copies in four modules and eight callers. The two pinned drifts become the keyword-only `normalise` and `max_qty`. "No copy left" means no regex compile or match call, no `bool`, no 999/9999 and no message prefix outside the module.
- DECISION: refactor-v2-02 uses an equivalent of smell 2. The god module is `invoicer.pricing`, which stays as the middle layer while parsing and rendering move out, instead of being emptied into a re-export. The function limit is 15 statements counted at every depth.
- DECISION: refactor-v2-02's reference is 341 changed lines, above the 80–200 target. A module split counts each moved line twice: about 260 lines are moved, and the net logic change is about 80. Since the size is a target and not a criterion, I kept the module at a realistic size.
- DECISION: refactor-v2-03 uses smell 3 with five forms of state over six modules plus the `Desk` facade. Module and class assignments allow only constants, names, and tuples or `frozenset` of them, with `dataclasses.field(...)` also allowed in class bodies. `functools.cache` and `lru_cache` are banned.
- DECISION: refactor-v2-04 uses smell 4 over seven modules with three dispatch functions. Exhaustive means every member named as `Status.<NAME>` in the body, no `else:` and no wildcard `case`, plus the stated `TypeError(f"not a Status: {status!r}")`.
- DECISION: refactor-v2-03 and refactor-v2-04 touch 8 files, above the 3–6 target. The brief's smells span five or more modules, and the new module plus the facade or `model` adds to that.
- DECISION: refactor-v2-04's fixture has 196 source lines, under the brief's 200 but inside the common 150–600. I did not pad it.
- DECISION: feature-v2-03 uses suggestion 3. A conflict is an error: more entries than steps, or a name mismatch at any position, raises `CheckpointError` before any step runs. A fresh run deletes the old checkpoint before step 1, and once a step runs every later step runs.
- DECISION: feature-v2-04 uses suggestion 4. Overrides are a second rule file with the same grammar, not per-resource blocks. Precedence runs overrides, then specificity (literal segments, then no `**`, then fewer `*`), then deny over allow, then deny by default. The deciding rule is the first in file order.
- DECISION: every task sets `suite_version: 2` as the common rules require. The suite file still says 1, so the unmodified validator flags exactly that. I did not edit the suite file, which is not mine, and validated again with a version-2 copy.
- DECISION: the `success_criterion` counts include parametrized cases. Every case is red at base.

## Could not do / limitations

- Nothing ran inside `loa-ablation:258`, because docker is off-limits. Python 3.11 compatibility is checked only syntactically.
- The hardness is uncalibrated. Whether a0_bare scores at most 0.5 on a task is known only after the calibration smoke.

## Handoff notes for the lead

- Have the fairness reviewer trace each assertion to a TASK.md sentence, starting with these:
- **refactor-v2-02:** the callers rule forbids reading parsing or rendering names through `pricing`. Pricing must import parsing because the brief requires the re-exports.
- **refactor-v2-03:** the class-body clause, and the rule that a never-mutated module dict still counts as state (`DEFAULT_SLA_HOURS`).
- **refactor-v2-04:** the `TypeError` for `"pending"`. A `str`-mixin Enum compared with `is` still passes.
- **feature-v2-03:** the order of the error messages, and the rule that a fresh run deletes the file first.
- **feature-v2-04:** the tie cases, which come from the deciding-rule sentence.
- Rerun `ablation-grade.sh --self-check base` and `--self-check reference` per id in the image.
- Scratch trees and scripts live under `/tmp/e2/` and are not part of the patch.
