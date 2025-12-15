# Meta Knowledge Base Integration Plan
## Incorporating THJ Meta Knowledge into PRD and Agent Workflows

**Date:** 2025-12-11
**Version:** 1.1
**Status:** Planning (Updated with Actual Structure)
**Repository:** https://github.com/0xHoneyJar/thj-meta-knowledge (Private)
**Local Path:** `/home/merlin/Documents/thj/code/thj-meta-knowledge/`

---

## Executive Summary

This document outlines the plan for integrating The Honey Jar's organizational meta knowledge base into the Onomancer Bot PRD and agentic-base workflow. The meta knowledge base serves as the organization's single source of truth for:

- Company standards, patterns, and conventions
- Historical decisions and their rationale (ADRs)
- Product context and domain knowledge
- Team processes and best practices
- Organizational culture and values
- Technical debt registry and resolution plans

**Goal:** Enable all agents (PRD architect, implementers, reviewers, etc.) to access organizational context when making decisions, ensuring consistency with established patterns and avoiding repeated mistakes.

---

## Current State Analysis

### What We Have

**PRD v1.3 Structure:**
- Comprehensive functional requirements (FR-1 through FR-9)
- Stakeholder feedback integration (7 Linear issues)
- Bibliography section with external resources (Appendix E)
- Related documents section (Appendix A)

**Agent Bibliography Sections:**
- All 9 agents now have bibliography sections
- References to framework docs, APIs, best practices
- No organizational knowledge base references yet

**Gap:**
- No references to org-specific patterns, standards, or historical context
- Agents lack access to institutional knowledge
- Risk of reinventing solutions or repeating past mistakes

### What We Have (Actual Structure)

**Meta Knowledge Base Content (from local repository):**
```
thj-meta-knowledge/
├── README.md                      # Repository overview and navigation
├── LINKS.md                       # Centralized URL registry (all product URLs)
├── TERMINOLOGY.md                 # Glossary of brand-specific terms
├── UNANSWERED_QUESTIONS.md        # Questions needing human input
│
├── ecosystem/                     # High-level architecture
│   ├── OVERVIEW.md                # System map and brand overview
│   └── DATA_FLOW.md               # Data flow patterns
│
├── products/                      # Product documentation (8 products)
│   ├── cubquests/README.md        # Quest platform docs
│   ├── mibera/README.md           # NFT marketplace (shadow realm)
│   ├── henlo/README.md            # Memecoin arcade
│   ├── set-and-forgetti/README.md # DeFi vaults
│   ├── fatbera/README.md          # Liquid staking
│   ├── apdao/README.md            # Governance DAO
│   ├── interpol/README.md         # LP locker
│   └── beraflip/README.md         # (additional product)
│
├── contracts/                     # Smart contract addresses
│   └── REGISTRY.md                # All contracts by category
│
├── decisions/                     # Architecture Decision Records
│   ├── INDEX.md                   # ADR listing (5 documented)
│   ├── TEMPLATE.md                # ADR template
│   ├── ADR-001-envio-indexer-consolidation.md
│   ├── ADR-002-database-platform-supabase-over-convex.md
│   ├── ADR-003-authentication-provider-dynamic-over-alternatives.md
│   ├── ADR-004-internal-first-cubquests.md
│   └── ADR-005-resource-system-core-mechanic.md
│
├── debt/                          # Technical debt registry
│   └── INDEX.md                   # Known issues by product
│
├── knowledge/                     # Developer knowledge captures
│   ├── README.md                  # Knowledge capture overview
│   ├── merlin/                    # Merlin's captured knowledge
│   │   ├── agentic-base.md
│   │   └── score-words.md
│   ├── soju/                      # Soju's captured knowledge (primary)
│   │   ├── cubquests.md
│   │   ├── mibera.md
│   │   ├── henlo.md
│   │   └── discord-bots.md
│   └── ZERGUCCI/                  # Zergucci's captured knowledge
│       ├── sf-contracts.md        # Set & Forgetti contracts
│       └── fatbera-contracts.md   # fatBERA contracts
│
├── infrastructure/                # Deployment & config
│   ├── ENV_VARS.md                # Environment variables by project
│   └── DEPLOYMENTS.md             # Deployment topology
│
├── services/                      # External services inventory
│   └── INVENTORY.md               # Master service list (Envio, Supabase, etc.)
│
├── repos/                         # GitHub repository audit
│   ├── INVENTORY.md               # Active repos (57)
│   └── DEPRECATED.md              # Archived repos (143)
│
├── operations/                    # Operational docs
│   └── FAQ.md                     # Troubleshooting guide
│
├── runbooks/                      # Operational procedures
│   ├── INDEX.md                   # Runbook listing
│   ├── incident-response/
│   ├── deployment/
│   ├── support/
│   └── maintenance/
│
├── audits/                        # Security audits
│   ├── README.md                  # Audit index
│   ├── reports/                   # PDF audit reports
│   └── logs/                      # Documentation audit logs
│
├── prompts/                       # Interview prompts for knowledge capture
│   ├── KNOWLEDGE_CAPTURE.md       # Developer interview template
│   ├── ADR_CAPTURE.md             # Decision documentation template
│   ├── SERVICE_DEEP_DIVE.md       # Service documentation template
│   ├── RUNBOOK_CAPTURE.md         # Operational procedure template
│   ├── AUDIT_CAPTURE.md           # Doc validation template
│   ├── templates/
│   │   └── CONTEXT_BRIEF.md
│   └── modules/
│       └── PRE_EXPLORATION.md
│
└── .meta/                         # AI navigation
    └── RETRIEVAL_GUIDE.md         # How AI should navigate this repo
```

