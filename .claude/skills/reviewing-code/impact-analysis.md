# Impact Analysis Protocol for reviewing-code Agent

**Version**: 1.0
**Status**: Active
**Owner**: reviewing-code skill
**Integration**: ck semantic search (Sprint 4)

---

## Purpose

This protocol defines how the reviewing-code agent performs comprehensive impact analysis before reviewing sprint implementations. Using semantic/hybrid search (when available), the agent discovers all code affected by changes, test coverage gaps, and pattern consistency issues.

---

## Core Principle

**NEVER review in isolation**. Always analyze impact radius first to understand:
1. What code depends on changed modules (downstream impact)
2. What tests cover the changes (regression risk)
3. What patterns exist for consistency checking
4. What documentation needs updating

---

## Impact Analysis Workflow

### Phase 1: Change Identification
**Before searching**, extract what changed from reviewer.md:

```xml
<change_analysis>
  <sprint_id>sprint-N</sprint_id>
  <changed_modules>
    <module path="/abs/path/to/module.ts">
      <functions>functionA, functionB</functions>
      <exports>ClassX, interfaceY</exports>
    </module>
  </changed_modules>
  <change_type>new_feature|enhancement|bugfix|refactor</change_type>
</change_analysis>
```

### Phase 2: Dependent Discovery
Find all code that depends on changed modules:

**Find Direct Imports** (regex search):
```bash
# For each changed module
regex_search(
  pattern: "import.*<module_name>|from.*<module_name>|require\(.*<module_name>",
  path: "src/"
)
```

**Find Semantic Dependencies** (with ck):
```bash
# Find code that conceptually uses changed functionality
semantic_search(
  query: "<changed_function_name> <functionality_description>",
  path: "src/",
  top_k: 20,
  threshold: 0.5
)
```

**Example**:
```bash
# Changed: src/auth/jwt.ts - validateToken()
# Find imports:
regex_search("import.*jwt|from.*jwt|require.*jwt", "src/")
# Find semantic usage:
semantic_search("token validation authentication verify", "src/", 20, 0.5)
```

### Phase 3: Test Coverage Analysis
Find tests that cover changed code:

**Find Direct Test Files**:
```bash
# Pattern: <module>.test.ts, <module>.spec.ts
hybrid_search(
  query: "test <module_name> <function_name>",
  path: "tests/|__tests__|*.test.*|*.spec.*",
  top_k: 10
)
```

**Find Integration Tests**:
```bash
# Semantic search for test scenarios
semantic_search(
  query: "<feature_description> integration test e2e",
  path: "tests/",
  top_k: 10,
  threshold: 0.4
)
```

**Identify Coverage Gaps**:
- Changed functions WITHOUT corresponding tests
- New exports WITHOUT test coverage
- Modified interfaces WITHOUT updated contract tests

### Phase 4: Pattern Consistency Check
Verify changes follow existing patterns:

**Find Similar Implementations**:
```bash
# Compare with existing patterns
semantic_search(
  query: "<similar_feature> <pattern_keywords>",
  path: "src/",
  top_k: 10,
  threshold: 0.6
)
```

**Check Architectural Patterns**:
- Error handling approach (consistent?)
- Validation patterns (same style?)
- Logging conventions (followed?)
- Testing patterns (similar structure?)

### Phase 5: Documentation Impact
Find docs that reference changed code:

```bash
# Find documentation mentions
hybrid_search(
  query: "<module_name> <function_name>",
  path: "docs/|*.md|grimoires/loa/",
  top_k: 10
)
```

**Flag Documentation Drift**:
- PRD/SDD sections referencing changed modules
- README examples using changed APIs
- Architecture docs describing changed patterns

### Phase 6: Tool Result Clearing
After impact analysis (typically >30 results):

1. **Extract high-signal findings**:
   - Dependents list (file:line)
   - Test coverage map
   - Pattern deviations
   - Documentation drift items

2. **Synthesize to feedback template**:
   ```markdown
   ## Impact Analysis

   **Changed Modules**: [List]
   **Dependents Found**: X files
   **Test Coverage**: Y% (Z gaps identified)
   **Pattern Consistency**: [Pass|Concerns]
   **Documentation Updates Needed**: [List]

   ### Dependency Graph
   - `/abs/path/to/dependent1.ts:45` - Imports validateToken()
   - `/abs/path/to/dependent2.ts:89` - Uses auth middleware

   ### Coverage Gaps
   - `functionA()` - No unit test found
   - `ClassX` - Integration test missing

   ### Pattern Deviations
   - Error handling: Uses throw instead of Result<T> pattern
   - Validation: Missing input sanitization (see auth/utils.ts:23)
   ```

3. **Clear raw search results** from working memory

4. **Retain only synthesis** in feedback

---

## Review Checklist Integration

After impact analysis, execute review with enhanced checklist:

### Code Quality
- [ ] Implementation follows discovered patterns
- [ ] Error handling consistent with similar code
- [ ] Validation approach matches existing patterns
- [ ] Logging conventions followed

