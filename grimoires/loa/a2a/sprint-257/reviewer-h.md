# Implementation Report: Sprint 257 (cycle-129 Sprint 3) — implementer H, Tasks 3.3 and 3.5

**Date:** 2026-10-14
**Engineer:** implementer H — Opus 5.5 subagent (model id `global.anthropic.claude-opus-5-5`)
**Sprint Reference:** grimoires/loa/sprint.md "## Sprint 3"
**Worktree / base:** `/home/merlin/Documents/thj/code/loa-wt-s3b`, branch `wt/cycle-129-s3b` at `a7682ba4` (not committed, KF-014)
**Patch:** `~/.cache/loa/cycle-129/patches/s3-h.patch`

---

## Executive Summary

Task 3.3 is in place. `adversarial-review.sh` runs `flatline_protocol.{code_review,security_audit}.advisory_voices` after the counted voices, on the same prompt files. The voices run concurrently under one wall clock (`advisory_timeout_seconds`, default 600) and use the same schema, qualification and KF-004 repair rules. Their findings are written only under a top-level `advisory_voices[]` block, and the rest of the envelope is not touched. The bats suite proves that the normalised envelope and the `verdict-derive.sh --json` output are byte-identical with and without advisory voices. An alias that is also in `companion_chain` is refused at plan time with the specified text. The budget pre-check now prices every planned voice through a new `python3 -m loa_cheval.metering.pricing --alias` CLI, with a logged 10 / 30 fallback. The catalog accepts `open_weight`, `price_source` and `price_date`, and a provenance pytest enforces them.

Task 3.5 is in place for my two scripts. Under `hounfour.locality: local_voices`, `adversarial-review.sh` plans only `dispatch_group: local` hops for the primary, companion, advisory and repair roles. Every hosted hop is refused by name at plan time, and the repair chain is pinned to the answering local voice. `flatline-orchestrator.sh` refuses hosted voices and the advisor_strategy scorer route. It drops a hosted tertiary and refuses red-team mode. The DEGRADED sentence is in the config comment, the audit stderr and `metadata.locality.note`. The session-exempt sentence is in `multi-model-reference.md`. The MODELINV fields belong to G, the Bridgebuilder `config.ts` change to I, and the health probe to G. Their contracts are below.

**Key Accomplishments:**
- Advisory voices with a byte-identical counted envelope, `duplicate_of` links, failed and timed-out statuses, and the promotion refusal.
- A catalog-priced budget gate that sums all planned voices, plus the price CLI, catalog provenance and the stale-price WARN with ledger `stale_catalog`.
- `local_voices` planning across dissent and Flatline through one fail-closed classifier (`.claude/scripts/lib/hop-locality.py`).

---

## AC Verification

**AC-3.3**: "bats (mock mode): an advisory voice's findings are present only under `advisory_voices[].findings` with `duplicate_of` links; `jq -S 'del(.advisory_voices)'` of the envelope and the `verdict-derive.sh --json` output are byte-identical with and without the advisory voice; a promotion attempt is refused by name (PRD AC-7.3)"
- Status: `✓ Met`
- Evidence: `.claude/scripts/adversarial-review.sh:3971` `_adv_advisory_block`. It builds `{alias, status, counted_as: "advisory_voice", findings}` and `:4011` tags each finding `voice: "advisory", answered_by: $a, duplicate_of: $dup`. At `:4867` the block is attached as `. + {advisory_voices: $av[0]}` after `verdict_quality`, the fold and the scope are final. The promotion refusal is at `:4297`: `advisory voice ${_av} cannot be counted: no arms report line for the alias (voice arms are a future iteration)`.
- Test: `tests/unit/adversarial-review-advisory.bats:39` ADV-1 checks presence only in the block, the tags, and `duplicate_of` = `DISS-001` or null. `:67` ADV-2 diffs `s3_norm` of both envelopes, each named input, the `verdict-derive.sh --json` output, and the a2a directory listing. `:133` ADV-5 checks the refusal text, exit 1, no call, and no envelope.
- Notes: the comparison is `jq -S 'del(.advisory_voices)'` with the clock-dependent fields deleted (`timestamp`, `ts_utc`, `repair_wall_seconds`; `tests/unit/adversarial-review-s3-helpers.bash` `s3_norm`). Two separate runs differ in those fields with or without advisory voices. This is the "normalised byte-identical comparison" of Appendix D IMP-006.

