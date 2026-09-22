# Sprint 2 implementation report — cycle-124 "model-generation floor" (global sprint-236)

Branch `feature/cycle-124-model-generation-floor`, Sprint 2 range `087fc39e..012d0c5e`. Sprint goal (sprint.md): every JSON-bearing model call is schema-enforced on the voices that support it (Anthropic HTTP `structured_json` entries, `claude-headless`, and — as a flagged exception — the OpenAI dissenter), only `auto`/`none` tool_choice is ever emitted, and the tolerant path with its repair loop remains for unenforced voices until measurement retires it.

## Commits (one per unit, no squash — SDD §7)

| Unit | Commit | Task |
|---|---|---|
| wire schemas + parity lint | `f6646c9e` feat(wire) | 2.1 |
| ledger-lib guard (framework fix found while closing Sprint 1) | `8f6f160c` fix(ledger-lib) | — |
| request field, adapters, tool_choice | `02a79256` feat(adapter) | 2.2 |
| cheval `--json-schema`, envelope, model-adapter | `66792935` feat(cheval) | 2.3 |
| dissent enforced branch, flag-less repair, DEGRADED | `4e60888b` feat(dissent) | 2.4 |
| Flatline plumbing, strict qualification, corpus | `7306f43c` feat(flatline) | 2.5 |
| **OpenAI `text.format` pass-through (isolated, droppable)** | `cdf6768f` feat(openai) | 2.6 |
| `$schema` meta-URI removed + headless retry (live finding) | `0c727a98` fix(wire) | 2.5/2.6 |
| corpus aligned to PRD AC-7.2 | `150868a5` test(fixtures) | 2.5 |
| ledger isolation for indirect spawners (live finding) | `7bd5f35f` fix(tests) | — |
| changelog, reference, KF-004 row, gitignore, repo map | `3b4c03b1` docs(sprint-2) | 2.6 |
| `--json-schema` refuses non-regular paths; live scaffold enforces the real wire schema | `fb7bf705` fix(cheval) | review prep |
| FR7-10 one sidecar per fixture (round-1 dissent DISS-001) | `037dee75` test(dissent) | review |
| trailer detection loose / acceptance strict; six-digit integer cap (late Sprint 1 audit, slice C HIGH+MEDIUM) | `89b41e23` fix(gates) | framework |
| model-id allowlist + associative pre-declaration in the dissent's maps lookup; rawfile dir under the trapped workdir (slice C MEDIUM+LOW) | `68371775` fix(dissent) | framework |
| ledger default `.run/`, hook v2, null-safe cache rates, Opus pins on the floor, probe exit 3, CI positive control, caching table (audit-slice tails) | `012d0c5e` fix(config) | framework |

Local-only artifacts (a2a is gitignored): this report, `adversarial-review.json` (measurement run), the dissent sidecars. Tracked evidence: the MODELINV/cost archives are host-local (`.run/archive/model-invoke-20260918T231348Z.jsonl`, `.run/archive/cost-ledger-20260918T231348Z.jsonl`); their ratio lines are quoted below.

## AC Verification

