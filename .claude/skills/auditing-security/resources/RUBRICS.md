# Audit Rubrics

Structured evaluation rubrics for each audit category. Use these to score findings consistently.

## How to Use

1. For each dimension, assess the codebase against the criteria
2. Assign score 1-5 based on the rubric
3. Record reasoning trace explaining the score
4. Calculate category average for overall health

---

## Security Rubrics

### SEC-IV: Input Validation
| Score | Criteria |
|-------|----------|
| 5 | All inputs validated, sanitized, and typed. Allowlist approach used. Schema validation on APIs. |
| 4 | Most inputs validated with minor gaps. Edge cases may lack validation. |
| 3 | Basic validation present but incomplete. Some injection risks remain. |
| 2 | Minimal validation. Clear injection vulnerabilities exist. |
| 1 | No input validation. User input flows directly to sensitive operations. |

### SEC-AZ: Authorization
| Score | Criteria |
|-------|----------|
| 5 | RBAC/ABAC properly implemented. All routes protected. Least privilege enforced. |
| 4 | Authorization present with minor gaps (some routes missing checks). |
| 3 | Basic auth checks but inconsistent. Privilege escalation may be possible. |
| 2 | Weak authorization. Easy bypass or missing on critical routes. |
| 1 | No authorization or completely broken access control. |

### SEC-CI: Confidentiality/Integrity
| Score | Criteria |
|-------|----------|
| 5 | Encryption at rest and in transit. Proper key management. Data classified and protected. |
| 4 | Good encryption with minor gaps. Some sensitive data handling could improve. |
| 3 | Basic encryption but inconsistent. Some data exposure risks. |
| 2 | Weak or missing encryption. Sensitive data partially exposed. |
| 1 | No encryption. Sensitive data in plaintext. Secrets in code. |

### SEC-IN: Injection Prevention
| Score | Criteria |
|-------|----------|
| 5 | Parameterized queries everywhere. No string concatenation in queries. ORM used safely. |
| 4 | Mostly safe with minor gaps in edge cases. |
| 3 | Mixed usage. Some queries parameterized, others vulnerable. |
| 2 | Frequent string concatenation in queries. Clear SQL/NoSQL injection paths. |
| 1 | Pervasive injection vulnerabilities. Eval/exec with user input. |

### SEC-AV: Availability/Resilience
| Score | Criteria |
|-------|----------|
| 5 | Rate limiting, circuit breakers, graceful degradation. DoS protection in place. |
| 4 | Good availability measures with minor gaps. |
| 3 | Basic rate limiting but incomplete. Some DoS vectors remain. |
| 2 | Minimal protection. Resource exhaustion possible. |
| 1 | No availability protection. Trivial DoS attacks possible. |

---

## Architecture Rubrics

### ARCH-MO: Modularity
| Score | Criteria |
|-------|----------|
| 5 | Clear separation of concerns. Well-defined interfaces. Easy to modify/extend. |
| 4 | Good modularity with minor coupling issues. |
| 3 | Some modularity but tight coupling in places. |
| 2 | Poor separation. Components heavily interdependent. |
| 1 | Monolithic. No clear boundaries. |

### ARCH-SC: Scalability
| Score | Criteria |
|-------|----------|
| 5 | Horizontally scalable. Stateless services. Caching strategy. Database sharding ready. |
| 4 | Mostly scalable with minor bottlenecks. |
| 3 | Can scale vertically but horizontal scaling problematic. |
| 2 | Scalability issues. Single points of failure. |
| 1 | Cannot scale. Architecture prevents growth. |

### ARCH-RE: Resilience
| Score | Criteria |
|-------|----------|
| 5 | Fault tolerant. Graceful degradation. Retry logic. Health checks. Circuit breakers. |
| 4 | Good resilience with minor gaps. |
| 3 | Basic error handling but cascading failures possible. |
| 2 | Fragile. Single component failure affects system. |
| 1 | No resilience. Any failure brings down system. |

### ARCH-CX: Complexity
| Score | Criteria |
|-------|----------|
| 5 | Simple, elegant design. Easy to understand. Well-documented patterns. |
| 4 | Reasonable complexity with minor over-engineering. |
| 3 | Moderately complex. Learning curve for new developers. |
| 2 | Overly complex. Hard to reason about. |
| 1 | Incomprehensible. Spaghetti architecture. |

### ARCH-ST: Standards Compliance
| Score | Criteria |
|-------|----------|
| 5 | Follows industry standards. Best practices throughout. Consistent patterns. |
| 4 | Mostly compliant with minor deviations. |
| 3 | Mixed adherence. Some non-standard approaches. |
| 2 | Frequent deviations from standards. |
| 1 | Ignores standards. Anti-patterns throughout. |

---

## Code Quality Rubrics

### CQ-RD: Readability
| Score | Criteria |
|-------|----------|
| 5 | Self-documenting code. Clear naming. Consistent formatting. Easy to follow. |
| 4 | Good readability with minor issues. |
| 3 | Readable but inconsistent. Some confusing sections. |
| 2 | Hard to read. Poor naming. Inconsistent style. |
| 1 | Incomprehensible. No standards followed. |

