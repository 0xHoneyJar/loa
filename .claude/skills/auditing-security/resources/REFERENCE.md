# Paranoid Auditor Reference

## Security Audit Checklist

### Secrets & Credentials
- [ ] Are secrets hardcoded anywhere? (CRITICAL)
- [ ] Are API tokens logged or exposed in error messages?
- [ ] Is .gitignore comprehensive?
- [ ] Are secrets rotated regularly?
- [ ] Are secrets encrypted at rest?
- [ ] Can secrets be recovered if lost?

### Authentication & Authorization
- [ ] Is authentication required for all sensitive operations?
- [ ] Are authorization checks performed server-side?
- [ ] Can users escalate privileges?
- [ ] Are session tokens properly scoped and time-limited?
- [ ] Is there protection against token theft or replay?
- [ ] Are API tokens using least privilege?

### Input Validation
- [ ] Is ALL user input validated and sanitized?
- [ ] Are there injection vulnerabilities? (SQL, command, code, XSS)
- [ ] Are file uploads validated? (Type, size, content)
- [ ] Are webhook payloads verified (signature/HMAC)?
- [ ] Are message contents sanitized before processing?

### Data Privacy
- [ ] Is PII logged?
- [ ] Are user IDs/emails exposed unnecessarily?
- [ ] Is communication encrypted in transit?
- [ ] Are logs secured and access-controlled?
- [ ] Is there a data retention policy?
- [ ] Can users delete their data?

### Supply Chain Security
- [ ] Are dependencies pinned to exact versions?
- [ ] Are dependencies audited for vulnerabilities?
- [ ] Are there known CVEs in current dependencies?
- [ ] Is there a process to update vulnerable dependencies?
- [ ] Are dependencies from trusted sources?

### API Security
- [ ] Are API rate limits implemented?
- [ ] Is there exponential backoff for retries?
- [ ] Are API responses validated before use?
- [ ] Is there circuit breaker logic?
- [ ] Are API errors handled securely?
- [ ] Are webhooks authenticated?

### Infrastructure Security
- [ ] Are production secrets separate from development?
- [ ] Is the process isolated? (Docker, VM, least privilege)
- [ ] Are logs rotated and secured?
- [ ] Is there monitoring for suspicious activity?
- [ ] Are firewall rules restrictive?
- [ ] Is SSH hardened?

## Architecture Audit Checklist

### Threat Modeling
- [ ] What are the trust boundaries?
- [ ] What happens if each component is compromised?
- [ ] What's the blast radius of each failure?
- [ ] Are there cascading failure scenarios?

### Single Points of Failure
- [ ] Is there a single instance? (No HA)
- [ ] What if external services go down?
- [ ] Are there fallback channels?
- [ ] Can the system recover from data loss?
- [ ] Is there a disaster recovery plan?

### Complexity Analysis
- [ ] Is the architecture overly complex?
- [ ] Are there unnecessary abstractions?
- [ ] Is the code DRY?
- [ ] Are there circular dependencies?
- [ ] Can components be tested in isolation?

### Scalability Concerns
- [ ] What happens at 10x current load?
- [ ] Are there unbounded loops or recursion?
- [ ] Are there memory leaks?
- [ ] Are database queries optimized?
- [ ] Are there pagination limits?

### Decentralization
- [ ] Is there vendor lock-in?
- [ ] Can the team migrate to alternatives?
- [ ] Are data exports available?
- [ ] Is there a path to self-hosted?
- [ ] Are integrations loosely coupled?

## Code Quality Audit Checklist

### Error Handling
- [ ] Are all promises handled?
- [ ] Are errors logged with context?
- [ ] Are error messages sanitized?
- [ ] Are there try-catch around external calls?
- [ ] Is there retry logic with backoff?
- [ ] Are transient errors distinguished from permanent?

### Type Safety
- [ ] Is TypeScript strict mode enabled?
- [ ] Are there `any` types that should be specific?
- [ ] Are API responses typed correctly?
- [ ] Are null/undefined handled properly?
- [ ] Are there runtime type validations?

### Code Smells
- [ ] Functions longer than 50 lines?
- [ ] Files longer than 500 lines?
- [ ] Magic numbers or strings?
- [ ] Commented-out code?
- [ ] TODOs that should be completed?
- [ ] Descriptive variable names?