### Impact Verification
- [ ] All dependents reviewed for compatibility
- [ ] No breaking changes to public APIs
- [ ] Integration points validated
- [ ] Backward compatibility maintained

### Test Coverage
- [ ] Unit tests exist for all changed functions
- [ ] Integration tests cover happy paths
- [ ] Edge cases tested
- [ ] Error scenarios validated
- [ ] Test patterns consistent with existing tests

### Documentation
- [ ] Code comments added where needed
- [ ] API documentation updated
- [ ] PRD/SDD sections reflect changes
- [ ] README updated if public APIs changed

### Security (if applicable)
- [ ] Input validation present
- [ ] Auth/authz checks in place
- [ ] Sensitive data handling secure
- [ ] No hardcoded secrets

---

## Search Strategy

Use search-orchestrator.sh for ck-first search with automatic grep fallback:

```bash
# Find imports (hybrid search for better semantic understanding)
.claude/scripts/search-orchestrator.sh hybrid "import <module>" src/ 20 0.5

# Find test files (by naming convention)
find tests/ -name "*<module>*test*" -o -name "*<module>*spec*"

# Find documentation mentions (hybrid search across docs)
.claude/scripts/search-orchestrator.sh hybrid "<module_name> documentation" docs/ 20 0.4
```

### Manual Fallback (if search-orchestrator unavailable)

```bash
grep -rn "import.*<module>" src/ | head -20
grep -rn "<module_name>" docs/ grimoires/loa/*.md
```

**Limitations**:
- May miss semantic dependencies
- Cannot assess pattern similarity
- Manual review required for consistency

**Mitigation**:
- Rely more on explicit naming conventions
- Request implementer provide dependency list
- Manual code inspection for patterns

---

## Search Mode Detection

Same as implementing-tasks:
```bash
if command -v ck >/dev/null 2>&1; then
    LOA_SEARCH_MODE="ck"
else
    LOA_SEARCH_MODE="grep"
fi
export LOA_SEARCH_MODE
```

**Communication**:
- ❌ NEVER SAY: "Using ck for impact analysis..."
- ✅ ALWAYS SAY: "Analyzing code impact...", "Finding dependents..."

---

## Attention Budget Management

| Operation | Token Limit | Action on Exceed |
|-----------|-------------|------------------|
| Dependent search | 3,000 tokens | Synthesize to feedback, clear results |
| Test discovery | 2,000 tokens | Synthesize coverage map, clear |
| Pattern checks | 2,000 tokens | Extract deviations only, clear |
| Session total | 15,000 tokens | Stop, synthesize all, then continue |

---

## Output Format: engineer-feedback.md

Include impact analysis section:

```markdown
# Sprint N Review Feedback

**Reviewer**: reviewing-code agent
**Date**: YYYY-MM-DD
**Status**: [All good|Changes required]

## Executive Summary
[Overall assessment with grounding citations]

## Impact Analysis

### Dependency Graph
**Dependents Found**: X files
[List with file:line references and word-for-word import statements]

### Test Coverage
**Coverage**: Y% of changed functions
**Gaps**:
- `functionA()` [/abs/path/to/impl.ts:45] - No unit test
- `ClassX` [/abs/path/to/class.ts:89] - Integration test missing

### Pattern Consistency
**Status**: [Pass|Concerns]
**Deviations**:
- Error handling: `throw new Error()` [impl.ts:67] vs Result<T> pattern [utils.ts:23]

### Documentation Drift
- PRD §3.2 references old API signature
- README example needs update for new parameters

## Detailed Review
[Task-by-task review with citations]

## Recommendations
[Actionable feedback]
```

---

## Example: Reviewing Auth Enhancement

**Sprint**: sprint-2/task-3 (OAuth2 integration)
**Changed**: src/auth/oauth.ts (new file), src/auth/middleware.ts (modified)

### Phase 1: Change Identification
```
Changed Modules:
- /project/src/auth/oauth.ts (new) - exports OAuthProvider, validateOAuthToken()
- /project/src/auth/middleware.ts (modified) - added oauthMiddleware()
```

### Phase 2: Dependent Discovery (with ck)
```bash
# Find imports of middleware
regex_search("import.*middleware|from.*middleware", "src/")
# Results: src/api/routes.ts:5, src/server.ts:12

# Find OAuth usage conceptually
semantic_search("OAuth authentication provider", "src/", 20, 0.5)
# Results: src/auth/oauth.ts (self), src/api/routes.ts (usage)
```

### Phase 3: Test Coverage
```bash
# Find OAuth tests
hybrid_search("test OAuth authentication", "tests/", 10)
# Results: tests/auth/oauth.test.ts (new file - good!)

# Find middleware tests
hybrid_search("test middleware authentication", "tests/", 10)
# Results: tests/auth/middleware.test.ts - DOES NOT include OAuth variant
```

**Gap Identified**: middleware.test.ts missing OAuth scenario

