# Sprint Plan: Cross-Codebase Feedback Routing

> Cycle: cycle-025 | PRD: grimoires/loa/prd.md | SDD: grimoires/loa/sdd.md
> Source: [#355](https://github.com/0xHoneyJar/loa/issues/355)
> Sprints: 3 | Estimated: ~470 lines across 6 files

## Sprint 1: Attribution Engine + Redaction

**Goal**: Build the core construct attribution and content redaction scripts. These are foundational — everything else depends on them.

### Task 1.1: Create construct-attribution.sh

**File**: `.claude/scripts/construct-attribution.sh`

Create the attribution engine that maps feedback text to installed constructs.

**Acceptance Criteria**:
- [ ] Reads installed constructs from `.constructs-meta.json` via `constructs-lib.sh`
- [ ] Implements weighted signal scoring: path match (1.0), skill name (0.6, word-boundary), vendor name (0.4, word-boundary), explicit mention (1.0)
- [ ] Names < 4 chars excluded from name matching
- [ ] Normalizes confidence to 0.0-1.0 (score / 3.0, capped)
- [ ] Resolves `source_repo` from `manifest.yaml` or `manifest.json`
- [ ] 3-level trust validation: format check, org-match, repo-exists (non-blocking)
- [ ] Handles disambiguation: highest confidence wins, `ambiguous: true` when top-2 within 0.1
- [ ] No-construct fast path: returns `{"attributed": false}` when no constructs installed
- [ ] Exit codes: 0 (success), 1 (invalid input), 2 (corrupt meta)
- [ ] Passes `bash -n`

### Task 1.2: Create feedback-redaction.sh

**File**: `.claude/scripts/feedback-redaction.sh`

Create the content redaction engine for external repo submissions.

**Acceptance Criteria**:
- [ ] Regex-based first pass: strips AWS keys, GitHub tokens, JWTs, generic secrets, absolute paths, env vars, SSH paths, git credentials
- [ ] Entropy-based second pass: flags strings >20 chars with Shannon entropy >4.5 bits/char
- [ ] Allowlist: SHA256 hashes, UUIDs, known URL patterns
- [ ] User toggles from config: `include_snippets`, `include_file_refs`, `include_environment`
- [ ] `--preview` flag shows diff of redacted content
- [ ] Exit codes: 0 (success), 1 (invalid input), 2 (empty output)
- [ ] Passes `bash -n`

### Task 1.3: Define JSON schema contracts (Flatline IMP-001)

Define the authoritative JSON output schemas for inter-script communication.

**Acceptance Criteria**:
- [ ] Attribution output schema defined and documented in script header comment
- [ ] Redaction output schema (stdout text, exit code contract) documented
- [ ] Classifier extended output schema (with `attribution` field) documented
- [ ] Ledger entry schema defined with all fields (repo, fingerprint, timestamp, epoch, issue_url, construct, feedback_type)

### Task 1.4: Add new scripts to syntax check list

**File**: `.claude/tests/hounfour/run-tests.sh`

**Acceptance Criteria**:
- [ ] `construct-attribution.sh` added to `SYNTAX_SCRIPTS` array
- [ ] `feedback-redaction.sh` added to `SYNTAX_SCRIPTS` array
- [ ] Both pass Phase 1 syntax check

## Sprint 2: Classifier Extension + Dedup Ledger

**Goal**: Wire attribution into the existing feedback classifier and add the dedup/rate-limit infrastructure.

### Task 2.1: Extend feedback-classifier.sh with construct category

**File**: `.claude/scripts/feedback-classifier.sh`

**Acceptance Criteria**:
- [ ] New `construct` signal patterns added: `.claude/constructs/` (weight 3), `constructs/skills/` (weight 3), `constructs/packs/` (weight 3)
- [ ] When construct signals detected: calls `construct-attribution.sh`
- [ ] If attribution confidence >= threshold (default 0.33): overrides classification to `construct`
- [ ] Output includes `attribution` object when construct detected
- [ ] `scores` object includes `construct` key (backward compatible — new field)
- [ ] All existing 4-category tests still pass (backward compatibility)
- [ ] When no constructs installed: `construct` score is 0, no attribution object

### Task 2.2: Create feedback-ledger.json management

Implement dedup and rate-limiting logic as functions callable from the feedback command.

**Acceptance Criteria**:
- [ ] `check_dedup(repo, fingerprint)` — returns existing issue URL if duplicate within 24h window
- [ ] `check_rate_limit(repo)` — returns warn/block/ok based on 24h count vs configured thresholds
- [ ] `record_submission(repo, fingerprint, issue_url, construct, feedback_type)` — appends to ledger
- [ ] Uses portable epoch arithmetic (no GNU `date -d`)
- [ ] Atomic writes (write-to-tmp + mv)
- [ ] Creates ledger file if missing
- [ ] Submissions include both `timestamp` (ISO) and `epoch` (Unix) fields

### Task 2.3: Functional tests for attribution and redaction (Flatline IMP-003)

Add test cases to the Hounfour test suite for the new scripts.

**Acceptance Criteria**:
- [ ] Attribution test: path-match input → correct construct + confidence
- [ ] Attribution test: no constructs → `{"attributed": false}`
- [ ] Attribution test: ambiguous match → `ambiguous: true` with candidates
- [ ] Redaction test: input with AWS key → key redacted
- [ ] Redaction test: input with absolute path → path made relative
- [ ] Redaction test: clean input → passes through unchanged
- [ ] Classifier test: construct path in context → `classification: "construct"`
- [ ] Classifier test: no construct path → existing classification (backward compat)

### Task 2.4: Add configuration defaults

**File**: `.loa.config.yaml.example`

**Acceptance Criteria**:
- [ ] `feedback.routing.construct_routing` section added with all config keys
- [ ] Sensible defaults documented inline
- [ ] No changes to existing config structure

## Sprint 3: Feedback Command Integration

**Goal**: Wire everything into the `/feedback` command for the end-to-end user flow.

### Task 3.1: Extend feedback.md Phase 0.5

**File**: `.claude/commands/feedback.md`

**Acceptance Criteria**:
- [ ] When classifier returns `classification: "construct"`:
  - [ ] Runs dedup check, shows "Already filed" if duplicate
  - [ ] Runs rate limit check, shows warning/block as appropriate
  - [ ] Runs `feedback-redaction.sh --preview` on draft content
  - [ ] Displays redacted preview to user
  - [ ] Shows trust warnings prominently if present
  - [ ] Presents routing options: construct repo / loa / project / clipboard
- [ ] When user confirms construct repo routing:
  - [ ] Applies full redaction
  - [ ] Creates issue via `gh issue create` with structured format
  - [ ] Records in dedup ledger
- [ ] When `gh` lacks write access:
  - [ ] Shows clear error message
  - [ ] Offers clipboard fallback
- [ ] All existing non-construct feedback paths unchanged

### Task 3.2: Structured issue format

Embedded in Task 3.1 — the issue body uses the format from SDD section 2.5 (FR-7):
- `[Loa Feedback]` title prefix
- Source, Loa version, pack info, severity
- Redacted description and details
- No code snippets by default
- Footer attribution to Loa Framework

### Task 3.3: End-to-end smoke test

Manual verification:
- [ ] `/feedback` with construct-related context detects construct, shows redacted preview, confirms, files issue
- [ ] `/feedback` with no construct context uses existing 4-repo routing unchanged
- [ ] `/feedback` with construct but no `source_repo` falls back to existing routing
- [ ] `/feedback` with construct but `gh` lacks access offers clipboard fallback
- [ ] Duplicate submission within 24h blocked with "Already filed"

## Dependencies

```
Sprint 1 (attribution + redaction) → Sprint 2 (classifier + ledger) → Sprint 3 (command integration)
```

All sprints are sequential — each builds on the previous.

## Risk Mitigation

| Risk | Sprint | Mitigation |
|------|--------|------------|
| No installed constructs to test with | 1-3 | Create mock construct directory structure for testing |
| `gh` auth varies by user | 3 | Test with both authenticated and unauthenticated gh |
| Vendor repos may not exist yet | 3 | Test clipboard fallback path |
