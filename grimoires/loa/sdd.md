# Software Design Document: Loa Friction Floor (cycle-125)

**Version:** 1.0
**Date:** 2026-09-23
**Author:** Architect Agent (unattended run)
**Status:** Draft
**PRD:** `grimoires/loa/prd.md` (cycle-125, FR-1…FR-5)

---

## Table of Contents

1. [Project Architecture](#1-project-architecture)
2. [Software Stack](#2-software-stack)
3. [Database Design](#3-database-design)
4. [UI Design](#4-ui-design)
5. [API Specifications](#5-api-specifications)
6. [Error Handling Strategy](#6-error-handling-strategy)
7. [Testing Strategy](#7-testing-strategy)
8. [Development Phases](#8-development-phases)
9. [Known Risks and Mitigation](#9-known-risks-and-mitigation)
10. [Open Questions](#10-open-questions)
11. [Appendix](#11-appendix)

---

## 1. Project Architecture

### 1.1 Principle

Every change in this cycle narrows an existing mechanism's false positives or widens an existing signal's reach; none introduces a new subsystem. Five components are touched, each already in the tree:

```
 PreToolUse fence ──► block-destructive-bash.sh   (FR-1: classification precision)
 State artefacts  ──► notes-guard.sh              (FR-2: heading-addressed reader for prd/sdd/sprint/NOTES)
 Run mode         ──► run-preflight.sh (new) + run-mode resources + workflow-state.sh (FR-3)
 Provider health  ──► loa-status.sh + loa_cheval.routing.circuit_breaker + cheval CLI (FR-4)
 Cost             ──► loa_cheval.metering.pricing/ledger + headless adapters + cost-report.sh (FR-5)
```

Cross-cutting: the prompt byte budget (`tools/check-prompt-budget.sh`) gates every skill edit; the fence corpus is a regression floor; the a2a record goes to `record/cycle-125-a2a`.

### 1.2 FR-1 — Fence precision (`.claude/hooks/safety/block-destructive-bash.sh`)

The hook is a carrier grammar over the raw command text: it scrubs known-safe carriers (`git`/`gh`/`br` argument text, a complete quoted `cat` heredoc — `_bdb_scrub_cat_heredoc`, lines 296–340), splits into lines, and runs rule groups with pre-filters (`:378–500`). Four rule groups misfire; each gets a precise, tested narrowing.

**D-1.1 `rm -rf` operand classes** (ladder at `:1070–1087`, `:1221–1240`). `_re_allow_list` already admits `./<visible>`, `dist`, `build`, `target`, `.next`, `out`, `coverage`, `node_modules`, `/tmp/…`. The catastrophic list (`_re_block_list`, `:1071`) and `_re_allow_exclude` (`:1086`, which already refuses every `./.name`) are evaluated first and are untouched. Four additions, none of which admits an arbitrary project directory (Flatline SKP-002: `rm -rf src` stays AMBIGUOUS; `./src/` remains the explicit spelling):
- *Cache vocabulary by last segment at any relative depth*: an operand with no leading `/`, `~`, `$`, `-`, no glob or `..` segment, whose last segment is one of `dist build out coverage target node_modules tmp temp __pycache__ .next .turbo .terraform .venv venv .tox .nox .pytest_cache .mypy_cache .ruff_cache .parcel-cache` or ends in `.egg-info` — covers `deploy/aws/x/.terraform`, `packages/web/dist`.
- *Scratch working directory*: Claude Code runs hooks in the project root, so the cwd signal is textual: the last `cd <dir>` in the command text before the rm segment (same statement chain) names the working directory. When that `<dir>` is a temp root (`/tmp/…`, `/var/tmp/…`, `/private/tmp/…`, `$(mktemp -d …)`, or the hook's real `$TMPDIR`), or when the hook's own `$PWD` is under a temp root, a bare relative visible name (`hda-sync`, `ajv-test`) is allowed — the whole cwd is scratch. Outside a scratch cwd the class does not apply.
- *Temp roots*: `/tmp/.+` (exists), `/var/tmp/.+`, `/private/tmp/.+`; `\$\{?TMPDIR\}?/.+` only when the hook's `$TMPDIR` is set, resolves under one of those roots, and the command text does not assign `TMPDIR` itself (Flatline SKP-004: classify the value, not the text); a bare `$TMPDIR` without a suffix stays blocked.
- *Bound variables*: an operand that is exactly `"$NAME"`, `$NAME`, `${NAME}` (optionally with a `/suffix` free of `..`) is allowed only when the command assigns `NAME` exactly once and the assigned value is itself allowed — a whole, plain `$(mktemp -d [-p dir])` substitution (no `;`, `|`, `&`, redirect or trailing path inside or after it) or a literal that passes this same ladder (`S=/tmp/claude-1000/x/scratchpad; rm -rf "$S/repro"`). The binding is trusted only when the command has no other way to rebind the name: any `eval`, `read`, `readarray`, `mapfile`, `declare`, `typeset`, `local`, `unset`, `source`, `printf -v`, `for NAME in` or `${NAME:=…}` anywhere voids it, as does a second `NAME=` (Flatline SKP-002/SKP-003: a textual check is only a proof when the text contains no rebinding vocabulary). Residual: shell aliases and functions defined outside the command are invisible to any text fence, today as before.
- *Reach check (Flatline SKP-001)*: the scratch-cwd class adds no reach beyond what the pre-existing `/tmp/.+` allowance already granted — `cd /tmp/x && rm -rf name` deletes `/tmp/x/name`, which `rm -rf /tmp/x/name` already passed; symlinks or checkouts under a temp root were and remain the operator's choice of location. The cache-vocabulary class extends the pre-existing top-level `dist|build|target|coverage|out|node_modules` allowance to any relative depth; a source-controlled directory that happens to carry one of those names is recoverable from git, which is why the original allowance existed (Flatline SKP-002, accepted and recorded in the risk table).
- *Read-only search patterns* (found while building the corpus: the fence blocked `grep -n "rm -rf dist" file`): the quoted pattern argument of `grep`/`egrep`/`fgrep`/`rg`/`ag`/`ack` (first quoted argument after the flags) and of `sed -n '/…/p'` is scrubbed to a space before matching, in the `_bdb_scrub` style. A quoted pattern never executes, so unlike the withdrawn remote-payload scrub this removes no protection.

**D-1.2 Remote payloads — no change.** The proposed scrub of quoted `ssh` / `docker exec` / `kubectl exec` payloads is withdrawn (Flatline SKP-001, both voices): the text fence blocks `ssh host 'rm -rf /'` today and that protection stays. The residual false positives from remote payloads (a minority of the FR-2-AMBIGUOUS hits) are accepted and noted in the hook header.

**D-1.3 Sink-aware SQL rules** (P8/P9/P10, `:690–760`). The three rules gain one shared precondition: the command must contain a SQL runner token — `psql`, `pgcli`, `mysql`, `mariadb`, `sqlite3`, `sqlcmd`, `duckdb`, `clickhouse-client`, `bq query`, `prisma db execute`, `supabase db`, `wrangler d1 execute`, `drizzle-kit`, `--command`, `-c ` following one of those, or a heredoc piped into one of them. Without a runner token the keyword is text (a test file, feedback markdown, a commit body) and the rules are skipped; with one, matching is unchanged. Residual documented: SQL executed through a language driver (`node -e`, `python -c`) is not matched today either (accepted, unchanged).

**D-1.4 `git branch -D` when merged** (P5, `:583–593`). The hook stays offline (Flatline SKP-005: it runs under the fail-open `hook-guard.sh`, so every added millisecond is a safety property): before emitting FR-1.1 it evaluates only `git merge-base --is-ancestor <name> <base>` for `base` in `origin/main`, `main`, `origin/master`, `master` (true merges; one local git call, no network). Squash-merged branches are handled by the new sanctioned helper `.claude/scripts/git-branch-prune.sh [--dry-run] [--base <ref>]`, which lists local branches whose upstream is gone or whose head has a merged PR (`timeout 5 gh pr list --state merged --head <name>`; `LOA_FENCE_NO_NETWORK=1` disables the probe) and deletes them with `git branch -D` through its own audited path (the hook recognises the helper's invocation shape, `git-branch-prune.sh`, not a bypass token). The FR-1.1 message names the helper. Any predicate failure → block as today.

**D-1.5 `git checkout -- <path>` / `git restore <path>` for generated files** (P7, `:660–668`). Allow when every path operand is generated: `git check-attr linguist-generated -- <path>` reports `set`/`true`, or the path matches `(^|/)(dist|build|coverage|_generated|__generated__|generated)(/|$)` or ends with `.lock`, `-lock.json`, `-lock.yaml`. Any other operand keeps the block.

**D-1.6 Corpus.** `tests/fixtures/fence-corpus/corpus.jsonl`: `{ "id", "cmd", "expect": "allow"|"block", "rule", "why", "cwd": "repo"|"tmp" }` — ≥ 40 benign rows drawn from the attributed samples (`<path>` placeholders resolved to neutral relative paths) and ≥ 15 dangerous rows, at least one dangerous twin per relaxation (`rm -rf src`, `rm -rf ./.git/`, `rm -rf ~/dist`, `rm -rf ../dist`, `rm -rf "$HOME"`, `TMPDIR=/ … rm -rf "$TMPDIR/x"`, `T=$(mktemp -d); T=/; rm -rf "$T"`, `ssh host 'rm -rf /'`, `psql -c 'DROP TABLE users'`, `git branch -D unmerged-branch` on a fixture repo, `git checkout -- src/app.ts`). Sanitisation is reproducible (Flatline SKP-004): a corpus lint in the same bats file fails on any row containing `://`, an IPv4 shape, `@`, `sk-`/`AKIA`/`ghp_` key shapes, `s3://`, or a hostname-like `\.(com|io|net|fm)\b`. `tests/unit/block-destructive-bash.bats` gains one data-driven test that pipes each row through the hook as a Claude Code PreToolUse payload (with `cwd` mapped to a repo fixture or a tmp dir and `TMPDIR` set per row) and asserts the expectation; the summary line prints the benign pass rate (gate ≥ 80 %) and the dangerous block rate (gate 100 %); a companion case times the corpus run before and after (≤ 1.5×).

### 1.3 FR-2 — Sectioned planning artefacts (`.claude/scripts/notes-guard.sh`)

`notes-guard.sh` already indexes `## ` blocks with dates and kinds (`index_blocks`, `:82–101`), selects ranges (`select_ranges`), emits them under `READ_CAP` with a footer (`cmd_read`, `:124–148`). Generalise without a second reader:

- `read --file <path> --section <spec>`: `<spec>` is either `Sprint N` (matches `^## Sprint N\b`, the sprint-plan heading grammar used by `sprint-plan-mode.md`'s discovery `grep -E "^## Sprint [0-9]+:"`), a numbered SDD section (`^## N\. `), or a case-insensitive substring of an H2 heading (first match). Output: that block through the line before the next `## `, budgeted by `READ_CAP` with the existing footer. No match → a loud one-line `NOTES-GUARD: no section matching '<spec>' in <file>; headings: …` and exit 0 with the `--index` listing (never empty).
- `read --file <path> --index`: one line per H2 — `L<start>-L<end>  <bytes>B  <heading>` — so an agent can choose offsets without a blind `Read`.
- The NOTES-specific default (`## Blockers` + newest `## Session Continuity` + 3 newest `## Decision Log`) stays the behaviour when neither `--section` nor `--index` is given and the file is `NOTES.md`; for any other file the default is `--index`.
- `check --file <path>` already works for any file; `loa-status.sh` (new "Artefacts" line) runs it for `prd.md`, `sdd.md`, `sprint.md`, `NOTES.md` and prints `warn` at ≥ 100 KiB.

**Skill routing (budget-neutral).** The shared include `.claude/data/skill-includes/context_discipline.md` gains one sentence (≤ 100 B): "Big artefacts: `notes-guard.sh read --file <prd|sdd|sprint|NOTES> --section <H>` / `--index` before a blind Read." Regenerating the include grows every skill by the same bytes; the three skills within 80 B of the cap (`implementing-tasks` 16,358 B, `reviewing-code` 16,334 B, `auditing-security` 16,308 B) receive compensating trims of ≥ 120 B each (shorten the Fast-Gate Parity and Documentation Verification sentences; no rule removed). `implementing-tasks` additionally replaces its primary "read `grimoires/loa/sprint.md`" instruction with the `--section 'Sprint N'` form (net ≤ +40 B, covered by the trim). `tools/check-prompt-budget.sh` is the gate; `tests/unit/prompt-audit-keeplist.bats` protects the keep-listed strings.

**Rotation on upgrade.** `update-loa.sh main()` (`:531`) gains a post-refresh step: `notes-guard.sh check --file "$grimoire/NOTES.md"`; exit 3 → `notes-guard.sh rotate --file …` and a log line; the rotate is never silent. `mount-submodule.sh` is unchanged (a fresh mount has an empty NOTES).

### 1.4 FR-3 — Run preflight, task checkpoints, resume surfacing

**D-3.1 `run-preflight.sh` (new).** One script that composes the existing checks into a checklist with `--json` and an `--unattended` strictness flag; exit 1 on any failed predicate. Predicates:

| id | Predicate | Source | Unattended rule |
|----|-----------|--------|-----------------|
| P1 | effective `permissions.defaultMode` | `.claude/settings.local.json` > `.claude/settings.json` > `~/.claude/settings.json` (Claude Code precedence) | passes on `bypassPermissions`, or on `acceptEdits`/`default` when P2 confirms the run's allow rules are present (Flatline SKP-012: bypass is not required, prompt-free coverage is); `plan` fails; `auto` fails with the observed symptom ("prompts unavailable → auto-denied"). The checklist names the trade-off: an unattended run cannot answer prompts, so the fences are the guard |
| P2 | tool allow rules | `check-permissions.sh --quiet` (existing step 4 of the run pre-flight) | pass-through |
| P3 | voices | for each stage in `flatline_protocol.{code_review,security_audit}`: model + `fallback_chain` → provider credential env var present *or* CLI hop binary on PATH (`claude`, `codex`, `agy`) | fail only if a required stage has **no** usable voice; else warn per missing voice |
| P4 | breakers | `.run/circuit-breaker-*.json` state via `loa_cheval.routing.circuit_breaker.list_buckets` | OPEN for the only usable voice of a stage → fail; otherwise warn with age |
| P5 | NOTES size | `notes-guard.sh check` | exit 3 → fail (rotate hint) |
| P6 | run state | `.run/state.json` / `.run/sprint-plan-state.json` / `.run/simstim-state.json` | `RUNNING`/`INTERRUPTED` older than 12 h → fail with the resume command; `HALTED` → fail with `/run-resume` |
| P7 | beads | `beads-health.sh --quick --json` | pass-through (existing step 2) |
| P8 | branch | `run-mode-ice.sh validate` | pass-through (existing step 3) |

Wiring: the run-mode SKILL "Pre-flight Checks" list (`SKILL.md:65–86`) collapses steps 2–5 into "run `.claude/scripts/run-preflight.sh --unattended`; nonzero → HALT with its checklist" (net negative bytes; the script owns the detail). `run-sprint-plan` and `run-bridge` reference the same line.

**D-3.2 Task checkpoints.** Beads are the task ledger: `/implement sprint-N` claims and closes one bead per task, and re-entry skips closed beads (this is verified by a fixture in Sprint 3; if it does not hold, the gap is fixed in `implementing-tasks` resources). Run mode mirrors it into state for visibility: `sprint-plan-state.json` gains `checkpoint: {sprint, task, phase, ts}` updated after each task close and each phase change. Write discipline (Flatline SKP-010): every write goes through `jq … > "$f.tmp.$$" && mv -f "$f.tmp.$$" "$f"` under `flock` on `$f.lock` (the same idiom `archive_cycle_in_ledger` uses), the schema block gains `schema_version: 2` (readers accept 1 and 2; a missing `checkpoint` reads as "sprint granularity"), and a checkpoint that does not parse or names a bead that is not closed is discarded in favour of the beads truth with a logged line — beads remain the recovery source, the checkpoint is a hint. `run-resume` reports the checkpoint and re-enters the sprint; `/implement` resumes at the first open bead.

**D-3.3 Surfacing.** `workflow-state.sh get_suggested_command` returns `/run-resume` when any run/simstim state is `HALTED`/`INTERRUPTED`, or `RUNNING` with `last_activity` older than 12 h; `loa-status.sh` prints `Run: <state> (<age>) → <command>`; a new SessionStart line in `loa-kf-surface.sh`'s sibling `loa-run-state-surface.sh` (one line, only when a resumable state exists) is added to `.claude/settings.json` and `.claude/hooks/settings.hooks.json` behind `hook-guard.sh`. `session-limit-capture.sh` output (`.run/session-limit-state.json`) feeds the same line when `reset_at_epoch` has passed ("session limit reset — resume available").

### 1.5 FR-4 — Provider health

- **Status.** `loa-status.sh` gains a "Providers" block: for each provider present in the catalog or config: breaker per auth type from `python3 -m loa_cheval.routing.circuit_breaker --list` (thin CLI over `list_buckets`, `:682`) with state and age since `opened_at`; credential present = env var set (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_API_KEY`/`GEMINI_API_KEY`) shown as `present`/`absent`, never the value; CLI hop = `command -v claude|codex|agy`. `--json` mirrors it.
- **Re-route.** `retry.py:149` consults `check_state` before each call; an OPEN bucket raises `ProviderUnavailableError`, which is walk-eligible in `cheval.py`'s chain (`:90–102`). Sprint 4 pins this with a test: breaker fixture OPEN for `anthropic/http_api` → invoking the `opus` alias walks to the configured `claude-headless` entry (dry-run trace). The status line then reads `anthropic http: OPEN 3d (walking to claude-headless)`.
- **Expiry and reset.** `check_state` already moves OPEN → HALF_OPEN after `reset_timeout_seconds` (`circuit_breaker.py:536–553`); the status line prints `probe due in …`. New CLI: `cheval --reset-breaker <provider>[:<auth_type>]` → `_write_state(_default_state(...))` plus `_emit_journal_marker(reason="operator reset")`.
- **Seeding.** New `.claude/templates/known-failures.md.template` (the header, INDEX skeleton and entry grammar of `grimoires/loa/known-failures.md`); `init_state_zone` in `mount-submodule.sh` (`:1121`) and the equivalent block in `mount-loa.sh` create `grimoires/loa/known-failures.md` from it when missing; `check-loa.sh` warns when absent.

### 1.6 FR-5 — Cost accounting

- **Resolution ladder in `find_pricing`** (`pricing.py:219–247`): exact `providers.<p>.models.<m>` → `<m>` with a trailing `-YYYY-MM-DD` stripped → alias resolution through the loaded config's alias tables (`aliases`, `backward_compat_aliases`) to `provider:model` → hop names (`codex-headless`, `claude-headless`, `agy-headless`, `cursor-headless`) resolve through the hop's configured underlying model. Result carries `pricing_source: config` with a new additive `pricing_resolution: exact|dated|alias|hop` field on the row.
- **Adapters record the resolved id.** The headless adapters (`codex_headless_adapter.py:410` and siblings) already prefer `actual_model` from the CLI event; when absent they now pass the alias-resolved catalog id instead of the requested alias, and record the hop in the additive `transport` field. `create_ledger_entry` (`ledger.py:106–180`) accepts `resolved_model` and `transport`.
- **Estimates.** When a CLI hop reports no usage and cheval counted tokens itself (`usage_source != "actual"`), the row is priced from those counts and marked `cost_estimated: true`.
- **Report.** `cost-report.sh`: `--include-legacy` reads `grimoires/loa/a2a/cost-ledger.jsonl` in addition; `--migrate-legacy` appends legacy rows (tagged `legacy: true`) to the current ledger through the resolver-validated writer and writes `.run/cost-ledger-migration-<ts>.json` as the receipt; a new line "Unpriced rows: N (S %)" and JSON `unpriced_rows`/`unpriced_share`.
- **Enforcer.** `cost-budget-enforcer` reads `cost-report.sh --json` totals and `unpriced_share`; it never certifies "under budget" while the unpriced share exceeds 5 % — unknown spend is reported as unknown, not as zero (Flatline SKP-019). Dated-id resolution is recorded per row as `pricing_resolution: dated`; an operator who knows a dated release is priced differently adds an exact catalog entry, which always wins (Flatline SKP-018).

> Sources: prd.md FR-1…FR-5; .claude/hooks/safety/block-destructive-bash.sh:296-340,378-500,583-593,660-668,690-760,1070-1087,1221-1240; .claude/scripts/notes-guard.sh:82-148; .claude/skills/run-mode/SKILL.md:65-86; .claude/skills/run-mode/resources/state-schemas.md:75-97; .claude/adapters/loa_cheval/providers/retry.py:140-160; .claude/adapters/loa_cheval/routing/circuit_breaker.py:82-107,527-553,682; .claude/adapters/loa_cheval/metering/pricing.py:219-247; .claude/adapters/loa_cheval/metering/ledger.py:106-180; .claude/adapters/loa_cheval/providers/codex_headless_adapter.py:386-410; .claude/scripts/mount-submodule.sh:1121-1154; .claude/scripts/update-loa.sh:531

---

## 2. Software Stack

| Layer | Technology | Notes |
|---|---|---|
| Hooks and scripts | bash 5 (`set -euo pipefail`, `LC_ALL=C`), jq 1.7, awk | no new runtime dependency; `gh` optional (D-1.4), `timeout` from coreutils |
| Adapter substrate | Python 3.11+ (`loa_cheval`), stdlib only | pricing/ledger/breaker changes stay in existing modules |
| Tests | bats-core via `npx --no-install bats`, pytest for `loa_cheval` | ledger isolation env in every harness (KF-033) |
| Prompt surface | SKILL.md / skill-includes / resources | budgets enforced by `tools/check-prompt-budget.sh` |
| Records | git branch `record/cycle-125-a2a` | Template Protection keeps sprint records off `main` |

> Sources: .claude/scripts/notes-guard.sh:1-5; .claude/adapters/loa_cheval/metering/ledger.py:1-30; tools/check-prompt-budget.sh:53

---

## 3. Database Design

No database. The persistent structures touched are JSON/JSONL files under `.run/` and markdown under `grimoires/loa/`. Additive fields only:

| File | Field(s) added | Semantics |
|---|---|---|
| `.run/sprint-plan-state.json` | `checkpoint: {sprint, task, phase, ts}` | last completed unit; informational for `/loa` and `run-resume` |
| `.run/cost-ledger.jsonl` rows | `pricing_resolution`, `transport`, `cost_estimated`, `legacy` | resolution path, hop name, estimate flag, migrated-row marker |
| `.run/cost-ledger-migration-<ts>.json` | receipt: source path, rows, bytes, sha256 before/after | written by `--migrate-legacy` |
| `.run/audit.jsonl` | existing `action: block` rows keep `pattern_id`; allow decisions from the new classes are not journaled (unchanged posture) | |
| `grimoires/loa/known-failures.md` | seeded from the template on mount | append-only ledger grammar unchanged |
| `tests/fixtures/fence-corpus/corpus.jsonl` | `{id, cmd, expect, rule, why}` | regression floor |

Schema documentation: `resources/state-schemas.md` (run mode) and `.claude/data/trajectory-schemas/` are unchanged except the checkpoint block; the cost-ledger row schema in `loa_cheval` docs lists the four new optional keys.

> Sources: .claude/skills/run-mode/resources/state-schemas.md:75-97; .claude/adapters/loa_cheval/metering/ledger.py:151-180

---

## 4. UI Design

Terminal text only.

- **Fence messages** keep the `BLOCKED [id]: …` grammar; relaxed classes emit nothing. FR-1.1's message names `git-branch-prune.sh`; FR-1.3's names the generated-path rule.
- **`notes-guard.sh read --index`**: `L12-L88   4,210B  ## Sprint 1: Fence precision`.
- **Preflight checklist** (also `--json`):
  ```
  run-preflight: unattended
   ✓ P1 permission mode: bypassPermissions (.claude/settings.local.json)
   ✗ P3 voices: security_audit has no usable voice — set OPENAI_API_KEY or install `codex`
   ⚠ P4 breaker: anthropic/http_api OPEN 3d (walking to claude-headless)
  result: FAIL (1 failed, 1 warning) — fix the ✗ lines and re-run
  ```
- **`/loa` additions**: `Run: HALTED 2d ago → /run-resume`; `Artefacts: prd 101K (warn) · sdd 69K · sprint 42K · NOTES 56K`; `Providers: anthropic http OPEN 3d, headless ok, key absent, hop claude ok · openai ok · google http ok, hop agy absent`.
- **Cost report**: existing markdown plus `Unpriced rows: 12 (3 %)` and a `Legacy ledger included` line when requested.

> Sources: .claude/scripts/loa-status.sh:554-700; .claude/scripts/notes-guard.sh:138-140

---

## 5. API Specifications

Command-line contracts (all additive; existing invocations unchanged):

| Command | New surface | Exit codes |
|---|---|---|
| `block-destructive-bash.sh` (hook) | env `LOA_FENCE_NO_NETWORK=1` disables the `gh` merged-PR probe in D-1.4 | 0 allow, 2 block (unchanged) |
| `git-branch-prune.sh [--dry-run] [--base <ref>]` | lists/deletes local branches that are merged (ancestor or merged PR) or whose upstream is gone | 0 ok, 1 nothing to do, 2 usage |
| `notes-guard.sh read --file F [--section S | --index | --full]` | section/heading addressing for any markdown artefact | 0 (never empty), 2 usage |
| `run-preflight.sh [--unattended] [--json] [--stage code_review,security_audit]` | checklist of P1–P8 | 0 pass, 1 fail, 2 usage |
| `workflow-state.sh --json` | `suggested_command` may be `/run-resume`; new `run_state: {file, state, age_h}` | unchanged |
| `loa-status.sh [--json]` | `run`, `artefacts`, `providers` objects | unchanged |
| `python3 -m loa_cheval.routing.circuit_breaker --list [--json]` | bucket listing for scripts | 0 |
| `cheval --reset-breaker <provider>[:<auth_type>]` | resets a bucket, journals the reset | 0, `INVALID_INPUT` on unknown provider |
| `cost-report.sh [--include-legacy] [--migrate-legacy] [--json]` | legacy path handling, unpriced share | 0, 2 on resolver refusal (unchanged) |
| Ledger row | optional `pricing_resolution`, `transport`, `cost_estimated`, `legacy` | — |
| Hook payload for the corpus test | Claude Code PreToolUse JSON on stdin `{"tool_name":"Bash","tool_input":{"command":…}}` | as hook |

> Sources: .claude/hooks/safety/block-destructive-bash.sh:432-470 (emit_block, exit 2); .claude/scripts/notes-guard.sh:37-58 (usage); .claude/adapters/cheval.py:2620-2645 (CLI flags)

---

## 6. Error Handling Strategy

- **Fail closed where a wrong "allow" is destructive**: every D-1.x relaxation applies only when its predicate is positively established; any error in the predicate (missing `gh`, timeout, unreadable attribute) falls back to the current block. `LOA_FENCE_NO_NETWORK=1` skips the network probe rather than guessing.
- **Fail loud where silence hides state**: the preflight prints every predicate with its result; a predicate that cannot be evaluated reports `?` and counts as a failure in `--unattended`.
- **Never empty**: the artefact reader always prints either the block, or the index with a one-line reason.
- **Cost**: an unresolvable id stays `pricing_source: unknown`, cost 0, and is counted, never estimated from a guessed price; `--migrate-legacy` refuses if the receipt cannot be written first.
- **Breaker reset** journals before writing; an unknown provider/auth type is `INVALID_INPUT` (exit 2) with the list of known buckets.
- **Rotation on upgrade** logs the archive path; a rotate failure (exit 4, target exists) is reported and the update continues (the block line still protects the file).

> Sources: .claude/hooks/safety/block-destructive-bash.sh:432-470; .claude/scripts/notes-guard.sh:150-178; .claude/adapters/loa_cheval/routing/circuit_breaker.py:203-260

---

## 7. Testing Strategy

| Area | Tests (all test-first) |
|---|---|
| FR-1 | `tests/unit/block-destructive-bash.bats`: corpus-driven case (benign ≥ 80 %, dangerous 100 %) + one named case per D-1.x relaxation and its dangerous twin; `tests/unit/git-branch-prune.bats` with a fixture repo (merged branch, squash-merged branch via a stub `gh`, unmerged branch); runtime measured before/after on the corpus (`time`), asserted within 1.5× |
| FR-2 | `tests/unit/notes-guard.bats` (+ `--section`, `--index`, non-NOTES default, no-match path); a case reading this repo's `prd.md`/`sdd.md` by section under 25k tokens (byte proxy ≤ 100 KiB); `tests/unit/update-loa-*.bats` rotation case with a generated ≥ 200 KiB NOTES fixture; `tools/check-prompt-budget.sh` and `prompt-audit-keeplist.bats` green |
| FR-3 | `tests/unit/run-preflight.bats`: one passing and one failing fixture per predicate (settings fixtures in a tmp `HOME`/project); `tests/unit/workflow-state.bats` resume suggestion cases; an integration fixture proving `/implement` re-entry skips closed beads (or the fix that makes it so); hook-wiring test for the SessionStart line (`tests/unit/hook-wiring.bats`) |
| FR-4 | pytest: breaker `--list`, reset, expiry; chain walk on OPEN (dry-run trace) ; bats: `loa-status.bats` provider snapshot with fixture buckets and env; mount tests assert the seeded `known-failures.md` |
| FR-5 | pytest: `find_pricing` ladder over the fleet's ids (`gpt-5.2-2025-12-11`, `gpt-5.5-2026-04-23`, `gemini-2.5-pro`, `codex-headless`, `claude-fable-5-1`) and unknown ids; adapter tests pin resolved-id recording per hop; bats: `cost-report.bats` legacy include/migrate/receipt/unpriced share; ledger isolation (`LOA_COST_LEDGER_PATH`) in every case |
| Cross-cutting | `repo-map-gen.sh --validate`, checksum regen, `lint-invariants.sh`, full `tests/unit/` before each sprint close (known host reds: KF-034 publication suite under forced tag signing) |

> Sources: tests/unit/block-destructive-bash.bats; tests/unit/notes-guard.bats; tests/unit/hook-wiring.bats; grimoires/loa/known-failures.md KF-033, KF-034

---

## 8. Development Phases

| Sprint | Scope | Exit criteria |
|---|---|---|
| Sprint 1 — Fence precision | D-1.1…D-1.6, `git-branch-prune.sh`, corpus, bats | corpus gates met; existing fence suite green; runtime within budget; REPO-MAP/checksums regenerated |
| Sprint 2 — Sectioned artefacts | `notes-guard.sh` `--section`/`--index`; include line + compensating trims; `/implement` sprint-block read; `/loa` artefact sizes; `update-loa.sh` rotation; migration addendum | reader bats; budgets green; rotation test; docs |
| Sprint 3 — Run preflight and resume | `run-preflight.sh`; run-mode SKILL/resources edits; checkpoint field; `workflow-state.sh`/`loa-status.sh` surfacing; SessionStart line; re-entry proof | predicate fixtures; resume suggestion; hook-wiring test |
| Sprint 4 — Provider health and cost | breaker `--list`/`--reset-breaker`/status block; chain-walk test; KF template + seeding; pricing ladder; adapter resolved-id; `cost-report.sh` legacy/unpriced; enforcer field names; CHANGELOG `[Unreleased]`; E2E goal validation | tests per item; `cost-report` on the fleet-id fixture < 5 % unpriced; CI green; Bridgebuilder pass triaged |

Each sprint: implement → `/review-sprint` → `/audit-sprint` (dissent) → COMPLETED → ledger/beads; record on `record/cycle-125-a2a`.

> Sources: prd.md §Timeline & Milestones; grimoires/loa/context/cycle-125-brief.md §4

---

## 9. Known Risks and Mitigation

| Risk | Mitigation |
|---|---|
| A new allow class admits a destructive `rm` (e.g. a bare name that is a symlink to `/`) | the catastrophic list is evaluated first; bare names may not start with `/`, `~`, `.`, `$`; dangerous twins in the corpus; audit dissent on Sprint 1 |
| A source-controlled directory named like a build output (`build/`, `target/`) is deleted through the cache-vocabulary class | accepted: the top-level allowance for those names pre-dates this cycle and git recovers tracked content; the class never matches `src`, `lib`, `app`, `grimoires` or hidden names outside the vocabulary (Flatline SKP-002) |
| Dated OpenAI ids priced from the base id when the release is priced differently | `pricing_resolution: dated` on the row; an exact catalog entry always wins (Flatline SKP-018) |
| `gh` probe adds latency or leaks branch names to the network | only on `git branch -D`, 5 s timeout, `LOA_FENCE_NO_NETWORK=1` opt-out, failure = block |
| Sink-aware SQL misses a runner (e.g. a project-local script named `db.sh`) | conservative list plus `--command`/`-c` forms; residual documented in the hook header; corpus row for `psql -f file.sql` |
| Skill byte budgets overflow after the include grows | trims land in the same commit; `check-prompt-budget.sh` in CI |
| Section reader changes what review/audit see | `--full` retained; skills read the sprint block plus ACs; cycle-124 A/B harness available |
| Preflight blocks a run the operator wants | checklist names the exact fix; interactive mode keeps today's behaviour |
| Pricing ladder maps a dated id to the wrong price | dated suffix stripping only when the base id exists; `pricing_resolution` recorded per row; report shows the share |
| Only one dissent voice on this host | failed-run envelopes per skill guidance; OpenAI voice functional |

> Sources: prd.md §Risks & Mitigation; grimoires/loa/known-failures.md KF-017

---

## 10. Open Questions

1. (Resolved — Flatline SKP-022 caught the contradiction with D-1.2.) Remote payloads are **not** scrubbed; `ssh host 'rm -rf /'` stays blocked and the residual false positives are accepted. No opt-in is offered in this cycle.
2. Does `/implement sprint-N` re-entry already skip closed beads in every path (bug run mode included)? Sprint 3 proves it with a fixture before relying on it for task-level resume.
3. `cost-budget-enforcer`: keep with real field names (this cycle) or retire in the F6 surface diet?
4. Should `--migrate-legacy` also rewrite `hounfour.metering.ledger_path` in the repository config when it still points at the legacy path? Out of scope unless the audit asks.
5. Pricing-snapshot governance (Flatline IMP-001): prices come from the catalog (`.claude/defaults/model-config.yaml`, regenerated by `tools/regen-model-artifacts.sh`); this cycle records `pricing_resolution` per row but does not detect stale prices. A freshness marker on the catalog pricing block is a follow-up.

> Sources: prd.md §Appendix (assumptions); grimoires/loa/context/cycle-125-brief.md §2 FR-3, FR-5

---

## 11. Appendix

### A. Evidence for the recent-version fence targets
Rule hits in sessions active since 2026-08-01: `FR-2-AMBIGUOUS` 284, `FR-1.4` 147, `FR-1.5` 80, `FR-1.3` 70, `FR-1.6` 52, `FR-1.1` 46 (versus genuine catches `P2` 31, `P3` 30, `FR-SZ2-*` 70).

### B. Byte headroom at design time
`implementing-tasks` 16,358 B · `reviewing-code` 16,334 B · `auditing-security` 16,308 B · `designing-architecture` 14,984 B · `run-mode` 15,761 B · `CLAUDE.loa.md` 10,225 B · protocols 199,593 B.

### C. Fleet ids to price (FR-5 fixture)
`gpt-5.2-2025-12-11`, `gpt-5.5-2026-04-23`, `gemini-2.5-pro`, `gemini-3.1-pro-preview`, `claude-opus-4-7`, `codex-headless`, `claude-fable-5-1`.

> Sources: grimoires/loa/reports/usage-mining-2026-09-23.md §3 F1, F5; tools/check-prompt-budget.sh output 2026-09-23
