# DevRel Translator Reference

## Audience Analysis Matrix

### Technical Level Guide

| Audience | Technical Level | Primary Concerns | Communication Style |
|----------|-----------------|------------------|---------------------|
| CEO/COO | Very Low | Business impact, strategy | Bottom-line first, metrics |
| CFO | Very Low | Cost, ROI, budget | Financial framing |
| Board | Very Low | Governance, risk, strategy | Strategic, formal |
| Investors | Very Low | ROI, market position | Growth-focused, metrics |
| Product Manager | Medium | Features, timeline, users | Feature-focused |
| Marketing | Low | Messaging, positioning | Benefits-focused |
| Sales | Low | Customer value, competition | Value proposition |
| Legal/Compliance | Low-Medium | Risk, regulations | Precise, documented |
| CTO/Tech Lead | High | Architecture, decisions | Technical depth OK |
| DevRel | High | Implementation, patterns | Full technical |

### What Each Audience Cares About

| Audience | Cares About | Doesn't Care About |
|----------|-------------|-------------------|
| Executives | Business value, risk, timeline | Implementation details |
| Board | Strategy, governance, compliance | Technical specifics |
| Investors | Growth, metrics, competitive position | Day-to-day operations |
| Product | Features, UX, timeline | Infrastructure details |
| Marketing | Benefits, positioning, messaging | Technical architecture |
| Compliance | Regulations, audit trail, risk | Performance metrics |
| Technical | Architecture, decisions, tradeoffs | Marketing messaging |

## Translation Checklist

### Before Writing
- [ ] Identified target audience
- [ ] Understood their technical level
- [ ] Identified their primary concerns
- [ ] Read all source documents thoroughly
- [ ] Noted key metrics and achievements
- [ ] Identified risks and limitations
- [ ] Determined what decisions need to be made

### While Writing
- [ ] Leading with business value, not technical details
- [ ] Using analogies for complex concepts
- [ ] Quantifying impact with specific metrics
- [ ] Acknowledging risks and limitations honestly
- [ ] Including clear next steps
- [ ] Avoiding jargon (or defining it immediately)
- [ ] Using active voice
- [ ] Being specific, not vague

### After Writing
- [ ] Non-technical person could understand this
- [ ] "So what?" is answered
- [ ] "What's next?" is clear
- [ ] Risks are communicated
- [ ] Recommendations are actionable
- [ ] Source documents are cited
- [ ] Visual suggestions included where helpful

## Common Technical Terms → Business Translations

### Architecture Terms
| Technical Term | Business Translation |
|----------------|---------------------|
| API | Connection point between systems |
| Microservices | Modular system design (easy to update individually) |
| Database | Where we store information |
| Cache | Fast-access memory (improves speed) |
| Load balancer | Traffic distributor (prevents overload) |
| CI/CD | Automated deployment pipeline |
| Infrastructure as Code | Automated, repeatable server setup |

### Security Terms
| Technical Term | Business Translation |
|----------------|---------------------|
| Authentication | Verifying who you are (like showing ID) |
| Authorization | Verifying what you can do (like badge access levels) |
| RBAC | Role-based permissions (different access for different roles) |
| Encryption | Scrambling data so only authorized parties can read it |
| TLS/SSL | Secure connection (the lock icon in browsers) |
| Vulnerability | Security weakness that could be exploited |
| Penetration testing | Simulated attack to find weaknesses |
| MFA/2FA | Two-step verification (password + phone code) |

### Development Terms
| Technical Term | Business Translation |
|----------------|---------------------|
| Sprint | Time-boxed development cycle (usually 2 weeks) |
| Refactoring | Improving code without changing functionality |
| Technical debt | Shortcuts that need to be fixed later |
| Test coverage | Percentage of code tested automatically |
| Bug | Defect in the software |
| Feature flag | On/off switch for new features |
| Rollback | Reverting to previous version |

### Performance Terms
| Technical Term | Business Translation |
|----------------|---------------------|
| Latency | Delay/response time |
| Throughput | How much work the system can handle |
| Uptime | Time the system is available |
| SLA | Service commitment (e.g., 99.9% uptime) |
| Scalability | Ability to handle growth |
| Bottleneck | Point that limits overall performance |

## Analogy Bank

### Security Analogies
| Concept | Analogy |
|---------|---------|
| Authentication | Security guard checking your ID |
| Authorization | Badge access levels in an office building |
| Firewall | Bouncer at a club checking the list |
| Encryption | Speaking in code only you and recipient understand |
| Multi-factor auth | Key + fingerprint to open a safe |
| VPN | Private tunnel through public space |
| Audit log | Security camera footage |

