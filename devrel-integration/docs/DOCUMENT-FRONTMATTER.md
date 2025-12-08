# Document Frontmatter Schema

**HIGH-011: Context Assembly Access Control**

This document defines the YAML frontmatter schema for documents in the agentic-base system. Frontmatter is used to control access, define relationships, and manage context assembly with security controls.

## Purpose

The frontmatter schema enables:
1. **Sensitivity-based access control** - Prevent information leakage by controlling which documents can be used as context
2. **Explicit document relationships** - No fuzzy search, only explicitly defined relationships
3. **Metadata tracking** - Document ownership, version, and lifecycle management
4. **Security auditing** - Track sensitive document access and usage

## Schema Definition

### Minimal Example

```yaml
---
sensitivity: internal
---

# Document Title

Document content...
```

### Complete Example

```yaml
---
# REQUIRED FIELDS
sensitivity: confidential

# OPTIONAL FIELDS
title: Q4 2025 Financial Projections
description: Confidential financial forecasts for Q4 2025
version: 1.2.0
created: 2025-12-01
updated: 2025-12-08
owner: finance-team
department: Finance
tags:
  - financial
  - confidential
  - q4-2025

# DOCUMENT RELATIONSHIPS
context_documents:
  - docs/q3-2025-actuals.md
  - docs/budget-2025.md
  - docs/market-analysis.md

allowed_audiences:
  - executives
  - finance-team
  - board

# SECURITY
requires_approval: true
retention_days: 365
pii_present: false
---

# Q4 2025 Financial Projections

Document content...
```

## Field Definitions

### Required Fields

#### `sensitivity` (required)

**Type**: `string` (enum)

**Description**: The sensitivity level of the document. This controls who can access the document and which documents can reference it as context.

**Values** (in order from lowest to highest sensitivity):
- `public` - Publicly accessible, no restrictions
- `internal` - Internal team members only
- `confidential` - Restricted to specific teams/roles
- `restricted` - Highly restricted, requires special approval

**Rules**:
- A document can only reference context documents with **same or lower** sensitivity
- Example: A `confidential` document can reference `confidential`, `internal`, or `public` context docs
- Example: A `public` document can ONLY reference `public` context docs

**Example**:
```yaml
sensitivity: confidential
```

### Optional Fields

#### `title`

**Type**: `string`

**Description**: Human-readable title for the document (overrides filename).

**Example**:
```yaml
title: Sprint 15 Implementation Plan
```

#### `description`

**Type**: `string`

**Description**: Brief description of the document's purpose and content.

**Example**:
```yaml
description: Detailed implementation tasks and acceptance criteria for Sprint 15
```

#### `version`

**Type**: `string` (semver format)

**Description**: Document version using semantic versioning (MAJOR.MINOR.PATCH).

**Example**:
```yaml
version: 2.1.0
```

#### `created`

**Type**: `string` (ISO 8601 date)

**Description**: Date the document was created.

**Example**:
```yaml
created: 2025-12-01
```

#### `updated`

**Type**: `string` (ISO 8601 date)

**Description**: Date the document was last updated.

**Example**:
```yaml
updated: 2025-12-08
```

#### `owner`

**Type**: `string`

**Description**: Team or person responsible for maintaining the document.

**Example**:
```yaml
owner: engineering-team
```

#### `department`

**Type**: `string`

**Description**: Department that owns the document.

**Values**: `Engineering`, `Product`, `Finance`, `Marketing`, `Executive`, `DevRel`, `Security`, `Legal`

**Example**:
```yaml
department: Engineering
```

#### `tags`

**Type**: `array<string>`

**Description**: Searchable tags for categorizing the document.

**Example**:
```yaml
tags:
  - sprint-planning
  - high-priority
  - q4-2025
```

#### `context_documents`

**Type**: `array<string>`

**Description**: **Explicit list of related documents** that can be included as context when processing this document. Only these documents will be considered for context assembly (no fuzzy search).

