# Paranoid Cypherpunk Security Auditor

## Agent Profile

**Agent Name**: `paranoid-auditor`
**Role**: Security Auditor
**Experience**: 30+ years
**Command**: `/audit`
**Model**: Sonnet
**Usage**: Ad-hoc (not part of linear workflow)

## Purpose

Perform comprehensive security and quality audits of codebases, infrastructure, and implementations. Provides brutally honest assessment with prioritized vulnerability findings and actionable remediation guidance.

## When to Use This Agent

See the complete agent definition at `.claude/agents/paranoid-auditor.md` for detailed usage examples and workflow.

### Common Scenarios

- Before production deployment (highly recommended)
- After major code changes or new features
- When implementing security-sensitive functionality (authentication, payments, data handling)
- After adding new dependencies or integrations
- Periodically for ongoing projects (quarterly recommended)
- When compliance or security certification is required

Check the agent file for specific invocation examples and detailed process descriptions.

## Key Deliverables

- `SECURITY-AUDIT-REPORT.md` - Comprehensive audit report with:
  - Executive summary and overall risk assessment
  - CRITICAL findings (must fix immediately)
  - HIGH priority findings (fix before production)
  - MEDIUM priority findings (schedule for upcoming sprints)
  - LOW priority findings (backlog items)
  - Threat model analysis
  - Security checklist with compliance status
  - Actionable remediation guidance with code examples

Refer to the agent definition file for complete deliverables and output specifications.

## Workflow

The agent follows a comprehensive audit methodology defined in `.claude/agents/paranoid-auditor.md`:

1. **Comprehensive Security Assessment**
   - OWASP Top 10 vulnerability scanning
   - Code review for security anti-patterns
   - Dependency and supply chain analysis
   - Cryptographic implementation review
   - Secrets and credential management audit
   - Input validation and sanitization review
   - Authentication and authorization analysis
   - Data privacy and PII handling assessment
   - Infrastructure security evaluation
   - Error handling and information disclosure review

2. **Audit Report Generation**
   - Findings categorized by severity
   - Detailed vulnerability descriptions
   - Security impact and exploitation scenarios
   - Specific remediation guidance
   - Overall risk assessment

3. **Follow-up Support**
   - Review fixes after implementation
   - Verify remediation effectiveness
   - Re-audit after critical fixes

For complete workflow details, process phases, and operational guidelines, consult the agent definition file.

## Integration with Other Agents

This agent operates independently (ad-hoc) but integrates with the workflow:

- **Typical Usage**: Run before Phase 6 (Deployment) to ensure production-readiness
- **Can be invoked**: At any point in the workflow when security review is needed
- **Related Workflow**: See [PROCESS.md](../PROCESS.md) for complete process documentation
- **Agent Index**: See [00-INDEX.md](./00-INDEX.md) for all agents overview

## Best Practices

- Run audit before every production deployment
- Address all CRITICAL findings before going live
- Re-run audit after fixing critical issues to verify fixes
- Use audit report as input for security documentation
- Track security debt and remediation progress
- Integrate security reviews into CI/CD pipeline

Consult the agent definition file at `.claude/agents/paranoid-auditor.md` for:
- Detailed best practices
- Quality standards
- Communication style (brutally honest)
- Decision-making frameworks
- Edge cases and special situations

## Audit Scope

The audit covers:

- ✅ Injection vulnerabilities (SQL, command, XSS, etc.)
- ✅ Authentication and session management
- ✅ Sensitive data exposure
- ✅ XML/XXE attacks
- ✅ Broken access control
- ✅ Security misconfiguration
- ✅ Cross-Site Scripting (XSS)
- ✅ Insecure deserialization
- ✅ Using components with known vulnerabilities
- ✅ Insufficient logging and monitoring
- ✅ Cryptographic implementation
- ✅ API security
- ✅ Secrets management
- ✅ Infrastructure security

## Further Reading

- **Agent Definition**: `.claude/agents/paranoid-auditor.md` (complete agent prompt and instructions)
- **Command Definition**: `.claude/commands/audit.md` (slash command implementation)
- **Process Documentation**: [PROCESS.md](../PROCESS.md) (complete workflow including audit phase)
- **Agent Index**: [00-INDEX.md](./00-INDEX.md) (all agents overview)

---

*For the most up-to-date and detailed information about this agent, always refer to the source definition at `.claude/agents/paranoid-auditor.md`*
