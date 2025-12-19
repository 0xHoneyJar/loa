# Sprint 3 Implementation Report

**Sprint**: Sprint 3 - Candidate Surfacing
**Implementation Date**: 2025-12-19
**Engineer**: Sprint Task Implementer

---

## Executive Summary

Sprint 3 implements automatic detection and surfacing of ADR and Learning candidates to Linear. This completes the feedback loop from Loa back to Hivemind OS, enabling the organization to capture and review architectural decisions and learnings discovered during development.

**Sprint Completion Status**: All 6 tasks completed

---

## Tasks Completed

### S3-T1: Create Candidate Surfacer Library

**Acceptance Criteria**:
- [x] Document ADR candidate patterns
- [x] Document Learning candidate patterns
- [x] Define extraction format
- [x] Define batch collection approach

**Implementation**:

Created `.claude/lib/candidate-surfacer.md` (951 lines) containing:

1. **ADR Candidate Detection** (lines 20-117)
   - Qualification criteria for ADR candidates
   - Detection patterns: explicit decision statements, trade-off discussions, architecture phase decisions
   - Extraction format (JSON schema)
   - False positive filters and confidence scoring

2. **Learning Candidate Detection** (lines 120-207)
   - Qualification criteria for Learning candidates
   - Detection patterns: discovery statements, pattern emergence, implementation insights
   - Extraction format (JSON schema)
   - False positive filters and confidence scoring

3. **Batch Collection** (lines 210-261)
   - Collection strategy during phase execution
   - In-memory storage structure
   - Ephemeral storage until user approval

4. **Linear Issue Templates** (lines 324-478)
   - ADR Candidate template with proper fields
   - Learning Candidate template with proper fields
   - Linear MCP usage patterns

**Files**:
- Created: `.claude/lib/candidate-surfacer.md` (951 lines)

---

### S3-T2: Implement ADR Candidate Detection

**Acceptance Criteria**:
- [x] Scan SDD output for decision patterns
- [x] Extract: decision statement, alternatives, rationale, trade-offs
- [x] Store candidates in memory during phase
- [x] Handle multiple candidates per phase
- [x] Ignore false positives

**Implementation**:

Added ADR detection implementation flow to candidate-surfacer.md (lines 667-732):

1. **Step-by-step detection process**:
   - Read SDD content after written
   - Pattern matching with regex patterns
   - Extract candidate data from surrounding context
   - Score candidates using confidence scoring
   - Filter low confidence (score < 2)
   - Store for batch review

2. **Detection Patterns**:
   ```
   - /We decided to use (.+) instead of (.+)/i
   - /Choosing (.+) over (.+) because (.+)/i
   - /After evaluating.* we selected (.+)/i
   - /The decision is to (.+)/i
   - /Going with (.+) rather than (.+)/i
   - /Trade-off.* (.+) vs (.+)/i
   - /Pros and cons of (.+)/i
   - /Considered alternatives:/i
   ```

3. **Confidence Scoring**:
   - +2 if explicit decision language
   - +2 if alternatives discussed
   - +1 if trade-offs documented
   - +1 if cross-component impact
   - -1 if minor/localized
   - -2 if no rationale

**Files**:
- Modified: `.claude/lib/candidate-surfacer.md` (added lines 667-732)

---

### S3-T3: Implement Learning Candidate Detection

**Acceptance Criteria**:
- [x] Scan implementation reports and review feedback for patterns
- [x] Extract: pattern description, context, evidence
- [x] Store candidates in memory during phase
- [x] Link to relevant code/tests when possible

**Implementation**:

Added Learning detection implementation flow to candidate-surfacer.md (lines 736-811):

1. **Step-by-step detection process**:
   - Read reviewer.md or engineer-feedback.md after written
   - Pattern matching with learning-specific patterns
   - Extract pattern, context, evidence, recommended application
   - Score candidates
   - Filter low confidence (score < 2)
   - Store for batch review