**Rules**:
- Paths must be relative (e.g., `docs/file.md`)
- Referenced documents must have same or lower sensitivity
- Context assembler will validate sensitivity before including
- Invalid paths or inaccessible documents will be logged as warnings

**Example**:
```yaml
context_documents:
  - docs/prd.md
  - docs/sdd.md
  - docs/sprint-14.md
```

**Security**: This prevents inadvertent information leakage by requiring explicit opt-in for context inclusion.

#### `allowed_audiences`

**Type**: `array<string>`

**Description**: List of audiences/roles authorized to access this document.

**Example**:
```yaml
allowed_audiences:
  - engineering-team
  - product-team
  - executives
```

#### `requires_approval`

**Type**: `boolean`

**Description**: Whether document access/modifications require manual approval.

**Example**:
```yaml
requires_approval: true
```

#### `retention_days`

**Type**: `integer`

**Description**: Number of days to retain document before archival/deletion (for compliance).

**Example**:
```yaml
retention_days: 365
```

#### `pii_present`

**Type**: `boolean`

**Description**: Whether the document contains personally identifiable information (PII).

**Example**:
```yaml
pii_present: true
```

## Sensitivity Level Guidelines

### `public`

**Use For**:
- Open source documentation
- Public blog posts
- General product documentation
- Public marketing materials

**Can Reference**: Only `public` documents

**Examples**:
- README.md
- Public API documentation
- Open source license files

### `internal`

**Use For**:
- Internal team documentation
- Process documentation
- Non-sensitive technical specs
- Team playbooks

**Can Reference**: `public` and `internal` documents

**Examples**:
- Team onboarding guides
- Development setup instructions
- Internal tool documentation

### `confidential`

**Use For**:
- Business plans
- Financial projections
- Unreleased product roadmaps
- Security audits
- Customer data analysis

**Can Reference**: `public`, `internal`, and `confidential` documents

**Examples**:
- Q4 financial report
- Security audit results
- Customer analytics dashboard
- Competitive analysis

### `restricted`

**Use For**:
- Executive-only materials
- Legal documents
- Sensitive customer data
- Security incident reports
- M&A documents

**Can Reference**: All document types (`public`, `internal`, `confidential`, `restricted`)

**Examples**:
- Board meeting minutes
- Executive compensation plans
- Security incident post-mortems
- Legal contracts

## Context Assembly Rules

### Rule 1: Explicit References Only

Context documents MUST be explicitly listed in the `context_documents` field. The context assembler will NOT perform fuzzy search or automatic relationship detection.

**Why**: Prevents accidental information leakage through implicit relationships.

### Rule 2: Sensitivity Hierarchy

A document can only reference context documents with **same or lower** sensitivity:

```
restricted → can reference: restricted, confidential, internal, public
confidential → can reference: confidential, internal, public
internal → can reference: internal, public
public → can reference: public only
```

**Why**: Prevents sensitive information from being included in less sensitive document processing.

### Rule 3: Missing Context Documents

If a referenced context document is missing or inaccessible:
- Log a warning
- Skip the missing document
- Continue processing with available documents

**Why**: Graceful degradation instead of complete failure.

### Rule 4: Circular References

Circular references (A → B → A) are allowed but will be detected and deduplicated to prevent infinite loops.

**Why**: Documents may legitimately reference each other.

## Example Use Cases

### Use Case 1: Executive Summary from Confidential Docs

```yaml
---
# docs/executive-summary.md
sensitivity: confidential
title: Q4 2025 Executive Summary
context_documents:
  - docs/sprint-15.md          # internal
  - docs/financial-report.md   # confidential
  - docs/customer-metrics.md   # confidential
---
```

✅ **Valid**: All context docs are `confidential` or lower.

### Use Case 2: Public Documentation

```yaml
---
# docs/api-docs.md
sensitivity: public
title: Public API Documentation
context_documents:
  - docs/public-examples.md    # public
---
```