**AC-3.5**: "The budget gate reads the catalog price and logs the fallback; a zero-priced entry estimates zero and is logged; a non-zero open-weight price without provenance fails the catalog test (PRD AC-7.5)"
- Status: `✓ Met`
- Evidence: `.claude/scripts/adversarial-review.sh:3865` `_adv_budget_estimate` makes one CLI call for every planned voice. It logs `budget: no catalog price for <alias> (<role>) — the fixed 10 / 30 USD per Mtok applies to this voice` and `budget: <alias> (<role>) is zero-priced in the catalog — estimated 0c`. It is called at `:4332` with primary, companion first hop and advisory voices, and `estimate_voices` lands in the `budget_exceeded` envelope at `:4338`. The CLI is `.claude/adapters/loa_cheval/metering/pricing.py:572` `_main`, with `:555` `lookup_alias`. Provenance is read in `_provenance_fields`, the WARN and `stale_catalog` come from `:358` `pricing_source_for`, and the ledger uses it at `.claude/adapters/loa_cheval/metering/ledger.py:170`.
- Test: `tests/unit/adversarial-review-budget.bats:47` BUD-1 (catalog price, 201c, no fallback line), `:60` BUD-2 (fallback logged), `:71` BUD-3 (zero estimates 0c, logged, admitted at a 0c budget), `:84` BUD-4 (sum over voices). `.claude/adapters/tests/test_catalog_pricing_provenance.py:104` covers the live-catalog invariant, and `:128` shows that a non-zero open-weight price without provenance fails.
- Notes: the live catalog has no open-weight row. The invariant holds vacuously today, and fixture cases prove that the check fails when it should.

**AC-3.6**: "Under `local_voices`: no hosted hop in the inventory is planned, each refusal named; the repair chain stays on the declared providers; MODELINV rows carry `locality`; the DEGRADED sentence is present in config and output; the session-exempt sentence is in the docs (PRD AC-8.1 … AC-8.3)"
- Status: `⚠ Partial`. My scripts' share is met. The MODELINV fields and the probe are in G's patch, and the Bridgebuilder hops are I's (see Known Limitations).
- Evidence: the refusal line is logged at `.claude/scripts/adversarial-review.sh:3851` as `locality: local_voices refuses hosted hop $h ($p)`. The filter is applied to the primary at `:4274`, repair `tiny claude-headless` at `:4283`, advisory at `:4306`, the companion at `:4458`, and the budget's companion at `:4326`. The repair pin is at `:689`: under `local_voices` `_repair_chain_base` returns only a local answering voice. The DEGRADED sentence is `:3860` and is logged on audit at `:4285`. `metadata.locality` (refused list and note) is written at `:4849`. In Flatline, `.claude/scripts/flatline-orchestrator.sh:717` `flatline_locality_gate` logs `:737` and refuses the scorer route at `:746`. The gate is called in `main` at `:2521`, and red-team is refused at `:2527`. The config comment is `.loa.config.yaml.example:822`, and the docs sentence is `.claude/loa/reference/multi-model-reference.md:102`.
- Test: `tests/unit/adversarial-review-locality.bats:68` LOC-1 (only the local hop dispatched; four refusals by role), `:91` LOC-2 (repair pinned, even with a key and a pin), `:108` LOC-3 (redaction-style: no hosted hop in CALLS or in any planned hop), `:135` LOC-4 (duplicate_voice; DEGRADED sentence in output and config; the gate and verdict-derive accept the envelope), `:163` LOC-5 (default unchanged), `:210` LOC-8 (docs sentence). `tests/unit/flatline-locality.bats:36` covers FLL-1 to FLL-7.
- Notes: "MODELINV rows carry `locality`" is G's writer change, and I state the contract below. Neither suite can assert it until G's patch is applied.