2. **Detection Patterns**:
   ```
   - /We discovered that (.+) works better/i
   - /This approach proved more effective (.+)/i
   - /Lesson learned: (.+)/i
   - /Key insight: (.+)/i
   - /Found that (.+) solves (.+)/i
   - /This pattern emerged (.+)/i
   - /The successful approach was (.+)/i
   - /What worked well: (.+)/i
   - /This technique consistently (.+)/i
   - /Recommended approach: (.+)/i
   ```

3. **Confidence Scoring**:
   - +2 if explicit learning language
   - +2 if file/line references
   - +1 if measurable outcomes
   - +1 if cross-project applicability
   - -1 if single instance only
   - -2 if no evidence

**Files**:
- Modified: `.claude/lib/candidate-surfacer.md` (added lines 736-811)

---

### S3-T4: Implement Batch Review UX

**Acceptance Criteria**:
- [x] After phase completion, display candidate summary
- [x] Show count: "2 ADR candidates, 1 Learning candidate"
- [x] Options: [Submit all] [Review first] [Skip]
- [x] Non-blocking: phase is already complete

**Implementation**:

Added Batch Review implementation to candidate-surfacer.md (lines 815-882):

1. **AskUserQuestion Integration**:
   - When candidates exist, use structured question format
   - Options: "Submit all to Linear", "Review each first", "Skip for now"
   - Non-blocking design

2. **Review Mode Flow**:
   - For each candidate, prompt Include/Exclude
   - Build submission batch based on user choices

3. **Skip Behavior**:
   - Candidates discarded
   - No persistent storage
   - Phase proceeds normally

**Example Prompt**:
```json
{
  "question": "2 ADR candidates and 1 Learning candidate detected. What would you like to do?",
  "header": "Candidates",
  "options": [
    { "label": "Submit all to Linear", "description": "Create Linear issues for team review (Recommended)" },
    { "label": "Review each first", "description": "Review each candidate before submitting" },
    { "label": "Skip for now", "description": "Discard candidates and continue" }
  ]
}
```

**Files**:
- Modified: `.claude/lib/candidate-surfacer.md` (added lines 815-882)

---

### S3-T5: Implement Linear Issue Creation

**Acceptance Criteria**:
- [x] Use Linear MCP to create issues
- [x] ADR Candidate template with proper labels
- [x] Learning Candidate template with proper labels
- [x] Use Product Home project ID from integration-context.md
- [x] Handle Linear unavailable: save to pending-candidates.json

**Implementation**:

Added Linear Submission implementation to candidate-surfacer.md (lines 886-947):

1. **Submission Flow**:
   - Read integration-context.md for team ID
   - Check/create labels (`adr-candidate`, `learning-candidate`)
   - Create issues with proper templates
   - Handle failures with fallback

2. **ADR Issue Structure**:
   - Title: `[ADR-Candidate] {decision summary}`
   - Labels: `adr-candidate`, `sprint:{current-sprint}`, `agent:architect`
   - Body: Full ADR template

3. **Learning Issue Structure**:
   - Title: `[Learning-Candidate] {pattern summary}`
   - Labels: `learning-candidate`, `sprint:{current-sprint}`, `agent:implementer`
   - Body: Full Learning template

4. **Fallback Handling**:
   - Save to `loa-grimoire/pending-candidates.json`
   - Show message with retry instructions
   - Non-blocking continuation

**Files**:
- Modified: `.claude/lib/candidate-surfacer.md` (added lines 886-947)

---

### S3-T6: Extend `/architect` Command with Surfacing

**Acceptance Criteria**:
- [x] After SDD written, run ADR candidate detection
- [x] Show batch review prompt
- [x] If approved, create Linear issues
- [x] Log surfacing results to analytics
- [x] Continue to next phase (non-blocking)

**Implementation**:

Extended `.claude/commands/architect.md` with Phase Post-SDD (lines 194-277):

1. **Step 1: Scan SDD for Decision Patterns**
   - Decision patterns documented
   - Trigger keywords listed

2. **Step 2: Extract ADR Candidates**
   - Decision, context, alternatives, rationale, trade-offs

