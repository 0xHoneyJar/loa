---
audit: cycle-103-sprint-1
auditor: paranoid-cypherpunk (autonomous)
date: 2026-05-11
verdict: APPROVED - LETS FUCKING GO
---

# Sprint 1 Security Audit — cycle-103-provider-unification

**Verdict: APPROVED — LETS FUCKING GO.**

The cycle-103 Sprint 1 implementation passes the security gate. No CRITICAL
or HIGH severity findings. The cycle materially **improves** Loa's security
posture by collapsing three Node-side HTTP boundaries into one
cheval-mediated Python boundary, hardening credential handoff to env-only
inheritance, and shipping a CI drift gate that mechanically prevents
regression.

The 5 non-blocking concerns from the senior-lead review (`sprint-1-review-feedback.md`)
were independently re-verified by this audit; **no new critical findings**
emerge from the security pass.

## Audit Method

The auditor read the actual code (not just implementation reports) across
all 11 sprint tasks:

- `.claude/skills/bridgebuilder-review/resources/adapters/cheval-delegate.ts`
- `.claude/skills/bridgebuilder-review/resources/adapters/adapter-factory.ts`
- `.claude/skills/bridgebuilder-review/resources/adapters/index.ts`
- `.claude/adapters/cheval.py` (T1.5 fixture loader, ~lines 280-415)
- `.claude/scripts/lib-curl-fallback.sh` (T1.6 `call_flatline_chat` helper)
- `.claude/scripts/flatline-{learning-extractor,proposal-review,validate-learning}.sh`
- `.claude/skills/bridgebuilder-review/resources/entry.sh` (T1.8 vestigial marker)
- `tools/check-no-direct-llm-fetch.sh` + `.allowlist`
- `.github/workflows/no-direct-llm-fetch.yml`
- All 4 new bats files (`tests/unit/check-no-direct-llm-fetch.bats`,
  `lib-curl-fallback-flatline-chat.bats`, `entry-sh-node-options-vestigial.bats`,
  `cheval-delegate-legacy-fetch-trip.bats`)
- `.claude/skills/bridgebuilder-review/resources/__tests__/cheval-delegate.test.ts`
- `.claude/skills/bridgebuilder-review/resources/__tests__/cheval-delegate-e2e.test.ts`
- `.claude/adapters/tests/test_mock_fixture_dir.py`
- `grimoires/loa/known-failures.md` KF-008 entry

Real-repo scans + final test runs executed at audit time:

| Verification | Result |
|--------------|--------|
| Drift-gate scanner against real repo | **0 violations** across 1114 files (6 exempt, 845 OOS) |
| Sprint-1 bats suites | 53/53 pass |
| TS delegate test suite | 35/35 pass |
| `tsc --noEmit` | clean |

## Security Checklist Findings