**Key Characteristics:**
- **Central Hub**: Single source of truth for THJ ecosystem knowledge
- **AI-Friendly**: Designed for both humans and AI consumption (see `.meta/RETRIEVAL_GUIDE.md`)
- **Stable Information**: Reference-level content that doesn't change frequently
- **Living Documentation**: Continuously updated through developer interviews
- **Cross-Referenced**: Links to Linear for work items, GitHub for code

---

## Integration Strategy

### Phase 1: PRD Updates (Immediate)

#### 1.1 Add Meta Knowledge Base Section to Appendix

**Location:** `docs/prd.md` - Appendix E: Bibliography & References

**New Subsection:**
```markdown
#### Organizational Meta Knowledge Base

**The Honey Jar Meta Knowledge** (organizational standards, decisions, and context):
- **Repository**: https://github.com/0xHoneyJar/thj-meta-knowledge
- **Standards**:
  - Coding Standards: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/coding-standards.md
  - API Design Patterns: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/api-design.md
  - Security Standards: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/security-standards.md
  - Testing Standards: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/testing-standards.md
- **Architecture Decision Records (ADRs)**:
  - ADR Index: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/decisions/index.md
  - Technology Stack Decisions: See ADRs for rationale behind chosen technologies
  - Database Choices: See ADRs for data storage patterns
- **Product Context**:
  - MiBera Product Context: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/products/mibera/overview.md
  - User Personas: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/products/mibera/user-personas.md
- **Processes**:
  - Development Workflow: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/processes/development-workflow.md
  - Code Review Process: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/processes/review-process.md
  - Incident Response: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/processes/incident-response.md
- **Technical Debt Registry**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/technical-debt/registry.md
- **Templates**: https://github.com/0xHoneyJar/thj-meta-knowledge/tree/main/templates

**Note:** All agents should consult the meta knowledge base when making decisions that may have organizational precedent or when writing code that should follow established patterns.
```

#### 1.2 Update Functional Requirements to Reference Meta Knowledge

**FR-6 (Security & Compliance) - Add subsection:**
```markdown
- **FR-6.9**: Organizational Security Standards Compliance
  - All implementations must comply with THJ security standards
  - Reference: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/security-standards.md
  - Automatic validation against known security patterns
  - Flagging of deviations from established security practices
```

**FR-8 (Comprehensive Knowledge Base) - Update:**
```markdown
- **FR-8.7**: Meta Knowledge Base Integration
  - Link all PRDs, SDDs, and sprint plans to relevant ADRs from meta knowledge base
  - Reference organizational patterns when documenting technical decisions
  - Cite precedent decisions for similar problems
  - Example: "Authentication approach follows ADR-015: OAuth 2.0 for User Auth"
```

#### 1.3 Add Meta Knowledge to Stakeholder Insights

