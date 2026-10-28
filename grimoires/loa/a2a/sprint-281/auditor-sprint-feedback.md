# Security & Quality Audit Report — Sprint 281 (cycle-137 sprint-1)

**Auditor:** Paranoid Cypherpunk Auditor (Claude Fable 5.1)
**Date:** 2026-10-28
**Scope:** the 22-pass extreme-software-optimization loop as landed on `feature/cycle-137-performance` — 20 commits 395795939 … c0d41f5e3 (18 System Zone files + `checksums.json`, `tests/unit/perf-spawn-budget.bats`, three bats helper files, CHANGELOG) plus the Sprint 281 gate fixes on `tests/unit/perf-spawn-budget.bats`: review 74790b2d1 → d005a771a, audit 227da3249 → 747b5db0d. `security-audit-scope.sh --paths <24 files>`: 0 controllers / routes / handlers / API endpoints; sinks: command exec 2 files, file operations 1 file; auth 2 files; LLM/AI 2 files. Working file: `grimoires/loa/a2a/audits/2026-10-28/SECURITY_ANALYSIS_TODO.md` (15 sources, 10 sinks, every entry traced).
**reviewed_head:** 747b5db0d (the review verdict in `engineer-feedback.md` names d005a771a; the two commits after it are the audit's own test-only fix, red-first, lead-read, and the guard is 8/8 on this head).
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain N/A) over the full code diff, two-pass source/sink tracing, and the two-voice security dissent.

---

## Executive Summary

The loop removes process spawns from the hooks on the per-tool-call path, from `compat-lib.sh` (sourced by ~78 scripts), from the grimoire index, the repo-map engine and the cheval provider registry, and every pass proves byte-identical output old-vs-new on the live inputs and an adversarial fixture matrix. From a security standpoint the question is whether any fast path changes what untrusted data can do: it does not. Untrusted inputs (hook payloads, known-failures bodies, decisions rows, handoff and notes text) still enter static jq/awk programs as DATA — never as program text — and the awk sanitisers are byte-for-byte twins of the `tr | sed | cut` pipelines they replace; the four fences keep their fail-open / fail-closed semantics (implement-gate still ASKs on an unparsable payload and ALLOWs a parsed payload without a path; notes-size-guard reproduces the composite last-document rule); the trust store and audit chain were not touched (pass 12 made no change); the lazy adapter import resolves names from a static table only; the integrity manifest is consistent (`check-loa.sh` All checks passed on 747b5db0d).

The security dissent (gpt-5.5-pro via codex-headless + claude-headless, 2/2 voices, consensus APPROVED) returned three LOW findings and no blocking one. One was a real hardening gap in the new spawn-budget guard — the traced hooks inherited the developer's or CI runner's whole environment, so an ambient override could have pointed a hook at live state and any expanded value would have landed in the trace file — fixed red-first inside this sprint (227da3249 → 747b5db0d). The other two are pre-existing (an unbounded KF row count on a default-off surface; a trajectory append in the karpathy hook without the symlink guard its state files have) and are filed as beads. My own pass confirms the review's medium observation on awk portability as an availability concern for the SessionStart surface on macOS hosts, carried to Sprint 2 Task 2.1.

**Overall Risk Level:** LOW

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 3 |

---

## Category Scores (Rubric-Based Assessment)

**Scoring Method:** Each dimension scored 1-5 per `resources/RUBRICS.md`

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 4.6/5 | IV:5 AZ:5 CI:4 IN:5 AV:4 |
| Architecture | 4.6/5 | MO:4 SC:5 RE:5 CX:4 ST:5 |
| Code Quality | 4.6/5 | RD:4 TC:5 EH:5 TS:4 DC:5 |
| DevOps | 4.4/5 | AU:5 OB:4 RC:5 AC:4 DS:4 |
| Blockchain | N/A | — |
| **Overall** | **4.55/5** | *Weighted average (equal weights, four categories)* |

**Risk Level Mapping:**
- 4.5-5.0: LOW | 3.5-4.4: MODERATE | 2.5-3.4: HIGH | 1.0-2.4: CRITICAL

Notes on the sub-5 dimensions: SEC-CI 4 — the lazily probed `_COMPAT_*` flags are empty until a helper runs (a direct external reader sees `""`; documented, only `dx-utils.sh` in-tree and guarded). SEC-AV 4 — the awk sanitiser's portability on BWK awk / BSD `cut` hosts (MED-001). ARCH-MO/CX 4 — the one-jq programs are dense (each states the shape it accepts). CQ-RD/TS 4 — same density; bash has no types. DO-OB/AC/DS 4 — the budgets are measured on one toolchain (now recorded) and the CI run on the PR is the proof.

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Production)