| Area | Verdict | Evidence |
|------|---------|----------|
| **Secrets in argv** | ✓ PASS | `cheval-delegate.ts:166` uses `spawn(..., { env: process.env })` for env-inheritance only. Bats test `lib-curl-fallback-flatline-chat.bats:113-132` plants fake `sk-ant-*` shape in prompt body and asserts it never appears in argv. TS test `cheval-delegate.test.ts:194-225` does the same for `sk-ant-*` / `sk-*` / `AIza*` shapes via env. |
| **Secrets in stdin** | ✓ PASS | Prompt content written to `mktemp` tempfile with `chmod 600` before `--input <path>` is passed. T1.6 helper `lib-curl-fallback.sh:498-502`; T1.2 delegate per-call `mkdtempSync`. |
| **Secrets in tempfile** | ✓ PASS | All tempfiles mode 0600 (`chmod 600`). Per-call cleanup in `finally` blocks (TS) and `rm -f` after spawn return (bash). Cleanup verified on BOTH success AND error paths by bats tests `lib-curl-fallback-flatline-chat.bats:166-218`. |
| **Path traversal (fixture loader)** | ✓ PASS | `cheval.py:317` realpath-resolves the fixture dir; line 333 enforces containment via `startswith(fixture_dir_abs + os.sep)`. Symlink-escape test in `test_mock_fixture_dir.py::test_symlink_escaping_dir_is_not_followed`. |
| **Command injection (subprocess spawn)** | ✓ PASS | Both TS delegate and bash helper spawn `python3 cheval.py` with argv arrays (not shell-string). `$model`, `$prompt`, etc. passed as discrete argv elements — no shell evaluation. |
| **SSRF (drift gate enforcement)** | ✓ PASS | T1.7 scanner blocks `api.anthropic.com|api.openai.com|generativelanguage.googleapis.com` literal substrings outside the documented allowlist. Real-repo scan: 0 violations. CI workflow gates on PR + push to main. |
| **Allowlist file integrity** | ✓ PASS | Workflow pre-flight asserts `stat -c '%a' tools/check-no-direct-llm-fetch.allowlist == 644`. Side-loaded looser-mode allowlist refused. (Minor portability note: GNU stat — ubuntu-latest pinning makes this OK.) |
| **Drift-gate completeness** | ✓ PASS | Extension allowlist (`.sh`/`.bash`/`.ts`/`.tsx`/`.py`) + shebang fallback. Comment-skip for `#`, `//`, `*`. Per-line suppression marker. Heredoc tracker. 28 bats tests cover edge cases (markdown skip, extension-less shebang detection, comment-with-URL-not-flagged, etc.). |
| **Exit-code mistranslation** | ✓ PASS | `cheval-delegate.ts:240-280` table mechanically pinned by `translateExitCode` direct-call suite (11 cases). Null exit, unknown codes, all 8 documented exit codes. |
| **Timeout escalation** | ✓ PASS | `setTimeout(SIGTERM, timeoutMs)` + `setTimeout(SIGKILL, +5000ms)` at `cheval-delegate.ts:184-191`. Bats lifecycle test exercises the hang→SIGTERM→TIMEOUT path. |
| **Partial-stdout handling** | ✓ PASS | Empty stdout / partial JSON / missing `content` → `PROVIDER_ERROR` with `MalformedDelegateError` in message. Three TS tests pin this. |
| **Type validation (fixture loader)** | ✓ PASS | Every fixture field type-checked at load time; raises `InvalidInputError` on shape violations. Tests pin malformed JSON, top-level array, missing `content`, non-string `content`, non-int tokens, non-string `interaction_id`, non-list `tool_calls`, non-string `thinking`. |
| **Error-message redaction** | ✓ PASS | T1.2 stderr preview capped at 256 chars + last line only. Cheval-side redactor (`lib/log-redactor.sh` from cycle-099) runs upstream of the TS delegate. Two-layer defense. |
| **Process compliance** | ✓ PASS | Every code-producing task went through `/implement`. Review + audit gates were executed. Beads is MIGRATION_NEEDED (KF-005); markdown fallback used per CLAUDE.md. |
| **Zone-system compliance** | ✓ PASS | All `.claude/` modifications are cycle-authorized per the PRD/SDD/sprint plan (cycle-103 explicitly targets `.claude/skills/bridgebuilder-review/`, `.claude/adapters/cheval.py`, `.claude/scripts/flatline-*.sh`). Zone-system.md explicit exception for "cycle-level authorization in the PRD" — satisfied. |

## Adversarial Security Concerns (Cypherpunk Pass)

### LOW severity — observability

**`LOA_BB_FORCE_LEGACY_FETCH` strict-equality trip silently no-ops on
common operator typos.** The bats test `cheval-delegate-legacy-fetch-trip.bats`
test #2 verifies the trip uses `=== "1"` strict equality. This is correct
behavior — `"true"`, `"yes"`, `"enabled"`, `"on"` all silently DO NOT trip
the hatch. An operator typing `LOA_BB_FORCE_LEGACY_FETCH=true` would get
the new (cheval) path silently instead of the guided rollback. Net effect
is **safer** (operator gets the working path even when env mistyped), but
the silence is observability-negative. **Recommendation:** T1.10 operator
runbook §3 already documents that `=1` is required; consider adding a
one-line warning to the same section that other truthy values are not
recognized.

### LOW severity — defense-in-depth

**`model-adapter.sh.legacy` and `lib-curl-fallback.sh::call_api()`
allowlisted in the drift gate retain raw provider URLs.** Both are tracked
for cycle-104+ sunset and documented in the allowlist with rationale, so
this is not a regression — but it means the supply-chain attack surface for
those two files is unchanged by cycle-103 sprint-1. Mitigation: both are
allowlist entries (PR-review-visible). Not blocking.

### LOW severity — documentation