---

## Tasks Completed

### Task 3.3 — advisory voices, budget gate, catalog provenance

| File | Action | Description |
|------|--------|-------------|
| `.claude/scripts/adversarial-review.sh` | Modified | Config reads at `:233-251`. `_adv_conf_advisory_voices`, `_adv_budget_estimate`, `_adv_run_advisory_voices`, `_adv_advisory_walk`, `_adv_advisory_block` and `_adv_reap_advisory` are new; the reap runs on EXIT, INT and TERM. The fallback-chain build moved before the budget gate unchanged. Plan-time promotion refusal. Advisory run and attach before `write_output` |
| `.claude/adapters/loa_cheval/metering/pricing.py` | Modified | `open_weight`, `price_source` and `price_date` on `PricingEntry`, plus `price_is_stale` and `pricing_source_for` (90 days, WARN once). The CLI is `--alias … [--json] [--catalog] [--config]` |
| `.claude/adapters/loa_cheval/metering/ledger.py` | Modified | `pricing_source` comes from `pricing_source_for` (`stale_catalog`), and `pricing_resolution` is kept for it |
| `.claude/adapters/loa_cheval/metering/rollup.py` | Modified | `stale_catalog` counts as a priced row, not as an unpriced one |
| `.claude/defaults/model-config.yaml` | Modified | Header comment documenting the three provenance fields. No row was added |
| `.claude/schemas/model-config.schema.json` | Modified | `open_weight`, `price_source` and `price_date` on `modelConfig` |
| `.claude/adapters/tests/test_catalog_pricing_provenance.py` | Created | 19 tests: the invariant, the check's own failure cases, freshness, ledger and CLI |
| `.claude/skills/reviewing-code/SKILL.md`, `.claude/skills/auditing-security/SKILL.md` | Modified | One reading sentence each, byte-neutral or smaller (see "Removed skill text") |
| `.loa.config.yaml.example` | Modified | `advisory_voices: []` and `advisory_timeout_seconds: 600` in both blocks, plus the commented `hounfour.advisory_promotion` |
| `tests/unit/adversarial-review-advisory.bats`, `-budget.bats`, `-s3-helpers.bash` | Created | Mock-mode suites |
| `tests/unit/adversarial-review-normalise.bats` | Modified | The NRM-46 argv lint's SMALL allowlist gains the new small operands, each with a reviewed reason |

### Task 3.5 — `hounfour.locality: local_voices`

| File | Action | Description |
|------|--------|-------------|
| `.claude/scripts/lib/hop-locality.py` | Created | Fail-closed classifier: the catalog merged with the project's `hounfour.providers` and `hounfour.aliases`. A hop is local only when its model entry or provider says `dispatch_group: local` and every `fallback_chain` hop is local too |
| `.claude/scripts/adversarial-review.sh` | Modified | `_adv_locality_*`, plan-time refusals for the primary, companion (`locality_refused`), advisory and repair roles, the repair pin, `metadata.locality`, and the DEGRADED sentence |
| `.claude/scripts/flatline-orchestrator.sh` | Modified | `flatline_locality_mode` and `flatline_locality_gate` (memoised), called in `main` before the dry run and in `run_phase1`, `run_phase2` and `run_inquiry`. Red-team mode is refused |
| `.loa.config.yaml.example` | Modified | `hounfour.locality: hosted` with the inventory comment and the DEGRADED sentence |
| `.claude/loa/reference/multi-model-reference.md` | Modified | The session-exempt sentence |
| `tests/unit/adversarial-review-locality.bats`, `tests/unit/flatline-locality.bats` | Created | Planning, redaction-style, DEGRADED, default and invalid-value cases |

**Deviations from plan:**
- The promotion refusal refuses the whole run (exit 1, `advisory_promotion_refused`). It does not quietly keep the alias advisory or counted.
- Under `local_voices`, Flatline refuses red-team mode, because its pipeline plans its own hops. It also refuses the advisor_strategy scorer route, because cheval resolves that tier rather than a declared hop.
- An invalid `hounfour.locality` value refuses the run in both scripts. It does not fall back to hosted.

