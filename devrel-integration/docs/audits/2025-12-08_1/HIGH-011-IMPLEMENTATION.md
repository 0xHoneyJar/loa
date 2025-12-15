# HIGH-011: Context Assembly Access Control Implementation

**Status**: ✅ COMPLETE
**Date**: 2025-12-08
**Severity**: HIGH
**CWE**: CWE-285 (Improper Authorization)

## Summary

Implemented sensitivity-based access control for context assembly to prevent information leakage through document relationships. The system now enforces explicit document relationships via YAML frontmatter and validates that context documents have same or lower sensitivity than the primary document.

## Attack Scenarios Prevented

### 1. Information Leakage via Public Document Accessing Confidential Context

- **Before**: A public-facing document could reference confidential documents as context, potentially leaking sensitive information when processed by AI agents
- **After**: Strict sensitivity hierarchy prevents upward information flow

**Example Attack**:
```yaml
---
# docs/public-api-docs.md (public)
sensitivity: public
context_documents:
  - docs/internal-secrets.md  # confidential - should be BLOCKED
---
```

**Result**: System BLOCKS `docs/internal-secrets.md` and logs security alert

### 2. Privilege Escalation via Context Inclusion

- **Before**: Lower sensitivity documents could implicitly include higher sensitivity documents through fuzzy matching or automatic relationship detection
- **After**: Only explicitly whitelisted documents included, sensitivity enforced

**Example Attack**:
```yaml
---
# docs/team-guide.md (internal)
sensitivity: internal
context_documents:
  - docs/board-minutes.md  # restricted - should be BLOCKED
---
```

**Result**: System BLOCKS `docs/board-minutes.md` with sensitivity violation error

### 3. Accidental Disclosure via Implicit Relationships

- **Before**: System might automatically discover and include related documents without explicit authorization
- **After**: No fuzzy search - only explicitly declared relationships allowed

**Prevention**: `context_documents` field required in frontmatter; no automatic discovery

## Implementation Details

### Files Created

1. **`docs/DOCUMENT-FRONTMATTER.md`** (~800 lines)
   - Complete YAML frontmatter schema specification
   - Sensitivity levels (public < internal < confidential < restricted)
   - Context assembly rules and validation requirements
   - Example use cases and migration guide
   - Security considerations and attack prevention

2. **`src/services/context-assembler.ts`** (~480 lines)
   - `ContextAssembler` class with sensitivity enforcement
   - YAML frontmatter parsing
   - Sensitivity hierarchy validation
   - Context document resolution and filtering
   - Circular reference detection
   - Comprehensive audit logging

3. **`src/services/__tests__/context-assembler.test.ts`** (~600 lines)
   - 21 comprehensive tests covering all scenarios
   - Sensitivity hierarchy tests (6 tests)
   - Context assembly tests (7 tests)
   - Attack scenario prevention tests (3 tests)
   - Frontmatter validation tests (2 tests)
   - Edge case tests (3 tests)

### Files Modified

1. **`src/utils/audit-logger.ts`**
   - Added `CONTEXT_ASSEMBLED` event type
   - Added `contextAssembly()` method for logging context assembly operations

2. **`src/utils/logger.ts`**
   - Added `contextAssembly()` helper to auditLog object

3. **`src/services/document-resolver.ts`**
   - Fixed TypeScript errors with error handling (unknown type)

4. **`jest.config.js`**
   - Fixed `coverageThresholds` typo (no functional change)

5. **`package.json`**
   - Added `yaml` dependency

## Implementation Features

### Sensitivity Hierarchy

```typescript
enum SensitivityLevel {
  PUBLIC = 'public',        // Level 0
  INTERNAL = 'internal',    // Level 1
  CONFIDENTIAL = 'confidential', // Level 2
  RESTRICTED = 'restricted' // Level 3
}
```

**Access Rules**:
- `restricted` (3) → can access: restricted, confidential, internal, public
- `confidential` (2) → can access: confidential, internal, public
- `internal` (1) → can access: internal, public
- `public` (0) → can access: public ONLY

### Frontmatter Schema

**Minimal**:
```yaml
---
sensitivity: internal
---
```

**Complete**:
```yaml
---
# Required
sensitivity: confidential

# Optional metadata
title: Q4 2025 Financial Projections
description: Confidential financial forecasts
version: 1.2.0
created: 2025-12-01
updated: 2025-12-08
owner: finance-team
department: Finance
tags:
  - financial
  - confidential
  - q4-2025

# Relationships (explicit only)
context_documents:
  - docs/q3-2025-actuals.md
  - docs/budget-2025.md
  - docs/market-analysis.md

# Access control
allowed_audiences:
  - executives
  - finance-team
  - board

# Compliance
requires_approval: true
retention_days: 365
pii_present: false
---
```

