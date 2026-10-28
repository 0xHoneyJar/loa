# Security analysis working file — Sprint 281 audit (cycle-137 sprint-1), 2026-10-28

Scope: `git diff main...HEAD -- .claude tests CHANGELOG.md` at d005a771a (24 files: 19 System Zone files incl. `checksums.json`, 4 test files, CHANGELOG). `security-audit-scope.sh --paths …`: 0 controllers/routes/handlers/API endpoints; sinks: command exec 2 files, file operations 1 file; auth files 2; LLM/AI files 2. Statuses: PENDING → CONFIRMED (a defect) / SAFE / PARTIAL / N/A.

## Phase 1A — untrusted sources (entry points)

| # | Source | Trust | File:line | Reaches | Status |
|---|---|---|---|---|---|
| S1 | PreToolUse payload on stdin (tool_input.file_path / notebook_path, cwd, active_skill, agent_id) | UNTRUSTED (agent-authored) | `.claude/hooks/compliance/implement-gate.sh:216-241` | one static jq program (`jq -nj … <<<"$input"`), NUL-terminated fields read with `read -d ''`; then the existing path classification | SAFE — program text is static; data enters as stdin; non-string / NUL / multi-document shapes fall to mode L (the original jq calls); unparsable → mode U → ASK (fail-closed unchanged) |
| S2 | PreToolUse payload on stdin | UNTRUSTED | `.claude/hooks/safety/notes-size-guard.sh:37-42` | static `jq -rn 'reduce inputs …'`; the path is compared to the NOTES path only | SAFE — static program; the composite last-document rule reproduced; no exec of the value |
| S3 | PostToolUse payload session id (`PAYLOAD_SID_JSON`) and `LOA_SESSION_ID` | UNTRUSTED | `.claude/hooks/quality/karpathy-surgical-diff-check.sh:124-146` | `SESSION_JSON` built by string concatenation ONLY after `^[A-Za-z0-9._-]+$`; else the original jq encode; `task_raw` from `run-checkpoint read --json` through the unchanged jq `gsub` sanitiser | SAFE — the charset gate makes the concatenated JSON string valid by construction; the decode fast path applies only to `"[A-Za-z0-9._-]*"` |
| S4 | `.run/sprint-plan-state.json`, `state.json`, `simstim-state.json` contents | SEMI-TRUSTED (framework-written, repo-local) | `.claude/hooks/session-start/loa-run-state-surface.sh:49-63` | `jq -rs` program with `$3`/`$4` interpolated — the three call sites (lines 72-74) pass literal jq expressions; values with control bytes → slow path → `_san` | SAFE — interpolation surface is constant call sites (pre-existing shape); control bytes never reach the fast path |
| S5 | `grimoires/loa/known-failures.md` bodies | UNTRUSTED (agent-authored, ships in every clone) | `.claude/hooks/loa-kf-surface.sh:91-128` → stdout (session context) | awk `san()` strips C0/C1/DEL, flattens whitespace, caps 100 bytes | SAFE on GNU/mawk/busybox (byte-for-byte twin of `tr\|sed\|cut`); PARTIAL on BWK awk (`/\000/` regex) and BSD `cut` hosts (char vs byte cap) — carried to Sprint 2 Task 2.1 (review obs 1) |
| S6 | `known-failures.md`, `visions/entries/*.md`, `lore/index.yaml`, `handoffs/INDEX.md`, `NOTES.md`, `decisions.yaml` | UNTRUSTED | `.claude/scripts/grimoire-index.sh:56-80, 93-210` → INDEX.md / JSON | `SAN_AWK` twin of `san()`; vision basename via `ENVIRON["BN"]` (data, not program text); `rd()`/`split()` field emulation; render_md `esc` on every cell | SAFE — every cell sanitised; no field reaches a shell or awk program as code |
| S7 | `.loa.config.yaml` keys (cache-manager `get_config`) | OPERATOR-OWNED | `.claude/scripts/cache-manager.sh:165-172` | `yq -r ".$key"` — `key` interpolated into the yq expression | SAFE — the three callers (lines 189, 201, 212) pass literal keys; pre-existing shape (the removed probe interpolated the same way) |
| S8 | model catalog yaml (`loa-status` ceiling read) | OPERATOR-OWNED | `.claude/scripts/loa-status.sh:848-895` (unchanged by the loop; pass 14 touched the agy memo only) | — | N/A for this sprint |
| S9 | push config yaml (`notifications.push_command.*`) | OPERATOR-OWNED | `.claude/scripts/lib/push-notify-lib.sh:52-62` | one static `yq eval` program; `PUSH_COMMAND` later executed by the unchanged `_push_notify` (operator-configured command, pre-existing trust model) | SAFE — fast path yields the same three values as the per-field reads (39/39 fixtures incl. multi-line → fallback); no widening of what is executed |
| S10 | `.run/sprint-plan-state.json` (run-checkpoint `cmd_read`) | SEMI-TRUSTED | `.claude/scripts/run-checkpoint.sh:187-245` | static `jq -s -r`; fields with newline/NUL → fallback; the `bead_closed` trust check untouched | SAFE |
| S11 | `.loa.config.yaml` (upgrade-health-check probes) | OPERATOR-OWNED | `.claude/scripts/upgrade-health-check.sh:219-260` | static yq program; non-boolean lines → fallback | SAFE |
| S12 | provider `type` strings from model config | OPERATOR-OWNED | `.claude/adapters/loa_cheval/providers/__init__.py:45-62, 92-105` | `_ADAPTER_TYPES.get(type)` → `_adapter_class(name)` → `importlib.import_module` of a name from the static `_ADAPTER_MODULES` table only; `__getattr__` raises AttributeError for any other name | SAFE — no attacker-chosen module import; unknown type → ConfigError text unchanged |
| S13 | repository source files (repo_map.py scan) | SEMI-TRUSTED | `.claude/scripts/lib/repo_map.py:100-187, 320-340` | pure computation; `--out-md/--out-json` paths come from the wrapper's `mktemp` | SAFE |
| S14 | `PATH` directory listings (bats symlink farms) | TEST-ONLY | `tests/unit/{dec-write-lib,loa-decisions-surface,red-test-check}.bats` | `ln -s -- "${batch[@]}" "$dir/"` under BATS tmp | SAFE (test scope); review obs 3 recorded the pre-existing IFS quirk |
| S15 | spawn-budget fixtures and traces | TEST-ONLY | `tests/unit/perf-spawn-budget.bats` | `BASH_XTRACEFD` to a file under `$W`; `SHELLOPTS=xtrace` exported to the traced target only | SAFE — traces never leave BATS tmp; the live config path is asserted absent |

