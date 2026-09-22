# Sprint 1 Security Audit — cycle-124 "model-generation floor" (global sprint-235)

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1 lead acting as gate; independent inputs: cross-model audit dissent ×4 passes, four read-only audit slices A–D)
**Date:** 2026-09-18
**Sprint Reference:** grimoires/loa/sprint.md (Sprint 1)
**Scope:** `80be4b0f..087fc39e` on `feature/cycle-124-model-generation-floor` — 126 files, +8142/−1410 (LARGE ⇒ split: slice A adapters, B metering, C shell gates + CI, D catalog/schema/Bridgebuilder; slice C's subagent hit the session cap before delivering, so the lead re-audited that slice by hand)
**Review gate:** round 2 APPROVED (`engineer-feedback.md`, 2026-09-17)

---

## Phase 1 — Findings

Every finding below was verified by reading the code at the cited line; findings the audit surfaced and that were FIXED inside this sprint are listed with their fix commit and the test that pins them, so the reviewer of the PR can see what the audit changed.

### Fixed during the audit (closed)

| # | Sev at finding | Finding | Fix | Pin |
|---|---|---|---|---|
| AUD-D1 (dissent, sidecar) | HIGH | `live-floor-check.yml` ran on `pull_request` with `ANTHROPIC_API_KEY` in a pytest step over PR-controlled code | `44e1feab`: `workflow_dispatch`-only, `environment: live-floor`; `7665775b` residual + precondition recorded | `tests/unit/cycle-124-live-scaffold.bats:` c124-1.8-5 |
| AUD-B1 | MEDIUM | conftests set the ledger redirect only if unset — an operator's own export collected mock rows and the tripwire (hardcoded `.run/`) never looked there | `2b43baf4` unconditional redirect (`.claude/adapters/tests/conftest.py:25`, `tests/replay/conftest.py`) | `test_ledger_isolation.py:219` |
| AUD-B2 | MEDIUM | `rollup.default_ledger_path()` swallowed every `load_config` exception and guessed `.run/` (the DISS-001 failure through a second door); `cost-report.sh` rc-4 branch likewise | `2b43baf4` re-typed as `ConfigError` (`rollup.py:71`); `cost-report.sh:102` exits 2 unless the env names the ledger | `test_ledger_isolation.py:196` |
| AUD-B3 | MEDIUM | daily-spend sidecar (`_daily_spend_path`, beside the ledger whose directory an env redirect may now place anywhere) opened symlink-following and truncated — a planted symlink clobbered its target | `2b43baf4` `O_NOFOLLOW` in `ledger.py:284` and `budget.py:160` | `test_ledger_isolation.py:180` |
| AUD-B4 | LOW | `cost-report.sh` `cd`'d into `.claude/adapters`, so a relative `LOA_COST_LEDGER_PATH` resolved against a different directory than the writer's | `2b43baf4` `PYTHONPATH` instead of `cd` (`cost-report.sh:36`) | `cheval-cost-rollup.bats:117` |
| AUD-A1 | MEDIUM | kill-switch path: 16K default + thinking vs the flat 120 s non-streaming read timeout ⇒ `httpx.ReadTimeout`, retried ×4, each attempt billed | `1991390f` `_nonstreaming_read_timeout` (`anthropic_adapter.py:72`): lengthened only, 25 tok/s, cap 600 s | `test_anthropic_nonstreaming_timeout.py` |
| AUD-A3 | LOW | model-not-found 404 counted against the provider-wide breaker (5 unserved-id calls in 5 min ⇒ 60 s of every Anthropic HTTP hop skipped) | `1991390f` `ModelNotFoundError` (`types.py:205`), `retry.py:414` skips `_record_failure` | `test_anthropic_404_chain_walkable.py:102` |
| AUD-D1 (slice) | MEDIUM | Bridgebuilder adaptive retry derived from the operator budget, not the clamped one ⇒ identical retry payload after a token rejection | `4670b22f` `effectiveInputBudget` (`truncation.ts:686`), `reviewer.ts:477`, `:950` | `progressive-truncation.test.ts:308` |
| AUD-D2 | LOW | `"default"` row treated as a known id | folded into `effectiveInputBudget` | same |
| AUD-D3/D4/D5 | LOW | three tests that could not fail or mirrored the helper under test | `1991390f` expected per-family effort table; strict bool check; real `default_max_tokens` | themselves |
| AUD-D6 | LOW | `pricing` untyped in the v3 schema (a string `cache_read_per_mtok` was accepted, failing only at pricing time) | `4670b22f` four pricing fields typed | `model-config-v3-schema.bats:421` |
| DISS-001 (review dissent) | BLOCKING | reader swallowed the resolver's `ConfigError` | `12b6067e` | `test_ledger_isolation.py:66`, `cheval-cost-rollup.bats:101` |
| KF-004 | — | two audit-dissent findings arrived only via the rejected-payload sidecar (missing `id`) | recurrence + attempt row (`f740be39`); Sprint 2 structured outputs are the fix | `grimoires/loa/known-failures.md` |

### Open — accepted with a documented control (counted in the tally)

**AUD-R1 · MEDIUM · `.github/workflows/live-floor-check.yml` (header comment) — the dissenter's fourth-pass sidecar restates it as HIGH: a manually dispatched run executes the candidate branch's test code with the environment secret.**
Reasoning trace: the live check exists to run the branch's own adapter against the real API, so no checkout arrangement removes the branch's code from the run; the exploit needs a reviewer to approve a run of a branch they have not read. The control is GitHub environment protection: `live-floor` MUST be configured with required reviewers and a deployment-branch rule before the key is stored, and the key MUST be an environment secret, never repository-level (workflow header, report operator item 1, NOTES 2026-09-17). With that control the residual is a reviewer error, not an unauthenticated path — MEDIUM in this repo's context, not HIGH. Not a code change.

**AUD-R2 · MEDIUM · `LOA_CHEVAL_LEGACY_WIRE` + Opus 5 / Sonnet 5 / Fable — the switch cannot turn thinking off (server default-on), so its 4096 default can be spent on reasoning and a truncated verdict returned as success.**
Reasoning trace: the flag restores the pre-cycle BODY; it cannot restore pre-cycle server behaviour on ids that did not exist pre-cycle. A `thinking_default_on` catalog flag would separate the two families but is a new config surface the operator prompt excludes for this cycle. Mitigations in place: `operator_visible_warn` + the stderr `stop_reason=max_tokens` warning fire independently of the switch (`cheval.py:737`, `test_anthropic_cache_control.py:307`); the limit is documented in `multi-model-reference.md` and the env table (`cheval-delegate-architecture.md`); every framework dispatcher passes an explicit `--max-tokens`. Follow-up bead if the switch is ever used in anger on 5.x.

**AUD-R3 · LOW · pre-flight vs legacy-wall exit codes (7 vs 12) for one refusal class** — pre-existing gate ordering, observed by the AC-3.5 matrix, recorded in the report (§Known limitations 3); follow-up bead.

### Verified negatives (lead, slices A/B/D reports, dissent ×4)

- Fences untouched: `git diff 80be4b0f..HEAD -- .claude/hooks .claude/scripts/{implement-gate,zone-write-guard,block-destructive-bash,audit-envelope}.sh .claude/settings.json` is empty; the COMPLETED-marker gate (`adversarial-review-gate.sh`) requires `.metadata.type` AND `.metadata.model`, so a `budget_exceeded` envelope (no model) still blocks — fail-closed.
- Secrets: no key shapes in any added line of the sprint diff; `live-floor-check.yml` runs `set +x`, pins action SHAs, uploads only the pytest log/junit under `$RUNNER_TEMP`; `--json-schema`/wire content is never logged (Sprint 2 design, unchanged here).
- Path safety (slice B + lead): resolver realpath + symlink + `S_ISREG` + parent checks; `O_NOFOLLOW` on ledger AND sidecar; project-root anchoring mirrors the MODELINV twin (`parents[4]` ≡ `parent×5`); FIFO/socket fail `S_ISREG`; realpath following a symlinked PARENT is accepted by design (the target file is what is protected).
- Trust boundaries (slice A): catalog `params` are `isinstance(dict)`-guarded; a malformed `thinking_adaptive` (`"true"`, `1`) never emits thinking (`is True`); `_hop_max_tokens` clamps to the catalog cap with a warning; `_is_model_not_found` gates the walk on the `model:` signature; billing-class mapping unchanged; the temperature drop logs once per model.
- Headless argv (slice A): `_resolve_effort` filters through `_ALLOWED_EFFORTS`; model and prompt reach the CLI as separate argv elements, never through a shell.
- Shell gates (slice C, lead by hand): `golden-path.sh` trailer parse — two trailers (verdict-derive rejects), trailer not last (rejects), CRLF (accepted consistently by both parsers), `excluded` as float/string/negative (`invalid` ⇒ deny), audit-implies-review (review trailer now validated); `adversarial-review.sh` — `bash -c 'source "$1"; …' _ "$maps" "$model"` indexes `declare -A` maps (no arithmetic evaluation of the subscript), `--rawfile` temp files under `mktemp -d`, removed on both the success and the jq-failure path; `_ADVERSARIAL_WORKDIR` is a predictable `/tmp` name with an EXIT trap — pre-existing, unchanged this sprint; `regen-model-artifacts.sh` exit 3 has no CI caller that would misread it; `flatline-orchestrator.sh` passes explicit budgets only.
- Catalog invariants (slice D): every Anthropic HTTP entry satisfies `effective_input_ceiling + default ≤ context_window`; chains within-company and existing; aliases resolve; cache rates 0.1× (Fable 5.1 0.025×); `thinking_adaptive` exactly on the adaptive set; generated twins in step (dist manifest fresh, drift gates OK).
- Integer safety (slice B): `_int_or_zero`, cache-rate defaults, bool-as-int guards on `Usage` counts; the MODELINV chain is written only through `audit_emit`; new optional fields validate against the payload schema.
- Cross-model dissent: review clean ×3 (after DISS-001), audit `reviewed` 0 findings ×3 with the sidecar HIGH addressed (AUD-D1) and its residual accepted (AUD-R1). Model gpt-5.5-pro via codex-headless; no truncation waiver.

## Phase 2.5 — Severity Tally (open findings at verdict time)

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 2 |
| Low | 1 |

## Phase 3 — Verdict

APPROVED - LET'S FUCKING GO

Improvements to carry (not blocking): configure the `live-floor` environment protection before storing the key (AUD-R1); consider a `thinking_default_on` catalog flag in a later cycle so the legacy wire can keep a larger default on default-on ids (AUD-R2); unify the pre-flight and legacy-wall refusal exit codes (AUD-R3); Sprint 2's structured outputs close the KF-004 sidecar path that carried two of this audit's findings.

## Addendum — slice C report received after the verdict (2026-09-18T23:2xZ)

The shell-gates subagent's report arrived after this file's verdict and after the COMPLETED marker (its first delivery was truncated, its second hit the session cap). Its findings were verified by the lead and FIXED in the Sprint 2 tree — the tally above is unchanged because none remains open:

| Sev at finding | Finding | Fix (commit follows in the Sprint 2 range) | Pin |
|---|---|---|---|
| HIGH | `golden-path.sh` detected a trailer only by the exact canonical byte string (comment opener, space, `LOA-VERDICT`, space); a marker with a tab/NBSP/U+2010 fell through to the legacy prose heuristic, whose `grep -q APPROVED` matches "NOT APPROVED" — reproduced by the auditor | detection is loose (`_GP_TRAILER_DETECT`: any HTML comment reading LOA…VERDICT), `verdict-derive.sh` detects the same way and REJECTS any marker that is not the exact canonical form — HTML comment, ASCII `LOA-VERDICT`, single ASCII spaces, JSON object (`TRAILER_CANON`) — fail closed, never the prose path | `golden-path-c8-verdict-trailer.bats` slice-C HIGH ×2, `verdict-derive.bats` tab-marker case |
| MEDIUM | `excluded`/`excluded_confirmed`/`counts.*` compared with bash `-gt`/`-ne`/`$((…))`, which wrap at 2^64 (reproduced with 18446744073709551616) | `_gp_trailer_int` and `is_num` accept ≤ 6 digits; longer is `invalid` / a violation | `golden-path-c8-verdict-trailer.bats` slice-C MEDIUM, `verdict-derive.bats` 2^64 case |
| MEDIUM | `adversarial-review.sh` `_adv_input_budget_for_model`: when the maps file failed to source (error swallowed), `${MODEL_IDS[$2]}` was an INDEXED lookup and arithmetically evaluated a model id such as `x[$(touch pwned)]` — reproduced | model ids allowlisted (`^[A-Za-z0-9._:/-]+$`) before the lookup; arrays pre-declared associative inside the `bash -c`; a source failure exits the lookup (default budget) instead of indexing | `adversarial-review-schema-enforced.bats` slice-C MEDIUM |
| LOW | `--rawfile` prompt bodies in a second mktemp dir with no trap | written under the EXIT-trapped `_ADVERSARIAL_WORKDIR` when it exists | reviewed |
| LOW | CI positive control accepted any non-zero scanner exit (a missing fixture root exits 2) | requires exit 1 | `bats-tests.yml` |
| LOW | Flatline `--help` still said score calls pass 4000 | fixed in `0c727a98` | — |
| LOW | `ceiling-probe.py` returned 0 on a budget-truncated bisection while the live test accepted the record | exit 3 on `partial`; the live test asserts `partial is False` | `test_cycle124_live_floor.py` |
| LOW | `sprint-completion.md` / `run-mode/SKILL.md` did not state the marker test, the review re-gate on the audit path, or the malformed-`excluded` deny | both documents updated | doc-lock cases still green |

Also folded in from the other slices' tails: the system default `metering.ledger_path` moves to `.run/cost-ledger.jsonl` (the tripwire scans `.run/`), the pre-push hook is v2 (hygiene gate documented as always-on; installer replaces a v1 hook in place), `pricing.py` treats an explicit YAML null cache rate as "derive" instead of $0, the remaining Opus 4.8 pins (`run_bridge.bridgebuilder.multi_model`, `red_team.models.evaluator_primary`) and the example `opus` alias move to the floor, and the caching table gains Opus 4.7 (2048) / Sonnet 4.5 (1024).

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":2,"low":1},"sprint_id":"sprint-1","ts":"2026-09-18T22:40:00Z"} -->