### Testing
- [ ] Unit tests exist? (Coverage %)
- [ ] Integration tests exist?
- [ ] Security tests exist?
- [ ] Edge cases tested?
- [ ] Error paths tested?
- [ ] CI/CD runs tests?

### Documentation
- [ ] Is threat model documented?
- [ ] Are security assumptions documented?
- [ ] Are all APIs documented?
- [ ] Is there incident response plan?
- [ ] Are deployment procedures documented?
- [ ] Are runbooks available?

## DevOps Audit Checklist

### Deployment Security
- [ ] Are secrets via env vars (not baked into images)?
- [ ] Are containers running as non-root?
- [ ] Are container images scanned?
- [ ] Are base images from official sources and pinned?
- [ ] Is there a rollback plan?
- [ ] Are deployments zero-downtime?

### Monitoring & Observability
- [ ] Are critical metrics monitored?
- [ ] Are there alerts for anomalies?
- [ ] Are logs centralized?
- [ ] Is there distributed tracing?
- [ ] Can you debug without SSH?
- [ ] Is there a status page?

### Backup & Recovery
- [ ] Are configurations backed up?
- [ ] Are secrets backed up securely?
- [ ] Is there a tested restore procedure?
- [ ] What's the RTO?
- [ ] What's the RPO?
- [ ] Are backups encrypted?

### Access Control
- [ ] Who has production access?
- [ ] Is access logged and audited?
- [ ] Is there MFA for critical systems?
- [ ] Are staging and production separate?
- [ ] Can developers access production data?
- [ ] Is there a process for revoking access?

## Blockchain/Crypto Audit Checklist (If Applicable)

### Key Management
- [ ] Are private keys generated securely?
- [ ] Are keys encrypted at rest?
- [ ] Is there a key rotation policy?
- [ ] Are keys backed up?
- [ ] Is there multi-sig?
- [ ] Are HD wallets used?

### Transaction Security
- [ ] Are transaction amounts validated?
- [ ] Is there front-running protection?
- [ ] Are nonces managed correctly?
- [ ] Is there slippage protection?
- [ ] Are gas limits set appropriately?
- [ ] Is there replay attack protection?

### Smart Contract Interactions
- [ ] Are contract addresses verified?
- [ ] Are contract calls validated before signing?
- [ ] Is there reentrancy protection?
- [ ] Are integer overflows prevented?
- [ ] Is there proper access control?
- [ ] Has the contract been audited?

## Red Flags (Immediate CRITICAL)

### Security Red Flags
- Private keys in code or env vars
- SQL queries via string concatenation
- User input not validated
- Secrets in Git history
- Authentication bypassed
- Sensitive data in logs

### Quality Red Flags
- No tests for critical functionality
- Tests that don't actually test anything
- Copy-pasted code blocks
- Functions over 100 lines
- Callback hell (nested promises)
- Empty catch blocks

### Architecture Red Flags
- Tight coupling between components
- Business logic in UI
- Direct database access from routes
- God objects
- Circular dependencies

### Performance Red Flags
- N+1 queries
- Missing database indexes
- Synchronous operations blocking async
- Memory leaks
- Infinite loops without base case

## Severity Classification

### CRITICAL
- Exploitable with immediate impact
- Data breach possible
- Financial loss possible
- Fix within 24 hours

### HIGH
- Exploitable with significant impact
- Security boundary violation
- Fix before production

### MEDIUM
- Limited exploitability
- Defense in depth violation
- Address in next sprint

### LOW
- Best practice violation
- Technical debt
- Address when convenient

## Parallel Audit Guidelines

### When to Split
| Size | Lines | Strategy |
|------|-------|----------|
| SMALL | <2,000 | Sequential |
| MEDIUM | 2,000-5,000 | Consider splitting |
| LARGE | >5,000 | MUST split |

### Category Assignment
- Security: auth/, api/, middleware/, config/
- Architecture: src/, infrastructure/
- Code Quality: src/, tests/
- DevOps: Dockerfile, terraform/, .github/
- Blockchain: contracts/, wallet/, web3/

### Consolidation
1. Collect all findings
2. Deduplicate overlaps
3. Sort by severity
4. Calculate overall risk
5. Generate unified report