None.

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] awk sanitiser portability — the SessionStart KF surface on BWK awk / BSD cut hosts

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `.claude/hooks/loa-kf-surface.sh:92-100` (twin `.claude/scripts/grimoire-index.sh:59-66`)
**Criterion:** SEC-AV: Availability/Resilience
**Reasoning Trace:**
> Pass 6 replaced the per-field `tr -d '\000-\010…' | tr '\t\n\r' '   ' | sed … | cut -c1-100` pipeline with an awk `san()` under `LC_ALL=C`. The twin is byte-exact on GNU/mawk/busybox (pass-4 and pass-6 reviewer fixtures). Two host dependencies remain: `gsub(/\000/, …)` and the octal classes in a regex constant on BWK one-true-awk (macOS `/usr/bin/awk`), and BSD `cut -c` being character-based under UTF-8 (so the former macOS cap was 100 characters, the new cap is 100 bytes and can end mid-codepoint). The hook's `2>/dev/null || true` turns an awk that rejects the program into the loud "parsed ZERO KF entries" path (exit 0), so the failure mode is loss of the surface, not an injection.
**Description:** Verified at review and audit: mawk 1.3.4 and busybox awk run both programs identically. BWK awk UNVERIFIED on this host (not installed; no yacc to build it; the upstream repository was unreachable from here at 2026-10-28T03:00Z).
**Impact:** On a macOS host without coreutils the SessionStart known-failures table may degrade to the zero-entries warning for every session, or truncate a long non-ASCII symptom differently from the reference spec; the sanitiser's control-byte stripping is unaffected. Failure: when a host's awk rejects the NUL regex, every session on that host loses the KF table; when `cut` was character-based, a >100-byte non-ASCII symptom is cut mid-codepoint into the session context.
**Remediation:** Sprint 2 Task 2.1 (brief A) runs the golden comparison under every awk available including a BWK awk when obtainable, on a fixture with `\001`, `\177`, NUL and a 3-byte-UTF-8 symptom longer than 100 bytes, and either states the byte cap as the contract (GNU `cut -c` was already byte-based on Linux, so Linux output is unchanged) or trims a trailing partial sequence after `substr`.
**References:** CWE-838 (inappropriate encoding for output context) for the mid-codepoint tail; availability of a safety surface (the KF table is the intake discipline's index).

---

## Low Priority Issues (Technical Debt)

### [LOW-001] spawn-budget tracer inherited the ambient environment (FIXED in this sprint)

**Severity:** LOW | **Confidence:** high
**Component:** `tests/unit/perf-spawn-budget.bats:_trace` (line ≈ 70 before the fix)
**Description:** `_trace` ran the production hooks with `env VAR=… bash -x` without `-i`, so the developer's or CI runner's whole environment reached the traced hooks: an ambient `LOA_*` override could point a hook at live state (making a budget nondeterministic) and any value a hook expands would be written to the trace file, whose path the failure message prints. Failure: an ambient token, path or session id lands in `TRACE_FILE`, or an ambient override silently invalidates the "fixtures stand alone" guarantee the budgets rest on. (Security dissent DISS-C-001.)
**Remediation:** Done red-first: 227da3249 adds case (h) — an exported canary reaches the traced script and its trace (fails on the old tracer); 747b5db0d runs the target under `env -i PATH HOME=<fixture> TMPDIR=<fixture> LANG=C <explicit list>`, and the post-run assertion refuses the live repository's `.loa.config.yaml`, `.run/` and `grimoires/` paths as command arguments (a plain assignment of a default path before the test seam overrides it is allowed — the kf-surface hook does exactly that at line 74). Budgets re-measured three times, identical: kf-surface 34 → 36 trace lines (two bash-internal lines from the explicit environment; external-tool lines unchanged), the other five unchanged. Guard 8/8 on 747b5db0d.

### [LOW-002] unbounded KF row count injected into the session context (pre-existing)

**Severity:** LOW | **Confidence:** medium
**Component:** `.claude/hooks/loa-kf-surface.sh:118-128`
**Description:** Every distinct `## KF-NNN:` heading yields one sanitised 100-byte line injected at SessionStart; the per-field cap and sanitiser hold, the total volume is unbounded. Pre-existing — pass 6 moved the formatting into awk without changing the row set; the feature is default-off (`known_failures.surface_at_session_start`). Failure: a repository or PR branch shipping a known-failures.md with thousands of synthetic headings floods the session context with attacker-authored fragments before the agent reads anything else. (Security dissent DISS-C-002.)
**Remediation:** bead bd-4sikh — cap the emitted rows in the awk END loop (first N by file order, or top-N by recurrence) with one trailing `… +N more entries (see known-failures.md)` line; keep `kf_count` reporting the total.

### [LOW-003] karpathy trajectory append follows a symlinked directory or file (pre-existing)

**Severity:** LOW | **Confidence:** medium
**Component:** `.claude/hooks/quality/karpathy-surgical-diff-check.sh` (the `>> "$TRAJ_DIR/karpathy-${TS:0:10}.jsonl"` append, ≈ line 214)
**Description:** `STATE_DIR` / `TASK_FILE` carry `-L` guards (≈ lines 162, 165) but the trajectory append does not; `TRAJ_DIR` defaults to `grimoires/loa/a2a/trajectory` inside the repository, a path a cloned repository can populate with symlinks. Pre-existing — pass 19 touched only the session-id encode (lines 124-146), which is correct and does not weaken this. The appended bytes are a fixed JSON schema with numeric fields and a JSON-encoded session id. Failure: a symlink at the per-day trajectory file or the directory makes the hook append a well-formed JSON line to an arbitrary file the user already owns when the surgical-diff threshold trips. (Security dissent DISS-C-003.)
**Remediation:** bead bd-kdzc3 — mirror the state-file guards (`[[ -L "$TRAJ_DIR" ]] && exit 0` after the `mkdir`; `[[ -L "$traj" ]] && exit 0` before the append), optionally requiring the realpath under `REPO_ROOT` unless `KARPATHY_TRAJECTORY_DIR` is set.

---

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and no `adversarial-rejected-audit*.jsonl` sidecar exists beside `adversarial-audit.json`.

---

## Cross-Model Observations

`adversarial-review.sh --type audit --sprint-id sprint-281 --diff-file <code-only diff of main...HEAD at d005a771a over .claude, tests, CHANGELOG.md> --budget 700 --json` (no context file; a `--diff-range main...HEAD` run would exceed the 200c config budget on this branch because of 140 KB of planning prose — the review hit that refusal first). Envelope: status `clean`, primary gpt-5.5-pro (answered via codex-headless), companion claude-headless `succeeded` / `independent_voice`, 2/2 voices, consensus APPROVED, `locality` null (NOT DEGRADED_SECURITY_REVIEW), `cost_usd` 0. Three LOW findings, all from the companion voice, triaged above (LOW-001 fixed; LOW-002 and LOW-003 pre-existing → beads bd-4sikh, bd-kdzc3). The primary voice returned no findings and concurred with the approval. The two fix commits after the dissent (227da3249, 747b5db0d) change only `tests/unit/perf-spawn-budget.bats`; they were lead-read and are covered by the guard's own 8/8 run and the pre-existing bats suites (no production path changed).

Review demotions to confirm: the review trailer counts `excluded: 0`; confirmed — `excluded_confirmed: 0`.

---

## Security Checklist Status

### Secrets & Credentials
- [x] No hardcoded secrets (full diff read; the only token-shaped strings are the pre-existing test-fixture redaction probes)
- [x] Secrets in gitignore (unchanged; `.env*` untouched)
- [x] No credential handling changed (the lazy adapter import resolves classes only; no auth code touched)
- [x] Trace files of the spawn-budget guard now run under an explicit environment (LOW-001 fixed)
- [x] The audit's own artefacts carry no secrets (envelopes `cost_usd` 0; no provider lines)

### Authentication & Authorization
- [x] No authentication or authorization code in scope (N/A)
- [x] Fences keep their decisions: implement-gate ASK on unparsable / ALLOW without a path / classify otherwise; notes-size-guard block rule; the Stop guard's push gate values identical old vs new
- [x] No privilege escalation path introduced (no new exec of data; no new sudo/chmod)
- [x] Tokens N/A
- [x] Token theft N/A

### Input Validation
- [x] Untrusted inputs enter static jq/awk programs as data (`<<<"$input"`, file arguments, `ENVIRON["BN"]`); no interpolation of untrusted text into program text (the two pre-existing interpolations — `yq -r ".$key"` in cache-manager and `"$3 // empty"` in run-state-surface — take literal call-site arguments)
- [x] Sanitisers are byte-for-byte twins of the former pipelines (control bytes stripped, whitespace flattened, capped; `esc` on every rendered cell)
- [x] File uploads N/A
- [x] Webhook signatures N/A

### Data Privacy
- [x] No PII in logs (hooks print sanitised fragments of repo-local files only)
- [x] Encryption in transit N/A (no network code)
- [x] Data retention unchanged
- [x] Right to deletion N/A

### Supply Chain
- [x] Dependencies unchanged (stdlib `importlib` only)
- [x] npm audit N/A for this diff (no JS/TS touched)
- [x] No known CVEs introduced
- [x] Integrity manifest consistent (`check-loa.sh` All checks passed on 747b5db0d; REPO-MAP consistent)

### API Security
- [x] Rate limits N/A
- [x] Exponential backoff N/A
- [x] Response validation: every fast path validates its shape (line counts, types, charset) before trusting the result; otherwise the verbatim original path runs
- [x] Circuit breakers N/A
- [x] No stack traces exposed (error texts unchanged on every degraded path)

---

## Threat Model Summary

**Trust Boundaries:**
- Agent-authored hook payloads on stdin (PreToolUse / PostToolUse / SessionStart / Stop) → the hooks' parsers
- Repository-controlled grimoire files (known-failures, visions, lore, handoffs, NOTES, decisions) → session context and the generated index
- Operator-owned configuration (`.loa.config.yaml`, model catalog, push config) → yq reads and, for the push command, execution under the operator's own trust
- Repository source tree → the repo-map engine (pure computation)

**Attack Vectors:**
- Payload shapes that make a fast path misclassify a write (implement-gate): LOW — every non-plain shape falls to the original jq calls; unparsable → ASK
- Crafted grimoire text reaching the session context or the index unsanitised: LOW — sanitisers unchanged in effect; unbounded row volume is pre-existing (LOW-002)
- Program-text injection through yq/jq expressions: LOW — only literal call-site keys are interpolated (pre-existing shape)
- Attacker-chosen module import through the lazy registry: NONE — names come from a static table; others raise AttributeError
- Symlink following on write paths: LOW — the loop adds no write path; the pre-existing trajectory append is LOW-003
- Portability-induced loss of a safety surface (MED-001): MEDIUM on BWK awk / BSD cut hosts, unverified

**Mitigations:**
- "Fast path with verbatim fallback" on every hook; byte-identical fixture matrices per pass (`a2a/sprint-281/evidence/`)
- Static sanitiser twins under `LC_ALL=C`; `esc` on rendered cells
- Integrity manifest regenerated per commit; guard tests on the hot paths with an explicit environment and live-state refusal
- Trust store, audit chain and `br` contract calls untouched

**Residual Risks:**
- MED-001 until Sprint 2 Task 2.1 verifies BWK awk and decides the byte-cap contract
- LOW-002 / LOW-003 until their beads land
- The budgets' toolchain dependence until the PR's Shell Tests run confirms them on the CI runner

---

## Positive Findings

- Every pass is one revertable commit with a parity harness, a fresh-context review and the orchestrator's re-derivation; divergences are enumerated (six, all benign).
- The fences' fail-open / fail-closed semantics are preserved by construction, and the per-pass fixture matrices cover the adversarial shapes (multi-document, non-object, NUL, control bytes, invalid UTF-8, BOM, duplicate keys).
- The spawn-budget guard is deterministic, now counts the hidden spawns too, runs under an explicit environment and refuses live-state reads.
- No new persistent cache, no new write path, no new data source, no `eval`, no change to credential or trust-store code.
- The engineer's report walks every acceptance criterion with `file:line` evidence, and the evidence is preserved under `a2a/sprint-281/evidence/`.

---

## Recommendations

### Immediate Actions (24 Hours)
1. None blocking. Write `COMPLETED`, mark ledger sprint 281 completed, record the two audit fix commits in `e2e.md`.

### Short-Term Actions (1 Week — Sprint 2)
1. Task 2.1: run both KF awk programs under every awk available (BWK awk when obtainable) and decide the byte-cap contract (MED-001).
2. Land bd-kdzc3 (karpathy trajectory symlink guards) and bd-4sikh (KF row cap) as small red-first fixes, or schedule them.

### Long-Term Actions (1 Month)
1. bd-0h7kq: one lazily built dispatch mapping in `providers/__init__.py`; `cli_adapter_types()` from a static auth table.
2. Keep the spawn-budget toolchain note current when CI's pinned tools change.

---

## Verdict

**APPROVED - LET'S FUCKING GO**

**Next Steps:**
1. `COMPLETED` marker for sprint-281; ledger sprint 281 → completed; `a2a/index.md` row; `e2e.md` finalised.
2. Sprint 282 under `/run sprint-2 --local` (worktrees from 747b5db0d; brief A carries MED-001).

---

**Audit Completed:** 2026-10-28T03:30:00Z
**Next Audit Recommended:** Sprint 282 (`/audit-sprint sprint-2`)
**Remediation Tracking:** beads bd-4sikh, bd-kdzc3, bd-0h7kq; Sprint 2 Task 2.1

---

*Generated by Paranoid Cypherpunk Auditor Agent*
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":3},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-281","ts":"2026-10-28T03:30:00Z"} -->
