# Sprint Plan: Multi-Model Adversarial Review Upgrade

**Cycle**: cycle-040
**Sprint**: 1 (single sprint — config/registration + smoke test)
**Version**: 1.1 (post-Flatline review)
**PRD**: `grimoires/loa/prd.md`
**SDD**: `grimoires/loa/sdd.md`
**Depends-On**: [PR #413](https://github.com/0xHoneyJar/loa/pull/413) (**MERGED** — gpt-5.3-codex base + backward-compat aliases)

---

## Sprint Goal

Upgrade the default external model from GPT-5.2 to GPT-5.3-codex across all review/audit/flatline contexts, activate Gemini 2.5 Pro as the Flatline tertiary model, complete Gemini 3 model registration, and add a flatline iteration safety cap of 5.

## Task Breakdown

### T1: Review and merge PR #413
**Priority**: P0 (blocker)
**Acceptance Criteria**:
- PR #413 rigorously reviewed (code correctness, Responses API routing, test coverage)
- Verify: jq fallback chain at `model-adapter.sh.legacy:557-563` correctly parses both API response shapes
- Verify: `validate_model_registry()` passes
- PR #413 merged to main
- `gpt-5.2-codex` → `gpt-5.3-codex` changes from PR #413 are present on main

### T2: Gemini 3 model registration in legacy adapter
**Priority**: P0
**Files**: `.claude/scripts/model-adapter.sh.legacy`
**Acceptance Criteria**:
- `gemini-3-flash` and `gemini-3-pro` added to all 4 maps (MODEL_PROVIDERS, MODEL_IDS, COST_INPUT, COST_OUTPUT)
- Pricing: gemini-3-flash $0.20/$0.80 per MTok, gemini-3-pro $2.50/$15.00 per MTok
- `validate_model_registry()` passes with zero errors
- Confirm `gemini-2.5-pro` already exists in all 4 maps (it does — verified in exploration; this is the model T5 activates)

### T3: Gemini 3 model registration in shim adapter
**Priority**: P0
**Files**: `.claude/scripts/model-adapter.sh`
**Acceptance Criteria**:
- `gemini-3-flash` and `gemini-3-pro` added to MODEL_TO_ALIAS map
- Mapped to `google:gemini-3-flash` and `google:gemini-3-pro`

### T4: Flatline secondary model upgrade
**Priority**: P1
**Files**: `.loa.config.yaml`, `flatline-orchestrator.sh`
**Acceptance Criteria**:
- `.loa.config.yaml` `flatline_protocol.models.secondary` → `gpt-5.3-codex`
- `get_model_secondary()` default → `'gpt-5.3-codex'`

### T5: Gemini tertiary model activation
**Priority**: P1
**Files**: `.loa.config.yaml`
**Acceptance Criteria**:
- `hounfour.flatline_tertiary_model: gemini-2.5-pro` added to `.loa.config.yaml`
- Flatline Phase 1 would produce 6 calls (3 models × 2 modes)
- Flatline Phase 2 would produce 6 cross-scoring calls

### T6: Model-config aliases update
**Priority**: P1
**Files**: `.claude/defaults/model-config.yaml`
**Acceptance Criteria**:
- `reviewer` alias → `openai:gpt-5.3-codex`
- `reasoning` alias → `openai:gpt-5.3-codex`
- All downstream agent bindings (flatline-reviewer, flatline-skeptic, flatline-scorer, flatline-dissenter, gpt-reviewer, reviewing-code, jam-reviewer-gpt, jam-reviewer-kimi) inherit via alias

### T7: GPT review document model update
**Priority**: P1
**Files**: `gpt-review-api.sh`, `gpt-review-integration.md`, `gpt-review.md`
**Acceptance Criteria**:
- `DEFAULT_MODELS` prd/sdd/sprint → `gpt-5.3-codex`
- Protocol doc `documents: "gpt-5.2"` → `documents: "gpt-5.3-codex"`
- Command doc same change

### T8: Red team model update
**Priority**: P1
**Files**: `.loa.config.yaml`
**Acceptance Criteria**:
- `red_team.models.attacker_secondary` → `gpt-5.3-codex`
- `red_team.models.defender_secondary` → `gpt-5.3-codex`

### T9: Flatline iteration cap
**Priority**: P1
**Files**: `.loa.config.yaml`, `flatline-orchestrator.sh`
**Acceptance Criteria**:
- `flatline_protocol.max_iterations: 5` in config
- `get_max_iterations()` function in orchestrator reads this config (default 5)
- Orchestrator logs warning when cap is reached

### T10: Example config mirror
**Priority**: P2
**Files**: `.loa.config.yaml.example`
**Acceptance Criteria**:
- All config changes from T4, T5, T8, T9 mirrored in example config
- Tertiary model shown as commented example with explanation

### T11: Reference documentation update
**Priority**: P2
**Files**: `.claude/loa/reference/flatline-reference.md`, `.claude/protocols/flatline-protocol.md`
**Acceptance Criteria**:
- Model table updated to show 3-model setup
- Config examples updated
- max_iterations documented

### T12: Test fixture updates
**Priority**: P2
**Files**: Test fixtures that reference `gpt-5.2` as default
**Acceptance Criteria**:
- Any test fixtures with hardcoded `gpt-5.2` (non-codex) model defaults updated
- Existing test suites still pass

### T13: End-to-end smoke test (Flatline IMP-003, SKP-002)
**Priority**: P1
**Acceptance Criteria**:
- Run a live 3-model Flatline review against a test document (can use the PRD itself)
- Verify tertiary model (Gemini 2.5 Pro) actually participates: `tertiary-review.json` and `tertiary-skeptic.json` exist and contain valid JSON
- Verify all 6 Phase 2 cross-scoring files are produced
- Verify consensus output includes 3-way scoring
- Run at least one GPT review with `gpt-5.3-codex` for doc phase and verify APPROVED/CHANGES_REQUIRED verdict

### T14: Rollback documentation (Flatline IMP-002)
**Priority**: P2
**Acceptance Criteria**:
- Document single-commit revert strategy: `git revert <commit>` restores all defaults
- Alternative: ordered manual rollback steps for partial revert (e.g., disable tertiary only)

## Dependency Graph

```
T1 (review + merge PR #413)
 └→ T2, T3 (Gemini 3 registration — parallel)
     └→ T4 (flatline secondary)
         └→ T5 (Gemini tertiary)
     └→ T6 (model-config aliases)
         └→ T7 (GPT review docs)
     └→ T8 (red team)
     └→ T9 (iteration cap)
         └→ T10 (example config)
             └→ T11 (reference docs)
                 └→ T12 (test fixtures)
                     └→ T13 (end-to-end smoke test)
                         └→ T14 (rollback docs)
```

## Estimated Size

- **Total files**: ~11-15
- **Total line changes**: ~60-80
- **Complexity**: Low (config + registration + smoke test, minimal new logic)
- **Risk**: Low (all changes have instant rollback via single git revert)
