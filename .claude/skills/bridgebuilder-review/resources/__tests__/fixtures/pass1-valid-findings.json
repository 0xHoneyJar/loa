<!-- bridge-findings-start -->
```json
{
  "schema_version": 1,
  "findings": [
    {
      "id": "F001",
      "title": "Missing input validation on user endpoint",
      "severity": "HIGH",
      "category": "security",
      "file": "src/api/users.ts:42",
      "description": "The POST /users endpoint accepts user input without sanitization, which could lead to injection attacks.",
      "suggestion": "Add zod schema validation before processing the request body."
    },
    {
      "id": "F002",
      "title": "Efficient use of database connection pooling",
      "severity": "PRAISE",
      "category": "quality",
      "file": "src/db/pool.ts:15",
      "description": "Connection pool configuration uses bounded sizing with health checks — solid production practice.",
      "suggestion": "No changes needed."
    },
    {
      "id": "F003",
      "title": "Test coverage gap in error handling path",
      "severity": "MEDIUM",
      "category": "test-coverage",
      "file": "src/api/users.ts:78",
      "description": "The catch block at line 78 handles database connection failures but has no corresponding test case.",
      "suggestion": "Add a test that mocks a connection failure and verifies the 503 response."
    }
  ]
}
```
<!-- bridge-findings-end -->