**Update Section 2.5 (Stakeholder Insights) to include:**
```markdown
### Organizational Knowledge Context

The Honey Jar maintains a meta knowledge base that captures:
- **Standards**: How we build software (coding conventions, API patterns, security requirements)
- **Decisions**: Why we made specific technical choices (ADRs with rationale and trade-offs)
- **Products**: Context about our products, users, and domains
- **Processes**: How we work together (development workflow, code reviews, incident response)
- **Technical Debt**: Known issues and resolution plans

**Impact on Requirements:**
- All functional requirements must align with organizational standards
- Technical decisions should reference existing ADRs or create new ones
- Product features must consider existing product context and user personas
- Implementation must follow established development workflows
```

### Phase 2: Agent File Updates (High Priority)

All 9 agents need updated bibliography sections to include meta knowledge base references.

#### 2.1 PRD Architect Agent

**File:** `.claude/agents/prd-architect.md`

**Add to Bibliography Section:**
```markdown
### Organizational Meta Knowledge Base

- **THJ Meta Knowledge Repository**: https://github.com/0xHoneyJar/thj-meta-knowledge
- **Standards & Patterns**:
  - Coding Standards: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/coding-standards.md
  - API Design: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/api-design.md
  - Security Standards: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/security-standards.md
- **Historical Context**:
  - ADR Index: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/decisions/index.md
  - Review ADRs before proposing new architectural approaches
- **Product Context**:
  - Product overviews, user personas, technical context for each THJ product
  - Essential for understanding product requirements and constraints
- **Templates**:
  - PRD Template: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/templates/prd-template.md

**Usage Instructions:**
- When gathering requirements, check if similar features exist in other products (consult product context)
- Reference existing ADRs when technical decisions are needed
- Ensure functional requirements align with organizational security standards
- Use the PRD template structure when generating documents
```

#### 2.2 Architecture Designer Agent

**File:** `.claude/agents/architecture-designer.md`

**Add to Bibliography Section:**
```markdown
### Organizational Meta Knowledge Base

- **THJ Meta Knowledge Repository**: https://github.com/0xHoneyJar/thj-meta-knowledge
- **Architecture Decision Records (ADRs)**:
  - ADR Index: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/decisions/index.md
  - **CRITICAL**: Always review existing ADRs before proposing new architectural approaches
  - If similar decisions exist, reference them and explain why you're following or deviating
  - If no precedent exists, create a new ADR in your SDD
- **Standards**:
  - API Design Patterns: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/api-design.md
  - Security Standards: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/security-standards.md
  - Testing Standards: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/testing-standards.md
- **Technical Debt Registry**:
  - Known technical debt: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/technical-debt/registry.md
  - Avoid introducing solutions that conflict with debt resolution plans
  - Consider existing technical debt when designing new systems

**Usage Instructions:**
- Start SDD generation by reviewing relevant ADRs
- Reference ADRs when justifying technology choices
- Follow established API design patterns
- Ensure architecture complies with security standards
- Check technical debt registry to avoid exacerbating existing problems
- When proposing new architectural patterns, create ADRs with rationale
```

#### 2.3 Sprint Task Implementer Agent

**File:** `.claude/agents/sprint-task-implementer.md`

**Add to Bibliography Section:**
```markdown
### Organizational Meta Knowledge Base

- **THJ Meta Knowledge Repository**: https://github.com/0xHoneyJar/thj-meta-knowledge
- **Coding Standards**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/coding-standards.md
  - **MANDATORY**: All code must follow organizational coding standards
  - Naming conventions, file organization, code style
  - Language-specific patterns and anti-patterns
- **API Design Patterns**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/api-design.md
  - REST API conventions (naming, status codes, error handling)
  - GraphQL patterns (if applicable)
  - Authentication and authorization patterns
- **Testing Standards**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/testing-standards.md
  - Required test coverage thresholds
  - Testing patterns and best practices
  - What to test and what to skip
- **Development Workflow**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/processes/development-workflow.md
  - Git workflow (branch naming, commit messages, PR process)
  - Local development setup
  - CI/CD pipeline expectations

**Usage Instructions:**
- Review coding standards before starting implementation
- Follow API design patterns when creating new endpoints
- Write tests according to testing standards
- Follow development workflow for Git operations
- When in doubt about implementation approach, check if a pattern exists in meta knowledge
```

#### 2.4 Senior Tech Lead Reviewer Agent

**File:** `.claude/agents/senior-tech-lead-reviewer.md`

