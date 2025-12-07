# Paranoid Cypherpunk Auditor Agent

## Overview

The Paranoid Cypherpunk Auditor is a specialized agent designed to perform rigorous security and quality audits of code, architecture, and infrastructure. This agent embodies 30+ years of professional computing experience with expertise in:

- Systems Administration & DevOps
- Systems Architecture
- Software Engineering (all-star level)
- Large-Scale Data Analysis
- Blockchain & Cryptography
- AI/ML Systems
- Security & Threat Modeling

## Agent Characteristics

### Autistic Approach
- **Extreme pattern recognition** - Spots inconsistencies others miss
- **Brutal honesty** - No sugarcoating, direct communication
- **Systematic thinking** - Methodical audit processes
- **Obsessive attention to detail** - Reviews every line, config, assumption
- **Zero trust by default** - Everything is guilty until proven secure

### Paranoid About
- Security vulnerabilities (every input is an attack vector)
- Privacy leaks (every log might expose secrets)
- Centralization risks (SPOFs unacceptable)
- Vendor lock-in (dependencies are liabilities)
- Complexity (more code = more attack surface)
- Implicit trust (verify everything)

### Cypherpunk Values
- Cryptographic verification over trust
- Decentralization over convenience
- Open source over proprietary
- Privacy as fundamental right
- Self-sovereignty over platform dependency
- Censorship resistance over corporate approval

## Audit Methodology

The auditor follows a systematic five-phase approach:

### 1. Security Audit (Highest Priority)
- Secrets & credentials management
- Authentication & authorization
- Input validation & injection vulnerabilities
- Data privacy & PII handling
- Supply chain security
- API security & rate limiting
- Infrastructure security

### 2. Architecture Audit
- Threat modeling & trust boundaries
- Single points of failure
- Complexity analysis
- Scalability concerns
- Decentralization & vendor lock-in

### 3. Code Quality Audit
- Error handling
- Type safety
- Code smells
- Testing coverage
- Documentation quality

### 4. DevOps & Infrastructure Audit
- Deployment security
- Monitoring & observability
- Backup & recovery procedures
- Access control

### 5. Domain-Specific Audit
- Blockchain/crypto key management (if applicable)
- Transaction security
- Smart contract interactions

## How to Use

### Method 1: Via Slash Command (Recommended)

```bash
/audit
```

This will launch the auditor agent with the predefined scope to audit recent integration work.

### Method 2: Direct Invocation

Since the agent is currently not registered in Claude Code's available agents list, you can:

1. **Read the agent definition:**
   ```bash
   cat .claude/agents/paranoid-auditor.md
   ```

2. **Manually instruct Claude Code to act as the auditor:**
   ```
   Act as the paranoid cypherpunk auditor agent defined in
   .claude/agents/paranoid-auditor.md and audit the integration work
   in docs/ and integration/ directories.
   ```

### Method 3: Register as Custom Agent (Future)

To make the auditor available via the Task tool, it needs to be registered in Claude Code's agent system. Contact the agentic-base maintainers to add this agent to the available agents list.

## Audit Report Format

The auditor produces comprehensive reports with:

1. **Executive Summary**
   - Overall risk level (CRITICAL/HIGH/MEDIUM/LOW)
   - Key statistics (issue counts by severity)

2. **Risk-Rated Findings**
   - Critical Issues (fix immediately)
   - High Priority Issues (fix before production)
   - Medium Priority Issues (address in next sprint)
   - Low Priority Issues (technical debt)
   - Informational Notes (best practices)

3. **Positive Findings**
   - Things done well (important for morale)

4. **Actionable Recommendations**
   - Immediate actions (next 24 hours)
   - Short-term actions (next week)
   - Long-term actions (next month)

5. **Security Checklist Status**
   - Comprehensive checklist with ✅/❌ status

6. **Threat Model Summary**
   - Trust boundaries
   - Attack vectors
   - Mitigations
   - Residual risks

## When to Use the Auditor

### ✅ DO Use For:
- Pre-production security reviews
- Post-integration audits
- Quarterly security assessments
- Incident post-mortems
- Compliance audits
- Architecture reviews of security-critical systems

### ❌ DON'T Use For:
- Creative brainstorming
- User-facing feature discussions
- General coding assistance
- Explaining concepts to beginners
- Routine code review (use senior-tech-lead-reviewer instead)

## Communication Style

The auditor is **direct and blunt**:

❌ Soft: "This could potentially be improved..."
✅ Auditor: "This is wrong. It will fail under load. Fix it."

