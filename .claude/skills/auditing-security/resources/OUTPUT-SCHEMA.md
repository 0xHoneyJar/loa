# Structured Finding Output Schema

Defines the JSONL output format for machine-parseable audit findings.

## Finding Schema

Each finding is a JSON object on a single line in the JSONL file.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "AuditFinding",
  "type": "object",
  "required": ["id", "category", "criterion", "severity", "score", "finding", "reasoning_trace", "confidence"],
  "properties": {
    "id": {
      "type": "string",
      "pattern": "^[A-Z]{2,4}-[0-9]{3}$",
      "description": "Unique finding ID (e.g., SEC-001, ARCH-042)"
    },
    "category": {
      "type": "string",
      "enum": ["security", "architecture", "code_quality", "devops", "blockchain"],
      "description": "Audit category"
    },
    "criterion": {
      "type": "string",
      "description": "Specific rubric dimension (e.g., input_validation, modularity)"
    },
    "severity": {
      "type": "string",
      "enum": ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"],
      "description": "Finding severity"
    },
    "score": {
      "type": "integer",
      "minimum": 1,
      "maximum": 5,
      "description": "Rubric score for this dimension"
    },
    "file": {
      "type": "string",
      "description": "File path where issue was found"
    },
    "line": {
      "type": "integer",
      "description": "Line number (if applicable)"
    },
    "code_snippet": {
      "type": "string",
      "description": "Relevant code excerpt"
    },
    "reasoning_trace": {
      "type": "string",
      "description": "How the issue was discovered - analysis path and evidence"
    },
    "finding": {
      "type": "string",
      "description": "Clear description of the issue"
    },
    "critique": {
      "type": "string",
      "description": "Specific guidance for improvement"
    },
    "remediation": {
      "type": "string",
      "description": "Exact fix with code example if applicable"
    },
    "confidence": {
      "type": "string",
      "enum": ["high", "medium", "low"],
      "description": "Confidence in the finding"
    },
    "references": {
      "type": "array",
      "items": {"type": "string"},
      "description": "CVE, CWE, OWASP, or other references"
    }
  }
}
```

## Example Findings

### Security Finding
```json
{"id":"SEC-001","category":"security","criterion":"input_validation","severity":"HIGH","score":2,"file":"src/api/users.ts","line":42,"code_snippet":"const query = `SELECT * FROM users WHERE id = ${userId}`;","reasoning_trace":"Traced user input from req.params.userId through controller to database query. Found string interpolation in SQL query construction at L42, bypassing ORM parameterization.","finding":"SQL injection vulnerability via unsanitized userId parameter","critique":"The userId is interpolated directly into SQL string. Even if userId appears numeric, type coercion allows injection. The ORM's parameterized query feature is available but not used here.","remediation":"Replace L42 with: `const user = await db.query('SELECT * FROM users WHERE id = $1', [userId]);`","confidence":"high","references":["CWE-89","OWASP-A03:2021"]}
```

### Architecture Finding
```json
{"id":"ARCH-012","category":"architecture","criterion":"modularity","severity":"MEDIUM","score":3,"file":"src/services/","reasoning_trace":"Analyzed import graph and found UserService imports from PaymentService, OrderService, and NotificationService. PaymentService also imports UserService creating circular dependency detected via tsc --traceResolution.","finding":"Circular dependency between UserService and PaymentService","critique":"Tight coupling between these services will make testing and modification difficult. Consider extracting shared logic to a separate module or using events for decoupling.","remediation":"1. Extract shared types to src/types/\n2. Use event emitter for cross-service communication\n3. Consider domain events pattern","confidence":"high","references":["Clean Architecture","DDD Bounded Contexts"]}
```

### Code Quality Finding
```json
{"id":"CQ-007","category":"code_quality","criterion":"error_handling","severity":"LOW","score":4,"file":"src/utils/api.ts","line":78,"code_snippet":"} catch (e) { console.log(e); }","reasoning_trace":"Reviewed error handling patterns across codebase. Found 3 instances of catch blocks that only console.log errors without proper handling or re-throwing.","finding":"Silent error swallowing in API utility","critique":"Errors are logged but not handled or propagated. This makes debugging difficult and can hide critical failures in production.","remediation":"Replace with: `} catch (e) { logger.error('API call failed', { error: e, context }); throw new ApiError('Request failed', { cause: e }); }`","confidence":"medium","references":["Error Handling Best Practices"]}
```

## Output File Location

Findings should be written to:
```
grimoires/loa/a2a/audits/YYYY-MM-DD/findings.jsonl
```

## Summary Record

At the end of the JSONL file, include a summary record:

```json
{"type":"summary","timestamp":"2026-01-30T12:00:00Z","category_scores":{"security":3.2,"architecture":4.1,"code_quality":3.8,"devops":4.0},"overall_score":3.8,"risk_level":"MODERATE","total_findings":{"CRITICAL":0,"HIGH":2,"MEDIUM":5,"LOW":8,"INFO":3},"verdict":"CHANGES_REQUIRED"}
```

## Parsing Example

```bash
# Get all HIGH severity findings
cat findings.jsonl | jq -c 'select(.severity == "HIGH")'

# Calculate average security score
cat findings.jsonl | jq -s '[.[] | select(.category == "security") | .score] | add / length'

# Get findings for a specific file
cat findings.jsonl | jq -c 'select(.file | contains("users.ts"))'
```
