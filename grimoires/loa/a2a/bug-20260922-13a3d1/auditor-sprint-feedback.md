# sprint-bug-239 Security Audit — Aleph gates block Loa; make Aleph opt-in

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1 lead acting as gate; independent input: diff-only cross-model audit dissent gpt-5.5-pro, four rounds as the diff evolved — every payload the model produced was dropped by the strict schema and recovered from the sidecar, KF-004 class; final round's record `adversarial-audit.json` + `adversarial-rejected-audit.jsonl`)
**Date:** 2026-09-22
**Bug:** 20260922-13a3d1 · **Implementation Report:** `grimoires/loa/a2a/bug-20260922-13a3d1/reviewer.md`
**Scope:** working tree over `5543b413` — one new library, one new test suite, `mount-submodule.sh`, `mount-loa.sh`, `check-loa.sh`, three Aleph test suites, two workflows, two config files, CHANGELOG (SMALL; sequential)
**Review gate:** round 1 APPROVED (`engineer-feedback.md`, 2026-09-22)

---

## Verdict: APPROVED - LET'S FUCKING GO

---

## Executive Summary

The change removes a third-party component from Loa's trust path rather than adding one: with the switch off, no Aleph code runs during mount, update, health check, tests or CI. The predicate takes no model input and no network; it reads one file the repository owns with POSIX awk and an environment variable the operator sets. Two of the dissenter's rounds found real weaknesses in the first cut and both are fixed in the diff under audit: a pull request could have flipped its own gate (the gate now reads the base ref's config), and a runner without `yq` would have silently disabled verification for an opted-in repository (the reader has no optional dependency). The dissenter's final point — that the vendored Aleph bytes are unverified while the switch is off — is true, is the direct consequence of the maintainer's decision, and is recorded as the one medium with a decision bead. No finding blocks.

**Security Issues Found (Phase 2.5 tally):**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 2 |

---

## Phase 1 — Findings

Every item verified by reading the code at the cited line and, where stated, by running it.

### Trust boundaries

- **Predicate inputs** (`.claude/scripts/lib/aleph-opt-in.sh:25-40`): `LOA_ALEPH_ENABLED` (operator environment) and `<repo_root>/.loa.config.yaml` (repository-owned). The awk program is a fixed literal; the file path is quoted; the result is compared to the literal `true`. No `eval`, no command substitution of file content, no network. A flow-form or nested layout reads as disabled — the safe direction. Clean.
- **Gate inputs in CI** (`aleph-bundle-integrity.yml:45-66`): on `pull_request` the gate checks out `github.event.pull_request.base.sha` — the base branch's config, which the PR author does not control — and runs the same awk. `persist-credentials: false`; `permissions: contents: read` unchanged. The `verify` job keeps its own PR-head checkout for the actual verification, as before. The sync workflow is schedule/dispatch on `main` only (`aleph-release-sync.yml:59-60`), so its gate reads `github.sha`. Clean.
- **Fallback direction** (`mount-submodule.sh:512-517`, `check-loa.sh:20-25`): a missing lib defines `aleph_opt_in_enabled() { return 1; }` — disabled, never an unbound function under `set -e`; `update-loa.sh` reaches the predicate only through `aleph_refresh_is_applicable` (`:226-236`), which now returns 1 first (`mount-submodule.sh:1379`). An older submodule that lacks the predicate keeps its previous "verify_aleph=true" compatibility branch, i.e. it still verifies — the conservative side for an opted-in consumer on an old helper. Clean.
- **Tests as a gate surface**: `skip` in `setup()` runs before any fixture is built (`aleph-release-ingestion.bats:5-8` etc.), so the required `Shell Tests` job cannot touch the pin, the bundle or Node when the switch is off. With `LOA_ALEPH_ENABLED=1` the suites run unchanged (41/41 on the two that do not depend on this host's lock-file mode). Clean.

### Data and secrets

- No secrets, tokens or new permissions in the range; `git diff` scanned. `.loa.config.yaml` is tracked here as the template's own config; the added block carries no operator data. Clean.

### Fences and zones

- `git diff -- .claude/hooks .claude/scripts/{zone-write-guard,block-destructive-bash,implement-gate,audit-envelope}.sh .claude/settings.json` is empty. System-Zone edits were made under a re-armed framework-dev marker scoped to this bug; it is deleted when the bug closes. `.claude/checksums.json` and `REPO-MAP.md` regenerated; `repo-map-gen.sh --validate` consistent; `lint-invariants.sh` 0 error.

### Open (counted)

**AUDB-M1 · MEDIUM · `.claude/aleph/**`, `.claude/skills/loa-aleph/**`, `.loa-aleph.lock.json` (230 vendored files)** — with `aleph.enabled: false` (this repository's default) nothing verifies these bytes: the Aleph verifier is gated and Loa's own `.claude/checksums.json` has never listed them (0 entries; `check-loa.sh:64-67` delegates them to Aleph on purpose). A pull request that edits the vendored launcher `.claude/aleph/bin/loa-aleph.mjs` passes every Loa gate; the code executes only on an explicit `/loa-aleph` invocation, so the blast radius is "a user who runs the disabled component", not Loa's paths. Recovered from the dissenter's final-round payload ("tampered vendored Aleph payloads pass CI"). This is the consequence the maintainer chose when making Aleph opt-in, so it is tallied and tracked rather than fixed here: bead bd-c7ma (remove or quarantine the vendored tree, or add the paths to Loa's System-Zone checksum). Confidence high.

**AUDB-L1 · LOW · `.claude/scripts/lib/aleph-opt-in.sh:27-29`** — the environment override accepts `1|true|TRUE|yes`; a stray `LOA_ALEPH_ENABLED=yes` in a CI matrix enables Aleph paths for that job. Documented; the variable name is explicit. Recorded.

**AUDB-L2 · LOW · `.github/workflows/aleph-bundle-integrity.yml:68-69`** — gating `verify` on `gate` changes when the check appears: with the switch off the job is skipped, so the check name is absent from the PR rather than failing. Branch protection does not list it as required (verified: `Template Protection`, `Validate Framework Files`, `Lint Markdown`, `Lint YAML`, `Shell Tests`), so no required-check name goes missing. Recorded for anyone who later marks it required.

### Cross-model dissent record

| Round | Diff state | Result | Disposition |
|---|---|---|---|
| 1 | first cut | HIGH "PR-controlled opt-in gate lets Aleph integrity checks be bypassed" (rejected: missing `failure_mode`; recovered) | fixed — gate reads the base ref's config; AO-5b |
| 2 | after round 1 | HIGH ×2 "silently disables itself when yq is unavailable" / "bypassed by parser absence" (rejected: empty description; titles recovered) | fixed — POSIX awk reader in the lib and both gates, no optional parser; AO-1/AO-5 lock it |
| 3 | re-run, unchanged diff | clean | — |
| 4 | final diff | HIGH "integrity verification is disabled by default; tampered vendored payloads pass CI" (rejected: missing `failure_mode`; recovered) | AUDB-M1 above — accepted consequence of the maintainer's decision; bead bd-c7ma |

### Verified negatives

- Predicate: `LOA_ALEPH_ENABLED=0`, an absent config, a foreign `other: enabled: true`, a quoted `"yes please"` all read as disabled; `aleph: enabled: true` with a trailing comment reads as enabled (AO-1).
- Mount: on a consumer fixture carrying managed Aleph paths, `aleph_refresh_is_applicable` returns 1 without opt-in and 0 with it; both functions are defined after `--source-only` (AO-2).
- Health check: `check-loa.sh` exit 0 and prints `Aleph: opt-in disabled (aleph.enabled: false) — integrity check skipped` (AO-3 grep-locks the call site).
- Workflows: every non-gate job in both files has `needs` containing `gate` and an `if` containing `needs.gate.outputs.enabled == 'true'`; the gate's `run` block contains no `yq` outside comments (AO-5); the integrity gate's checkout `ref` is the PR base sha (AO-5b).
- Bootstrap: `lib/aleph-opt-in.sh` is in `mount-loa.sh`'s pipe-mode download list (`:88`; `mount-loa-pipe-download-complete.bats` 3/3).
- Full unit run: 5,534 cases, 33 red = the 38 baseline minus the 7 Aleph reds (now skipped) plus two caught-and-fixed during the sprint; no production-ledger rows written by the suite (every row in the window is one of this bug's own dissent dispatches, `tr-flatline-dissenter-*`).

## Phase 2.5 — Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 2 |

## Phase 3 — Verdict

APPROVED - LET'S FUCKING GO

Improvements to carry: decide the vendored tree's fate (bd-c7ma) — removing it is the option that fully honours "Aleph never interferes with Loa consumers"; the earlier cycle beads stand.

## Documentation audit

CHANGELOG entry present; the switch is documented at the point of use (`.loa.config.yaml.example:481-489`) and in the lib header; both workflow gates carry an explanatory comment; no secrets or internal URLs. Manually verified — no `documentation-coherence-*` reports exist for this sprint.

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":2},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-bug-239","ts":"2026-09-22T11:05:00Z"} -->
