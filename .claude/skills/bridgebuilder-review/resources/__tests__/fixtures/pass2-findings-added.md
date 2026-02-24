## Summary

This PR has several issues that need attention.

## Findings

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
      "description": "The POST /users endpoint accepts user input without sanitization.",
      "suggestion": "Add zod schema validation."
    },
    {
      "id": "F002",
      "title": "Efficient use of database connection pooling",
      "severity": "PRAISE",
      "category": "quality",
      "file": "src/db/pool.ts:15",
      "description": "Connection pool configuration uses bounded sizing with health checks.",
      "suggestion": "No changes needed."
    },
    {
      "id": "F003",
      "title": "Test coverage gap in error handling path",
      "severity": "MEDIUM",
      "category": "test-coverage",
      "file": "src/api/users.ts:78",
      "description": "The catch block has no corresponding test case.",
      "suggestion": "Add a test that mocks a connection failure."
    },
    {
      "id": "F004",
      "title": "Hallucinated finding — this was not in Pass 1",
      "severity": "LOW",
      "category": "quality",
      "file": "src/utils/helpers.ts:10",
      "description": "This finding was invented by Pass 2 and should fail validation.",
      "suggestion": "This should not exist."
    }
  ]
}
```
<!-- bridge-findings-end -->

## Callouts

- Good overall structure.
