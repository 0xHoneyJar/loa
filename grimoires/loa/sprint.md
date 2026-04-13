# Sprint Plan: cycle-060 — Lore Promoter

**Cycle**: cycle-060
**PRD**: grimoires/loa/prd.md
**SDD**: grimoires/loa/sdd.md
**Issue**: [#481](https://github.com/0xHoneyJar/loa/issues/481)
**Branch**: feat/cycle-060-lore-promoter
**Date**: 2026-04-13

---

## Cycle Summary

Build `.claude/scripts/lore-promote.sh` — the consumer for `.run/bridge-lore-candidates.jsonl` that promotes vetted PRAISE findings into `grimoires/loa/lore/patterns.yaml`. Closes Gap 1 of the HARVEST phase from RFC-060 `/spiral` design. Interactive mode default; threshold mode for high-confidence patterns; sanitization + merge gating defense-in-depth.

## Sprint 1 — Lore promoter MVP

**Scope**: MEDIUM (5 tasks)
**FRs**: FR-1 through FR-8 (per PRD)
**Goal**: Ship `lore-promote.sh` with crash-consistent two-phase write, journal-as-source-of-truth, sanitization pipeline, BATS test coverage.

### Tasks

| ID | Task | Files | FR | Goal |
|----|------|-------|-----|------|
| T1 | Create `.claude/scripts/lore-promote.sh`. Flag parser (`--queue`, `--lore`, `--interactive`, `--threshold N`, `--dry-run`, `--help`). Strict mode (`set -euo pipefail`). Resolve queue + journal paths; acquire flock on `.run/lore-promote.lock` covering both files. | `.claude/scripts/lore-promote.sh` (new) | FR-1 | G-1 |
| T2 | Queue state machine: load queue, load journal, compute pending = candidate_keys - decided_keys (composite `pr_number:finding_id` per Flatline SDD blocker #4 fix). | Same file | FR-6 | G-1 |
| T3 | Sanitization pipeline: ANSI strip → control-char strip → injection pattern scan → length limits. Reject candidate on any failure with logged reason. | Same file | FR-5, NFR-4 | G-2 |
| T4 | Two-phase write: sanitize → write `patterns.yaml.tmp` → atomic mv → append journal entry. Recovery logic: detect `id` already in `patterns.yaml` but missing journal entry → backfill. ID generation per FR-2.1 (slug + collision suffix). | Same file | FR-2, FR-2.1, NFR-3, FR-8 | G-1 |
| T5 | BATS tests at `tests/unit/lore-promote.bats`. 12 cases per SDD §4: happy-path interactive, reject, skip, idempotency, sanitization rejection, length limits, ID collision, empty queue, missing yaml auto-create, threshold ≥2 PRs floor, unknown flag, crash recovery. | `tests/unit/lore-promote.bats` (new) | — | G-3 |

### Acceptance Criteria

- [ ] `lore-promote.sh` exists, executable, passes `bash -n`
- [ ] Default invocation against synthetic queue produces interactive prompts
- [ ] Threshold mode (`--threshold 2`) auto-promotes patterns from ≥2 distinct merged PRs
- [ ] Sanitization rejects injection patterns; rejection logged with reason
- [ ] ID collision triggers `-<6-char-hash>` suffix; collision unit test passes
- [ ] Re-running the promoter is idempotent (no duplicate `patterns.yaml` entries)
- [ ] Missing `patterns.yaml` auto-created with empty array + comment header
- [ ] Empty queue exits 0 with stderr "no candidates queued"
- [ ] All 12 BATS cases pass
- [ ] Inline usage header lists every flag + exit codes
- [ ] No new package dependencies (uses `bash`, `jq`, `yq`, `flock`, `gh` optional)
- [ ] AC Verification section in `reviewer.md` per cycle-057 gate (#475)

### Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `flock` not available on macOS | Document `brew install util-linux`; fail with clear error if missing |
| `yq` v3 vs v4 incompatibility | Pin to v4 syntax (already Loa hard prereq); test in CI |
| Real candidates queue is empty (no PRAISE findings have flowed yet via post-PR loop) | Synthetic fixtures in BATS suite; manual end-to-end test deferred to once real queue accumulates |
| Threshold mode auto-promotion accidentally fires on adversarial content | NFR-4 defense layers + min-2-merged-PRs floor; interactive default |

### Goals

- **G-1**: Closes the HARVEST loop for PRAISE findings (consumer side)
- **G-2**: Promotion is safe by default — no auto-promotion of unsanitized content from un-merged PRs
- **G-3**: Test coverage prevents silent regression as candidate format evolves

### Dependencies

- `post-pr-triage.sh` (v1.73.0) — produces queue
- `core/lore-loader.ts` (v1.75.0) — consumes patterns.yaml
- `bridge-triage-stats.sh` (v1.79.0) — observes queue state
- `flock`, `yq`, `jq`, `gh` (existing prereqs)

### Zone & Authorization

**System Zone writes**: `.claude/scripts/lore-promote.sh` (new). Cycle-060 authorization.
**State Zone writes**: `grimoires/loa/lore/patterns.yaml` (script output), `grimoires/loa/a2a/trajectory/lore-promote-*.jsonl`.
**Tests** at `tests/unit/lore-promote.bats` (test zone, freely writable).

## AC Verification (per cycle-057 gate)

The `reviewer.md` for this cycle MUST include `## AC Verification` section walking each acceptance criterion verbatim with file:line evidence. Auto-rejection by `/review-sprint` if missing or vague (per #475).

---

*1 sprint, 5 tasks, closes #481, dogfoods cycle-057 AC gate (#475) for the second time*