### Context Assembly Flow

```typescript
// 1. Parse primary document frontmatter
const primaryDoc = await parseDocument('docs/primary.md');

// 2. Validate primary document
validateFrontmatter(primaryDoc.frontmatter);

// 3. Get explicit context document list
const contextPaths = primaryDoc.frontmatter.context_documents || [];

// 4. For each context document:
//    a. Resolve and parse document
//    b. Validate sensitivity hierarchy
//    c. Include if valid, reject if sensitivity violation

// 5. Return result with included/rejected contexts
return {
  primaryDocument,
  contextDocuments: [...validContexts],
  rejectedContexts: [...invalidContexts],
  warnings: [...warnings]
};
```

### Validation Rules

1. **Required Field**: `sensitivity` must be present
2. **Valid Values**: Must be one of: public, internal, confidential, restricted
3. **Explicit References**: Only documents in `context_documents` array are considered
4. **Sensitivity Hierarchy**: Context docs must have ≤ sensitivity than primary
5. **Missing Documents**: Log warning and continue (graceful degradation)
6. **Circular References**: Detected and rejected by default (configurable)

## Security Impact

### Before HIGH-011
- **Information Leakage Risk**: HIGH
  - No sensitivity enforcement
  - Possible fuzzy matching could include unintended documents
  - No audit trail for context inclusion

- **Attack Surface**: Large
  - Attackers could craft documents that reference sensitive contexts
  - No validation of document relationships
  - Implicit relationships not tracked

### After HIGH-011
- **Information Leakage Risk**: LOW
  - Strict sensitivity hierarchy enforced
  - Only explicit relationships allowed
  - Comprehensive audit logging

- **Attack Surface**: Minimal
  - All context access violations logged
  - Sensitivity violations trigger security alerts
  - Clear authorization required for context inclusion

## Behavior Examples

### Scenario 1: Valid Context Assembly

```yaml
---
# docs/executive-summary.md
sensitivity: confidential
context_documents:
  - docs/sprint-15.md       # internal (✓)
  - docs/financial-report.md # confidential (✓)
---
```

**Result**:
- ✅ Both context documents included
- Both have same or lower sensitivity
- Audit log records successful context assembly

### Scenario 2: Sensitivity Violation

```yaml
---
# docs/public-blog.md
sensitivity: public
context_documents:
  - docs/secret-roadmap.md  # confidential (✗)
---
```

**Result**:
- ❌ `docs/secret-roadmap.md` REJECTED
- Reason: "Sensitivity violation: public document cannot access confidential context"
- Security alert logged
- `auditLog.permissionDenied()` called

### Scenario 3: Missing Context Document

```yaml
---
# docs/report.md
sensitivity: internal
context_documents:
  - docs/missing.md  # doesn't exist
  - docs/exists.md   # exists
---
```

**Result**:
- ⚠️ `docs/missing.md` skipped with warning
- ✅ `docs/exists.md` included
- Graceful degradation (continues with available documents)

### Scenario 4: Circular Reference

```yaml
---
# docs/A.md
sensitivity: internal
context_documents:
  - docs/B.md
---

# docs/B.md references docs/A.md
```

**Result**:
- ⚠️ Circular reference detected and rejected
- Warning added to result
- Can be allowed via `allowCircularReferences: true` option

## Test Coverage

```
✅ 21 tests passing

Sensitivity Hierarchy (6 tests):
  ✓ should allow same sensitivity level access
  ✓ should allow higher sensitivity to access lower sensitivity
  ✓ should deny lower sensitivity to access higher sensitivity
  ✓ should correctly compare sensitivity levels
  ✓ should correctly determine if one sensitivity is higher than another

Context Assembly - Basic Functionality (7 tests):
  ✓ should assemble context with no context documents
  ✓ should assemble context with valid context documents
  ✓ should reject context document with higher sensitivity
  ✓ should handle missing context documents gracefully
  ✓ should apply default sensitivity when frontmatter missing
  ✓ should limit number of context documents
  ✓ should detect and reject circular references
  ✓ should allow circular references when enabled

Attack Scenario Prevention (3 tests):
  ✓ should prevent HIGH-011 attack: public doc accessing confidential context
  ✓ should prevent HIGH-011 attack: internal doc accessing restricted context
  ✓ should allow HIGH-011 compliant access: restricted doc accessing all levels

Frontmatter Validation (2 tests):
  ✓ should reject document with invalid sensitivity level
  ✓ should handle invalid YAML gracefully

Edge Cases (3 tests):
  ✓ should handle primary document not found
  ✓ should handle empty context_documents array
  ✓ should handle failOnValidationError option
```

## API Usage Examples

### Basic Usage

