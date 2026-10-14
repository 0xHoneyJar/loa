# Karpathy Principles Protocol

> **Version**: 3.0 — this protocol holds the full principle text; `.claude/loa/CLAUDE.loa.md` carries a ~700-byte kernel (four names, the ladder, the never-simplify-away floor, the `loa:shortcut:` marker, `simplicity_intensity`) and points here.
> **Source**: [Andrej Karpathy's LLM Coding Guidelines](https://github.com/forrestchang/andrej-karpathy-skills)

## Enforcement map

| Principle | Mechanism | Where |
|-----------|-----------|-------|
| 1 Think Before Coding | judgment + `AskUserQuestion` (prose-only) | the principle text below |
| 2 Simplicity First | `simplicity_intensity` config + audit-gate floor (C-PROC-011) | `.loa.config.yaml.example` `karpathy_principles:` block (~:2795) |
| 3 Surgical Changes | PostToolUse:Write\|Edit diff-size hook, warn-by-default | `.claude/hooks/quality/karpathy-surgical-diff-check.sh` (`surgical_diff_warning`, `diff_lines_per_task`) |
| 4 Goal-Driven | success-criteria gate at /implement entry | `implementing-tasks/SKILL.md` `<karpathy_goal_driven_gate>` (`require_success_criteria`) |

Trajectory events: `grimoires/loa/a2a/trajectory/karpathy-{date}.jsonl` (schema `.claude/data/trajectory-schemas/karpathy-check.payload.schema.json`).

Config keys: `.loa.config.yaml.example` `karpathy_principles:` — `surface_assumptions`, `simplicity_intensity` (full | ultra; no advise-only level), `surgical_diff_warning`, `diff_lines_per_task` (default 100), `require_success_criteria`, plus v2-reserved keys.

Enforcement history/runbook: `grimoires/loa/runbooks/karpathy-enforcement.md`.

## Principles (full text)

Applies on every code-touching turn, not just `/implement`. The kernel in `CLAUDE.loa.md` is a summary of this section; the floor in principle 2 is never softened.

Adapted from [Andrej Karpathy's LLM coding observations](https://x.com/karpathy/status/2015883857489522876).
Mechanical agent hygiene: `.claude/protocols/agent-ergonomics.md`.

### 1. Think Before Coding

Surface assumptions explicitly. When multiple interpretations exist, present
them rather than choosing silently. When requirements are unclear, ask before
implementing — in interactive sessions via `AskUserQuestion`; in unattended
runs (Run Mode state RUNNING), record the open question and your chosen
interpretation in NOTES.md Decision Log and proceed on the documented
assumption instead of halting to ask.

### 2. Simplicity First

Write the minimum code that solves the request — nothing speculative: no unasked features, no single-use abstractions, no unrequested "flexibility" or "configurability", no error handling for impossible scenarios. If 200 lines could be 50, rewrite simpler. The test: would a senior engineer call this overcomplicated?

Before writing code, walk the ladder — stop at the first rung that holds:
1. Does this need to be built at all? (YAGNI — speculative need: say so and skip)
2. Does the standard library already do it? Use it.
3. Does a native platform feature cover it? Use it.
4. Does an already-installed dependency solve it? Use it. (Never add one for a few lines.)
5. Can it be one line? Make it one line.
6. Only then: write the minimum code that works.

The ladder is a reflex, not a research project — the first lazy solution that
works is the right one.

Two stdlib options the same size? Take the edge-case-correct one — lazy means
less code, not the flimsier algorithm. Deletion over addition, boring over
clever, fewest files, shortest working diff.

Never simplify away: input validation at trust boundaries, error handling that
prevents data loss, security, accessibility, real-hardware calibration, and
anything explicitly requested. Lazy means efficient, not careless (the audit
gate enforces this floor). When the user asks for the full version, build it —
don't re-argue.

**Output discipline**: code first, then at most three lines — what you skipped
and when to add it (`[code] → skipped: X, add when Y`). An explanation longer
than the code is complexity smuggled back as prose; cut it. Reports,
walkthroughs, or per-phase notes the user explicitly asked for are exempt —
give those in full.

**Intensity** (`simplicity_intensity`, default `full`): `full` enforces the
ladder — stdlib and native first, shortest diff. `ultra` is deletion-first —
challenge whether the requirement should shrink before building; ship the
one-liner and question the rest of the requirement in the same response. There
is no advise-only level — the floor above is never softened.

### 3. Surgical Changes

Touch only what the request requires: match existing style (even if you'd do it differently), never "improve" adjacent code, comments, or formatting, don't refactor the unbroken, remove only imports/variables YOUR change orphaned, and leave pre-existing dead code alone (mention it separately). Every changed line traces to the request — "while I'm here" changes go in the PR description, not the diff.

Mark deliberate simplifications in-code so they read as intent, not ignorance:
`// loa:shortcut: <what>`. When the shortcut has a known ceiling, name both the
ceiling and the upgrade trigger — `# loa:shortcut: global lock; per-account
locks if throughput matters`. A marker that names a ceiling with no upgrade
trigger rots silently — don't leave one.

### 4. Goal-Driven Execution

Transform tasks into verifiable goals before starting — "add validation" → "write tests for invalid inputs, then make them pass"; "fix the bug" → "write a failing repro test first, then make it pass"; "refactor X" → "tests green before AND after (behavior preserved)". Multi-step work states the plan + per-step verification up front; vague criteria ("make it robust") become concrete checks ("returns 401 on invalid creds").

Non-trivial logic (a branch, loop, parser, money or security path) MUST leave at
least one runnable check that fails if the logic breaks — satisfied by the
sprint's acceptance-criteria tests. Trivial one-liners need no test (YAGNI
applies to tests too) — but never skip the check on logic that can break.

## Provenance

<!-- provenance: text moved here from CLAUDE.loa.md in cycle-124 (FR-8); v2 gutting cycle-121 (#1074 dual-maintenance); enforcement hooks PRs #960/#961 -->
