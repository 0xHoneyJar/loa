# Parallel Audit Splitting

Moved out of `SKILL.md`'s `<parallel_execution>` block — read this when Phase -1 rates the codebase LARGE (>5,000 lines) and you want a starting per-category split.

## Splitting strategy: by audit category

Spawn 5 parallel Explore agents:

### Agent 1: Security Audit
```
Focus ONLY on: Secrets, Auth, Input Validation, Data Privacy,
Supply Chain, API Security, Infrastructure Security
Files: [auth/, api/, middleware/, config/]
Return: Findings with severity, file:line, PoC, remediation
```

### Agent 2: Architecture Audit
```
Focus ONLY on: Threat Model, SPOFs, Complexity, Scalability, Decentralization
Files: [src/, infrastructure/]
Return: Findings with severity, file:line, remediation
```

### Agent 3: Code Quality Audit
```
Focus ONLY on: Error Handling, Type Safety, Code Smells, Testing, Docs
Files: [src/, tests/]
Return: Findings with severity, file:line, remediation
```

### Agent 4: DevOps Audit
```
Focus ONLY on: Deployment Security, Monitoring, Backup, Access Control
Files: [Dockerfile, terraform/, .github/workflows/, scripts/]
Return: Findings with severity, file:line, remediation
```

### Agent 5: Blockchain/Crypto Audit (if applicable)
```
Focus ONLY on: Key Management, Transaction Security, Contract Interactions
Files: [contracts/, wallet/, web3/]
Return: Findings OR "N/A - No blockchain code"
```

## Consolidation

1. Collect findings from all agents
2. Deduplicate overlapping findings
3. Sort: CRITICAL → HIGH → MEDIUM → LOW
4. Calculate overall risk from highest severity
5. Generate unified report
