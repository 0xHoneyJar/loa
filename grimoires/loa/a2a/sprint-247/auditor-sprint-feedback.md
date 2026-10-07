# Security & Quality Audit Report — Sprint 1 (cycle-126, global sprint 247)

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1 lead, unattended `/run sprint-plan`) with the independent security dissenter (`adversarial-review.sh --type audit`, no reviewer context; dissenter `gpt-5.5-pro` → `codex-headless`, run per focused chunk against `0df687c8`, chunk b re-run against the hardening head)
**Date:** 2026-09-25
**Scope:** the Sprint 1 diff `a775f14d..HEAD` — `loa_cheval/routing/ceiling.py` (new), `cheval.py` gate + chain loop, `types.py`, `providers/{base,anthropic,openai,google,bedrock,retry}.py`, `metering/{pricing,ledger}.py`, the catalog, `tools/ceiling-probe-live.py`, `loa-status.sh`, `cost-report.sh`, `flatline-orchestrator.sh`, `gen-adapter-maps.sh`, `lib-multipass.sh`, Bridgebuilder generator / pipeline / config / personas, and the tests
**Methodology:** systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain n/a) over the actual code, the review record (`engineer-feedback*.md`), and the per-chunk dissent envelopes with every rejected-payload sidecar hand-triaged

---

## Executive Summary

The sprint moves every size decision onto the resolved catalog entry and adds four new surfaces the auditor cared about: a state file written by the request path (`.run/ceiling-observed.json`), a catalog writer in the probe tool, a second provider endpoint call (`count_tokens`) and a new request header (`anthropic-beta`). Each was read for the classic failure classes — path handling and symlinks, concurrent writers, injection into headers / YAML / shell, credential exposure in logs and envelopes, unbounded input from the catalog or the provider, and fail-open behaviour on malformed state.

No critical or high finding stands. The state file is written under an interprocess lock, atomically, with the lock opened `O_NOFOLLOW`; the catalog writer edits only the named block and refuses unknown tiers and partial bisections; the beta header is allowlisted (no CR/LF, no free text) and never derived from a request; the count endpoint sends the same prompt to the same provider with the same headers; every provider message is sanitised at the adapter and, after this audit, again at the non-walkable exit; a malformed store or multiplier degrades to today's behaviour rather than failing open or crashing; the opt-in that unlocks larger inputs is env-only and default-off. The independent dissenter returned no accepted findings on any chunk; its one schema-rejected payload (a MEDIUM on message redaction at the calibration exit) was hand-triaged, judged a defence-in-depth gap rather than an exposure (the text was already adapter-sanitised and the envelope emitter redacts), and closed with a test-first hardening.

**Overall Risk Level:** LOW

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 3 |

---

## Category Scores (Rubric-Based Assessment)

**Scoring Method:** Each dimension scored 1-5 per `resources/RUBRICS.md`

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 4.6/5 | IV:5 AZ:5 CI:4 IN:5 AV:4 |
| Architecture | 4.4/5 | MO:5 SC:4 RE:4 CX:4 ST:5 |
| Code Quality | 4.6/5 | RD:4 TC:5 EH:5 TS:4 DC:5 |
| DevOps | 4.2/5 | AU:5 OB:4 RC:4 AC:4 DS:4 |
| Blockchain | n/a | — |
| **Overall** | **4.5/5** | *Weighted average* |

**Risk Level Mapping:** 4.5-5.0: LOW | 3.5-4.4: MODERATE | 2.5-3.4: HIGH | 1.0-2.4: CRITICAL

---

## Critical Issues (Fix Immediately)

None.

## High Priority Issues (Fix Before Production)

None.

## Medium Priority Issues (Address in Next Sprint)

None open. Cross-model MEDIUM (schema-rejected payload, chunk b: "provider exception text persisted as `message_redacted` without redaction at `_calibration_needed_exit`") — **addressed in-sprint**: `sanitize_provider_error_message` is applied before the text is recorded or printed (`test_ceiling_e2e.py::test_calibration_exit_redacts_secret_shapes_in_the_recorded_message`); see Cross-Model Security Observations.

## Low Priority Issues (Technical Debt)

### [LOW-001] Store and catalog paths are read through a symlink
**Severity:** LOW
**Component:** `.claude/adapters/loa_cheval/routing/ceiling.py:load_observed`, `tools/ceiling-probe-live.py:_write_catalog_file`
**Description:** the lock file is opened `O_NOFOLLOW` and both writers replace the path entry (a planted symlink is swapped for a regular file, never followed), but the read side opens the path normally, so a symlink at the store or at the `--write-catalog` path is read through (the store: parsed as JSON, malformed → empty; the catalog: text the operator pointed the tool at).
**Remediation:** open the read side with `O_NOFOLLOW` too (or `os.lstat` + refuse), matching the ledger writer; low value because both paths are operator-owned locations under the repository.