### Architecture Analogies
| Concept | Analogy |
|---------|---------|
| Microservices | Lego blocks vs. one solid piece |
| API | Waiter taking orders between kitchen and customers |
| Load balancer | Traffic cop directing cars |
| Cache | Keeping frequently used items on your desk |
| Database | Filing cabinet for information |
| Cloud | Renting vs. owning a building |
| Containers | Shipping containers (standardized, portable) |

### Process Analogies
| Concept | Analogy |
|---------|---------|
| Agile/Sprints | Building in stages, reviewing as you go |
| CI/CD | Assembly line with quality checks |
| Code review | Peer editing before publication |
| Testing | Dress rehearsal before the show |
| Staging | Test kitchen before restaurant opening |
| Rollback | Undo button for the whole system |

## Risk Communication Framework

### Severity Levels (for executives)

| Level | Business Meaning | Action Required |
|-------|------------------|-----------------|
| Critical | Business cannot operate | Immediate fix (24 hours) |
| High | Significant impact | Fix before production |
| Medium | Limited impact | Address in next sprint |
| Low | Minor concern | Address when convenient |

### Risk Matrix Template

```
Impact →      Low         Medium       High
Likelihood ↓
High         Medium      High         Critical
Medium       Low         Medium       High
Low          Low         Low          Medium
```

### Risk Communication Structure
1. **What is the risk?** (plain language)
2. **What could happen?** (worst case scenario)
3. **How likely is it?** (probability)
4. **What are we doing about it?** (mitigation)
5. **What's the residual risk?** (after mitigation)

## Document Structure Templates

### Executive Summary Structure
1. **What we built** (1-2 sentences, no jargon)
2. **Why it matters** (business value, strategic alignment)
3. **Key achievements** (3-5 bullet points with metrics)
4. **Risks & limitations** (honest assessment)
5. **Next steps** (clear recommendations)
6. **Resources needed** (timeline, budget, people)

### Progress Update Structure
1. **Bottom line** (on track / delayed / blocked)
2. **What we delivered** (accomplishments)
3. **What's deferred** (and why)
4. **Key metrics** (quantified progress)
5. **What's next** (upcoming work)
6. **Needs from leadership** (decisions, resources)