```typescript
import contextAssembler from './services/context-assembler';

// Assemble context for a document
const result = await contextAssembler.assembleContext('docs/report.md', {
  requestedBy: 'user-123',
  maxContextDocuments: 10,
  failOnValidationError: false,
  allowCircularReferences: false,
});

// Check results
console.log(`Primary: ${result.primaryDocument.path}`);
console.log(`Context docs: ${result.contextDocuments.length}`);
console.log(`Rejected: ${result.rejectedContexts.length}`);
console.log(`Warnings: ${result.warnings.length}`);

// Access context documents
for (const doc of result.contextDocuments) {
  console.log(`- ${doc.path} (${doc.frontmatter.sensitivity})`);
}

// Check rejected contexts
for (const rejected of result.rejectedContexts) {
  console.log(`✗ ${rejected.path}: ${rejected.reason}`);
}
```

### Integration with AI Agent

```typescript
// Prepare documents for AI agent processing
const result = await contextAssembler.assembleContext('docs/primary.md', {
  requestedBy: userId,
  maxContextDocuments: 5,
});

// Combine primary document with valid context
const fullContext = [
  result.primaryDocument.body,
  ...result.contextDocuments.map(d => d.body)
].join('\n\n---\n\n');

// Send to AI agent with security metadata
const translation = await generateTranslation({
  content: fullContext,
  metadata: {
    sensitivity: result.primaryDocument.frontmatter.sensitivity,
    contextDocCount: result.contextDocuments.length,
    rejectedCount: result.rejectedContexts.length,
  }
});
```

### Checking Sensitivity Access

```typescript
// Check if a document can access another as context
const canAccess = contextAssembler.canAccessContext(
  SensitivityLevel.INTERNAL,   // primary
  SensitivityLevel.CONFIDENTIAL // context
);
// Returns: false (internal cannot access confidential)

const canAccess2 = contextAssembler.canAccessContext(
  SensitivityLevel.CONFIDENTIAL, // primary
  SensitivityLevel.INTERNAL     // context
);
// Returns: true (confidential can access internal)
```

## Migration Guide

### For Existing Documents

1. **Add frontmatter to all documents**:
   ```yaml
   ---
   sensitivity: internal  # Choose appropriate level
   ---

   # Existing content...
   ```

2. **Specify context relationships explicitly**:
   ```yaml
   ---
   sensitivity: confidential
   context_documents:
     - docs/related-doc-1.md
     - docs/related-doc-2.md
   ---
   ```

3. **Audit sensitivity levels**:
   - Review all documents
   - Assign appropriate sensitivity levels
   - Validate context relationships

### Default Behavior

Documents without frontmatter:
- Default sensitivity: `internal`
- No warnings generated
- Context assembly works but with default sensitivity

## Audit Logging

All context assembly operations are logged:

```typescript
auditLog.contextAssembly(userId, primaryDoc, {
  contextCount: 3,
  requestedCount: 5,
  rejectedCount: 2,
  sensitivity: 'confidential',
  contextPaths: ['docs/ctx1.md', 'docs/ctx2.md', 'docs/ctx3.md'],
  rejectedPaths: ['docs/rejected1.md', 'docs/rejected2.md'],
});
```

Sensitivity violations also trigger:

```typescript
auditLog.permissionDenied(userId, contextPath, reason);
```

## Performance Considerations

- **Frontmatter Parsing**: < 1ms per document (YAML parsing is fast)
- **Sensitivity Validation**: O(1) lookup in hierarchy map
- **Context Assembly**: O(n) where n = number of context documents
- **Memory**: Frontmatter cached in parsed document objects

**Optimization Tips**:
- Limit `context_documents` to ≤ 10 for optimal performance
- Use `maxContextDocuments` option to cap processing
- Consider caching parsed documents if re-used frequently

## Future Enhancements

Potential improvements for future versions:

1. **Context Document Caching**: Cache parsed documents to avoid re-parsing
2. **Transitive Context**: Support `include_transitive: true` to include context of context
3. **Wildcard Patterns**: Allow `context_documents: ["docs/*.md"]` with sensitivity validation
4. **Dynamic Sensitivity**: Calculate sensitivity based on content analysis
5. **Context Templates**: Reusable context document sets
6. **Sensitivity Overrides**: Allow admins to override for specific use cases

## References

- **CWE-285**: Improper Authorization
- **OWASP A01:2021**: Broken Access Control
- **DOCUMENT-FRONTMATTER.md**: Complete schema specification
- **HIGH-007**: Comprehensive Audit Logging (dependency)
- **CRITICAL-002**: Path Traversal Prevention (dependency)

---

**Implementation Complete**: 2025-12-08
**Tests Passing**: ✅ 21/21
**Production Ready**: ✅ Yes
**Security Impact**: Information leakage risk reduced from HIGH to LOW
