# Security & Quality Audit — sprint-bug-240: the post-merge pipeline cannot cut a pre-release

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1 lead acting as gate; independent input: cross-model security dissent gpt-5.5-pro over the diff only, no context file — `adversarial-audit.json`, status `clean`, 0 findings, 0 rejected payloads, `verdict_quality.status: APPROVED`)
**Date:** 2026-09-23
**Scope:** working tree over `a20fffeb` — `.claude/scripts/semver-bump.sh`, `.claude/scripts/post-merge-orchestrator.sh`, `.claude/scripts/sync-readme-version.sh`, three bats suites, `grimoires/loa/runbooks/post-merge-candidates.md`, `PROCESS.md`, CHANGELOG `[Unreleased]` line, ledger, regenerated REPO-MAP + checksums
**Prerequisite:** `engineer-feedback.md` reads `All good` (review round 1, trailer consistent: 0/0/1/2, `excluded: 0`)
**Methodology:** Sources → sinks trace over the diff (Phase 1A/1B), independent dissent (1C), five-category pass (Security, Architecture, Code Quality, DevOps; Blockchain n/a)

---

## Executive Summary

The change adds one read of repository-controlled content (the topmost `CHANGELOG.md` heading) to the version computer, threads a boolean derived from the version string through the candidate, the release POST and the read-back, and widens a format guard in the README sync script. Every new input is constrained before use: the heading is extracted by a regex that admits only `[0-9A-Za-z.-]` (`semver-bump.sh:145`), is only ever used behind a fixed `refs/tags/v` prefix in `git rev-parse -q --verify` (`:149`) and as a `jq --arg` value (`:509-510`), and must additionally satisfy the SemVer §9 grammar before it can change `next` (`:152-166`). The `prerelease` boolean is a literal `true`/`false` (`post-merge-orchestrator.sh:1062-1065`, `:1459-1462`) passed with `--argjson`. The README script validates with the same §9 grammar before the value reaches `sed` (`sync-readme-version.sh:57-61`), so the substitution side can never see `|`, `&` or `\`. No guard was weakened: the clean-tree, digest, checkout, origin and push-URL checks are untouched, and the release read-back gained a condition (`:1119-1120`). The dissenter found nothing; my own pass found one medium and two low observations, none blocking.

**Overall Risk Level:** LOW

---

## Phase 1A/1B — Sources and sinks in the diff

| # | Source (trust) | Sink | Guard on the path | Status |
|---|---|---|---|---|
| S1 | `CHANGELOG.md` topmost heading (repository content, same trust class as the commit subjects semver already parses) | `git rev-parse -q --verify "refs/tags/v${heading}"` (`semver-bump.sh:149`) | grep regex restricts to `[0-9A-Za-z.-]` and a fixed shape (`:145`); fixed `refs/tags/v` prefix rules out option injection; a failed lookup means "untagged", never an error | SAFE |
| S2 | same heading | `next` (drives tag name, markers, CHANGELOG heading match) | §9 `prerelease_re` / `release_re` + triple equality with the computed version (`:152-166`) | SAFE |
| S3 | same heading | `jq --arg heading` (`:509-510`) | `--arg` string binding | SAFE |
| S4 | `version` (semver result) | `prerelease` literal → `--argjson` in POST and read-back (`post-merge-orchestrator.sh:1110-1111, 1119-1120`) and candidate (`:1466-1471`) | value is one of two literals | SAFE |
| S5 | approved candidate JSON (`--publish`) | flag/tag consistency check (`:1502-1503`) | digest approval already binds bytes; the new predicate only narrows acceptance | SAFE |
| S6 | `.loa-version.json` `framework_version` (operator file) | `sed` replacement (`sync-readme-version.sh:91-93`) | §9 grammar guard (`:57-61`) excludes every sed-special character | SAFE |
| S7 | bats fixtures | mocked `gh`, temp repositories | no network, no repo writes | SAFE |

---

## Observations

### 1. Architecture — single-changelog assumption

- **MEDIUM** (confidence: medium) `.claude/scripts/semver-bump.sh:141-145` — the transition reads only `${PROJECT_ROOT}/CHANGELOG.md`; the orchestrator's multi-changelog routing (`_discover_changelogs`, issue #697, `post-merge-orchestrator.sh:700-710`) can finalize sibling `*-CHANGELOG.md` files. A downstream repository that keeps its rc heading in a domain changelog gets no transition and the candidate keeps the computed release version — the pre-fix behaviour, not a regression, but the runbook should say "root `CHANGELOG.md`". Loa itself is single-changelog. Suggested follow-up: document in the runbook (done in this round: the runbook names `CHANGELOG.md`), consider `_discover_changelogs` parity later.

### 2. Code Quality — two prerelease grammars

- **LOW** (confidence: high) `.claude/scripts/update-loa-bump-version.sh:213` accepts `([-.][A-Za-z0-9._-]+)?` while `sync-readme-version.sh:57-58` now enforces §9. On the pipeline's path both only ever see a `semver-bump.sh` result, so they cannot disagree; an operator running the bump script by hand with `2.0.0-rc..1` would stamp markers the README check then refuses (`--check` exit 2) — fail-loud, acceptable, noted in `reviewer.md`.

### 3. DevOps — test suite sensitivity to the operator's global git config

- **LOW** (confidence: high) `tests/unit/post-merge-publication.bats:16` — `git tag v1.0.0` (lightweight) fails with `fatal: no tag message?` when the operator's global git config forces annotated/signed tags; on this host that turned the whole suite red and let it be mis-filed as a pre-existing failure. `GIT_CONFIG_GLOBAL=/dev/null` in `setup()` (or `git -c tag.forceSignAnnotated=false -c tag.gpgSign=false tag v1.0.0`) would make the suite hermetic. Outside this fix's diff; recorded as a follow-up bead candidate.

### Cross-Model Security Observations

None — the dissenter returned an empty findings array from a completed run (`adversarial-audit.json`, `metadata.status: clean`, `degraded: false`). Not a degraded review.

---

## Category pass

| Category | Result |
|---|---|
| Security | Every new input constrained before its sink (table above); no new dependency, no network, no secret; read-back strengthened; publication cannot record `DONE` on a mis-flagged release (`post-merge-orchestrator.sh:1119-1122`) |
| Architecture | Transition lives in the single version computer; all consumers inherit `next`; additive JSON fields; candidate `schema_version` unchanged with a tolerant predicate for pre-existing candidates |
| Code Quality | `set -euo pipefail` paths checked: every command substitution that may fail is guarded (`|| return 1`, `if … then`); `bump` classification untouched; `--help` and header comments updated; `bash -n` clean |
| DevOps | 13 new tests, red-first record in `reviewer.md`; 220 passing across 15 release-pipeline suites; REPO-MAP and checksums regenerated and validated; runbook + PROCESS.md updated |
| Blockchain | n/a |

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 2 |

Review demotions confirmed: the review trailer records `excluded: 0`; nothing to confirm (`excluded_confirmed: 0`).

---

## Phase 3 — Verdict

APPROVED - LET'S FUCKING GO

Improvements to carry: multi-changelog parity for the transition (Observation 1), hermetic git config in the publication suite (Observation 3).

## Documentation audit

CHANGELOG `[Unreleased]` entry present; the signal is documented where an operator will look (`grimoires/loa/runbooks/post-merge-candidates.md` §Pre-release candidates, `PROCESS.md` §Versioning Contract, `semver-bump.sh --help`); no secrets or internal URLs. Manually verified — no `documentation-coherence-*` reports exist for this sprint.

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":2},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-bug-240","ts":"2026-09-22T22:20:00Z"} -->