3. **Step 3: Apply Confidence Filter**
   - Scoring system documented
   - Keep candidates with score >= 2

4. **Step 4: Show Batch Review**
   - AskUserQuestion integration
   - Three options documented

5. **Step 5: Handle User Response**
   - Submit all: Create Linear issues
   - Review first: Per-candidate prompts
   - Skip: Discard and continue

6. **Step 6: Continue to Sprint Planning**
   - Non-blocking completion

Also extended `/implement` command with Phase 5.5 for Learning candidate surfacing:
- Foreground section: lines 526-591
- Background section: lines 245-254

**Files**:
- Modified: `.claude/commands/architect.md` (added lines 109-118 background, 194-277 foreground)
- Modified: `.claude/commands/implement.md` (added lines 245-254 background, 526-591 foreground)

---

## Technical Highlights

### Non-Blocking Design

All candidate surfacing is non-blocking:
- Phase completes normally first
- Candidates presented after phase output saved
- User choice doesn't affect phase success
- Linear failures don't block workflow

### Confidence Scoring System

Implemented a scoring system to filter false positives:
- Explicit language patterns: +2
- Evidence/alternatives: +2
- Trade-offs/outcomes: +1
- Cross-scope impact: +1
- Minor/localized: -1
- Missing rationale/evidence: -2

Threshold: score >= 2 to pass

### Fallback Handling

Graceful degradation for Linear failures:
- Save to `loa-grimoire/pending-candidates.json`
- Clear error message with retry instructions
- Phase continues without blocking

---

## Testing Summary

No automated tests for this sprint - implementation is documentation/patterns for agents to follow. Manual verification:

1. **Pattern matching**: Tested against SDD section 2 (Architecture Decisions Summary)
   - 5 decisions detected with proper structure

2. **Batch review flow**: Documented with AskUserQuestion format

3. **Linear templates**: Verified against existing Linear issue patterns

---

## Linear Issue Tracking

Linear issues skipped for this sprint - framework meta-work doesn't require external tracking.

---

## Known Limitations

1. **Pattern Detection is Heuristic**: Relies on text patterns, may miss decisions phrased differently. Future iteration could add LLM-based semantic detection.

2. **ADR Flow Under Review**: As noted in notepad, there's a question about whether ADR candidates should go to Library or Laboratory. Continuing with Linear-based flow pending team discussion.

3. **Parallel Hivemind Changes**: Hivemind OS repo is being updated concurrently, which may cause breaking changes to symlink paths. Implementation continues as planned with awareness of potential conflicts.

---

## Verification Steps

### Verify Candidate Surfacer Library
```bash
# Check file exists and has expected size
wc -l .claude/lib/candidate-surfacer.md
# Expected: ~951 lines

# Verify key sections exist
grep -n "ADR Candidate Detection" .claude/lib/candidate-surfacer.md
grep -n "Learning Candidate Detection" .claude/lib/candidate-surfacer.md
grep -n "Batch Review Implementation" .claude/lib/candidate-surfacer.md
grep -n "Linear Submission Implementation" .claude/lib/candidate-surfacer.md
```

### Verify Architect Command Extension
```bash
# Check Phase Post-SDD exists
grep -n "Phase Post-SDD: ADR Candidate Surfacing" .claude/commands/architect.md
# Should show line in both foreground and background sections
```

### Verify Implement Command Extension
```bash
# Check Phase 5.5 exists
grep -n "Phase 5.5: Learning Candidate Surfacing" .claude/commands/implement.md
# Should show line in both foreground and background sections
```

---

## Files Modified Summary

| File | Lines Added | Action |
|------|-------------|--------|
| `.claude/lib/candidate-surfacer.md` | 951 | Created |
| `.claude/commands/architect.md` | +93 | Extended |
| `.claude/commands/implement.md` | +77 | Extended |
| `loa-grimoire/notepad.md` | +34 | Added ADR flow note |

**Total**: ~1,155 new lines of documentation/patterns

---

*Implementation completed by Sprint Task Implementer*
*Ready for senior technical lead review*