## Phase 1B — dangerous sinks (backward trace)

| # | Sink | File:line | Sources reaching it | Guard | Status |
|---|---|---|---|---|---|
| K1 | `importlib.import_module(module)` | `providers/__init__.py:59` | S12 via `_ADAPTER_MODULES.get(name)` only | static table; `name` not in table → AttributeError | SAFE |
| K2 | `exec -a / bash -c` in the companion shim | `tests/unit/adversarial-review-companion.bats` (not touched this sprint) | — | — | N/A |
| K3 | File writes: `mv "$TMPM" "${OUT_MD}"` (repo-map), `mv "$tmpj" "$OUT_JSON"` (grimoire-index), `.run/platform-features.json` recorder (implement-gate, unchanged) | `repo-map-gen.sh:84-92`, `grimoire-index.sh:322-330` | internal temp files | `set -euo pipefail` + trap; `mktemp` in both | SAFE |
| K4 | stdout → session context (SessionStart hooks) | `loa-kf-surface.sh:135-139`, `loa-run-state-surface.sh:64-70` | S5, S4 | `san()` / `_san` | SAFE (S5 portability PARTIAL as above) |
| K5 | `yq -r ".$key"` expression interpolation | `cache-manager.sh:170` | S7 (literal keys) | callers literal | SAFE |
| K6 | jq expression interpolation `"$3 // empty"` | `loa-run-state-surface.sh:55-58` | S4 call sites (literals) | constant | SAFE |
| K7 | `eval`, `source` of data, `bash -c "$var"` | none introduced | — | — | N/A — grep over the diff: no new `eval`, no `source` of a data path, no `bash -c` with interpolated data |
| K8 | Integrity manifest `.claude/checksums.json` | `.claude/checksums.json` | the 18 touched files | `check-loa.sh` "All checks passed" on d005a771a | SAFE |
| K9 | Trust-store / audit chain (`_check_trust_store`, `audit_emit`) | `audit_envelope.py` | untouched (pass 12 zero-change) | — | N/A |
| K10 | Credentials / `.env*` / push config execution path | — | S9 values identical old vs new | — | SAFE |