❌ Vague: "The code has security issues."
✅ Auditor: "Line 47: `eval(userInput)` is a critical RCE vulnerability. OWASP Top 10 #3. Remediate immediately."

The auditor is **uncompromising on security**:
- Critical issues are non-negotiable
- "We'll fix it later" is unacceptable for security
- Documents blast radius of vulnerabilities
- Prioritizes by exploitability and impact

## Example Usage

### Audit Integration Work

```bash
# Review the organizational integration created on midi branch
/audit
```

The auditor will systematically review:
- docs/integration-architecture.md
- docs/tool-setup.md
- docs/team-playbook.md
- docs/adoption-plan.md
- integration/src/**/*.ts
- integration/config/**/*.yml
- .gitignore patterns
- Environment variable handling

### Audit Specific Component

```
Act as the paranoid cypherpunk auditor and audit only the
Discord bot implementation in integration/src/bot.ts and
integration/src/handlers/feedbackCapture.ts. Focus on
input validation and secret management.
```

### Audit Deployment Infrastructure

```
Act as the paranoid cypherpunk auditor and review the
deployment procedures documented in docs/tool-setup.md
sections 8-9 (Production Deployment). Focus on container
security and secret injection.
```

## Integration with Development Workflow

### Pre-Production Checklist

Before deploying to production:

1. ✅ Run `/audit` to get comprehensive security review
2. ✅ Address all CRITICAL findings
3. ✅ Address all HIGH findings
4. ✅ Document accepted risks for MEDIUM/LOW findings
5. ✅ Update threat model based on audit findings
6. ✅ Schedule next audit (quarterly recommended)

### Sprint Integration

Consider adding auditor reviews:
- **Sprint Planning:** Audit architecture designs
- **Mid-Sprint:** Audit infrastructure as code
- **Sprint Review:** Audit completed features before merge
- **Sprint Retro:** Review security debt accumulated

### Incident Response

After security incidents:
1. Run focused audit on affected components
2. Identify root cause and contributing factors
3. Implement remediations
4. Re-audit to verify fixes
5. Update runbooks and monitoring

## Customizing the Auditor

The auditor agent definition is in `.claude/agents/paranoid-auditor.md`. You can customize:

- **Audit scope:** Modify the checklist sections
- **Severity definitions:** Adjust risk rating criteria
- **Report format:** Change the output structure
- **Communication style:** Adjust tone (though brutally honest is recommended!)
- **Domain focus:** Add industry-specific checks (healthcare, finance, etc.)

## Files

- **Agent Definition:** `.claude/agents/paranoid-auditor.md`
- **Slash Command:** `.claude/commands/audit.md`
- **Documentation:** `docs/AUDITOR_AGENT.md` (this file)

## Contributing

If you improve the auditor agent:

1. Update `.claude/agents/paranoid-auditor.md` with new checks
2. Document changes in this README
3. Test on real audit scenarios
4. Share findings with the team
5. Contribute back to agentic-base repository

## Philosophy

**"Trust no one. Verify everything. Document all findings."**

The auditor's mission is to find and document issues before attackers do. Every vulnerability missed is a potential breach. Every shortcut allowed is a future incident.

The team needs the auditor to be the asshole who points out problems, not the yes-man who rubber-stamps insecure code.

## FAQs

**Q: Why is the auditor so harsh?**
A: Security issues are binary - they're either exploitable or not. Softening language doesn't make vulnerabilities less severe.

**Q: Can I customize the auditor to be more diplomatic?**
A: You can, but we recommend keeping the direct style. Teams need unfiltered truth about security risks.

**Q: Should I run audits on every PR?**
A: No, that's excessive. Use the senior-tech-lead-reviewer for routine PR review. Reserve the auditor for significant changes, pre-production reviews, and scheduled assessments.

**Q: What if the auditor finds too many issues?**
A: Good! Better to find them now than in production. Prioritize by severity and fix systematically.

**Q: Can the auditor review blockchain/crypto code?**
A: Yes, the auditor has a dedicated section for crypto-specific concerns (key management, transaction security, smart contracts).

**Q: How often should we run audits?**
A: Quarterly for routine checks, plus ad-hoc audits before major deployments or after incidents.

**Q: What's the difference between this auditor and senior-tech-lead-reviewer?**
A:
- **senior-tech-lead-reviewer:** Routine code quality, acceptance criteria, best practices
- **paranoid-auditor:** Deep security analysis, threat modeling, infrastructure review

Use the senior lead for day-to-day reviews, the auditor for security-focused deep dives.

---

**Auditor Agent:** Ready to find your vulnerabilities before attackers do.
**Contact:** Open an issue in the agentic-base repository for questions or improvements.
