# Catalog evidence — cycle-124 Sprint 1 Task 1.3 (FR-3 / SDD §2.1, §2.5)

> Tracked here rather than under `grimoires/loa/a2a/sprint-235/` (gitignored as sprint-scoped agent exchange) so the `reference → probed` flips outlive the sprint.

Every Anthropic catalog value changed this cycle, with its provenance.
`reference` = the `claude-api` skill's model table (cached 2026-06-24, read
2026-09-17 on this host). `probed` = confirmed by a live call (`GET
/v1/models` for ids, `tools/ceiling-probe-live.py` for the ceiling, one metered
call for pricing) — **probed wins**. No Anthropic HTTP credential exists on
this host, so nothing is `probed` yet; `.github/workflows/live-floor-check.yml`
(Task 1.4) flips the column when the operator adds `ANTHROPIC_API_KEY`.

| Entry | Value | Source | Note |
|---|---|---|---|
| `claude-fable-5-1` | id exists; 1M ctx / 128K out | reference | new entry; `fable` alias target |
| `claude-fable-5-1` | $10 / $50 per MTok; cache read $0.25 (0.025×) | reference | the documented exception to the 0.1× cache-read rule |
| `claude-fable-5-1` | forced `tool_choice` any/tool ⇒ HTTP 400 | reference | consumed by FR-7 (`tool_choice required` ⇒ `InvalidInputError`) |
| `claude-fable-5` | 1M ctx / 128K out (was 200K / 32K envelope) | reference | pricing unchanged; cache read $1.00 (0.1×) |
| `claude-opus-5` | id exists; 1M / 128K; $5 / $25; cache read $0.50 | reference | new entry; `opus` alias target; adaptive thinking default-on |
| `claude-opus-4-8`, `-4-7`, `-4-6` | 1M / 128K (were 200K / 32K) | reference | 1M context / 128K output on the 4.6+ family |
| `claude-opus-4-8`, `-4-7`, `-4-6`, `claude-sonnet-4-6` | `thinking_adaptive: true` | reference | thinking is OFF unless requested on these; `budget_tokens` 400 on 4.7+ |
| `claude-sonnet-5` | 128K out (was 16K envelope); `thinking_adaptive: true` | reference | default-on server-side; emitted explicitly for chain parity |
| `claude-sonnet-5` | $2 / $10 per MTok; cache read $0.20 | reference | ⚠ the cycle-120 entry carried $3/$15 as the post-2026-08-31 rate; the reference table lists $2/$10 — a metered probe decides. Pricing affects cost accounting only, never routing. |
| `claude-sonnet-4-6` | 1M / 128K (was 200K / 16K); cache read $0.30 | reference | |
| `claude-sonnet-4-5-20250929`, `claude-haiku-4-5-20251001` | 200K ctx unchanged; cache read 0.1× | reference | haiku gains `structured_json` |
| `structured_json` set | fable-5-1, fable-5, opus-5, opus-4-8, sonnet-5, haiku-4-5 | reference | `output_config.format` json_schema; NOT on opus-4-7 / opus-4-6 / sonnet-4-6 |
| every HTTP entry | `effective_input_ceiling: 180000` | kf_derived | streaming-probed KF-002 ceiling (cycle-102 Sprint 4A, Issue #823 replay); `min(180000, ctx − default_max_tokens)` computed per entry; `calibrated_at: null` until `tools/ceiling-probe.py` runs |
| every HTTP entry | v2 `max_input_tokens` / `streaming_*` / `legacy_*` removed | — | the 36K legacy wall is `_LEGACY_TRANSPORT_INPUT_WALL` in cheval (Task 1.4) |
| aliases | `opus → claude-opus-5`, `fable → claude-fable-5-1`; bare self-maps | — | 4-8 self-maps kept (pinnable) |
| `claude-headless` | unchanged (200K, no pricing) | — | `cli_model: fable` — the CLI resolves its own generation |

## How a value flips to `probed`

1. `GET https://api.anthropic.com/v1/models` with the operator's key: every
   id in the first column must appear (`claude-opus-5`, `claude-fable-5-1`
   especially). A missing id is chain-walkable at runtime (HTTP 404 ⇒
   `ProviderUnavailableError`) but must be recorded here as `absent`.
2. `tools/ceiling-probe-live.py --model <id>` (Task 1.8 scaffold): binary-search
   input size under streaming; write `ceiling_calibration.calibrated_at` and
   `source: empirical_probe`.
3. One metered call per priced entry: compare MODELINV `cost_micro_usd`
   against `pricing.*` for the reported usage; a mismatch is a pricing
   correction PR, not a silent edit.
