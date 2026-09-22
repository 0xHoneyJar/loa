# v2.0.0-rc.1 — Model-generation floor (release candidate)

**Pre-release.** First cut of the 2.0 line: it soaks with real users, fixes land as `-rc.N`, and `2.0.0` is promoted when the exit criteria below hold. Stable users can stay on `v1.202.1`.

## What changed

Loa's own use of Claude moves to the Opus 5 / Sonnet 5 / Fable 5.1 generation: per-model output budgets (16K/64K on Anthropic, clamped to the catalog), adaptive thinking on the 4.6+ family, prompt caching, structured outputs for dissent and Flatline, a measured prompt diet (byte budgets on every PR, eval A/B), coverage-first review/audit with enforced verdict trailers, bounded NOTES.md, ledger isolation, Aleph opt-in, and a post-merge pipeline that prepares candidates — pre-releases included — and publishes only an approved digest. Full list: `CHANGELOG.md` `[2.0.0-rc.1]`.

## Breaking, with the switch

| Change | Switch / compat |
|---|---|
| Anthropic `max_tokens` default 4096 → 16K/64K; `--max-tokens 0` refused | `LOA_CHEVAL_LEGACY_WIRE=1`, or explicit `--max-tokens N` |
| Adaptive thinking + block-form `system` on the wire | `LOA_CHEVAL_LEGACY_WIRE=1` (pre-2.0 body, byte-for-byte) |
| `opus` → `claude-opus-5`, `fable` → `claude-fable-5-1` | pin the old id (still in the catalog) |
| `tool_choice: required` / unknown raises | `auto`, `none` or a named tool |
| `repair_loop`, `effort:` config keys removed | delete them; stale keys are ignored |
| Cost ledger default → `.run/cost-ledger.jsonl`; readers fail closed | `LOA_COST_LEDGER_PATH`, `--ledger <old path>` |
| Three protocols archived to `grimoires/loa/archive/protocols/` | read from the archive path |
| NOTES.md 200 KiB block line on growth | `notes-guard.sh rotate` |
| **Aleph opt-in** (`aleph.enabled: false`) | `aleph.enabled: true` before upgrading |
| Pipeline prepares, never auto-publishes | `--publish FILE --approve-sha256 DIGEST` |
| Golden path enforces `LOA-VERDICT` consistency | files without a trailer keep the prose heuristic |

Guide: `docs/migration/v2.0-model-generation-floor.md` · Decisions: `docs/architecture/ADR-004-model-generation-floor.md` · Evidence: `grimoires/loa/reports/breaking-surface-audit-2.0.0-rc.1.md`.

## Operator steps

1. Merge PR #1266 (title keeps `cycle-124`); the pipeline prepares `v2.0.0-rc.1` with `prerelease: true`.
2. Inspect per `grimoires/loa/runbooks/post-merge-candidates.md`, publish with `--publish … --approve-sha256`, confirm **Pre-release** on GitHub.
3. `gh release edit v2.0.0-rc.1 --notes-file grimoires/loa/reports/release-notes-2.0.0-rc.1.md`.

## Soak plan

Two weeks minimum. Downstream mounts upgrade via the migration guide and report issues labelled `2.0.0-rc`; fixes merge to `main` and become `-rc.2`, `-rc.3`, … automatically.

## rc exit criteria (promotion to 2.0.0)

- ≥ 2 downstream mounts upgraded through the migration guide and reported back.
- No CRITICAL or HIGH issue open against the rc for 14 consecutive days.
- `live-floor-check.yml` recorded a pass on `main` or the release branch.
- `check-loa.sh` green on a fresh mount with Aleph absent; `tools/check-prompt-budget.sh` ok.
- Promotion PR: rollup under `## [2.0.0] — <date> — Model-generation floor`, markers at `2.0.0`; the pipeline prepares `2.0.0` with `prerelease: false`.