### CQ-TC: Test Coverage
| Score | Criteria |
|-------|----------|
| 5 | >80% coverage. Unit, integration, e2e tests. Critical paths covered. |
| 4 | Good coverage (60-80%) with minor gaps. |
| 3 | Moderate coverage (40-60%). Critical paths tested. |
| 2 | Low coverage (<40%). Many untested paths. |
| 1 | No tests or tests don't run. |

### CQ-EH: Error Handling
| Score | Criteria |
|-------|----------|
| 5 | Comprehensive error handling. Meaningful messages. Proper logging. Recovery paths. |
| 4 | Good handling with minor gaps. |
| 3 | Basic try/catch but generic errors. Some unhandled paths. |
| 2 | Minimal error handling. Silent failures. |
| 1 | No error handling. Crashes on errors. |

### CQ-TS: Type Safety
| Score | Criteria |
|-------|----------|
| 5 | Strong typing throughout. No `any`. Validated at boundaries. |
| 4 | Good typing with minor gaps. |
| 3 | Partial typing. Some `any` usage. |
| 2 | Weak typing. Frequent `any` or type assertions. |
| 1 | No types or types ignored. |

### CQ-DC: Documentation
| Score | Criteria |
|-------|----------|
| 5 | Comprehensive docs. API documented. README current. Architecture explained. |
| 4 | Good docs with minor gaps. |
| 3 | Basic docs but outdated or incomplete. |
| 2 | Minimal docs. Missing critical information. |
| 1 | No documentation. |

---

## DevOps Rubrics

### DO-AU: Automation
| Score | Criteria |
|-------|----------|
| 5 | Full CI/CD. Automated testing, building, deployment. Infrastructure as code. |
| 4 | Good automation with minor manual steps. |
| 3 | Partial automation. Some manual deployment. |
| 2 | Minimal automation. Mostly manual processes. |
| 1 | No automation. Everything manual. |

### DO-OB: Observability
| Score | Criteria |
|-------|----------|
| 5 | Comprehensive logging, metrics, tracing. Alerting configured. Dashboards available. |
| 4 | Good observability with minor gaps. |
| 3 | Basic logging but limited metrics/tracing. |
| 2 | Minimal logging. No metrics. |
| 1 | No observability. Flying blind. |

### DO-RC: Recovery
| Score | Criteria |
|-------|----------|
| 5 | Automated backups. Tested recovery. RTO/RPO defined and met. |
| 4 | Good backup with minor recovery gaps. |
| 3 | Backups exist but recovery untested. |
| 2 | Minimal backups. Recovery uncertain. |
| 1 | No backups. Data loss likely. |

### DO-AC: Access Control
| Score | Criteria |
|-------|----------|
| 5 | Least privilege. Secrets management. Audit trails. MFA for admin. |
| 4 | Good access control with minor gaps. |
| 3 | Basic access control but some overprivileged accounts. |
| 2 | Weak access control. Shared credentials. |
| 1 | No access control. Credentials in code. |

### DO-DS: Deployment Safety
| Score | Criteria |
|-------|----------|
| 5 | Blue/green or canary deployments. Rollback automated. Feature flags. |
| 4 | Good deployment safety with minor gaps. |
| 3 | Basic rollback capability. Some risk on deploy. |
| 2 | Risky deployments. Manual rollback. |
| 1 | No deployment safety. YOLO deploys. |

---

## Blockchain/Crypto Rubrics (if applicable)

### BC-KM: Key Management
| Score | Criteria |
|-------|----------|
| 5 | HSM or secure enclave. Key rotation. No keys in code. Proper derivation. |
| 4 | Good key management with minor gaps. |
| 3 | Basic key management. Some exposure risks. |
| 2 | Weak key management. Keys in environment. |
| 1 | Keys in code. No management. |

### BC-TX: Transaction Safety
| Score | Criteria |
|-------|----------|
| 5 | Transaction signing secure. Nonce management. Gas optimization. Replay protection. |
| 4 | Good transaction handling with minor gaps. |
| 3 | Basic transaction safety. Some edge cases risky. |
| 2 | Transaction vulnerabilities present. |
| 1 | Insecure transaction handling. |

### BC-SC: Smart Contract Security
| Score | Criteria |
|-------|----------|
| 5 | Audited contracts. Reentrancy protection. Access controls. Upgrade patterns. |
| 4 | Good contract security with minor gaps. |
| 3 | Basic security but some vulnerabilities possible. |
| 2 | Known vulnerability patterns present. |
| 1 | Insecure contracts. Critical vulnerabilities. |

---

## Score Aggregation

**Category Score** = Average of dimension scores (rounded to 1 decimal)

**Overall Score** = Weighted average:
- Security: 30%
- Architecture: 20%
- Code Quality: 20%
- DevOps: 20%
- Blockchain: 10% (if applicable, else redistribute)

**Risk Level Mapping**:
| Score | Risk Level |
|-------|------------|
| 4.5-5.0 | LOW |
| 3.5-4.4 | MODERATE |
| 2.5-3.4 | HIGH |
| 1.0-2.4 | CRITICAL |