### [LOW-002] Local filesystem path in the envelope
**Severity:** LOW
**Component:** `.claude/adapters/cheval.py:_calibration_needed_exit` (`calibration_needed.store`)
**Description:** the envelope and stderr JSON carry the absolute store path. `.run/model-invoke.jsonl` already carries local paths elsewhere; the record branch does not ship `.run/`.
**Remediation:** keep the repo-relative form if the envelope is ever exported.

### [LOW-003] Catalog value interpolated into a yq path expression
**Severity:** LOW
**Component:** `.claude/scripts/loa-status.sh:_anthropic_ceiling_json`
**Description:** the `opus` alias target is spliced into `yq eval -r ".providers.anthropic.models.\"$model\"…"`. The value comes from the tracked catalog (an operator-controlled file), so this is a robustness note (a quote in a model id would break the expression), not an injection path.
**Remediation:** pass the id with `--arg` / `strenv` when yq supports it in this pipeline.

---

## Security Checklist Status

### Secrets & Credentials
- [x] No hardcoded secrets (the retired snapshot id was the only literal removed; no key or token in the diff; `_tiny_model_id` derives the probe target from the catalog)
- [x] Secrets in gitignore (`.run/ceiling-observed.json` lives under `.run/`, untracked; the record branch excludes it)
- [x] Credential presence only (health probe and `/loa` never print a value; `count_tokens` logs exception class names only)

### Authentication & Authorization
- [x] No new auth path (the count endpoint and the models probe reuse `_get_auth_header`; the CLI hops are untouched)
- [x] No privilege escalation (the opt-in and kill switches are env-only, default off, and only lower or restore bounds)

### Input Validation
- [x] Catalog inputs bounded (`_beta_header_value` allowlist `^[a-z0-9]+(-[a-z0-9]+)*-YYYY-MM-DD$`, `ConfigError` otherwise; `_mult` finite-and-positive; `_pos_int` guards on every ceiling field; `write_catalog` refuses unknown tiers and missing blocks)
- [x] Provider inputs bounded (`parse_context_limit` regexes with comma-tolerant integers; `is_context_limit_message` substring markers; messages sanitised at the adapter and again at the calibration exit)
- [x] No injection (no shell interpolation of provider text; the yq splice is catalog-only — LOW-003; bash associative-array subscripts in `flatline_voice_max_tokens` guarded by `declare -p`)

### Data Privacy
- [x] No PII in logs (prompt text never leaves the request path; the store holds counts and ids only)
- [x] Encryption in transit unchanged (same HTTPS endpoints)

### Concurrency & State
- [x] Observed store: `flock(LOCK_EX)` on `<store>.lock` (O_NOFOLLOW) from load through `os.replace`; 4 × 25 concurrent appends keep 100 rows; readers take no lock and always see a complete file
- [x] Catalog writer: temp + `os.replace`, one block edited, byte-identical elsewhere (test)
- [x] Fail-soft where it must be (a store write failure prints and still exits typed; a malformed store is empty, never a zero bound; a count failure keeps the heuristic)

### Supply Chain
- [x] No new dependency (`fractions`, `fcntl`, `math` are stdlib; `httpx` optional as before)

---

## Cross-Model Security Observations

- Dissenter (`--type audit`, six chunks, no reviewer context): **0 accepted findings** on chunks a–f against `0df687c8`; chunk b re-run against the hardening head — **0 findings, status clean** against `4b289413` (no new rejected payload); merged envelope `adversarial-audit.json` (`metadata.merged_from_chunks`, six chunks, 0 findings) with the per-chunk envelopes and the one rejected sidecar kept beside it. One schema-rejected payload (`adversarial-rejected-audit-b-cheval-gate.jsonl`, `reject_reason: missing-or-empty-failure_mode`): MEDIUM info-disclosure, "provider exception text persisted as `message_redacted` without redaction" at `_calibration_needed_exit`. Hand-triaged: the text reaching that exit is already `sanitize_provider_error_message`-sanitised by the adapter (cycle-103 T3.3) and the MODELINV emitter redacts secret shapes before writing; the arm's `str(_exc)` matched the pattern of every other arm in the loop. Judged a defence-in-depth gap; closed test-first in the same sprint (`_msg = _sanitize(str(_exc))` for both the record and the stderr JSON). **Confirmed by cross-model review** in the sense that the auditor's own pass had listed the same line as a LOW.
- The review-gate dissent's four HIGH findings (per-hop unverified flag; observed-store race; premium rounding order; non-finite multiplier crash) were all closed before this audit (`engineer-feedback.md` Previous Feedback Status) and the affected chunks re-ran clean under both gates.

---

## Verdict

APPROVED - LET'S FUCKING GO

Zero critical / high. Three LOW technical-debt notes recorded above; none blocks. The sprint's security posture is stronger than the baseline it replaces (a retired probe id, an unbounded per-call literal and a request temperature always on the wire are gone; the new state file is locked and atomic; the new header is allowlisted).

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":3},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-247","ts":"2026-09-25T05:40:00Z"} -->