### AC-7.1 … AC-7.5 as written in the PRD
- **Status**: ✓ Met
- **Evidence**:
  - AC-7.1 body-capture: `.claude/adapters/loa_cheval/providers/anthropic_adapter.py:253` (`output_config.format = {type: json_schema, schema}` iff `structured_json` ∈ capabilities and not legacy wire — effort shares the same object), `:644` (`_schema_enforced(body)`, stamped at both result sites), `:649` (`_transform_tool_choice`: `auto`/`none` only, `required`/unknown raise `InvalidInputError`); `.claude/adapters/loa_cheval/types.py:31` (`output_schema`); `.claude/adapters/tests/test_anthropic_output_schema.py` (8 cases: emission on a `structured_json` entry on both transports, absent without the capability, absent under `LOA_CHEVAL_LEGACY_WIRE`, byte-identical with no schema, effort + format in one object, `metadata.schema_enforced` true/false on the non-streaming AND streaming paths), `.claude/adapters/tests/test_tool_choice_no_forced_modes.py` (2 cases, 8 parametrisations), `.claude/adapters/tests/test_providers.py` (`test_tool_choice_required_raises` — the old pin flipped; no framework caller passed `required`: `grep -rn tool_choice .claude/adapters/cheval.py .claude/scripts` shows none). The gate model in the PRD text (`claude-opus-4-7` carries no `output_config.format`) is exercised through the capability list rather than the id: the catalog gives `structured_json` to fable-5-1/fable-5/opus-5/opus-4-8/sonnet-5/haiku and not to opus-4-7 (`.claude/defaults/model-config.yaml`), and the test's `["chat"]`-only entry is that shape.
  - AC-7.2 corpus: `tests/fixtures/structured-outputs/kf004/` — enforced-valid `review-blocking`, `review-advisory-anchorless`, `audit-critical`, `audit-all-severities`, `findings-empty-clean` (each `rejected_count == 0` and no sidecar row on the enforced path), legacy `legacy-fenced`, `legacy-prose-preamble` (rescued unenforced, `malformed_response` enforced), three `neg-*` drift shapes; `kf023/` — `reviewer-empty-with-reason` (accepted), `reviewer-empty-no-reason` (`schema_invalid`), `reviewer-prose` (`normalization_failed` / `enforced_parse_failed`), two extras; `truncated.json` (`stop_reason: max_tokens`). Hermetic envelopes with `_type`/`_expect` annotations; SYNTHETIC (README). Driven through both parse paths by `tests/unit/adversarial-review-schema-enforced.bats` FR7-10 (11 fixtures) and `tests/integration/flatline-content-qualified-quorum.bats` CQ-E5 (5 fixtures).
  - AC-7.3: `bash tools/check-no-swallowed-jq.sh` → `OK — no output-swallowing jq shapes on the enforced set`; `tests/integration/flatline-content-qualified-quorum.bats` 11/11 (CQ-1..3 unchanged + CQ-E1..E5: enforced prose → `enforced_parse_failed` with `normalize_json_response` stubbed to fail, enforced valid object accepted without normalize, `schema_invalid`, unenforced fenced rescue, corpus); `grep -rn 'repair_loop\|CONF_REPAIR_LOOP' .claude .loa.config.yaml .loa.config.yaml.example` → 0 hits (`tests/unit/repair-loop-flag-removed.bats` RL-1..3); the loop survives unconditionally on the unenforced branch (`.claude/scripts/adversarial-review.sh:1167`, `:1184`) and never runs on the enforced one; `tests/unit/adversarial-review-repair-loop.bats` updated to the flag-less behaviour (18 cases; the flag-OFF cases became the enforced-branch cases) plus `tests/unit/adversarial-review-schema-enforced.bats` (10 cases: strict parse, fenced/preamble/`max_tokens` ⇒ `malformed_response` with `parse_path=schema_enforced`, unenforced rescue, no normalization/repair on enforced, `clean` stamped, `invoke_dissenter` forwards the wire file, caller grep-lock) and `tests/unit/adversarial-review-degraded-on-rejection.bats` (DR-1..4: `_emit_rejection_degraded` at `.claude/scripts/adversarial-review.sh:1645`, unconditional).
  - AC-7.4: MODELINV `schema_enforced` + `output_schema_sha256` emitted only when a schema was requested — `.claude/adapters/cheval.py:2319` (state), `:2429` (emit), `.claude/adapters/loa_cheval/audit/modelinv.py:502` (emitter kwargs; payload schema fields from T1.2, no `writer_version` bump); `.claude/adapters/tests/test_cheval_json_schema_flag.py` (8 cases: canonical sha pinned `4528a3c7…`, bad/oversized/missing files ⇒ `INVALID_INPUT` before dispatch via the CLI, `--dry-run` reports the hash, request threading, envelope true/false/absent, CLI JSON flag); `.claude/scripts/model-adapter.sh:304` (`--json-schema` arm), `:433` (forward), `:556` (`translate_output` `schema_enforced` + `stop_reason`) pinned by `tests/unit/model-adapter-json-schema-forwarding.bats` MA-JS-1..4; `claude_headless_adapter.py:147` (argv `--json-schema <compact>` when the CLI knows the flag — probe `:93`), `:249` (`structured_output` preferred, `schema_enforced` from its presence), `:369` (one unenforced retry on a CLI-side schema rejection) — `.claude/adapters/tests/test_claude_headless_json_schema.py` (9 cases with the CLI JSON captured on this host: `structured_output: {"answer":"PONG","n":42}`, `stop_reason: tool_use`). Ratio one-liner and output: see "Measurement" below.
  - AC-7.5: `tests/unit/wire-schemas-api-safe.bats` W1–W5 (valid JSON/object root; every object node `additionalProperties:false` and `required == properties`; no keyword outside the subset — incl. no `$schema`/`$id` meta keys after the live finding; dissent enums == the prompt's advertised lists, label-anchored, and ⊆ `validate_finding`, marker-anchored at `.claude/scripts/adversarial-review.sh:279`, severities equal; persona field-set parity from each `flatline-*/persona.md` schema block); OpenAI pass-through `.claude/adapters/loa_cheval/providers/openai_adapter.py:435` (`text.format = {json_schema, name, strict: true, schema}`), `:163` (derived flag), `:67` (name = sanitized basename) — `.claude/adapters/tests/test_openai_output_schema.py` (5 cases, 10 parametrisations); the hunk is one commit (`cdf6768f`).

### `check-no-swallowed-jq.sh` green; `flatline-content-qualified-quorum.bats` green (extended)
- **Status**: ✓ Met
- **Evidence**: `bash tools/check-no-swallowed-jq.sh` → OK on the enforced set (both edited scripts are in it); `tests/integration/flatline-content-qualified-quorum.bats` 11/11 — the five CQ-E cases added at `tests/integration/flatline-content-qualified-quorum.bats` exercise `qualify_flatline_content`'s enforced branch (`.claude/scripts/flatline-orchestrator.sh:345`).

### MODELINV rows from one local Flatline run and one `/review-sprint` show `schema_enforced: true` on `claude-headless` calls; the ratio one-liner and its output recorded
- **Status**: ✓ Met
- **Evidence**: one real Flatline review (`flatline-orchestrator.sh --doc grimoires/loa/runbooks/ledger-hygiene-rotation.md --phase spec --skip-knowledge`, 4/4 Phase-1 calls, 2/2 voices, consensus computed) and one real review dissent (`adversarial-review.sh --type review --sprint-id sprint-236` on the Sprint 2 diff, `clean`) on this host, 2026-09-18T23:10–23:13Z. The one-liner
  ```
  jq -r 'select(.payload.schema_enforced != null) | [.payload.calling_primitive, .payload.final_model_id, .payload.transport, (.payload.schema_enforced|tostring)] | @tsv' .run/model-invoke.jsonl | sort | uniq -c
  ```
  printed
  ```
        (corrected 2026-09-21 — late Sprint 2 evidence review; recomputed from the archive with
         `grep '^{' .run/archive/model-invoke-20260918T231348Z.jsonl | jq -r 'select(.payload.schema_enforced != null) | (.payload.final_model_id) + " " + (.payload.schema_enforced|tostring)' | sort | uniq -c`)
              3 anthropic:claude-headless true
             10 openai:codex-headless false   (4 adversarial-review, 2 flatline-review, 2 flatline-skeptic, 1 flatline-score, 1 adversarial-audit)
  i.e. `claude-headless` 3/3 enforced (100 % of the hop that can enforce on this `cli-only` host), `codex-headless` 10/10 unenforced across the archive (the original text said "2/2" — an undercount; the schema is not forwarded to codex/gemini headless — follow-up bead, multi-provider). The rows now live in `.run/archive/model-invoke-20260918T231348Z.jsonl` (rotated per the runbook after this sprint's isolation finding, chain verified `OK 26 entries`; the archive's last line is the `[MODELINV-DISABLED]` rotation seal, so pipe through `grep '^{'` before `jq`). The first measurement run is itself evidence: every `claude-headless` voice failed with `--json-schema is not a valid JSON Schema: no schema with key or ref "https://json-schema.org/draft/2020-12/schema"` until `0c727a98` removed the meta-URI (re-probe: `structured_output` returned).

## Deliverables (sprint.md)

- Five wire schemas + `wire-schemas-api-safe.bats` — `f6646c9e`, `0c727a98`.
- `CompletionRequest.output_schema`, cheval `--json-schema`, capability-gated `output_config.format`, derived `schema_enforced`, `claude_headless` forwarding, `tool_choice` forced modes raise — `02a79256`, `66792935`.
- `model-adapter.sh` forwarding + `translate_output`; `adversarial-review.sh` enforced branch, flag-less repair loop, unconditional DEGRADED; `flatline-orchestrator.sh` plumbing + `qualify_flatline_content` — `66792935`, `4e60888b`, `7306f43c`.
- Fixture corpus — `7306f43c`, `150868a5`.
- OpenAI `text.format` pass-through (isolated commit) — `cdf6768f`.
- `repair_loop` removed from both configs; KF-004 attempt row (`grimoires/loa/known-failures.md:414`); ratio measured — `4e60888b`, `3b4c03b1`, this report.

## Tasks completed

- **2.1** wire schemas (persona-complete field sets, nullable-and-required conditionals) + W1–W5. Design point recorded in NOTES: the prompts advertise 11/12 categories, `validate_finding` accepts 20 — the wire enums follow the prompt and the test asserts ⊆ the validator instead of equality (shrinking the validator would reject broader tags from unenforced voices).
- **2.2** request field; Anthropic emission + derived flag at both result sites; `tool_choice` forced modes raise; headless probe/forward/parse; live scaffold schema case enabled.
- **2.3** `_read_output_schema` (object root, ≤ 64 KB, canonical sha), request threading, envelope + CLI JSON (`schema_enforced`, later `stop_reason`), model-adapter arm/forward/translate.
- **2.4** enforced strict-parse branch (`jq_strict`, `stop_reason=max_tokens` guard), tolerant path unchanged, repair loop flag-less on unenforced, sidecar gains `schema_enforced`/`parse_path`/`stop_reason`, `_emit_rejection_degraded` unconditional, `invoke_dissenter` 7th arg + caller, both config keys removed, `adversarial-finding.schema.json` metadata fields (`:186`).
- **2.5** `call_model` 7th arg appended after the D3 if/else (`.claude/scripts/flatline-orchestrator.sh:930`, `:1019`), 3+3+6 sites pass their schema, `run_inquiry` locked, strict qualification, corpus.
- **2.6** OpenAI pass-through (own commit), measurement, KF-004 row, docs, this report, REPO-MAP regenerated (`7bd5f35f`, `3b4c03b1`). Framework fixes found on the way: `ledger-lib.sh` string-sprint guard (`8f6f160c`, `.claude/scripts/ledger-lib.sh:578`), indirect-spawner ledger isolation (`7bd5f35f`), Flatline `--help` budget text.

## Late Sprint 1 audit findings folded into this range

The Sprint 1 audit's shell-gates slice reported after Sprint 1 was closed (first delivery truncated, second killed by the session cap). Verified by the lead and fixed here rather than reopened there — the Sprint 1 audit file carries an addendum table with the same rows:

| Sev | Finding | Fix | Pin |
|---|---|---|---|
| HIGH | `golden-path.sh` recognised a trailer only by the exact canonical byte string; a tab/NBSP/U+2010 marker fell to the prose heuristic, whose `grep -q APPROVED` matches "NOT APPROVED" (auditor reproduced an audited verdict from a CHANGES_REQUIRED trailer) | `.claude/scripts/golden-path.sh` `_GP_TRAILER_DETECT` (loose detection) + `.claude/scripts/verdict-derive.sh` `TRAILER_CANON` (strict acceptance) — a malformed marker can only deny | `tests/unit/golden-path-c8-verdict-trailer.bats` slice-C HIGH ×2; `tests/unit/verdict-derive.bats` tab-marker case |
| MEDIUM | bash `-gt`/`-ne`/`$((…))` wrap at 2^64 on trailer integers | six-digit cap in `_gp_trailer_int` and `is_num` | both suites' 2^64 cases |
| MEDIUM | `_adv_input_budget_for_model`: an unsourceable maps file left `MODEL_IDS` indexed and bash evaluated `x[$(touch pwned)]` (reproduced) | allowlist `^[A-Za-z0-9._:/-]+$`, `declare -A` pre-declaration, fatal source failure (`.claude/scripts/adversarial-review.sh`) | `tests/unit/adversarial-review-schema-enforced.bats` slice-C MEDIUM |
| LOW ×5 | rawfile dir without trap; CI positive control accepting exit 2; probe partial exit 0; `--help` budget text; doc-lock drift | `68371775`, `012d0c5e`, `0c727a98`, `89b41e23` | reviewed / `test_cycle124_live_floor.py` partial assert |

Slice A/B/D tails (LOWs): system default `metering.ledger_path` → `.run/`; pre-push hook v2 with the hygiene gate documented as always-on; `pricing.py` null-safe cache rates (`.claude/adapters/tests/test_cache_read_pricing.py` last case); the remaining Opus 4.8 pins and the example `opus` alias moved to the floor (`.claude/adapters/tests/test_anthropic_catalog_floor.py::test_advisor_tier_points_at_opus_5`); caching table rows for Opus 4.7 / Sonnet 4.5.

## Testing summary

| Suite | Command | Result |
|---|---|---|
| Adapter pytest | `cd .claude/adapters && python3 -m pytest tests -q -p no:cacheprovider` | 2256 passed, 6 skipped (2203 at Sprint 1 close) |
| Sprint 2 bats | `npx --no-install bats tests/unit/wire-schemas-api-safe.bats tests/unit/model-adapter-json-schema-forwarding.bats tests/unit/flatline-call-model-schema.bats tests/unit/adversarial-review-schema-enforced.bats tests/unit/adversarial-review-degraded-on-rejection.bats tests/unit/repair-loop-flag-removed.bats tests/unit/adversarial-review-repair-loop.bats tests/integration/flatline-content-qualified-quorum.bats tests/unit/cycle-124-live-scaffold.bats tests/unit/cycle-124-dispatch-budgets.bats` | 75/75 (74 + the slice-C subscript case) |
| Gate suites | `tests/unit/golden-path-c8-verdict-trailer.bats` (30), `tests/unit/verdict-derive.bats` (54), `tests/integration/test_golden_path.bats` (47), `tests/unit/c119-c8-consumer-inventory.bats` (12) | green |
| Other adversarial-review + Flatline suites | `tests/integration/adversarial-review-e2e.bats tests/unit/adversarial-review*.bats` (149) and `tests/unit/flatline*.bats tests/integration/flatline*.bats` (202) | green, unchanged |
| Ledger isolation | `tests/unit/ledger-isolation-discovery.bats` (DS-1..4), `tests/unit/ledger-lib.bats` (42) | green |
| Tripwires | `tools/check-no-swallowed-jq.sh`; `tools/check-ledger-hygiene.sh` after rotation | OK |
| Drift gates | `bash tools/regen-model-artifacts.sh --check` | OK (no catalog change this sprint) |

RED-first evidence (scratch worktrees, `scratchpad/red-proof-s2{a,b,c}.sh`): T2.1 — W1/W4/W5 red before the schemas existed; T2.2/2.3 on `f6646c9e` — 29 failed + 8 errors in the new pytest files (cheval rejected `--json-schema`), 3 bats red; T2.4 on `66792935` — 24 bats red (FR7, DR, RL and the re-pinned repair-loop cases); T2.5 on `4e60888b` — CM-1/2/4/5, CQ-E1/E2/E5 red. The OpenAI test file was written against the implemented adapter (body-capture pin), the `$schema` fix was driven by the live failure, and the ledger-lib case reproduced the live `LEDGER_ERROR` before the guard.

## Measurement notes and honesty pass

- The ratio is 100 % on `claude-headless` because it is the only hop on this host that can enforce; the Anthropic HTTP path (`output_config.format`) is unexercised live (no credential) — its shape is pinned by body tests and by the live scaffold's schema case, which the operator's `live-floor-check.yml` dispatch will run.
- `stop_reason` reaches the dissent only through cheval's CLI JSON; the SDD's `stop_reason ∉ {end_turn}` guard is implemented as `max_tokens ⇒ malformed_response` (other stop reasons pass through to the strict parse).
- `repaired_count` is now always present in the dissent envelope (it used to appear only with the flag); the finding schema remains a documentation contract (`additionalProperties:false` on metadata never validated live envelopes, which already carried `rejected_count`).
- Two suites had been writing mock rows into the operator ledgers since before this cycle (found by the tripwire this sprint); fixed and rotated — the archives keep the Sprint 1 rotation's lineage.

## Known limitations / operator items

1. Codex and Gemini headless voices run unenforced (no `--output-schema` forwarding) — follow-up bead (multi-provider, out of scope per the operator prompt).
2. The MODELINV hygiene scanner cannot recognise mock rows that carry real model ids — follow-up bead: stamp mock dispatches in the envelope.
3. Retiring the repair loop is keyed to the measured ratio on unenforced voices (PRD FR-7 item 6); this sprint keeps it.

## Verification steps for the reviewer

1. `cd .claude/adapters && python3 -m pytest tests -q -p no:cacheprovider` — 0 failed.
2. The Sprint 2 bats command above — 74 ok; `bash tools/check-no-swallowed-jq.sh` — OK.
3. `env -u ANTHROPIC_API_KEY python3 .claude/adapters/cheval.py --agent reviewing-code --prompt x --json-schema .claude/schemas/wire/dissent-review.wire.json --dry-run` — JSON with `output_schema_sha256`.
4. `claude -p 'Return {"scores":[]}' --output-format json --tools "" --model opus --json-schema "$(jq -c . .claude/schemas/wire/flatline-scorer.wire.json)"` — `structured_output` present (spends one subscription call).
5. `grep -rn 'repair_loop\|CONF_REPAIR_LOOP' .claude .loa.config.yaml .loa.config.yaml.example` — nothing.

## Addendum — late independent review input (2026-09-21)

The two reviewer trios dispatched during the Sprint 2 review delivered after the sprint closed
(adapters, shell/gates, evidence lenses). Their findings were verified by the lead and folded in
under Sprint 3 as late Sprint 2 input: slice B (shell) in `a1337ed4`, slices A/C (adapters, tests,
evidence) in the following commit; the measurement block above and the KF-004 row were corrected
from the archive (claude-headless 3/3 enforced holds; codex-headless was 10/10 unenforced, not 2/2).
Per-finding disposition: `grimoires/loa/a2a/sprint-236/engineer-feedback.md` §Addendum.