---

## Technical Highlights

### The envelope shape

With advisory voices configured, the counted envelope is unchanged, and one top-level key is added after `verdict_quality`, `metadata.companion_voice` and `metadata.scope` are final:

```json
"advisory_voices": [
  {"alias": "adv-two", "status": "succeeded", "counted_as": "advisory_voice",
   "findings": [{"id": "DISS-A1-001", "severity": "ADVISORY", "category": "error-handling", "anchor": "x.sh:9-12",
                 "description": "…", "failure_mode": "fm", "anchor_status": "valid",
                 "voice": "advisory", "answered_by": "adv-two", "duplicate_of": "DISS-001"}],
   "rejected_count": 0, "repaired_count": 0, "rejected_summary": [], "cost_usd": 0.002, "exit_code": 0},
  {"alias": "adv-slow", "status": "timed_out", "counted_as": "advisory_voice", "findings": [], …},
  {"alias": "gpt-5.5-pro", "status": "refused", "counted_as": "advisory_voice", "findings": [],
   "error": "locality: local_voices refuses hosted hop gpt-5.5-pro (openai)"}
]
```

- `status` is one of `succeeded`, `failed` (with `error`), `timed_out` or `refused`. None of these enters `voices_planned`, `voices_succeeded`, `verdict_quality`, `findings[]`, `metadata.cost_usd`, `metadata.rejected_*` or the sidecar listing.
- `duplicate_of` links to a counted finding with the same file and category whose anchor line range overlaps. The anchor forms are `file:N` and `file:N-M`. When either side has no line range, the anchors must be equal. Otherwise the field is null.
- An advisory voice's rejected payloads never land beside the envelope, because `LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE=1` is set inside its walker. They are summarised in its own entry, so `verdict-derive.sh` sees exactly the counted run's sidecars.
- The block and the counted envelope travel through files (`--slurpfile`), never argv.

### The locality inventory as implemented

| Hop | Script | Under `local_voices` |
|---|---|---|
| dissent primary + its `fallback_chain` | adversarial-review.sh | hosted hops refused (role `primary`). No local hop left means exit 1, `locality_refused` |
| dissent companion chain (default or `companion_chain`) | adversarial-review.sh | hosted hops refused (role `companion`). An empty chain means `companion_voice {planned: false, reason: locality_refused}` |
| advisory voices | adversarial-review.sh | hosted ones refused (role `advisory`) and listed in the block as `refused` |
| KF-004 repair chain (`tiny`, `claude-headless`, any `LOA_ADVERSARIAL_REPAIR_MODEL` pin) | adversarial-review.sh | refused (role `repair`). The chain is the answering voice when it is local, otherwise empty (`repair_skipped_no_hop`) |
| budget estimate's companion | adversarial-review.sh | the same filter; a refused hop is not priced |
| Flatline primary / secondary | flatline-orchestrator.sh | a hosted one is refused by name and the run exits 1 (`locality_refused`) |
| Flatline tertiary | flatline-orchestrator.sh | a hosted one is refused by name and not planned (2-model) |
| Flatline scorers | flatline-orchestrator.sh | they are the voices. The advisor_strategy scorer route is refused and pinned voices score |
| Flatline red-team mode | flatline-orchestrator.sh | refused whole |
| Bridgebuilder voices, consensus writer | I's `config.ts` | the rule is below |
| health probe | G's `model-health-probe.sh` | implemented by G (`_probe_locality_refused`), same refusal text |
| Claude Code session model | — | exempt (it is the platform) |

Every planned hop is dispatched through cheval: `model-adapter.sh` in dissent, `MODEL_INVOKE` in Flatline. The request-time rules for a local hop live in cheval, which is G's: IP-literal or `localhost` endpoint, no DNS, redirects refused, proxy env ignored, destination in MODELINV. Neither script opens a connection itself.

### MODELINV contract (for G)