### Phase 4: Pattern Check
```bash
# Find similar auth patterns
semantic_search("token validation authentication", "src/auth/", 10, 0.6)
# Results: jwt.ts:validateToken(), oauth.ts:validateOAuthToken()

# Compare implementations
# jwt.ts:45 - `export async function validateToken(token: string): Promise<Result<TokenPayload>>`
# oauth.ts:89 - `export async function validateOAuthToken(token: string): Promise<TokenPayload>`
```

**Deviation Identified**: oauth.ts returns raw TokenPayload instead of Result<T> pattern

### Phase 5: Documentation Check
```bash
# Find auth documentation
hybrid_search("OAuth authentication", "docs/|grimoires/loa/*.md", 10)
# Results: grimoires/loa/prd.md §3.2 - mentions OAuth as Ghost Feature!
```

**Documentation Drift**: PRD lists OAuth as Ghost, needs update to "Implemented"

### Phase 6: Synthesize Feedback
```markdown
## Impact Analysis

### Dependency Graph
**Dependents Found**: 2 files
- `/project/src/api/routes.ts:5` - `import { oauthMiddleware } from './auth/middleware'`
- `/project/src/server.ts:12` - `import { authMiddleware } from './auth/middleware'` (indirect)

### Test Coverage
**Coverage**: 75% (1 gap)
**Gaps**:
- `oauthMiddleware()` [/project/src/auth/middleware.ts:67] - No test in middleware.test.ts

### Pattern Consistency
**Status**: Concerns
**Deviations**:
- Return type: `validateOAuthToken()` returns `Promise<TokenPayload>` [oauth.ts:89] vs `Promise<Result<TokenPayload>>` [jwt.ts:45]
- Should follow Result<T> pattern for consistency

### Documentation Drift
- PRD §3.2 lists OAuth as Ghost Feature - needs update to "Implemented in sprint-2"
- Architecture diagram (SDD §5.1) missing OAuth provider box

## Detailed Review

### Task 3: OAuth2 Integration
**Status**: Changes required

**Implementation Quality**: Good
- Clean separation of concerns
- Proper async/await usage
- Good error messages

**Issues**:
1. **Pattern Inconsistency (Medium)**: Return type should use Result<T> pattern
   - Current: `Promise<TokenPayload>` [oauth.ts:89]
   - Expected: `Promise<Result<TokenPayload, AuthError>>` [jwt.ts:45 pattern]

2. **Test Gap (Low)**: Missing middleware test
   - `/tests/auth/middleware.test.ts` needs OAuth scenario
   - Should test: valid OAuth token, invalid token, expired token

3. **Documentation Drift (Low)**: Update PRD Ghost Feature status
   - Mark OAuth as "Implemented in sprint-2"
   - Update drift-report.md resolved section

## Recommendations

1. Update `validateOAuthToken()` to return `Result<TokenPayload, OAuthError>`
2. Add OAuth test cases to middleware.test.ts
3. Update PRD §3.2 and drift-report.md

All good pending these changes.
```

---

## Trajectory Logging

Log all impact analysis to trajectory:
```jsonl
{
  "ts": "2024-01-15T14:30:00Z",
  "agent": "reviewing-code",
  "phase": "impact_analysis",
  "sprint": "sprint-2",
  "changed_modules": ["/project/src/auth/oauth.ts", "/project/src/auth/middleware.ts"],
  "dependents_found": 2,
  "test_coverage": 0.75,
  "pattern_deviations": 1,
  "doc_drift_items": 2,
  "searches": [
    {"type": "regex", "query": "import.*middleware", "results": 2},
    {"type": "semantic", "query": "OAuth authentication", "results": 2},
    {"type": "hybrid", "query": "test OAuth", "results": 1}
  ]
}
```

---

## Success Criteria

Impact analysis is successful when:
- [ ] All dependents identified (or confirmed none exist)
- [ ] Test coverage assessed (gaps documented)
- [ ] Pattern consistency checked
- [ ] Documentation drift identified
- [ ] Synthesis complete in engineer-feedback.md
- [ ] Raw search results cleared
- [ ] All claims cite word-for-word code

---

## Anti-Patterns

❌ **NEVER DO**:
- Review code without impact analysis
- Approve without checking dependents
- Ignore test coverage gaps
- Skip pattern consistency check
- Keep raw search results in memory

✅ **ALWAYS DO**:
- Analyze impact before reviewing
- Document all dependents found
- Identify test coverage gaps
- Check pattern consistency
- Synthesize to feedback document
- Clear raw results after extraction

---

## Integration Points

This protocol integrates with:
- `.claude/protocols/tool-result-clearing.md` - Memory management
- `.claude/protocols/trajectory-evaluation.md` - Reasoning audit
- `.claude/protocols/citations.md` - Code evidence requirements
- `.claude/protocols/feedback-loops.md` - Review workflow
- `.claude/scripts/search-orchestrator.sh` - Search execution

---

**Status**: Active from Sprint 4
**Review**: After Sprint 5 validation