**Add to Bibliography Section:**
```markdown
### Organizational Meta Knowledge Base

- **THJ Meta Knowledge Repository**: https://github.com/0xHoneyJar/thj-meta-knowledge
- **Coding Standards**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/coding-standards.md
  - **ENFORCE**: Reject code that doesn't follow organizational standards
  - Provide specific citations when requesting changes
- **Code Review Process**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/processes/review-process.md
  - What to check, what to skip
  - When to approve, when to request changes
  - Communication tone and style
- **Security Standards**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/security-standards.md
  - Security requirements that must be validated
  - Common security pitfalls to watch for
- **Testing Standards**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/testing-standards.md
  - Test coverage thresholds
  - Test quality expectations

**Usage Instructions:**
- Compare implementation against coding standards, cite specific violations
- Follow organizational review process guidelines
- Enforce security standards compliance
- Verify test coverage meets organizational thresholds
- When providing feedback, reference meta knowledge patterns: "This doesn't follow our API error handling pattern (see standards/api-design.md#error-handling)"
```

#### 2.5 Paranoid Auditor Agent

**File:** `.claude/agents/paranoid-auditor.md`

**Add to Bibliography Section:**
```markdown
### Organizational Meta Knowledge Base

- **THJ Meta Knowledge Repository**: https://github.com/0xHoneyJar/thj-meta-knowledge
- **Security Standards**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/security-standards.md
  - **PRIMARY REFERENCE**: These are THJ's security requirements
  - Validate all code against these standards
  - Flag deviations as critical findings
- **Technical Debt Registry**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/technical-debt/registry.md
  - Known security-related technical debt
  - Check if new code exacerbates existing security debt
  - Reference existing debt items when finding similar issues
- **Incident Response**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/processes/incident-response.md
  - Security incident history and lessons learned
  - Past vulnerabilities that should never be repeated

**Usage Instructions:**
- Start every audit by reviewing THJ security standards
- Compare implementation against required security controls
- Check technical debt registry for known security issues
- Reference past incidents when they're relevant to findings
- In audit reports, explicitly state: "Violates THJ Security Standard: [link]" for compliance issues
```

#### 2.6 DevOps Crypto Architect Agent

**File:** `.claude/agents/devops-crypto-architect.md`

**Add to Bibliography Section:**
```markdown
### Organizational Meta Knowledge Base

- **THJ Meta Knowledge Repository**: https://github.com/0xHoneyJar/thj-meta-knowledge
- **Infrastructure Standards**: (if exists) https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/infrastructure-standards.md
  - Infrastructure as code patterns
  - Deployment standards
  - Monitoring and observability requirements
- **Security Standards**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/security-standards.md
  - Infrastructure security requirements
  - Secrets management patterns
  - Network security policies
- **Incident Response**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/processes/incident-response.md
  - Incident response runbooks
  - On-call procedures
  - Postmortem templates
- **Technical Debt Registry**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/technical-debt/registry.md
  - Infrastructure-related technical debt
  - Deployment process improvements needed

**Usage Instructions:**
- Follow infrastructure standards when designing deployment architecture
- Ensure security standards are met for all infrastructure components
- Create operational runbooks following incident response templates
- Check technical debt registry before implementing infrastructure changes
```

#### 2.7 Context Engineering Expert Agent

**File:** `.claude/agents/context-engineering-expert.md`

**Add to Bibliography Section:**
```markdown
### Organizational Meta Knowledge Base

- **THJ Meta Knowledge Repository**: https://github.com/0xHoneyJar/thj-meta-knowledge
- **Integration Patterns**: (if exists) https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/integration-patterns.md
  - How THJ connects external tools
  - API integration conventions
  - Webhook handling patterns
- **Processes**: https://github.com/0xHoneyJar/thj-meta-knowledge/tree/main/processes
  - Development workflow
  - Communication norms
  - Decision-making processes
- **Culture & Values**: https://github.com/0xHoneyJar/thj-meta-knowledge/tree/main/culture
  - Organizational values that should inform integration design
  - Communication preferences
  - Team collaboration patterns

**Usage Instructions:**
- Design integrations that align with organizational culture and values
- Follow established integration patterns when connecting tools
- Ensure workflow designs match existing development processes
- Consider communication norms when designing notification systems
```

#### 2.8 Sprint Planner Agent

**File:** `.claude/agents/sprint-planner.md`