Both scripts read `hounfour.locality` from the same `.loa.config.yaml` that cheval loads. They pass no env variable. G confirmed the contract by message. G's writer reads the key from the merged config for `locality_mode` and omits the field for an unknown value. It sets `hop_locality` to `local` when the model entry or its provider block says `dispatch_group: local`, which G aligned with this planner. The one divergence is a `CONFIG_FILE` override of adversarial-review.sh. Cheval still reads the project-root config, which is the case in tests only.

The health probe is G's (`_probe_locality_refused` in G's patch). It uses the same refusal text and does not apply the fallback_chain rule, because the probe checks one model and never walks a chain.

### Security

- The classifier fails closed. An unresolved hop, an unreadable config, a missing interpreter or a local entry whose `fallback_chain` reaches a hosted entry is hosted.
- The classifier runs under `python3 -I` and never imports the package. The price CLI runs with `PYTHONSAFEPATH=1`.
- Advisory aliases are validated like companion hops (`[A-Za-z0-9._/:-]{1,128}`, said by index and tag, never by value). Only the config key is spliced into yq expressions (CMP-150). jq operands are small reviewed scalars (NRM-46).
- The advisory walkers are reaped on EXIT, INT, TERM and the wall clock. The reap goes by pid plus start token (`_adv_is_same`), so a reused pid is never signalled.

---

## Testing Summary

| Test file | Tests | Result |
|---|---|---|
| `tests/unit/adversarial-review-advisory.bats` | 9 | pass |
| `tests/unit/adversarial-review-budget.bats` | 6 | pass |
| `tests/unit/adversarial-review-locality.bats` | 8 | pass |
| `tests/unit/flatline-locality.bats` | 7 | pass |
| `.claude/adapters/tests/test_catalog_pricing_provenance.py` | 19 | pass |
| existing suites | see "Final run" | |

The four new bats suites also passed three consecutive loops before the last lint fixes.

**Final run** (bats from `~/.cache/loa/cycle-128/bats-path`, `LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1`):

All 32 suites passed with 0 failures. The `adversarial-review*.bats` files are 12 suites and 533 tests, including the 284-test companion suite. The `flatline*.bats` files are 18 suites and 202 tests, including flatline-locality. verdict-derive has 75 tests and prompt-budget has 10. Earlier, the first full companion pass failed three of its lints on my code: CMP-121 (an explicit XDG_RUNTIME_DIR export in each suite), CMP-150 (a yq expression spliced from a variable) and CMP-199 (bare `!` negations, which bats never fails on). NRM-46 failed on new jq argv operands. All four were fixed before this final run.

**Other checks:**
- `bash tools/check-prompt-budget.sh`: exit 0. reviewing-code is 16,374 B, down from 16,379, and auditing-security is 16,310 B, down from 16,317. Neither charges a resource.
- `bash .claude/scripts/validate-skill-capabilities.sh`: 37 skills, 37 passed, 0 errors.
- `bash tools/check-no-raw-sha256sum.sh`: OK. `bash tools/check-no-swallowed-jq.sh`: OK. `bash tools/check-knob-readers.sh`: OK.
- `bash .claude/scripts/gen-adapter-maps.sh --check`: matches the YAML.
- The metering and pricing pytests: 195 passed, and 175 passed for the rollup, budget, cost and ledger set. The full adapters pytest gave 3,095 passed and 2 failed. Both failures are in `test_claude_headless_adapter.py`, where `claude` resolves to this host's `claude-fallback` wrapper. That is environmental and in a file I did not touch.

---

## Known Limitations