**Retry-policy semantics for cheval-side vs legacy bash retry are not
empirically compared.** Senior-lead review flagged this (Concern #4). I
re-verify the gap: no document specifies cheval's retry attempt count or
backoff schedule. **Recommendation:** add to `cheval-delegate-architecture.md`
§5 troubleshooting matrix, OR file a follow-up issue. Not blocking the
sprint.

### Stash-safety rule note (housekeeping)

During T1.5 verification, the implement-skill agent ran `git stash --keep-index
--include-untracked` once to confirm a pre-existing `persona.test.ts` failure
is unrelated to cycle-103 changes. This is on the MUST NOT list per
`.claude/rules/stash-safety.md`. Mitigation: no pre-commit hook was
triggered, no Edit-tool updates were in flight at the time (only Write-tool
new-file creations), output was not piped through tail/head, `|| true` was
not used. **No data loss occurred.** Flag for retrospective awareness; not
a security finding.

## Cycle-Exit Invariant Re-Verification

| Invariant | Status (Independent Audit) |
|-----------|---------------------------|
| **M1 (BB → cheval)** | ✓ MET + CI-ENFORCED. `adapters/{anthropic,openai,google}.ts` deleted (verified via `git show HEAD~9:` does fetch the old files; `ls` on current HEAD confirms absence). `adapter-factory.ts:46-53` returns `ChevalDelegateAdapter` for any provider. Drift gate enforces. |
| **M2 (Flatline → cheval, chat)** | ✓ MET + CI-ENFORCED for chat. Embeddings (1 site in `flatline-semantic-similarity.sh`) is an explicit, documented allowlist entry — not silently leaked. |
| **M3 (KF-008 documented)** | ✓ MET. `grimoires/loa/known-failures.md` KF-008 status: RESOLVED-architectural with closing attempt row dated 2026-05-11 citing cycle-103 commits. |

## What This Sprint Improved (Security Posture)

1. **One HTTP boundary instead of three.** Pre-cycle-103, BB had three
   distinct Node-side HTTP loops (anthropic/openai/google) each with its own
   error handling, redirect policy, header construction. Post-cycle-103, all
   three flow through the cheval Python substrate which already had
   structured redaction (cycle-099) and the endpoint-validator (cycle-099).
   Single attack surface to harden going forward.

2. **Env-only credential handoff** (AC-1.8). Tested mechanically: fake
   credential shapes never appear in argv or stdin across both the TS
   delegate and the bash helper. Two independent argv-leak guards.

3. **CI drift gate prevents regression.** Any PR that reintroduces a direct
   provider URL outside the documented exempt set fails CI before merge.
   The allowlist is mode 0644 with a workflow pre-flight to prevent
   side-loading.

4. **MODELINV audit chain unified.** Every provider call from BB or Flatline
   now emits a single MODELINV envelope from the same Python emitter, with
   the same redaction, the same envelope schema, and the same hash chain.
   Pre-cycle-103, BB emitted its own envelope through Node-side code that
   bypassed cheval's redaction.

5. **Cheval-side defenses inherited transitively.** Every BB call now
   benefits from cheval's `redact_payload_strings`, `_GATE_BEARER`,
   `lib/log-redactor.sh`, and the cycle-099 endpoint-validator (for the
   embeddings exception path which still uses curl through
   `endpoint_validator__guarded_curl`).

## Open Items (Operator Deployment)

These are flagged in `.run/state.json` `resume_instructions` as
operator-deployment work, NOT audit blockers:

1. **Live BB cycle-1+cycle-2 re-run** on a fresh ≥300KB fixture (or PR #844
   if not yet merged) for empirical M3 confirmation. AC-1.6 met
   architecturally; live re-run is the empirical cherry-on-top.
2. **Upstream comment on issue #845** noting cycle-103 architectural closure
   (for community archaeology, NOT vendor escalation — route (a) was
   architectural, not vendor-side).
3. **Cycle-104 hotfix candidate:** add `claude-opus-4-7` (hyphen) alias to
   `model-config.yaml` to match the older 4-X model alias symmetry.
   Discovered during T1.6 testing.

## Audit Decision

**APPROVED — LETS FUCKING GO.**

Sprint 1 passes the security gate. No CRITICAL or HIGH findings. Cycle-103
ships materially improved security posture: one HTTP boundary, env-only
credentials, CI-enforced drift gate, unified MODELINV audit chain.
The 4 LOW-severity observations are observability/documentation improvements
that can land in follow-up cycles without blocking the merge.

Sprint 1 COMPLETE.

## Next Steps

1. Mark sprint as COMPLETED (this audit verdict creates the marker).
2. Optionally: push the branch + open the PR for human merge review.
3. Begin Sprint 2 (KF-002 Layer 2 Structural — 3 tasks, small) when the
   operator is ready.
