# Implementation Report — sprint-bug-239: Aleph gates block Loa; make Aleph opt-in

**Bug:** 20260922-13a3d1 · **Triage:** `grimoires/loa/a2a/bug-20260922-13a3d1/triage.md` · **Plan:** `grimoires/loa/a2a/bug-20260922-13a3d1/sprint.md`
**Implementer:** Fable 5.1 lead (`/bug`, executed inside PR #1266 on `feature/cycle-124-model-generation-floor`) · **Date:** 2026-09-22 · **Bead:** bd-54ck

## Summary

Aleph is a third-party, vendored component that the Loa maintainer did not author; it must be opt-in and must never constrain Loa. PR #1266 went red because Loa's own capabilities lint added a frontmatter block to the Aleph-managed `loa-aleph/SKILL.md`, and Aleph's digest check sits in a required CI job. The fix puts one opt-in predicate in front of every place Aleph reached into Loa: the mount/update refresh, the health check, the three Aleph test suites and both Aleph workflows. Default is off; `aleph.enabled: true` in `.loa.config.yaml` (or `LOA_ALEPH_ENABLED=1`) restores the previous behaviour unchanged. No Aleph-managed file was touched and the capabilities block stays.

Assumptions (recorded here, Karpathy rule 1): the switch is a config key because "opt-in" has to be an operator choice, not a presence heuristic (the vendored tree is present in every clone); the env override exists so the Aleph suites and CI matrices can still be run deliberately; a missing `yq`, missing config or any non-`true` value reads as disabled (fail closed toward off).

## Changes

| File | Change |
|---|---|
| `.claude/scripts/lib/aleph-opt-in.sh` (new, 40 lines) | `aleph_opt_in_enabled [repo_root]` — env `LOA_ALEPH_ENABLED` (`1|true|yes`) or the bare boolean `true` directly under the top-level `aleph:` key, read with POSIX awk (`:25-40`); no yq: after the audit dissent's second round ("parser absence must never decide the gate") the reader has no optional dependency, so a missing parser cannot silently flip the switch |
| `.claude/scripts/mount-loa.sh:85-88` | the new lib joins the pipe-mode auxiliary download list (`mount-loa-pipe-download-complete.bats` #865 caught the omission in the full run) |
| `.claude/scripts/mount-submodule.sh` | sources the lib beside the other libs with a disabled fallback (`:510-517`); `aleph_refresh_is_applicable` returns 1 unless enabled (`:1379`) — `refresh_copy_set` (`:1421-1423`) and `update-loa.sh` `verify_copyset_gate` (`:226-236`) already route through this predicate, so mount, `--reconcile` and update all skip Aleph |
| `.claude/scripts/check-loa.sh` | sources the lib (`:18-25`); `check_aleph_integrity` runs only when enabled, else logs "Aleph: opt-in disabled … skipped" (`:559-563`) |
| `tests/unit/aleph-release-ingestion.bats`, `aleph-framework-integration.bats`, `aleph-submodule-real-installer.bats` | `setup()` sources the lib and `skip`s unless enabled (`:5-8` each); suites otherwise unchanged |
| `.github/workflows/aleph-bundle-integrity.yml` | `gate` job (`:34-66`) checks out the BASE ref's config on pull requests (`ref: ${{ github.event.pull_request.base.sha || github.sha }}`, `:45-48` — audit dissent round 1: a PR must not be able to flip its own gate) and reads `aleph.enabled` with the same awk as the lib (`:50-66`); `verify` `needs: gate`, `if: needs.gate.outputs.enabled == 'true'` (`:68-69`) |
| `.github/workflows/aleph-release-sync.yml` | same awk `gate` job (`:30-57`; schedule/dispatch on `main`, so it reads `github.sha`); `prepare` `needs: gate` + gated `if` (`:59-60`); `propose` `needs: [gate, prepare]` + gated `if` (`:600-601`) |
| `.loa.config.yaml.example:481-489`, `.loa.config.yaml:585-593` | `aleph: enabled: false` with the rationale comment |
| `tests/unit/aleph-opt-in.bats` (new) | AO-1..AO-7 plus AO-5b (base-ref gate); AO-1 and AO-5 also lock "no yq in the reader" |
| `CHANGELOG.md` Unreleased | entry |
| `grimoires/loa/REPO-MAP.md`, `.claude/checksums.json` | regenerated |

## Test-first record

`tests/unit/aleph-opt-in.bats` before the fix: AO-1, AO-3, AO-4, AO-5, AO-6 red (predicate missing; health check unconditional; suites never skip; workflows ungated; no config key). AO-7 was green already and is the regression lock that Loa's lint stays authoritative. AO-2 first passed vacuously — sourcing the mount script ran its `main` — and was rewritten to load functions with `--source-only` (the pattern the existing Aleph suite uses) and to assert both functions are defined; it then failed for the right reason and passed after the fix. After the fix: 7/7; AO-5b and the two "no yq" assertions were added on the dissent's rounds 1–2 and are green (8/8).

## AC Verification (sprint.md)

### Bug is no longer reproducible — `Shell Tests` and `Verify install` cannot go red on Aleph bytes when `aleph.enabled` is false
- **Status**: ✓ Met
- **Evidence**: the three Aleph suites skip themselves (`tests/unit/aleph-release-ingestion.bats:5-8` etc.; run: 61 tests, 0 `not ok`, 20 `# skip` in the ingestion suite alone — AO-4 asserts it); the integrity workflow's `verify` job is behind `needs: gate` / `if: needs.gate.outputs.enabled == 'true'` (`aleph-bundle-integrity.yml:68-69`; AO-5 asserts every non-gate job in both workflows); this repository sets `aleph.enabled: false` (`.loa.config.yaml:592-593`; AO-6). The digest mismatch itself is untouched and irrelevant while disabled; with `LOA_ALEPH_ENABLED=1` the framework-integration and real-installer suites still run and pass 41/41 (opted-in behaviour unchanged).

### Failing test proves the fix
- **Status**: ✓ Met
- **Evidence**: AO-1 (`tests/unit/aleph-opt-in.bats:33-49`) predicate default / enable / env / malformed / mis-scoped / no-yq; AO-2 (`:51-60`) mount predicate refuses without opt-in on a fixture carrying managed paths and applies with it; AO-3 (`:62-68`) health-check call site is guarded; AO-4 (`:70-79`) suites skip; AO-5 (`:81-96`) workflow gate wiring incl. no-yq reader; AO-5b (`:98-102`) base-ref checkout; AO-6 (`:104-107`) config; AO-7 (`:109-113`) capabilities lint green with the block in place. Red before / green after as recorded above.

### No regressions in existing tests
- **Status**: ✓ Met
- **Evidence**: `mount-submodule-*.bats`, `update-loa-*.bats`, `karpathy-config-schema.bats`, the four suites that read `.loa.config.yaml.example`, `skill-capabilities.bats`, `hook-wiring.bats`: 129/129; `lint-invariants.sh` 10 pass / 2 warn / 0 error (the two warns pre-date the bug); `repo-map-gen.sh --validate` consistent; `check-loa.sh` exit 0 with the new skip line; full `tests/unit/` run recorded in the addendum below.

### Fix addresses root cause (not just symptoms)
- **Status**: ✓ Met
- **Evidence**: no revert of the `capabilities:` block (`.claude/skills/loa-aleph/SKILL.md`, AO-7); no Aleph-managed file edited (`git diff --stat -- .claude/aleph .claude/commands/loa-aleph.md .claude/skills/loa-aleph .loa-aleph.lock.json tools/aleph-release-ingest.py` is empty for this sprint); every Aleph reach-in goes through the one predicate (`mount-submodule.sh:1379`, `check-loa.sh:559`, the three suites, two workflows), so a future Aleph byte change cannot turn a Loa gate red unless an operator opted in.

## Out of scope, noted

- The vendored Aleph tree, the `/loa-aleph` command file and `.loa-aleph.lock.json` stay in the repository, inert. With the opt-in off nothing verifies those bytes any more: Loa's own `.claude/checksums.json` never covered `.claude/aleph/**` or `.claude/skills/loa-aleph/**` (0 entries), and the only way they execute is an explicit `/loa-aleph` invocation. Removing or quarantining the vendored tree is a separate maintainer decision (bead filed in the audit).
- On this host `.loa-aleph.lock.json` is mode 664, which fails Aleph's own pin-mode check when opted in; a host artefact, not a repo change.
- The other two red CI checks on PR #1266 are unrelated to Aleph: `Reject backup-sibling files` counts the eight deleted `.constraint-*` twins (the check diffs without excluding deletions), and `Template Protection` refuses `grimoires/loa/a2a/sprint-*` records in this template repository — both need a maintainer call.

## Addendum — full unit suite and dissent rounds

Full `tests/unit/` (10:15–10:46Z, on the tree before the two dissent-driven refinements): 5,534 cases, 33 red. Against the 38-case pre-Sprint-4 baseline: the 7 `cycle-115 release ingestion` reds are gone (the suite now skips), the 8 time-dependent licence fixtures remain, and two new reds appeared — `#865 every lib/ file sourced by mount-loa.sh or mount-submodule.sh is in the download list` (the new lib was missing from `mount-loa.sh`'s pipe-mode list; fixed at `:88`, `mount-loa-pipe-download-complete.bats` 3/3) and `AO-5` (a yq expression in the test itself; fixed). Both re-run green individually; the rest of the red set is the known baseline. No row was appended to `.run/model-invoke.jsonl` / `.run/cost-ledger.jsonl` by the suite (every row in the window is a `tr-flatline-dissenter-*` dispatch from this bug's own dissent calls).

Audit dissent (gpt-5.5-pro, diff-only, four rounds as the diff evolved): round 1 — HIGH "PR-controlled opt-in gate lets Aleph integrity checks be bypassed" (a PR could flip `aleph.enabled` off in its own head) → the integrity gate now checks out the base ref's config (AO-5b); round 2 — HIGH ×2 "silently disables itself when yq is unavailable" / "bypassed by parser absence" → the reader is POSIX awk in the lib and both gates, no optional parser (AO-1/AO-5 lock it); round 3 — clean on the unchanged diff (a re-run); round 4 (final diff) — HIGH "integrity verification is disabled by default, allowing tampered vendored Aleph payloads to pass CI": accepted by design under the maintainer's directive and dispositioned in the audit (Loa's own System-Zone checksum still covers the vendored files; removing the vendored tree is a separate maintainer decision). All four payloads were dropped by the strict schema and recovered from the sidecars (KF-004 class; `adversarial-rejected-audit.jsonl` per-round copies `adversarial-rejected-audit.round-{1,2,3}.jsonl` and the final round beside this report).