- **The budget gate can refuse runs that passed before.** It now adds the companion's first hop, priced from the catalog, and each advisory voice. A large diff with a catalog-priced CLI companion (`claude-headless` prices as its `cli_model`, at 10 / 50 USD per Mtok) can exceed the default 150c. The `budget_cents` comments in `.loa.config.yaml.example` still say the gate covers "ONE dissent call" and that the companion is a further call it does not count. That text is outside my blocks, so the lead should change it to "every planned voice: the primary, the companion's first hop and each advisory voice". Fallback hops and the KF-004 repairs are still not counted.
- **The companion estimate skips the agy opt-in filter.** It uses the chain before that filter, so an agy hop that will not be planned is still priced, which overestimates.
- **MODELINV is G's.** No suite here asserts `locality_mode` / `hop_locality` on a row, and that waits for G's writer.
- **Bridgebuilder is I's.** I sent I the exact text and rule (below), and I reports byte-identical classification over ten hops. The probe is done in G's patch.
- **The dissent and Flatline planners trust the working tree's catalog and config.** On a pull request, Bridgebuilder reads the catalog from the trusted base ref. The dissent and Flatline planners read `.claude/defaults/model-config.yaml` and `.loa.config.yaml` from disk. That matches D-7.5, where the local working tree is trusted, because these scripts run on the operator's checkout, not on a PR head in CI. If a later cycle runs dissent in PR CI, it should take the trusted-ref rule from Bridgebuilder.
- **Some refused hops could never have run.** Under `local_voices`, `tiny` and `claude-headless` are always named as refused repair hops, even on a host without an Anthropic key or the CLI. They are inventory hops, so the refusal is stated rather than inferred.
- **The advisory voices delay the run but not the verdict.** They run after the counted voices, so a run can take up to `advisory_timeout_seconds` longer. The verdict and every counted field are final before they start.
- **Advisory voices may trigger repair calls.** An advisory voice on the unenforced path can make KF-004 repair calls, bounded per walker by `ADV_REPAIR_MAX_PER_RUN`. These calls are not in the budget estimate, as for any voice.

---

## Verification Steps

```bash
cd /home/merlin/Documents/thj/code/loa-wt-s3b
BATS=$(cat ~/.cache/loa/cycle-128/bats-path)
LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1 "$BATS" tests/unit/adversarial-review-advisory.bats tests/unit/adversarial-review-budget.bats \
  tests/unit/adversarial-review-locality.bats tests/unit/flatline-locality.bats
LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1 "$BATS" tests/unit/adversarial-review*.bats tests/unit/flatline*.bats tests/unit/verdict-derive.bats tests/unit/prompt-budget.bats
(cd .claude/adapters && python3 -m pytest -q tests/test_catalog_pricing_provenance.py tests/test_pricing*.py)
bash tools/check-prompt-budget.sh; bash .claude/scripts/validate-skill-capabilities.sh
PYTHONPATH=.claude/adapters python3 -W ignore::RuntimeWarning -m loa_cheval.metering.pricing --alias gpt-5.3-codex --alias opus --json
```

---

## Bridgebuilder rule for implementer I (`config.ts`)

Read `hounfour.locality` from the trusted configuration only. On a pull request that is the base branch's `.loa.config.yaml` or repository settings, the same source as D-7.5. A head-only `hounfour.locality: hosted` must never relax a trusted `local_voices`. A missing key means `hosted`, which is today's behaviour. Any other value is refused with:

```
hounfour.locality='<value>' is neither hosted nor local_voices
```

Under `local_voices`, resolve every Bridgebuilder voice model and the consensus writer model through the trusted `hounfour.aliases`, then the catalog, to `provider:model`. Keep a model only if its model entry, or its provider block, has `dispatch_group: local`, and every entry on its own `fallback_chain` is local by the same rule. An unresolved model is hosted. Drop each hosted model and log exactly this, once per model:

```
locality: local_voices refuses hosted hop <alias> (<provider>)
```

Never substitute another model. If no voice is left, fail the configuration with:

```
locality: local_voices leaves no local Bridgebuilder voice — declare a local provider (dispatch_group: local) or set hounfour.locality: hosted
```

The same classification is available as `python3 -I .claude/scripts/lib/hop-locality.py --catalog <model-config.yaml> --config <trusted .loa.config.yaml> -- <model>...`. It prints tab-separated lines of hop, provider, local or hosted, and a reason. The vitest needs four cases: one hosted plus one local voice keeps only the local one and emits the refusal string; a hosted consensus writer is refused; the default config is unchanged; a head-only `locality: hosted` over a trusted `local_voices` is ignored.

---

## Removed skill text (byte-neutral sentences)

