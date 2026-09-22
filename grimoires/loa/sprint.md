# Sprint Plan: Cycle-124 — Model-Generation Floor

> **Cycle**: `cycle-124-model-generation-floor` (ledger; global sprint ids allocated by `add_sprint` at registration — see the table below)
> **PRD**: `grimoires/loa/prd.md` (FR-1 … FR-10, AC-n.m) · **SDD**: `grimoires/loa/sdd.md` (§1.3 units, §2 data, §3 component designs, §6 tests)
> **Sprints**: 4 (local `sprint-1` … `sprint-4`)
> **Routing**: `/run sprint-plan` → `/implement` → `/review-sprint` → `/audit-sprint` per sprint, on branch `feature/cycle-124-model-generation-floor`; one draft PR to `main` requesting `@deep-name`, **merged with a merge commit or rebase, never squashed** (the revert units U0–U3/S2–S4 exist only if their labelled commits survive the merge — stated in the PR body). System-Zone writes under the bounded marker `.run/zone-guard-authorization.json` (deleted at cycle end).
> **Ground rules (every task)**: failing test first; smallest correct diff; no fence weakened; regenerate `grimoires/loa/REPO-MAP.md` after any `.claude/` change; catalog edits regenerate `generated-model-maps.sh`, the BB TS twins + `dist/`, and `model-config.yaml.checksum` in the same commit; every AC row in the sprint report cites `file:line` or observed output; live scaffolds skip without `LOA_RUN_LIVE_TESTS=1`.
> **Beads**: one epic per sprint via `create-sprint-epic.sh`, one task per row below via `create-sprint-task.sh` with the `⇐` blockers as `--deps` (KF-005/KF-022 discipline: DB authoritative, no `--rebuild`/`--import-only`).
> **Baselines (2026-09-17)**: adapter pytest 1937 passed / 6 skipped in 31 s; `golden-path-c8-verdict-trailer.bats` + `verdict-derive.bats` 32/32; parity goldens 32; `.run/cost-ledger.jsonl` 155 `mock-` rows, `.run/model-invoke.jsonl` 44 `/tmp/cheval-e2e-` rows.

---

## Executive Summary

Bring the framework's own use of Claude to the Opus 5 / Sonnet 5 / Fable 5.1 floor. Sprint 1 fixes the adapter and catalog (thinking, output budget, 1M/128K entries, cached persona blocks, cache telemetry) and two dishonest gates (verdict trailer consumption, test-polluted ledgers). Sprint 2 makes every JSON-bearing model call schema-enforced on the voices that support it. Sprint 3 cuts the prompt surface to the byte budgets with a coverage-first review prompt and an A/B gate. Sprint 4 bounds session memory.

| Sprint | Theme | Scope | Key deliverables | Dependencies |
|---|---|---|---|---|
| 1 | Adapter floor + gate honesty | LARGE (10 tasks) | ledger isolation, MODELINV schema, catalog at the current generation, `--effort` + defaults, adaptive thinking, cache blocks + telemetry, verdict gates, live scaffolds, rollback proof | none |
| 2 | Structured outputs | MEDIUM (6 tasks) | wire schemas, `--json-schema` end to end, capability-gated emission, headless enforcement, tolerant-path retention, fixture corpus | Sprint 1 |
| 3 | Prompt audit + review recall | LARGE (9 tasks) | budget + keep-list gates, 49-unit audit, protocol archivals, coverage-first prompts, effort wiring, eval executor + 10-PR corpus, A/B | Sprint 2 |
| 4 | Memory gate | SMALL (3 tasks) | `notes-guard.sh`, fences + writer gate, docs + memo | none (sequenced last) |

---

## Sprint 1: Adapter floor and gate honesty

### Sprint Goal
Every Anthropic HTTP request cheval builds is shaped for the current generation and observable, the catalog names the current models, and the review/audit gates and production ledgers are honest — with a live-check scaffold committed for the credentialed operator step.

### Deliverables
- [x] `LOA_COST_LEDGER_PATH`, `conftest.py` isolation, `tools/check-ledger-hygiene.sh` + CI/pre-push wiring, ledger rotation runbook executed locally (FR-6)
- [x] MODELINV payload schema with optional `tokens_cache_read`, `tokens_cache_creation`, `schema_enforced`, `output_schema_sha256`; mixed-writer fixture (U0)
- [x] `claude-opus-5`, `claude-fable-5-1`; 1M/128K family; v2 input fields removed, `effective_input_ceiling` 180K + calibration on every Anthropic HTTP entry; `params.thinking_adaptive`, `temperature_supported`, `structured_json`, `cache_read_per_mtok`; Sonnet 5 pricing 2/10; aliases + tier aliases retargeted; generated artifacts + checksum; two CI grafts; `live-floor-check.yml` (FR-3)
- [x] `default_max_tokens()`, `--effort`, `--max-tokens` default `None`, chain rebuild carries effort/budget, legacy-transport wall constant, model-aware dispatch budget in `adversarial-review.sh`, KF-002 re-baseline row (FR-2)
- [x] `thinking: {type: adaptive}` per catalog flag; temperature drop warning (FR-1)
- [x] System blocks with `cache_control`, cache counts in `Usage` (non-streaming + headless), MODELINV/CLI JSON/ledger cache fields, cache-read/write pricing (FR-4)
- [x] `_gp_verdict_gate` in `golden-path.sh`; run-mode + sprint-completion doc updates (FR-5)
- [x] Live scaffold `tests/replay/test_cycle124_live_floor.py`; `catalog-evidence.md` with `reference|probed` marks
- [x] Rollback proof per unit recorded in the sprint report

