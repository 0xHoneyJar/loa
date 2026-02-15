# Sprint Plan: BUTTERFREEZONE Pre-Merge Polish — Agent-API Interface Standard

> Cycle: cycle-017 (phase 3 — pre-merge finalization)
> Source: [PR #336](https://github.com/0xHoneyJar/loa/pull/336) iter2 review, Section IX, [#316](https://github.com/0xHoneyJar/loa/issues/316), [#43](https://github.com/0xHoneyJar/loa/issues/43)
> Branch: `feat/cycle-017-butterfreezone-excellence`
> Prior: Phase 1 (sprints 102-109) FLATLINED, Phase 2 (sprints 110-112) FLATLINED
> Goal: Final fixes, enshrine BUTTERFREEZONE as agent-api interface, merge PR #336

## Overview

Single sprint addressing the 3 remaining items from PR #336 feedback before merge:

1. **Substring semantics documentation** — iter2 INFO: document `grep -Fv` substring matching in config example
2. **Protocol version staleness advisory** — Section IX item 1: add version drift detection to validator
3. **Agent-API Interface Standard** — #316 + #43: formally enshrine BUTTERFREEZONE as the cross-repo agent legibility standard

**Team**: 1 engineer (autonomous)

---

## Sprint 8: Pre-Merge Polish — Agent-API Interface Standard

**Global ID**: sprint-113
**Goal**: Address remaining PR #336 feedback, enshrine BUTTERFREEZONE as the agent-api interface standard, regenerate with final HEAD, prepare for merge.

### Task 8.1: Document capability_overrides.suppress Substring Semantics

**Source**: Bridgebuilder iter2 INFO-1
**File**: `.loa.config.yaml.example`

Add a `capability_overrides` section to the butterfreezone config example documenting:
- `suppress` field: list of strings that suppress matching capability lines
- Matching uses `grep -Fv` (fixed-string, substring match — NOT exact match)
- A suppress value of `ci` removes any capability line containing `ci`
- Values are case-sensitive

**Acceptance Criteria**:
- [ ] `capability_overrides.suppress` section exists in butterfreezone config block
- [ ] Comment explains substring matching semantics
- [ ] Example shows suppress usage

### Task 8.2: Protocol Version Staleness Advisory in Validator

**Source**: Bridgebuilder Section IX item 1
**File**: `.claude/scripts/butterfreezone-validate.sh`

Add a staleness check that compares declared ecosystem protocol versions against the actual published npm package version. Uses `npm view @0xhoneyjar/loa-hounfour version` or `gh api` as fallback. This is advisory (WARN, not FAIL) — staleness is informational, not a merge blocker.

**Acceptance Criteria**:
- [ ] Validator checks ecosystem entries for `protocol` field
- [ ] Compares declared version against live npm version (when network available)
- [ ] Logs WARN on version mismatch, not FAIL
- [ ] Graceful skip when network unavailable (no false failures)
- [ ] Test: validator still passes when offline

### Task 8.3: Enshrine BUTTERFREEZONE as Agent-API Interface Standard

**Source**: [#316](https://github.com/0xHoneyJar/loa/issues/316), [#43](https://github.com/0xHoneyJar/loa/issues/43)
**Files**: `docs/architecture/capability-schema.md`, `PROCESS.md`

Formally declare BUTTERFREEZONE as the agent-api interface standard in architectural documentation:

1. Add "Agent-API Interface Standard" section to `docs/architecture/capability-schema.md` explaining:
   - BUTTERFREEZONE.md is the machine-readable project interface for agents
   - Every repo in the ecosystem SHOULD publish BUTTERFREEZONE.md
   - The AGENT-CONTEXT YAML block is the structured data contract
   - The mesh script enables cross-repo capability discovery
   - Relationship to #43 (cross-repo legibility) and #316 (not just a list)

2. Update `PROCESS.md` to reference BUTTERFREEZONE as the standard agent interface

**Acceptance Criteria**:
- [ ] Architecture doc declares BUTTERFREEZONE as agent-api interface standard
- [ ] Cross-repo adoption guidance documented
- [ ] PROCESS.md references the standard
- [ ] Links to #316 and #43 for provenance

### Task 8.4: Regenerate BUTTERFREEZONE.md and Final Validation

**Files**: `BUTTERFREEZONE.md`, `grimoires/loa/ground-truth/checksums.json`

1. Remove stale BUTTERFREEZONE.md to force regeneration
2. Run `butterfreezone-gen.sh` to regenerate with current HEAD SHA
3. Run `butterfreezone-validate.sh --strict` — must pass 17/17
4. Regenerate GT checksums

**Acceptance Criteria**:
- [ ] BUTTERFREEZONE.md regenerated with current HEAD SHA
- [ ] Validator: 17/17 pass (strict mode)
- [ ] GT checksums updated
- [ ] ground-truth-meta `head_sha` matches current HEAD

---

## Post-Sprint: Merge Checklist

After sprint completion:
1. Commit all changes
2. Push to remote
3. Update PR #336 description with final summary
4. Close #316 and #43 with PR #336 reference
5. Merge PR #336