**`.claude/skills/reviewing-code/SKILL.md`** gained `Read \`advisory_voices[].findings\` as advisory input, never counted.` (Phase 2.5, on its own line, so the resource pointer line is not charged). Removed:
- `(paths only)` in Phase 1 item 5. `"<changed file paths>"` already says it.
- `(nothing after it)` in the trailer line. "the LAST line" already says it.
- `reported` in "resolve any reported inconsistency".
- `("implemented in src/", "done")` in Automatic CHANGES_REQUIRED. "vague evidence … instead of `file:line` + a specific symbol" still defines it.

**`.claude/skills/auditing-security/SKILL.md`** gained `Read \`advisory_voices[].findings\` as advisory input, never tallied.` (Phase 1C, on its own line). Removed:
- `(do this first)` in the `## Phase -1: Scope` heading.
- `with what you have` in Phase 1B's last sentence.
- `(nothing after it)` in the trailer line.
- `reported` and `to the user` in the self-check sentence.

I first tried removing `(\`/validate\` is optional)` from reviewing-code, then restored it. Without its guard word "optional", the line read as an unguarded read of `resources/REFERENCE.md` and charged 12,815 B. I also restored "actually" in the audit Coverage paragraph, because that paragraph is review-recall prose that the arms measure.

---

## Assumptions

- [ASSUMPTION fact] "Same chunks" means the same `system-prompt.txt` / `user-prompt.txt` of one invocation. The chunk driver calls the script once per chunk (`LOA_ADVERSARIAL_RUN_TAG`), and the script itself does not chunk.
- [ASSUMPTION fact] `dispatch_group` is a model-entry field in the catalog and in the example's local block (D-7.1). The classifier also accepts it on the provider block, as D-8.0 phrases it "a provider that has `dispatch_group: local`".
- [ASSUMPTION fact] The catalog unit is micro-USD per Mtok. The CLI prints the catalog's integers, and the gate divides by 10^10 for cents. Each term is truncated, as the old `bc scale=0` formula was, so a fallback-priced primary estimates exactly what the old gate did.
- [ASSUMPTION fact] G's MODELINV writer reads `hounfour.locality` from the cheval-loaded config. G confirmed this; the proof is in G's patch, not in mine.
- [ASSUMPTION decision] An alias in both `advisory_voices` and the block's `companion_chain` refuses the run at plan time (exit 1, `advisory_promotion_refused`). Silently keeping either role would hide the contradiction.
- [ASSUMPTION decision] An invalid `hounfour.locality` value (for example `local`) refuses the run in both scripts and never falls back to hosted. An operator who wrote a local intent must not get hosted hops.
- [ASSUMPTION decision] Under `local_voices` the repair chain ignores `LOA_ADVERSARIAL_REPAIR_MODEL`, with a WARN. A hosted answering voice gets no repair hop at all.
- [ASSUMPTION decision] Under `local_voices`, Flatline refuses red-team mode and the advisor_strategy scorer route, because their hops are not declared hops this planner can classify.
- [ASSUMPTION decision] A hosted Flatline tertiary is dropped (2-model mode), as the agy opt-in gate does, while a hosted primary or secondary refuses the run.
- [ASSUMPTION decision] `duplicate_of` requires an overlapping line range when both anchors carry one. Otherwise both anchors must be equal strings. The first matching counted finding in envelope order wins.
- [ASSUMPTION decision] Advisory finding ids are renumbered `DISS-A<n>-NNN`, with n the voice's position, so they never collide with counted ids. `answered_by` keeps the alias.
- [ASSUMPTION decision] `stale_catalog` counts as a priced row in `rollup.py`. It is a price, only an old one.
- [ASSUMPTION decision] The NRM-46 allowlist gains only distinctively named variables (`_bv_*`, `_av_*`, two globals). No generic short names were added, because the allowlist is global.

## Process note

I made two edits through a `python3 - <<'EOF'` heredoc in Bash before switching to the Edit tool. One wired `_adv_reap_advisory` into the cleanup and the two traps of adversarial-review.sh. The other fixed a comment in that file. An empty `cat >> … <<'EOF'` was also run once against the advisory suite and appended nothing. Every other file was written with Write or Edit.