### Risk Assessment Structure
1. **Overall risk level** (Critical/High/Medium/Low)
2. **Key risks identified** (top 3-5)
3. **Mitigation status** (what we've done)
4. **Residual risks** (what remains)
5. **Recommendations** (what leadership should do)

## Visual Communication Guide

### When to Suggest Visuals

| Concept Type | Suggested Visual |
|--------------|------------------|
| System relationships | Architecture diagram |
| Data movement | Flow diagram |
| Process steps | Flowchart |
| Risk assessment | Risk matrix |
| Timeline | Gantt chart or roadmap |
| Comparisons | Table or bar chart |
| Progress | Progress bar or burndown chart |
| Metrics over time | Line chart |
| Proportions | Pie chart |

### Diagram Description Format
When suggesting visuals, describe:
1. **Type of visual** (diagram, chart, table)
2. **Purpose** (what it shows)
3. **Key elements** (what to include)
4. **Placement** (where in document)

## FAQ Development Guide

### Common Stakeholder Questions by Audience

**Executives:**
- What's the business value?
- What's the risk?
- When will it be ready?
- What resources do you need?
- What decisions do you need from me?

**Board:**
- How does this align with strategy?
- What are the governance implications?
- What are the compliance risks?
- How does this compare to competitors?

**Investors:**
- What's the ROI?
- How does this affect growth?
- What's the competitive advantage?
- What's the market opportunity?

**Product:**
- What features does this enable?
- How does this affect users?
- What's the timeline?
- What are the dependencies?

**Compliance:**
- Does this meet regulatory requirements?
- What data is collected/stored?
- How is data protected?
- Is there an audit trail?

## Quality Standards

### Metrics Quality
- [ ] Specific (not "improved" → "improved by 40%")
- [ ] Sourced (cite where metric came from)
- [ ] Relevant (matters to audience)
- [ ] Comparable (industry benchmark if available)
- [ ] Honest (don't cherry-pick)

### Recommendation Quality
- [ ] Specific (not "consider improvements")
- [ ] Actionable (clear next step)
- [ ] Owned (who should do it)
- [ ] Time-bound (when should it happen)
- [ ] Realistic (achievable)

### Risk Communication Quality
- [ ] Honest (don't minimize)
- [ ] Contextual (explain likelihood)
- [ ] Actionable (what can be done)
- [ ] Complete (don't hide problems)
- [ ] Balanced (don't catastrophize)

---

## /ride Translation Guide (v2.0)

### Ground Truth Artifacts

The following artifacts are generated by `/ride` and require translation:

| Artifact | Path | Focus |
|----------|------|-------|
| Drift Report | `grimoires/loa/drift-report.md` | Ghost Features, Shadow Systems |
| Governance Report | `grimoires/loa/governance-report.md` | Process maturity, compliance |
| Consistency Report | `grimoires/loa/consistency-report.md` | Code patterns, velocity |
| Hygiene Report | `grimoires/loa/reality/hygiene-report.md` | Technical debt, decisions |
| Trajectory Audit | `grimoires/loa/trajectory-audit.md` | Analysis confidence |

### Truth Hierarchy

```
CODE > Loa Artifacts > Legacy Docs > User Context
```

When documentation claims X but code shows Y, ALWAYS side with code.

### Financial Audit Terminology

| Technical | Audit Analogy | Business Translation |
|-----------|---------------|---------------------|
| Ghost Feature | Phantom Asset | "On the books but not in the vault" |
| Shadow System | Undisclosed Liability | "In the vault but not on the books" |
| Drift | Books != Inventory | "What we say != what we have" |
| Technical Debt | Deferred Maintenance | "Repairs we're postponing" |
| Strategic Liability | Material Weakness | "Risk requiring board attention" |

### Health Score Formula

```
HEALTH = (100 - drift%) x 0.50 + (consistency x 10) x 0.30 + (100 - hygiene x 5) x 0.20
```

| Component | Weight | Source |
|-----------|--------|--------|
| Documentation Alignment | 50% | drift-report.md |
| Code Consistency | 30% | consistency-report.md |
| Technical Hygiene | 20% | hygiene-report.md |

### Audience Adaptation for /ride

| Audience | Ghost Feature | Shadow System | Drift |
|----------|---------------|---------------|-------|
| Board | "Phantom asset on books" | "Undisclosed liability" | "34% documentation risk" |
| Investors | "Vaporware in prospectus" | "Hidden dependency risk" | "40hr remediation debt" |
| Executives | "Promise we haven't kept" | "System we don't know about" | "34% docs don't match reality" |
| Compliance | "Documentation gap" | "Untracked dependency" | "Audit finding exposure" |
| Eng Leadership | "Documented but unimplemented" | "Undocumented feature" | "Doc-code sync needed" |

### Grounding Protocol

Every claim MUST use one of these citation formats:

| Claim Type | Format | Example |
|------------|--------|---------|
| Direct quote | `"[quote]" (file:L##)` | `"OAuth not found" (drift-report.md:L45)` |
| Metric | `{value} (source: file:L##)` | `34% drift (source: drift-report.md:L1)` |
| Calculation | `(calculated from: file)` | `Health: 66% (calculated from: drift-report.md)` |
| Code ref | `(file.ext:L##)` | `RateLimiter (src/middleware/rate.ts:45)` |
| Assumption | `[ASSUMPTION] {claim}` | `[ASSUMPTION] OAuth was descoped` |

### Assumption Handling

Ungrounded claims MUST be flagged:

```markdown
[ASSUMPTION] The database likely needs connection pooling
  -> Requires validation by: Engineering Lead
  -> Confidence: MEDIUM
  -> Basis: Inferred from traffic patterns
```

### Translation Output Structure

```
grimoires/loa/translations/
+-- EXECUTIVE-INDEX.md       <- Start here (Balance Sheet of Reality)
+-- drift-analysis.md        <- Ghost Features (Phantom Assets)
+-- governance-assessment.md <- Compliance Gaps
+-- consistency-analysis.md  <- Velocity Indicators
+-- hygiene-assessment.md    <- Strategic Liabilities
+-- quality-assurance.md     <- Confidence Assessment
+-- translation-audit.md     <- Self-audit trail
```

### Self-Audit Checklist

Before completing translation:

- [ ] All metrics cite source file and line
- [ ] All claims grounded or flagged [ASSUMPTION]
- [ ] All Ghost Features cite evidence of absence
- [ ] All Shadow Systems cite code location
- [ ] Health score uses official weighted formula
- [ ] All jargon has business analogy
- [ ] Every finding answers "So what?"
- [ ] Actions have owner + timeline
- [ ] Beads suggested for strategic liabilities