**Add to Bibliography Section:**
```markdown
### Organizational Meta Knowledge Base

- **THJ Meta Knowledge Repository**: https://github.com/0xHoneyJar/thj-meta-knowledge
- **Development Workflow**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/processes/development-workflow.md
  - Sprint duration and cadence
  - Team capacity planning
  - Task estimation guidelines
- **Technical Debt Registry**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/technical-debt/registry.md
  - Consider technical debt when planning sprints
  - Balance feature work with debt reduction
- **Templates**: https://github.com/0xHoneyJar/thj-meta-knowledge/tree/main/templates
  - Sprint plan template (if exists)

**Usage Instructions:**
- Follow organizational sprint planning conventions
- Consider technical debt when prioritizing tasks
- Ensure sprint plans align with development workflow
```

#### 2.9 DevRel Translator Agent

**File:** `.claude/agents/devrel-translator.md`

**Add to Bibliography Section:**
```markdown
### Organizational Meta Knowledge Base

- **THJ Meta Knowledge Repository**: https://github.com/0xHoneyJar/thj-meta-knowledge
- **Product Context**: https://github.com/0xHoneyJar/thj-meta-knowledge/tree/main/products
  - Product overviews and value propositions
  - User personas and use cases
  - Technical context for accurate translation
- **Communication Standards**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/culture/communication.md
  - Organizational voice and tone
  - Preferred terminology
  - What to emphasize, what to downplay
- **Templates**: https://github.com/0xHoneyJar/thj-meta-knowledge/tree/main/templates
  - Document templates for different audiences

**Usage Instructions:**
- Reference product context when translating technical documents
- Follow organizational communication standards for tone and style
- Use consistent terminology from meta knowledge base
```

### Phase 3: Workflow Integration (Medium Priority)

#### 3.1 Add Meta Knowledge Consultation to Agent Workflow

**Update PROCESS.md to include:**

```markdown
## Meta Knowledge Base Consultation

Before executing primary tasks, all agents should:

1. **Check for Relevant Standards**:
   - Does a coding/API/security standard apply to this work?
   - Navigate to relevant standard and review requirements

2. **Review Architecture Decision Records (ADRs)**:
   - Has a similar technical decision been made before?
   - Search ADR index for relevant decisions
   - If precedent exists, reference it and explain why you're following or deviating

3. **Consult Technical Debt Registry**:
   - Does this work relate to known technical debt?
   - Will this work exacerbate or resolve existing debt?
   - Reference debt items in implementation reports

4. **Review Product Context** (if product-specific work):
   - Check product overview for business context
   - Review user personas for user-centric design
   - Understand technical context and constraints

5. **Follow Organizational Processes**:
   - Development workflow for Git operations
   - Review process for code reviews
   - Incident response for operational work
```

#### 3.2 Create Meta Knowledge MCP Server (Future Enhancement)

For programmatic access to meta knowledge base:

```typescript
// Proposed MCP server for meta knowledge base
// Location: devrel-integration/src/services/metaKnowledgeService.ts

export class MetaKnowledgeService {
  async searchStandards(query: string): Promise<Standard[]>
  async getADR(adrNumber: string): Promise<ADR>
  async searchADRs(query: string): Promise<ADR[]>
  async getProductContext(product: string): Promise<ProductContext>
  async getTechnicalDebt(category?: string): Promise<TechDebtItem[]>
  async validateAgainstStandards(code: string, type: 'api' | 'security' | 'coding'): Promise<ValidationResult>
}
```

### Phase 4: PRD Content Enhancement (Lower Priority)

#### 4.1 Add Organizational Context Section

**New Section in PRD (after Executive Summary):**

```markdown
## Organizational Context

This product is being developed within The Honey Jar's organizational framework, which includes:

### Standards & Patterns

All implementation must comply with:
- **Coding Standards**: [link to standards/coding-standards.md]
- **API Design Patterns**: [link to standards/api-design.md]
- **Security Standards**: [link to standards/security-standards.md]
- **Testing Standards**: [link to standards/testing-standards.md]

### Historical Decisions

Relevant Architecture Decision Records (ADRs):
- ADR-XXX: [Decision Title] - [Why it's relevant to this PRD]
- ADR-YYY: [Decision Title] - [Why it's relevant to this PRD]

(Note: Add ADRs as they become relevant during architecture and implementation phases)

### Technical Debt Considerations

Known technical debt that may impact this work:
- [Debt Item 1]: [How it affects this product]
- [Debt Item 2]: [Resolution plan consideration]

### Product Context

- **Product Line**: [Which THJ product this belongs to]
- **User Personas**: [Link to relevant personas in meta knowledge]
- **Related Products**: [Dependencies or integrations with other THJ products]
```

