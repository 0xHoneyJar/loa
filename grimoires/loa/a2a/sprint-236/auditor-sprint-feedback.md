# Sprint 2 Security Audit — cycle-124 "model-generation floor" (global sprint-236)

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1 lead acting as gate; independent input: cross-model audit dissent)
**Date:** 2026-09-20
**Sprint Reference:** grimoires/loa/sprint.md (Sprint 2)
**Scope:** `087fc39e..012d0c5e` — 78 files, +2764/−326 (MEDIUM size; audited sequentially by the lead: adapters/cheval, shell gates and dissent, Flatline, fixtures/tests, configs/docs)
**Review gate:** round 1 APPROVED (`engineer-feedback.md`, 2026-09-20)

---

## Phase 1 — Findings

Every item verified by reading the code at the cited line and, where stated, by running it.

### Trust boundaries and input handling

- `cheval --json-schema FILE` (`.claude/adapters/cheval.py:223`): regular file only (a FIFO or directory is `INVALID_INPUT` — `fb7bf705`), object root, ≤ 64 KB, parse failure ⇒ `INVALID_INPUT` before any dispatch; error messages carry the path, never content; the schema is never logged — the envelope carries its sha256 only (`:2319`, `:2429`). Clean.
- Schema on the wire: Anthropic `output_config.format` (`anthropic_adapter.py:253`) and OpenAI `text.format` (`openai_adapter.py:435`) send the operator-authored file from `.claude/schemas/wire/` (System Zone, tracked, linted by W1–W5); claude-headless forwards it as one argv element (≤ 64 KB, well under the per-argument limit) — no shell. Clean.
- `schema_enforced` is set by OUR adapters from the body they sent (`anthropic_adapter.py:644`, `openai_adapter.py:163`, `claude_headless_adapter.py:249`), never from model output; the dissent and Flatline read it from cheval's envelope, so a model cannot switch a consumer into the strict branch or out of it. Clean.
- Dissent enforced branch (`adversarial-review.sh:976`): `jq_strict` on the raw content, no fence strip, no `raw_decode`, no normalization, no repair; `stop_reason=max_tokens` ⇒ `malformed_response`; a valid-but-not-object payload ⇒ `malformed_response` (never `clean`). Unenforced branch byte-for-byte as before plus the repair loop, whose input is model output fed back to the same model — a pre-existing prompt-injection surface, unchanged in shape and bounded to one round-trip per rejected finding. Clean / accepted.
- `_adv_input_budget_for_model` (`adversarial-review.sh:86`): model ids allowlisted before the `bash -c` lookup; associative arrays pre-declared; source failure fatal to the lookup (late Sprint 1 slice-C MEDIUM — reproduced and closed in `68371775`; bats case). Clean.
- Gates (`golden-path.sh`, `verdict-derive.sh`, `89b41e23`): loose detection + strict acceptance of the trailer marker, six-digit integer cap — a malformed marker or an overflowing count can only deny. Reproductions from the slice-C report re-run green. Clean.

### Secrets, ledgers, CI

- No key shapes in any added line (`grep` over the range: 0). `live-floor-check.yml` unchanged this sprint (manual-only, environment-scoped). `.github/workflows/bats-tests.yml`: the hygiene positive control now requires scanner exit 1 (a missing fixture root can no longer pass as a rejection). Clean.
- Ledger isolation: two suites that ran the real dissent script in mock mode wrote mock rows into the operator ledgers (found by the tripwire; `7bd5f35f` redirects both and DS-1 now covers the indirect spawners); ledgers rotated per the runbook (`.run/archive/*-20260918T231348Z.jsonl`, chain verified). The system default `metering.ledger_path` moved to `.run/` so the tripwire scans where a downstream repo writes (`012d0c5e`). `pre-push-audit` v2 documents the always-on hygiene gate. Clean.
- Pricing: an explicit YAML null cache rate no longer prices cache tokens at $0 under `pricing_source: config` (`pricing.py` `_int_rate`, test). Clean.

### Fences and zones

- `git diff 087fc39e..HEAD -- .claude/hooks .claude/scripts/{implement-gate,zone-write-guard,block-destructive-bash,audit-envelope}.sh .claude/settings.json` is empty. System-Zone edits were made under the cycle's zone marker; `.claude/schemas/wire/` is new tracked content. Clean.

### Open (counted)

**AUD2-L1 · LOW · `tools/check-ledger-hygiene.sh` (MODELINV rule)** — mock-mode dispatches produce MODELINV rows that carry real model ids and fixture token counts; the scanner can only recognise `cheval-e2e-` paths, so a future leaking harness would go unseen on the MODELINV side (the cost ledger's `mock-*` identity still catches it). Follow-up bead: stamp mock dispatches in the envelope (e.g. `config_observed.mock_fixture_dir`) and teach the scanner the marker.

**AUD2-L2 · LOW · `openai_adapter.py:435` (isolated hunk)** — OpenAI strict-mode acceptance of the authored `anyOf [type, null]` nullable form is pinned by body tests only; no OpenAI HTTP credential on this host. Operator step before relying on an OpenAI HTTP dissenter; the hunk is droppable (`cdf6768f`).

### Verified negatives (summary)

- Dissent: `--type audit --sprint-id sprint-236 --budget 400` on the final diff → `reviewed`, 0 findings, `verdict_quality: APPROVED`, rejected-payload sidecar empty (gpt-5.5-pro via codex-headless; the audit dissenter itself ran `parse_path: normalized` — unenforced hop, as measured).
- Tripwires: `tools/check-no-swallowed-jq.sh` OK (both edited gate scripts are in its enforced set); `tools/regen-model-artifacts.sh --check` OK (catalog checksum re-baselined for the ledger default); `tools/check-ledger-hygiene.sh` OK after the rotation.
- Repair loop: one bounded round-trip per rejected finding; failure keeps the rejection + sidecar row; never entered on the enforced branch (FR7-1/6, repair-loop suite).
- `translate_output` adds `schema_enforced`/`stop_reason` only; consumers read them with `// false` / `// empty`.
- Configs: `repair_loop` keys removed; Opus pins on the floor; example alias updated; no new config surface introduced (the operator prompt's constraint).

## Phase 2.5 — Severity Tally (open findings at verdict time)

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 2 |

## Phase 3 — Verdict

APPROVED - LET'S FUCKING GO

Improvements to carry: mark mock dispatches in the MODELINV envelope so the hygiene scanner sees them (AUD2-L1); verify the OpenAI strict `anyOf` nullable form live before enabling an OpenAI HTTP dissenter (AUD2-L2); forward `--output-schema` to codex/gemini headless in a later multi-provider cycle; retire the repair loop when the unenforced ratio justifies it.

## Addendum (2026-09-21)

The late independent review input (see `engineer-feedback.md` §Addendum) contained one gate-relevant
security finding: lowercase trailer markers bypassed the fail-closed trailer path in golden-path
(MEDIUM). It is closed in `a1337ed4` with fail-closed tests; the remaining items are correctness and
evidence-quality fixes. No open finding changes the tally above.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":2},"sprint_id":"sprint-2","ts":"2026-09-20T00:40:00Z"} -->