### Acceptance Criteria
- [x] AC-6.1 … AC-6.4 (ledgers byte-identical across the suites; tripwire self-tests; rotation executed; discovery test)
- [x] AC-3.1 … AC-3.6 (`cheval --dry-run --model opus` → `claude-opus-5`, `fable` → `claude-fable-5-1`; drift gates; TS twin 1M budgets + dist parity; advisor tier via live config; AC-3.5 consumer matrix; v3 smoke flip + `cheval-input-gate.bats` in CI)
- [x] AC-2.1 … AC-2.6 (defaults table incl. non-streaming cap and catalog clamp; effort on chain walk; ceiling + default ≤ window; `--max-tokens 0` rejected; per-model effort validity)
- [x] AC-1.1, AC-1.2 (per-family body tests; schema-typed flag; thinking ⇒ no temperature; Bedrock unaffected); AC-1.3 committed as a skipped live scaffold with the operator command
- [x] AC-4.1, AC-4.2, AC-4.4 (block shape; telemetry end to end; other adapters byte-identical); AC-4.3 committed as a skipped live scaffold
- [x] AC-5.1, AC-5.2 (seven new bats cases incl. fail-closed; doc-lock; consumer-inventory and `test_golden_path.bats` green unmodified)
- [x] Adapter pytest ≥ 1937 passed, 0 failed; all three `model-registry-drift` checks green locally; REPO-MAP regenerated; `known-failures.md` KF-002 row added via `kf-write-lib.sh`

### Technical Tasks