## Second-order flows

- Cached values: the loop adds NO new persistent cache (the `.run/perf-cache` precedent is untouched; Sprint 2's C-5 adds one under the SDD § 3 rules). Memoised values (`_LOA_STATUS_AGY_OPT`, `_COMPAT_*`) live in one process.
- The `.skill-loop-progress.md`, perf report and CHANGELOG carry no secrets (grep for key shapes: none).

## Deferred / out of time budget

None — every entry traced.

## Phase 1C — security dissent (`adversarial-audit.json`, 2026-10-28T03:08:52Z)

`adversarial-review.sh --type audit --sprint-id sprint-281 --diff-file <code-only diff of main...HEAD at d005a771a> --budget 700 --json` (no context file). Status `clean`; primary gpt-5.5-pro (answered via codex-headless) + companion claude-headless (`succeeded`, `independent_voice`); 2/2 voices; consensus APPROVED; 3 LOW findings; `rejected_summary` empty; no sidecar; `cost_usd` 0; `locality` null (not degraded).

| Finding | Triage | Status |
|---|---|---|
| DISS-C-001 LOW — `_trace` passes the ambient environment to the traced hooks and only greps one live path | CONFIRMED as a test-harness hardening gap: fixed red-first in this sprint (227da3249 case (h) exported canary → 747b5db0d: `env -i` allowlist, live `.loa.config.yaml` / `.run/` / `grimoires/` paths refused as command arguments; budgets re-measured) | CONFIRMED → fixed |
| DISS-C-002 LOW — unbounded KF row count injected into the session context | Pre-existing (not introduced by pass 6, which only moved the formatting into awk); default-off feature; the per-field cap and sanitiser hold | SAFE for this sprint → bead bd-4sikh (cap rows + trailing "+N more") |
| DISS-C-003 LOW — karpathy trajectory append follows a symlinked `TRAJ_DIR` / per-day file | Pre-existing (pass 19 touched the session-id encode only, lines 124-146; the append at ~214 is unchanged); impact: a well-formed JSON line appended to a user-owned file | SAFE for this sprint → bead bd-kdzc3 (mirror the state-file `-L` guards) |

## Audit-time additions to Phase 1B

- S5/K4 reassessed with the review's observation 1: the awk sanitiser's portability (BWK awk `/\000/`, BSD `cut` char cap) is an availability concern for the SessionStart surface on macOS — MEDIUM (SEC-AV), carried to Sprint 2 Task 2.1 (brief A) with the BWK awk matrix; UNVERIFIED here (no BWK awk obtainable: repo unreachable, no yacc).
- K8: `.claude/checksums.json` re-verified on the audit head (`check-loa.sh` All checks passed); the two review/audit fix commits touch only `tests/unit/perf-spawn-budget.bats`, so no manifest change was due.