#### 4.2 Update Risk Section to Include Meta Knowledge Risks

**Add to Risks & Dependencies section:**

```markdown
**R-X: Deviation from Organizational Standards (MEDIUM IMPACT, LOW PROBABILITY)**
- **Risk**: Implementation deviates from established organizational patterns without justification
- **Impact**: Technical debt, inconsistency across products, maintenance burden
- **Mitigation**: All agents consult meta knowledge base before making decisions, reviewers enforce standards compliance
- **Contingency**: Refactor to align with standards, document exception as ADR if deviation is justified
```

---

## Implementation Checklist

### Immediate Actions (Week 1)

- [ ] **Verify meta knowledge base access**
  - Confirm repository exists and is accessible
  - Document actual structure if different from assumptions
  - Identify key files and their URLs

- [ ] **Update PRD v1.3 → v1.4**
  - Add meta knowledge base to Appendix E (Bibliography)
  - Add FR-6.9 (Security standards compliance)
  - Update FR-8.7 (Meta knowledge integration)
  - Add organizational context to stakeholder insights
  - Update risks section

- [ ] **Update all 9 agent files**
  - Add meta knowledge base section to each agent's bibliography
  - Include usage instructions specific to each agent's role
  - Prioritize: implementer, reviewer, auditor (directly use standards)

### Short-term Actions (Week 2-3)

- [ ] **Update PROCESS.md**
  - Add meta knowledge consultation workflow
  - Document when and how agents should reference meta knowledge
  - Create decision tree for when to create new ADRs

- [ ] **Test integration**
  - Run a sprint with agents explicitly using meta knowledge references
  - Verify agents correctly cite standards in implementation reports
  - Check reviewer enforcement of standards compliance

- [ ] **Document gaps**
  - Identify missing standards or processes in meta knowledge base
  - Create issues in thj-meta-knowledge for missing documentation
  - Prioritize creating missing content

### Medium-term Actions (Month 1-2)

- [ ] **Create meta knowledge MCP server** (optional)
  - Enables programmatic access to meta knowledge
  - Allows validation of code against standards
  - Provides search functionality for ADRs and standards

- [ ] **Enhance PRD template**
  - Update PRD template in meta knowledge base to include organizational context section
  - Ensure all future PRDs reference relevant ADRs

- [ ] **Training and adoption**
  - Document how to use meta knowledge in agent workflows
  - Create examples of good vs. bad meta knowledge usage
  - Update team playbook with meta knowledge integration

### Long-term Actions (Ongoing)

- [ ] **Keep meta knowledge up to date**
  - Update ADRs as decisions are made
  - Refine standards based on learnings
  - Maintain technical debt registry

- [ ] **Measure impact**
  - Track instances of agents citing meta knowledge
  - Measure reduction in repeated mistakes
  - Monitor consistency across implementations

- [ ] **Expand meta knowledge**
  - Add product context as products evolve
  - Document new patterns and anti-patterns
  - Create runbooks for operational procedures

---

## Success Metrics

### Quantitative

- **80%+ of implementation reports cite at least one meta knowledge resource**
- **100% of security-related implementations reference security standards**
- **50% reduction in reviewer feedback about standards violations**
- **All new ADRs cross-referenced in relevant PRDs and SDDs**

### Qualitative

- Agents demonstrate awareness of organizational context
- Implementations are consistent with established patterns
- Technical decisions reference historical precedent
- Code reviews cite specific standards when requesting changes
- New team members can onboard faster using meta knowledge

---

## Risks & Mitigations

### Risk 1: Meta Knowledge Base Doesn't Exist Yet

