# Bug Triage: {title}

## Metadata
- **schema_version**: 1
- **bug_id**: {bug_id}
- **classification**: {classification}
- **severity**: {severity}
- **eligibility_score**: {score}
- **eligibility_reasoning**: {reasoning}
- **test_type**: {test_type}
- **risk_level**: {risk_level}
- **created**: {timestamp}

## Reproduction
### Steps
1. {step}

### Expected Behavior
{expected}

### Actual Behavior
{actual}

### Environment
{environment}

## Analysis
### Suspected Files
| File | Line(s) | Confidence | Reason |
|------|---------|------------|--------|
| {path} | {lines} | {confidence} | {why} |

### Related Tests
| Test File | Coverage |
|-----------|----------|
| {test_path} | {coverage} |

### Test Target
{test_target_description}

### Constraints
{constraints}

## Fix Strategy
{strategy}

### Fix Hints
Structured hints for multi-model handoff (each hint targets one file change):

| File | Action | Target | Constraint |
|------|--------|--------|------------|
| {file} | {action} | {target} | {constraint} |