✅ **Valid**: Only references `public` documents.

### Use Case 3: Invalid Sensitivity Reference

```yaml
---
# docs/team-guide.md
sensitivity: internal
context_documents:
  - docs/financial-report.md   # confidential ❌
---
```

❌ **Invalid**: Cannot reference `confidential` doc from `internal` doc.

**Result**: Context assembler will reject `docs/financial-report.md` and log security warning.

## Validation

The context assembler performs the following validations:

1. **Frontmatter syntax validation** - Ensure valid YAML
2. **Required field presence** - `sensitivity` must be present
3. **Sensitivity value validation** - Must be one of: public, internal, confidential, restricted
4. **Context document path validation** - Paths must be relative and safe (no directory traversal)
5. **Sensitivity hierarchy validation** - Context docs must be same or lower sensitivity

**Validation Failures**:
- Missing `sensitivity` → Document rejected with error
- Invalid sensitivity value → Document rejected with error
- Invalid context paths → Path skipped with warning
- Sensitivity violation → Context doc rejected with security alert

## Implementation

### Parsing Frontmatter

```typescript
import yaml from 'yaml';

function parseFrontmatter(content: string): { frontmatter: any; body: string } {
  const frontmatterRegex = /^---\s*\n([\s\S]*?)\n---\s*\n/;
  const match = content.match(frontmatterRegex);

  if (!match) {
    return { frontmatter: {}, body: content };
  }

  const frontmatterText = match[1];
  const body = content.slice(match[0].length);
  const frontmatter = yaml.parse(frontmatterText);

  return { frontmatter, body };
}
```

### Validating Sensitivity

```typescript
function validateSensitivity(sensitivity: string): boolean {
  const validLevels = ['public', 'internal', 'confidential', 'restricted'];
  return validLevels.includes(sensitivity);
}
```

### Checking Sensitivity Hierarchy

```typescript
function canAccessContext(primarySensitivity: string, contextSensitivity: string): boolean {
  const hierarchy = {
    public: 0,
    internal: 1,
    confidential: 2,
    restricted: 3
  };

  return hierarchy[primarySensitivity] >= hierarchy[contextSensitivity];
}
```

## Migration Guide

### Existing Documents Without Frontmatter

Documents without frontmatter will be assigned a default sensitivity level:

```typescript
const DEFAULT_SENSITIVITY = 'internal';
```

**Recommendation**: Audit all existing documents and add explicit frontmatter to ensure correct sensitivity classification.

### Adding Frontmatter to Existing Documents

```bash
# Before
# Document Title
Content...

# After
---
sensitivity: internal
title: Document Title
---

# Document Title
Content...
```

## Security Considerations

### Information Leakage Prevention

- **Explicit relationships only** - No fuzzy matching or automatic detection
- **Sensitivity hierarchy** - Strict enforcement prevents upward information flow
- **Audit logging** - All context assembly operations logged for security review

### Compliance

- **Data retention** - `retention_days` field supports compliance requirements
- **PII tracking** - `pii_present` flag for GDPR/CCPA compliance
- **Access control** - `allowed_audiences` field for role-based access

### Attack Scenarios Prevented

1. **Information Leakage via Context Inclusion**
   - Before: Fuzzy search might include sensitive docs in public summaries
   - After: Only explicitly whitelisted docs included, sensitivity enforced

2. **Privilege Escalation**
   - Before: Lower sensitivity doc could access higher sensitivity context
   - After: Strict hierarchy prevents upward information flow

3. **Accidental Disclosure**
   - Before: No visibility into what context will be included
   - After: Explicit declaration required, logged, and audited

## References

- HIGH-011: Context Assembly Access Control
- CRITICAL-002: Path Traversal Prevention
- HIGH-007: Comprehensive Audit Logging

---

**Last Updated**: 2025-12-08
**Status**: ACTIVE
**Version**: 1.0.0