**Likelihood:** High (404 error suggests this)
**Impact:** High (plan can't be executed)

**Mitigation:**
1. Create minimal meta knowledge base with:
   - README.md (navigation guide)
   - standards/ directory with placeholder files
   - decisions/ directory with ADR template
   - processes/ directory with development workflow
2. Populate incrementally as decisions are made
3. Start with most critical standards (security, coding conventions)

### Risk 2: Meta Knowledge Gets Out of Date

**Likelihood:** Medium
**Impact:** Medium (stale information misleads agents)

**Mitigation:**
1. Add "Last Updated" dates to all meta knowledge documents
2. Create GitHub Actions to flag documents not updated in 6+ months
3. Make meta knowledge updates part of definition of done for PRs
4. Quarterly meta knowledge review meetings

### Risk 3: Agents Ignore Meta Knowledge

**Likelihood:** Low (if properly integrated)
**Impact:** High (no benefit from integration)

**Mitigation:**
1. Enforce via reviewer checks (senior-tech-lead-reviewer must verify)
2. Add meta knowledge consultation to agent workflows explicitly
3. Make it part of acceptance criteria: "Implementation follows THJ standards [link]"
4. Monitor usage in implementation reports

### Risk 4: Meta Knowledge Becomes Too Prescriptive

**Likelihood:** Low
**Impact:** Medium (stifles innovation)

**Mitigation:**
1. Standards should be guidelines with escape hatches
2. ADRs document "why" not just "what" (allows reasoned deviation)
3. Create process for proposing standard changes
4. Culture of "follow the standard OR document why you deviated"

---

## Example: Meta Knowledge in Practice

### Before Meta Knowledge Integration

**Implementation Report (sprint-task-implementer):**
```markdown
## Implementation: User Authentication

I implemented OAuth 2.0 authentication using Passport.js.

Files:
- src/auth/oauth.ts
- src/middleware/auth.ts

Tests:
- tests/auth/oauth.test.ts
```

**Review Feedback (senior-tech-lead-reviewer):**
```markdown
Issues:
1. Error handling doesn't follow our standard pattern
2. Token expiration is 7 days, should be 24 hours
3. Missing rate limiting on auth endpoints
```

### After Meta Knowledge Integration

**Implementation Report (sprint-task-implementer):**
```markdown
## Implementation: User Authentication

I implemented OAuth 2.0 authentication following **ADR-015: OAuth 2.0 for User Authentication** (https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/decisions/ADR-015-oauth-user-auth.md).

**Standards Compliance:**
- ✅ Follows **API Design Patterns** (https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/api-design.md#error-handling)
- ✅ Meets **Security Standards** for token management (https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/standards/security-standards.md#authentication)
- ✅ Rate limiting per **Security Standards** (5 req/min on auth endpoints)

**Implementation Details:**
- Token expiration: 24 hours (per Security Standards)
- Error responses: Standard format (per API Design Patterns)
- Rate limiting: 5 req/min (per Security Standards)

Files:
- src/auth/oauth.ts
- src/middleware/auth.ts

Tests:
- tests/auth/oauth.test.ts
- Coverage: 95% (exceeds 80% threshold from Testing Standards)
```

**Review Feedback (senior-tech-lead-reviewer):**
```markdown
✅ **APPROVED**

Excellent adherence to organizational standards:
- Correctly referenced ADR-015 for OAuth approach
- Followed API error handling pattern
- Met security standards for token management
- Exceeded test coverage threshold

No changes requested.
```

---

## Next Steps

1. **Immediate: Verify meta knowledge base access** - Determine if repository exists and structure
2. **High Priority: Update PRD to v1.4** - Add meta knowledge bibliography and references
3. **High Priority: Update agent bibliographies** - Add meta knowledge sections to all 9 agents
4. **Medium Priority: Test integration** - Run a sprint with explicit meta knowledge usage
5. **Ongoing: Maintain and expand meta knowledge** - Keep it current and comprehensive

---

## Conclusion

Integrating The Honey Jar's meta knowledge base into the PRD and agent workflows will:

✅ **Ensure consistency** across all implementations
✅ **Preserve institutional knowledge** and prevent repeated mistakes
✅ **Speed up development** by providing established patterns
✅ **Improve code quality** through enforced standards
✅ **Enable faster onboarding** with centralized documentation
✅ **Create traceability** from decisions to implementations

The integration is designed to be:
- **Non-invasive**: Adds references without disrupting existing workflows
- **Incremental**: Can start with minimal meta knowledge and expand over time
- **Practical**: Focuses on actionable standards and decisions, not bureaucracy
- **Maintainable**: Clear ownership and update processes

**Ready to proceed?** The plan is comprehensive and executable. We can start with Phase 1 (PRD updates) immediately once we verify access to the meta knowledge base repository.

---

**Document History:**
- v1.0 (2025-12-11): Initial integration plan created