- [x] Task 1.1: **Ledger isolation + tripwire (U3)** — `resolve_cost_ledger_path()` in `metering/ledger.py` (canonicalize, reject symlink target, parent must be an existing directory; the writer opens with `O_NOFOLLOW|O_APPEND|O_CREAT`, mode `0o644`, so a symlink swapped in between validation and write fails instead of following, hardlinks are out of the threat model for an untracked per-operator file, and concurrent writers keep today's line-atomic `O_APPEND` semantics; absolute/relative/symlink/missing-parent/traversal cases tested), `cheval.py:1437`, all readers incl. `rollup.py` and `cost-report.sh` resolve through it; `.claude/adapters/tests/conftest.py` (autouse, set-only-if-unset); `cheval-delegate-e2e.test.ts` env; 4 bats exports; `tools/check-ledger-hygiene.sh` + `bats-tests.yml` post-test step with sentinel controls + `pre-push-audit` call; `tests/unit/ledger-isolation-discovery.bats`; runbook `grimoires/loa/runbooks/ledger-hygiene-rotation.md` and its local execution (seal → mv → fresh chain; cost ledger moved after the `cost_micro_usd: 0` check). Tests first: `test_ledger_isolation.py`, `tests/integration/ledger-hygiene-tripwire.bats`. → **[G-6]** ⇐ none
- [x] Task 1.2: **MODELINV schema + mixed-writer fixture (U0)** — optional fields in `model-invoke-complete.payload.schema.json`; `tests/fixtures/modelinv/mixed-writer-rows.jsonl`; run `economy.py`, `health.py`, `journal.py`, `modelinv-rollup.sh`, `modelinv-coverage-audit.py`, `modelinv-v1.3-backcompat.bats` against it; no `writer_version` bump. Tests first: schema validation of a row with and without the new fields. → **[G-3, G-4]** ⇐ Task 1.1
- [x] Task 1.3: **Catalog at the current generation (U1a)** — `model-config.yaml` per SDD §2.1 (new entries, 1M/128K, v2 fields removed, ceiling + calibration, `params`, `structured_json`, `cache_read_per_mtok`, Sonnet 5 2/10, aliases, self-maps); `model-config-v3.schema.json` `params` typing; `.loa.config.yaml:36` + `.example:2675` → `claude-opus-5`; `gen-bb-registry.ts` derives Anthropic `maxInput` from `effective_input_ceiling − 20000`; `tools/regen-model-artifacts.sh` (NEW: one deterministic sequence — `gen-adapter-maps.sh` → `npm run gen-bb-registry` → `npm run build` → checksum — with a `--check` mode that runs the three drift checks; bats-pinned to be idempotent: a second run changes nothing) regenerates `generated-model-maps.sh`, BB TS twins, `dist/` + manifest, checksum; model-not-found (404) on a new primary id (`claude-opus-5`, `claude-fable-5-1`) is classified chain-walkable so the call falls to the 4.8/5 fallback instead of failing at first use if the account does not serve the id yet (pinned by a chain-walk test); `cycle099-sprint-1e-tests.yml` `--to-v3` flip; `cheval-input-gate.bats` G7 → v3 field + added to `bats-tests.yml`; `catalog-evidence.md`. Tests first: `test_anthropic_catalog_floor.py`, `tests/unit/cycle-124-anthropic-catalog.bats`, `model-config-v3-schema.bats` extension. → **[G-2]** ⇐ Task 1.1
- [x] Task 1.4: **Defaults, `--effort`, ceiling wall, dispatch budget (U1b)** — `default_max_tokens()` (Anthropic hops only; other providers keep the literal 4096, golden-body tests) + `_lookup_max_output_tokens()`; argparse `--effort`, `--max-tokens` default `None` (0 ⇒ `INVALID_INPUT`); `base_request`/`_entry_request` carry `effort` + per-hop default and clamp of an explicit value; per-family effort emission table (omit on sonnet-4-5/haiku/headless, `xhigh→high` on 4.6); MODELINV `payload.effort`; `_LEGACY_TRANSPORT_INPUT_WALL` in `_lookup_max_input_tokens`; per-model `xhigh` downgrade on 4.6 entries; `adversarial-review.sh` 160K Anthropic budget + pre-dispatch token log; explicit `--max-tokens` at bounded dispatchers (dissent/review/skeptic 16K, scorer 4K, BB delegate 16K) + `budget.py` per-call cost-ceiling test + timeout-audit table in the report; `LOA_CHEVAL_LEGACY_WIRE` kill switch in `base.py` with a legacy golden-body test; stale `cheval.py:337` comment fixed; `kf-write-lib.sh` KF-002 re-baseline row (sandbox with `--file <copy>` first); `live-floor-check.yml`. Tests first: `test_max_tokens_defaults.py`, `tests/unit/cycle-124-effort-flag.bats` (the literal `--effort xhigh` ⇒ `max_tokens ≥ 64000` via `--dry-run`), `tests/integration/input-size-consumers.bats` (AC-3.5), extended `test_chain_walk_audit_envelope.py`, AC-2.5 caller grep recorded. → **[G-1, G-2]** ⇐ Task 1.3
- [x] Task 1.5: **Adaptive thinking (U2a)** — `anthropic_adapter.complete()` emits `thinking` per `params.thinking_adaptive` (honoring the kill switch); temperature/top_p/top_k drop warning; per-family effort table + catalog invariant that every Anthropic id is in it; edit `test_anthropic_effort.py` fixture expectations. Tests first: `test_anthropic_thinking.py` (per family; never `budget_tokens`/`disabled`; byte-identical when the flag is absent or the kill switch is set; streaming inherits; thinking-block-first response fixtures on both transports), Bedrock golden-body test. → **[G-1]** ⇐ Task 1.4
- [x] Task 1.6: **Prompt caching + cache telemetry (U2b)** — `_persona_messages()` in cheval; `_transform_messages` string-or-blocks; `_parse_response` and `claude_headless_adapter` populate `Usage.cache_*`; MODELINV capture + CLI JSON `usage` fields; `pricing.py` cache read/write rates + `CostBreakdown`; `ledger.py`/`budget.py` cache token keys; `pricing_snapshot.cache_read_per_mtok`; `operator_visible_warn` on thinking + `max_tokens`. Tests first: `test_anthropic_cache_control.py`, `test_cache_read_pricing.py`, OpenAI/Google/headless golden-body tests (AC-4.4), `tests/unit/cycle-124-cache-telemetry.bats`. → **[G-3]** ⇐ Task 1.2, Task 1.5
- [x] Task 1.7: **Verdict gates (FR-5)** — `_gp_verdict_gate` helper + both call sites in `golden-path.sh` (the audit call site also requires, when the review trailer carries `excluded > 0`, that the audit trailer's `excluded_confirmed` equals it — fail closed; the field lands in Sprint 3 but the gate reads it as 0 when absent); `run-mode/SKILL.md:123,127,203-205`; `sprint-completion.md:67-76`. Tests first: seven new cases in `golden-path-c8-verdict-trailer.bats` (incl. exit-2-empty-stdout fail-closed, legacy preserved, stderr diagnostic), doc-lock test; `c119-c8-consumer-inventory.bats` + `test_golden_path.bats` unmodified and green; the 12 live trailer files re-derived. → **[G-5]** ⇐ none
- [x] Task 1.8: **Live-check scaffold** — `tests/replay/test_cycle124_live_floor.py` (`LOA_RUN_LIVE_TESTS=1`-gated: thinking shape ×4 models, second-call cache read on the BB voice, `GET /v1/models` + `ceiling-probe.py` → `catalog-evidence.md`; the schema-enforced-response case is `skip("lands in Sprint 2")` until Task 2.2, then enabled); wire into `live-floor-check.yml` (`HAS_KEY` env gate, fork note, retries ×2, $5 cap, artifact upload); the exact operator command and the red-result decision rule in the sprint report template; pin the expected pytest skip count. Tests first: the scaffold skips cleanly without the env var (pytest `-rs` shows skip reasons). → **[G-1, G-3]** ⇐ Task 1.6
- [x] Task 1.9: **Rollback proof** — on a scratch branch, `git revert` U3, U0, U1, U2 each in turn and run drift gates + adapter suite + golden-path bats; record results in `grimoires/loa/a2a/sprint-1/rollback-proof.md`. → **[G-2]** ⇐ Task 1.6, Task 1.7
- [x] Task 1.10: **Sprint 1 report + Flatline record** — `grimoires/loa/a2a/sprint-1/sprint-report.md` with `## AC Verification` (file:line per row), the PRD Flatline round-5 record (`flatline-prd.md`) with arbiter decisions, REPO-MAP regen, `just-say-no-to-process-porn-and-ceremony` honesty pass. → **[all]** ⇐ Task 1.8, Task 1.9

### Dependencies
- None on other sprints. Internal order: 1.1 → 1.2 → 1.3 → 1.4 → 1.5 → 1.6 → 1.8; 1.7 parallel; 1.9 after 1.6 + 1.7; 1.10 last.

### Security Considerations
- **Trust boundaries**: `--json-schema` is not in this sprint; `--effort` is an enum; `LOA_COST_LEDGER_PATH` is operator-controlled like `LOA_MODELINV_LOG_PATH`. Catalog values are data, validated by schema and invariant tests.
- **Fences**: none touched. The KF-002 wall is preserved (constant) and the pre-flight ceiling unchanged.
- **Secrets**: `live-floor-check.yml` reads `ANTHROPIC_API_KEY` only from the repository secret; outputs are uploaded as artifacts with MODELINV redaction rules applied (`sanitize_provider_error_message` on any error text).

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Wire-contract assumption wrong (no live run here) | Med | High | body tests pin the reference shape; draft PR + `live-floor-check.yml` merge precondition; values marked `reference` |
| Generated-artifact families drift (bash maps, TS twins, dist, checksum) | Med | Med | one commit; three drift gates run locally before push |
| 64K default breaks a capped non-Anthropic entry on a fallback hop | Low | High | catalog clamp + 16K fallback; AC-2.3 over the live yaml |
| `conftest.py` autouse masks a real env dependency | Low | Med | set-only-if-unset; explicit fallback test |

### Success Metrics
- `pytest .claude/adapters/tests`: 0 failed; new suites green
- `cheval --dry-run --model opus|fable` resolve to the new ids (observed output in the report)
- Production ledgers byte-identical across a full local test run; tripwire green after rotation
- `All good` + `{APPROVED, critical:1}` fixture → not reviewed in `golden-path.sh` (bats)

---

## Sprint 2: Structured outputs

### Sprint Goal
Every JSON-bearing model call is schema-enforced on the voices that support it (Anthropic HTTP `structured_json` entries, `claude-headless`, and — as a flagged exception — the OpenAI dissenter), only `auto`/`none` tool_choice is ever emitted, and the tolerant path with its repair loop remains for unenforced voices until measurement retires it.

### Deliverables
- [x] Five wire schemas under `.claude/schemas/wire/` + `wire-schemas-api-safe.bats` (enum parity)
- [x] `CompletionRequest.output_schema`, cheval `--json-schema`, capability-gated `output_config.format`, derived `schema_enforced`, `claude_headless` `--json-schema` forwarding, `tool_choice` forced modes raise
- [x] `model-adapter.sh` forwarding + `translate_output` flag; `adversarial-review.sh` enforced branch, flag-less repair loop on the unenforced branch, unconditional DEGRADED; `flatline-orchestrator.sh` schema plumbing + `qualify_flatline_content` enforced branch
- [x] Fixture corpus `tests/fixtures/structured-outputs/{kf004,kf023}/`
- [x] OpenAI `text.format` pass-through (isolated commit)
- [x] `repair_loop` key removed from both configs; KF-004 attempt row; `schema_enforced` ratio measured on this host

### Acceptance Criteria
- [x] AC-7.1 … AC-7.5 as written in the PRD
- [x] `check-no-swallowed-jq.sh` green; `flatline-content-qualified-quorum.bats` green (extended)
- [x] MODELINV rows from one local Flatline run and one `/review-sprint` show `schema_enforced: true` on `claude-headless` calls; the ratio one-liner and its output recorded

### Technical Tasks

- [x] Task 2.1: **Wire schemas + lint** — author the five `.wire.json` carrying each persona's complete documented field set; `tests/unit/wire-schemas-api-safe.bats` (valid JSON, object, `additionalProperties:false` + `required` == properties on every node, no unsupported keyword, enum parity with `adversarial-review.sh:712-714,741-743` and `validate_finding :258-263`, persona field-set parity with `.claude/skills/flatline-*/persona.md`). Tests first (RED: files absent). → **[G-4]** ⇐ none
- [x] Task 2.2: **Request field + gated emission + headless forwarding + tool_choice** — `types.py` `output_schema`; `anthropic_adapter.py` gated `output_config.format` (kill-switch aware) + `metadata.schema_enforced` at both result sites; `claude_headless_adapter.py`: probe `--json-schema` support once, forward compact JSON only when supported, prefer `structured_output` over `result`, `schema_enforced` from `structured_output` presence; `_transform_tool_choice` raises on `required`/unknown; update `test_providers.py:215-216`; enable the Sprint-1 live scaffold's schema case. Tests first: `test_anthropic_output_schema.py`, `test_tool_choice_no_forced_modes.py`, stubbed-CLI headless test using the real captured CLI JSON + an older-CLI stub. → **[G-1, G-4]** ⇐ Task 2.1
- [x] Task 2.3: **cheval flag + envelope + model-adapter** — `--json-schema` (read once, ≤ 64 KB, object, else `INVALID_INPUT`), `base_request`/`_entry_request.output_schema`, envelope `schema_enforced` + `output_schema_sha256` into MODELINV; `model-adapter.sh` `--json-schema` arm + forwarding + `translate_output` field. Tests first: `test_cheval_json_schema_flag.py`, `tests/unit/model-adapter-json-schema-forwarding.bats`. → **[G-4]** ⇐ Task 2.2
- [x] Task 2.4: **adversarial-review enforced branch + flag-less repair + DEGRADED** — `invoke_dissenter` schema arg selecting `dissent-${type}.wire.json`; enforced parse (`jq_strict`, `stop_reason` guard, `parse_path`); `CONF_REPAIR_LOOP` removed with the loop kept on the unenforced branch; DEGRADED on `rejected_count > 0` unconditional; metadata `parse_path`/`schema_enforced` + `adversarial-finding.schema.json` `$defs/metadata`; both config keys removed. Tests first: `adversarial-review-schema-enforced.bats`, `adversarial-review-degraded-on-rejection.bats`, `repair-loop-flag-removed.bats`, updated `adversarial-review-repair-loop.bats`. → **[G-4]** ⇐ Task 2.3
- [x] Task 2.5: **Flatline plumbing + qualification branch + corpus** — `call_model` 7th arg after the D3 `if/else`; review/skeptic/scorer sites pass schemas; `run_inquiry` locked unenforced; `qualify_flatline_content` enforced branch; fixture corpus (7 kf004 + 3 kf023 + truncated payload). Tests first: `flatline-call-model-schema.bats`, extended `flatline-content-qualified-quorum.bats`, corpus-driven cases in 2.4's suites. → **[G-4]** ⇐ Task 2.4
- [x] Task 2.6: **OpenAI pass-through (own commit) + measurement + report** — `openai_adapter.py` `text.format` json_schema strict + body test; one local Flatline run + one `/review-sprint`-style dissent call; `jq` ratio one-liner over `.run/model-invoke.jsonl` recorded; `kf-write-lib.sh attempt --id KF-004`; sprint report with `## AC Verification`, REPO-MAP regen, honesty pass. → **[G-4]** ⇐ Task 2.5

### Dependencies
- Sprint 1 (U0 schema fields, `structured_json` tokens, `--effort`/defaults plumbing, ledger isolation).

### Security Considerations
- **Trust boundaries**: `--json-schema` is a file path from trusted scripts; size cap and object check; schema never logged (sha256 only). Model output is data: enforced branch parses strictly, never `eval`s; unenforced branch unchanged.
- **Fences**: `check-no-swallowed-jq.sh` stays green (`jq_strict` everywhere); no fence patterns touched.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Unsupported keyword in a wire schema 400s on a hop | Low | Med | static lint (Task 2.1); hand-authored flat schemas |
| `additionalProperties:false` at the envelope top level rejects a sibling `metadata` block a model used to emit | Low | Low | named in the PR; today's parser ignored it |
| Enum drift between prompt text, wire schema and `validate_finding` | Med | Med | parity test |
| OpenAI hunk rejected by the operator | Med | Low | isolated commit; everything else independent |

### Success Metrics
- Corpus: every enforced payload `rejected_count == 0`, zero sidecar rows; every unenforced legacy shape still rescued
- `grep -rn 'repair_loop\|CONF_REPAIR_LOOP' .claude .loa.config.yaml*` → 0
- `schema_enforced: true` on 100 % of `claude-headless` calls in the local measurement

---

## Sprint 3: Prompt audit and review recall

### Sprint Goal
The always-loaded prompt surface fits the byte budgets with no measured quality loss, review prompts are coverage-first with the mechanical filter doing the filtering, and effort defaults reach the dispatched paths — gated by byte-identical parity goldens and a deterministic A/B over a 10-PR corpus.

### Deliverables
- [x] `tools/check-prompt-budget.sh` (+ resource charging), `tools/prompt-keeplist.txt`, `.github/workflows/check-prompt-budget.yml`; keep-list / provenance / generated-block / constraint-temp / protocol-refs / golden-scope bats
- [x] Arm-A baseline on the Sprint-2 tip; `evals/harness/execute-agent.sh`, `build-review-corpus.sh`, `evals/fixtures/review-prs/pr-01..10`, graders, suite, baseline with `prompt_tree_sha`
- [x] 49-unit prompt audit (reports + patches under `grimoires/loa/a2a/sprint-3/prompt-audit/`), lead gate applied, 13 skills ≤ 16 KB, `CLAUDE.loa.md` ≤ 10 KB (Karpathy kernel + pointer), 3 protocols archived, protocols ≤ 200 KB with per-file residual reported
- [x] Coverage-first block in reviewing-code, auditing-security, flatline-reviewer/skeptic; `verdict-derive.sh` additive `excluded` field; floors and escalation removed
- [x] Effort: frontmatter declarations, `model-adapter.sh resolve_effort()`, Flatline mode → effort, dead example block + TS sample deleted
- [x] Arm B + `compare.sh`; parity `capture.sh --verify` 32/32; reminder-hook one-shot fence test

### Acceptance Criteria
- [ ] AC-8.1 … AC-8.3; AC-9.1 … AC-9.3 as written in the PRD
- [x] `validate-skill-capabilities.sh`, `lint-invariants.sh`, `skill-capabilities.bats`, `skill-includes.bats`, `validation-skill-contracts.bats` green; `generate-constraints.sh`/`generate-skill-includes.sh` dry-run diff empty
- [x] The 10 `*.constraint-XXXXXX` files gone; `no-backup-files.yml` pattern extended

### Technical Tasks

- [x] Task 3.1: **Budget + keep-list + provenance + generated + constraint-temp + protocol-refs gates** — `tools/check-prompt-budget.sh` (`--json`, per-file 16,384 / 10,240, protocols fail 200,000 warn 143,360, unguarded-resource charging); `tools/prompt-keeplist.txt` + `grimoires/loa/a2a/sprint-3/prompt-audit/keep-list.md`; bats: `prompt-budget`, `prompt-audit-keeplist`, `no-history-in-rule-text` (with the KF-pointer exemption), `prompt-audit-generated-blocks`, `no-constraint-temp-files`, `protocol-refs-resolve`, `skill-loop-golden-scope`; delete the 10 twins; `no-backup-files.yml` regex; `check-prompt-budget.yml` with sentinel controls. Tests first (RED on today's tree). → **[G-7]** ⇐ none
- [x] Task 3.2: **Eval executor + corpus + graders** — `evals/harness/execute-agent.sh` at `run-eval.sh:379-380` (gated on `.agent.skill`; `claude -p … --model --effort`; model id recorded; env-isolated); `evals/fixtures/build-review-corpus.sh` + `review-prs/pr-01..10` (8 defect PRs from `fix(...)` commits, ≥ 6 real, + 2 clean; hidden manifest; synthetic ones labelled); **implementation-discipline fixtures** `evals/fixtures/implement-tasks/{01..05}` + graders (test-first, surgical-diff allowlist, zone compliance, tests-pass); `evals/graders/recall-vs-defects.sh`, `verdict-consistency.sh`, `implement-discipline.sh`, allowlist; `evals/tasks/{review-recall,implement-discipline}/*.yaml`, suites; `compare.sh` freshness rule. Tests first: `evals/tests/{execute-agent,recall-baseline-freshness,eval-recall-grader,implement-discipline-grader}.bats`. → **[G-7]** ⇐ none
- [x] Task 3.3: **Arm-A baseline** — `git worktree add` at the Sprint-2 tip (recorded sha; no prompt, eval or corpus change may land between tip selection and capture — the baseline file pins the tree sha and `compare.sh` refuses drift); run the review-recall suite (10 × 3), the audit planted-defect suite and the implementation-discipline suite at fixed effort; write `evals/baselines/{review-recall,implement-discipline}.yaml` with `prompt_tree_sha` + executor model id; commit under `grimoires/loa/a2a/sprint-3/ab/arm-a/`. Must complete **before** any Sprint 3 prompt hunk lands. → **[G-7]** ⇐ Task 3.2
- [x] Task 3.4: **Coverage-first prompts + `excluded` trailer field** — the `### Coverage` block into reviewing-code, auditing-security, flatline-reviewer/skeptic personas; remove `reviewing-code/SKILL.md:96-101` floors and `:155` escalation; `verdict-derive.sh` accepts/validates `excluded` mechanically (critical never excludable; high only with `speculative` + `confidence: low`; APPROVED with `excluded > 0` warns; `--gate audit --review-file` cross-checks `excluded_confirmed`); `_gp_verdict_gate` surfaces the count; frontmatter effort declarations. Tests first: `verdict-observations-section.bats` (both polarities; 0.6-confidence high still counts; `speculative` low high ⇒ excluded; a `speculative` critical ⇒ violation; audit mismatch ⇒ inconsistent). → **[G-7, G-5]** ⇐ Task 3.3
- [x] Task 3.5: **Effort wiring** — `model-adapter.sh resolve_effort()`; `flatline-orchestrator.sh` mode → effort; delete `.loa.config.yaml.example:213-224` + `docs/integration/runtime-contract.md:371-383` sample. Tests first: `effort-dispatch.bats` (stubbed `MODEL_INVOKE`; skill → flag; invalid ⇒ none; byte-identical resolutions; Flatline mapping; `PER_CALL_MAX_TOKENS` still appended). → **[G-7]** ⇐ Task 3.3
- [x] Task 3.6: **49-unit audit run + lead gate** — dispatch one Sonnet subagent per unit as a **read-only agent type** (`loa-scout`/Explore: no Write/Edit tools at all — the mechanical write boundary), ≤ 6 concurrent, each returning the report and the unified diff as structured text; the lead persists them as `<slug>.report.md` + `<slug>.patch` under the audit dir; lead gate per PRD FR-8 (mechanical path allowlist per unit — patches touching fences, hooks, `settings.json`, tool policy or generated files are rejected unread; grep of protected strings; scratch-apply + Task 3.1 bats; reject generated-marker or byte-count-only hunks); keep-list entries for the prose-only constraint classes that have no mechanical twin (agent-network L1–L7 universal invariants, Agent Teams MUST rows, Run Mode state recovery, session-limit capture, beads-first) — they collapse to Reference-Files pointer rows, never delete, and a grep-lock asserts each pointer row survives; apply accepted hunks; provenance footers; 3 protocol archivals (`git mv` + `protocols-summary.md`); `CLAUDE.loa.md` Karpathy kernel + `karpathy-principles.md` receives the rationale + self-description updated; regenerate constraints/skill-includes/REPO-MAP/`checksums.json` rows; update `skill-capabilities.bats`, `skill-includes.bats`, `validation-skill-contracts.bats` expectations. → **[G-7]** ⇐ Task 3.4, Task 3.5
- [x] Task 3.7: **Reminder-hook fence + parity verify** — `reminder-hooks-one-shot.bats` (green by design); `golden/capture.sh --verify` 32/32; all 32 goldens byte-identical (`skill-loop-golden-scope.bats`). → **[G-7]** ⇐ Task 3.6
- [x] Task 3.8: **Arm B + compare** — run the same suites on the audited tree (prompt-diet arm at the fixed effort; effort arm as a second single-variable run); `compare.sh`; results under `grimoires/loa/a2a/sprint-3/ab/arm-b/`; gate per AC-9.2. → **[G-7]** ⇐ Task 3.7
- [x] Task 3.9: **Sprint 3 report** — per-protocol residual table (bytes now vs 143,360 target, what remains and why), follow-up bead for the residual and for the codex `--output-schema` forwarding, `## AC Verification`, honesty pass. → **[all]** ⇐ Task 3.8

### Dependencies
- Sprint 2 landed (the A/B baseline is captured on the Sprint-2 tip).
- Task 3.3 before 3.4/3.5/3.6 (baseline before any prompt hunk).

### Security Considerations
- **Trust boundaries**: audit subagents are read-only and write only under `grimoires/loa/a2a/sprint-3/prompt-audit/`; the lead applies hunks. Fence *documentation* may shrink; fence *patterns* are keep-listed and bats-locked.
- **Eval executor**: `claude -p` with `--allowed-tools Read,Grep,Glob,Write` and `--permission-mode acceptEdits`, cwd = sandbox, ledgers redirected into the sandbox.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Audit deletes load-bearing text | Med | High | keep-list bats, lead gate, parity goldens byte-identical, A/B with clean PRs |
| A/B noise on 10 fixtures | Med | Med | 3 trials, deterministic grader, per-defect recall, clean-PR false-positive rate |
| Protocols cannot reach 140 KB without harm | High | Low | 200 KB gate this cycle; residual reported and filed |
| Session cap interrupts the 49-unit fan-out | Med | Med | ≤ 6 concurrent; resumable per unit (report + patch per file) |

### Success Metrics
- `check-prompt-budget.sh` exit 0; `wc -c` figures in the report
- recall B ≥ A per defect; false positives B ≤ A; audit tokens B ≤ 0.5 × A
- 32/32 goldens byte-identical

### Sprint 3 follow-ups (scope-split, carried out of the cycle)

AC-9.2 is partially met (report §AC-9.2: review recall within tolerance after one iteration; three residual `✗` sub-gates). Each residual is split to a named follow-up task in beads, tracked from here:

| Residual | Follow-up task (bead) | Concrete next action |
|---|---|---|
| Review clean-PR critical+high 0.167 vs baseline 0 (one high-severity finding in one of six clean trials, arm B2) | bd-azrr (implementing-tasks discipline) + a severity-calibration re-measure | widen the review corpus past the two clean PRs, re-run the review suite on the calibrated prompt, and re-read the severity sentence in reviewing-code's Coverage block against the per-trial outputs |
| Audit tokens per call 0.758 of baseline vs the ≤ 0.5 target | bd-gvxy | re-specify the gate against prompt-attributable tokens (`input_tokens` + `cache_creation_input_tokens`) or drop the 0.5 target; cache reads of the diff dominate the call |
| Implement-discipline composite 0/15 in both arms (`test_first` never satisfied), surgical 15/15 → 13/15 | bd-azrr | add at least one fixture where test-first is the natural path (or relax `all_must_pass` for this suite) so the composite can move; decide whether the Karpathy kernel needs an explicit no-scratch-files line |
| Recall grader rewards range citations (anchor ±3) | bd-a4td | credit a citation whose `must_match` string lies within the cited range; record the miss reason per defect |
| **Audit round 1 (2026-09-22) — medium findings, none blocking after HIGH-001 was fixed in-sprint** | | |
| A/B arms measured under an unconfined executor (host allow rules admitted Bash; 30/181 trials wrote to `/tmp`) | bd-vq7v | re-run arms A and B2 under `--restricted --tools` and refresh the baselines; until then the record carries the environment caveat |
| `compare.sh` freshness hashes `SHA256SUMS` itself; `--verify` has no caller; EA-8/9 pollute the dev eval ledger; citation regex can time a trial out instead of scoring 0 | bd-sk1t | `sha256sum -c` inside `check_freshness`; ledger into the test tmpdir; bound the token or score timeouts 0 |
| `check-prompt-budget.sh` passes an empty scan; `--json` hides the protocol warn; workflow lacks `permissions:` | bd-tc3i | exit 2 unless ≥1 SKILL.md, CLAUDE.loa.md and ≥1 protocol scanned; surface `protocols.warn`; `permissions: contents: read` |
| `verdict-derive.sh` accepts integral floats, strips the review marker case-sensitively, scans only uppercase severity words, exits silently on a trailer-less review | bd-zklv | integer-only `trailer_int`; `-i` on strip as on detect; scan the lowercased line; named violation at `:294` |
| Kernel rule "verdict-bearing work NEVER runs on a pinned cheaper model" dropped by the compression | bd-kqz4 | restore at the dispatch step in `PARALLEL-REVIEW.md` / `PARALLEL-SPLIT.md` and keep-list it |
| Agent-network L1–L7 read-before-touch imperative and routing table dropped from the kernel | bd-1ju5 | path-scoped `.claude/rules/agent-network.md`; keep-list row |
| Six low-severity prompt drops (escalation cue, Write-tool-for-source, fence inventory names, trajectory HALT, bridge re-read cue, autonomous clause) | bd-tjkx | decide per item: restore at point of use, widen a `paths:` scope, or record as accepted |
| Input guardrails fail open on orchestrator error (pre-existing design; dissent) | bd-2a9g | decide whether `LOA_RUN_MODE=run` treats orchestrator errors as BLOCK |
| Dissent sidecar truncated per run; reject log prints the post-repair reason (pre-existing; KF-004 recurrence 31) | bd-tdtr | per-run sidecar naming; log both reasons |

---

---

## Sprint 4: Memory gate (final)

### Sprint Goal
Session memory is bounded: the default session-start read is heading-based and capped, appends past 200 KiB are refused with a working escape hatch, rotation is tested, and the memory-tool question is decided in writing.

### Deliverables
- [ ] `.claude/scripts/notes-guard.sh` (`check | read [--full] | rotate`), `tests/fixtures/notes/make-large-notes.sh`
- [ ] `.claude/hooks/safety/notes-size-guard.sh` (+ `settings.json` entry), `FR-NOTES` pattern, `update-notes-learnings.sh` writer gate
- [ ] Readers/docs: `session-continuity.md`, `translating-for-executives/SKILL.md`, `ride-translation.md`, `structured-memory.md`, `context-engineering.md`, `NOTES.md.template`, `hooks-reference.md`; memo `grimoires/loa/reports/2026-09-17-notes-vs-memory-tool.md`

### Acceptance Criteria
- [ ] AC-10.1 … AC-10.3 as written in the PRD
- [ ] `block-destructive-bash.bats` existing cases green unmodified; `notes-template.bats` existing assertions untouched

### Technical Tasks

- [ ] Task 4.1: **`notes-guard.sh` + fixtures** — thresholds as literals; `check` (`--delta`), heading-based `read` with the 69,632 B cap and drift fallback, `rotate` with archive-fsync-then-write and refuse-existing. Tests first: `tests/unit/notes-guard.bats` (the 750 KB ≤ 20k-token headline, non-empty with the three headings, last-session/3-newest selection, drift marker, `--full` byte-identical, rotate round-trip/fsync order/gitignored/refuse-existing/retained < 100 KiB). → **[G-8]** ⇐ none
- [ ] Task 4.2: **Fences + writer gate** — `notes-size-guard.sh` (realpath, direction-aware, hook-guard-wrapped, `settings.json:560` array entry); `FR-NOTES` in `block-destructive-bash.sh`; `update-notes-learnings.sh` `check` before append/rewrite. Tests first: `notes-size-guard.bats` (grow denied / shrink allowed at 250 KiB, other paths exit 0, missing file, symlink/relative/custom dir, fail-open, rotate not blocked), extended `block-destructive-bash.bats` (`FR-NOTES` above/below threshold), writer-gate case in `notes-guard.bats`. → **[G-8]** ⇐ Task 4.1
- [ ] Task 4.3: **Readers, docs, memo, report** — the two live unbounded readers → `read`; `session-continuity.md:129,141`; `structured-memory.md`, `context-engineering.md:14`, `NOTES.md.template` heading, `hooks-reference.md` bypass note; decision memo; extend `notes-template.bats` (thresholds documented; unbounded-`cat` reader set empty); E2E goal validation table (G-1 … G-8, evidence per goal); sprint report + honesty pass; REPO-MAP regen; delete `.run/zone-guard-authorization.json` at cycle end (recorded in the report and PR body). → **[G-8, all]** ⇐ Task 4.2

### Task 4.E2E: End-to-End Goal Validation

| Goal | Validation action | Expected result |
|---|---|---|
| G-1 | run `test_anthropic_thinking.py`, `test_max_tokens_defaults.py`, `cycle-124-effort-flag.bats`, `test_tool_choice_no_forced_modes.py` | all green; `--effort xhigh` dry-run ≥ 64,000 |
| G-2 | `cheval --dry-run --model opus|fable`; drift gates | new ids; gates green |
| G-3 | `cycle-124-cache-telemetry.bats`; eligibility table in the report | cache fields propagate; live scaffold recorded as operator step |
| G-4 | corpus suites + ratio one-liner | 0 rejections on enforced subset; headless ratio 100 % locally |
| G-5 | `golden-path-c8-verdict-trailer.bats` | inconsistent trailer not reviewed |
| G-6 | sha256 of both ledgers before/after the full local suite; tripwire | identical; exit 0 |
| G-7 | `check-prompt-budget.sh`; `capture.sh --verify`; `compare.sh` | exit 0; 32/32; recall/fp/tokens gates met or residual reported |
| G-8 | `notes-guard.bats` headline case | ≤ 20k tokens, non-empty |

### Dependencies
- None functional; sequenced after Sprint 3 to avoid parallel edits to `context-engineering.md`.

### Security Considerations
- **Fences**: `FR-NOTES` is additive; hook is fail-open under `hook-guard.sh`; `rotate` never `git stash`es; archive fsynced before the live file changes.
- **Sensitive data**: NOTES.md is untracked; the archive dir is gitignored; the memo contains no operator content.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Hook mis-targets under a custom grimoire dir | Low | Med | realpath comparison; bats over symlink/relative/custom dir |
| `rotate` loses content | Low | High | archive-then-fsync-then-write; round-trip test |
| Direction-aware delta wrong for `replace_all` edits | Low | Low | occurrence count in the delta; test |

### Success Metrics
- 750 KB fixture → `read` ≤ 70,000 B, non-empty
- 250 KiB fixture: growing edit denied, shrinking edit allowed, `rotate` succeeds

---

## Sprint registration

| Local | Global | Epic bead | Task beads |
|---|---|---|---|
| sprint-1 | 235 | bd-wd1g | 1.1=bd-y0tl, 1.10=bd-72r4, 1.2=bd-5nvw, 1.3=bd-uya0, 1.4=bd-a7f1, 1.5=bd-0j6r, 1.6=bd-lcmv, 1.7=bd-e9wg, 1.8=bd-wq6o, 1.9=bd-s3p7 |
| sprint-2 | 236 | bd-2w21 | 2.1=bd-zeez, 2.2=bd-atr4, 2.3=bd-fyxx, 2.4=bd-xx0z, 2.5=bd-31gy, 2.6=bd-r7jd |
| sprint-3 | 237 | bd-nzvc | 3.1=bd-0h84, 3.2=bd-9eo6, 3.3=bd-cai2, 3.4=bd-ng37, 3.5=bd-s67e, 3.6=bd-k7dr, 3.7=bd-dsbw, 3.8=bd-2gs6, 3.9=bd-4ffi |
| sprint-4 | 238 | bd-ianm | 4.1=bd-m2ml, 4.2=bd-yml9, 4.3=bd-4q6k |

## Flatline record (sprint plan)

| Round | Cohort | Outcome | Integration |
|---|---|---|---|
| 1 (2026-09-17T03:25Z) | opus (claude-headless) + gpt-5.5 (codex-headless), 2/2, cross-scoring degraded | 0 HIGH_CONSENSUS, **8 BLOCKERs** (710–890), 22 medium | Accepted: explicit output budgets at bounded dispatchers + cost-ceiling test + timeout audit (SKP-003); red-live-check decision rule + unrun-check semantics + headless version gate (SKP-002); mechanical `excluded` rules (SKP-004); implementation-discipline A/B arm before the `CLAUDE.loa.md` cut + keep-list entries for the Process Compliance tables and the Karpathy floor (SKP-001 810); ledger-path safety (SKP-003 720); audit-subagent patch allowlist (SKP-007); Sprint-1 live schema case skipped until Sprint 2, pytest skip count pinned, baseline-freeze rule, epic-level bead edges (medium). Recorded, not adopted: moving a live probe ahead of Tasks 1.3–1.6 and a pre-implementation "authoritative provider verification" gate (no credential on this host; the credentialed run is the merge precondition — PRD §7); reordering Sprint 4 before Sprint 3 (kept: Sprint 3's audit should measure the final `context-engineering.md`; both touch it, so they stay sequential). |
| 2 (2026-09-17T05:20Z) | same cohort, 2/2, cross-scoring degraded | 0 HIGH_CONSENSUS, **8 BLOCKERs** (720–870), 26 medium | Folded: no-squash merge rule (SKP-004); ledger writer `O_NOFOLLOW` + threat-model note (SKP-003); `tools/regen-model-artifacts.sh` deterministic regen + idempotence pin (SKP-002); read-only audit agent type as the write boundary (SKP-007); keep-list entries + pointer-row grep-lock for prose-only constraint classes (SKP-002 760); model-not-found chain-walk for new ids (SKP-001 780); audit `excluded_confirmed` cross-check as a hard golden-path requirement (SKP-003 740). Recorded, not adopted: the pre-implementation provider verification gate (SKP-001 870 — fourth restatement; owned by the draft-PR merge precondition, the kill switch and the chain-walk). **Loop closed** at round 2 for the sprint plan: both voices agree on the residual theme and it is not resolvable from this host. |

## Provenance
<!-- provenance: cycle-124 · PRD Flatline rounds 1-5, SDD rounds 1-2, sprint rounds 1-2 (2026-09-17) · design panel wf_dbac0c36-a2b · evidence wf_6da40907-17d · framework-review-2026-09-17 §9 · rec 2 / rec 6 -->
