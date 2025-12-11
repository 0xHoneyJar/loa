# Product Requirements Document (PRD)
# Onomancer Bot: DevRel Documentation Automation System

**Project Name:** Onomancer Bot (DevRel Integration)
**Product Manager:** PRD Architect Agent
**Date:** 2025-12-11
**Version:** 1.3
**Status:** Approved - Ready for Architecture Phase (v1.3 alignment update)

**Changelog:**
- **v1.3** (2025-12-11): Added FR-6.5 (Agent Linear Integration for Audit Trail) to document already-implemented feature from Phases 1-5. This closes critical dependency gap where FR-7 (stakeholder visibility) depends on agents creating Linear issues but this requirement was never documented. FR-6.5 specifies label taxonomy, issue hierarchy, status transitions, and integration for sprint-task-implementer, devops-crypto-architect, and paranoid-auditor agents.
- **v1.2** (2025-12-11): Added stakeholder feedback integration from Linear (7 PRD-labeled issues), added build status and process reporting requirements (FR-7.x), added Linear integration capabilities for real-time visibility (FR-8.x), added comprehensive knowledge base requirements (FR-9.x), incorporated team workflow improvements
- **v1.1** (2025-12-10): Added project name requirement to `/translate` command, expanded scope to include ALL agentic-base documents (PRD, SDD, sprint.md, A2A docs), added automated triggers for PRD/SDD/sprint plan generation (FR-3.5, FR-3.6, FR-3.7), added FR-4.9 for complete workflow document access
- **v1.0** (2025-12-10): Initial PRD with core requirements for Google Workspace setup, transformation pipeline, automated triggers, Discord commands

---

## Executive Summary

**Problem:** Technical work (code, GitHub PRs, Linear issues, sprint reports, security audits) is trapped in developer-centric formats and locations, making it inaccessible to non-technical stakeholders. Product managers, marketing teams, documentation writers, and leadership depend on developers to manually translate and explain technical work. This creates a critical bottleneck that slows release velocity, reduces documentation quality, and prevents teams from working in parallel.

**Solution:** Build the **Onomancer Bot** - a Discord bot backed by the devrel-translator agent that automatically transforms technical documents into persona-specific summaries (executive summaries, blog drafts, technical tutorials, status updates) and stores them in Google Docs using infrastructure-as-code (Terraform). Stakeholders can access these documents on-demand via Discord slash commands, eliminating the developer bottleneck and enabling self-service access to technical information.

**Business Impact:** Dramatically increase release velocity by decoupling documentation/marketing workflows from developer availability. Enable non-technical stakeholders to self-serve information needs, allowing developers to focus on building while empowering the entire organization with programmatic access to technical knowledge.

---

## Table of Contents

1. [Stakeholder Insights](#stakeholder-insights)
2. [Problem Statement](#problem-statement)
3. [Vision & Goals](#vision--goals)
4. [User Personas & Stakeholders](#user-personas--stakeholders)
5. [Functional Requirements](#functional-requirements)
6. [Technical Requirements](#technical-requirements)
7. [Non-Functional Requirements](#non-functional-requirements)
8. [Scope & Prioritization](#scope--prioritization)
9. [Success Metrics](#success-metrics)
10. [Risks & Dependencies](#risks--dependencies)
11. [Open Questions](#open-questions)
12. [Appendix](#appendix)

---

## Stakeholder Insights

**Source:** 7 Linear issues with PRD label, captured from Discord team feedback sessions (2025-12-10 to 2025-12-11)

### Key Themes from Stakeholder Feedback

#### 1. Continuous Build Visibility (LAB-513, LAB-508)
**Problem:** Stakeholders need **continuous updates during the build process**, not just notifications when work is complete. Current workflow only provides visibility at milestone completion (sprint approval, audit completion).

**Quotes:**
- "Continuous updates during the build process" - Marketing team
- "Directional update as opposed to being created on the fly" - Team member
- "If had known what was going to happen rather than just a cubquest update would prepare" - Team member

**Requirements:**
- Real-time Linear issue updates visible to stakeholders
- Build status dashboard showing in-progress work
- Proactive notifications when agents start/complete tasks
- Transparency into what's being built before it's done

#### 2. Comprehensive Knowledge Base (LAB-513, LAB-509, LAB-508)
**Problem:** Teams need a **constantly updated, reliable knowledge base** that includes ALL decisions, discussions, specs, and changes - not just final documents. Current documentation is sparse and doesn't capture the "why" behind decisions.

**Quotes:**
- "A constantly updated, reliable product overview doc/knowledge base. Including all the small things we discuss in chats, decisions, changes, explanations, everything" - Marketing
- "Wish we had more detailed documentation even including every discord discussion topics" - Marketing
- "Clear questions on SC before work starts" - Team member
- "We should be shipping a full product not what we want to ship. If you think about a physical product it comes with instructions, manual, hazards, expiration dates" - Team member

**Requirements:**
- Complete documentation that includes decisions, rationale, and context
- Product specs with timelines and change history
- Best practices documentation (file formats, dimensions, naming conventions)
- Pre-work clarification documents (requirements, constraints, technical details)
- "Instructions manual" for every product feature

#### 3. Marketing and Communications Support (LAB-513, LAB-509)
**Problem:** Marketing team needs **custom data, technical accuracy validation, and structured content** that current system doesn't provide.

**Quotes:**
- "Some custom data for marketing stuff" - Marketing
- "When I need to double check if my mkt material is technically correct" - Marketing
- "General clarification about best sizes, formats, dimensions, etc" - Design/Marketing
- "Have needed explanations for how files should be named, where certain things will be displayed" - Design/Marketing

**Requirements:**
- Custom data extraction for marketing materials
- Technical accuracy validation service
- Asset specifications (sizes, formats, dimensions, naming)
- Marketing-ready feature descriptions with customer benefits
- A/B testing data to support design decisions

#### 4. Project Management and Planning (LAB-513, LAB-508)
**Problem:** Teams need **RACI matrices, Gantt charts, and structured project plans** with notifications, not just technical implementation details.

**Quotes:**
- "Marketing action plan include RACI + gantt, plus auto dm/notification" - Marketing
- "Consistency (work ethic) and better product design before creating" - Team member
- "Push notifications when important change made or decision need to discuss" - Marketing

**Requirements:**
- RACI (Responsible, Accountable, Consulted, Informed) matrices
- Gantt charts showing timeline and dependencies
- Automated notifications for important decisions
- Pre-planning phase with clear requirements before implementation

#### 5. Developer Workflow Improvements (LAB-512)
**Problem:** Teams need better **collaboration tools and workflow automation** specific to crypto/DAO operations.

**Quotes:**
- "Something wrt to easing multisig friction. I think there's things in place on safe regarding whitelisted functions that a single wallet can control" - Team member
- "Typically have found my dev relationship to just be bumping product advancements instigated by member questions" - Team member

**Requirements:**
- Multisig workflow automation for common operations
- Proactive collaboration tools (not reactive question-answering)
- Delegation dashboard updates
- Treasury dashboard automation

#### 6. Product Quality Standards (LAB-508, LAB-515)
**Problem:** Teams need **better product design and complete feature delivery**, not rushed or incomplete releases.

**Quotes:**
- "We should be shipping a full product not what we want to ship" - Team member
- "Hair on fire, core product doesn't work" - Team member about urgency prioritization

**Requirements:**
- Complete product checklist (not just MVP)
- Pre-launch quality gates
- Feature completeness validation
- Documentation requirements enforced before release

#### 7. Self-Service Information Access (LAB-513)
**Problem:** Stakeholders spend too much time researching answers that should be easily accessible. Current AI/research takes longer than asking developers, which defeats the purpose.

**Quotes:**
- "Most questions can solve by asking AI + doing my own research and reading, but it does take longer tho" - Marketing
- "When something is super new or super niche that doesn't exist in public knowledge base yet, so even AI has no clue can only scoop from human brain" - Marketing

**Requirements:**
- Faster than "ask AI + do research" - should be instant query
- Accessible knowledge base that AI can reference
- Expert knowledge capture (things not in public knowledge bases)

### Stakeholder Request Priority Matrix

| Priority | Requirement | Impact | Effort | MVP Status |
|----------|------------|---------|--------|------------|
| **CRITICAL** | Continuous build visibility | High | Medium | **v1.2** |
| **CRITICAL** | Comprehensive knowledge base | High | High | **v1.2** |
| **HIGH** | Marketing support (data, validation) | High | Low | **v1.2** |
| **HIGH** | RACI + Gantt + Notifications | Medium | Medium | **v1.2** |
| **MEDIUM** | Multisig workflow automation | Medium | High | Phase 2 |
| **MEDIUM** | A/B testing data | Low | Low | Phase 2 |
| **LOW** | Auto-generated tutorials | Low | Medium | Phase 2 |

---

## Problem Statement

### Current State

**Documentation Workflow Today:**
1. Developers write code and create PRs on GitHub
2. Sprint reports are generated in `docs/sprint.md` and `docs/a2a/reviewer.md`
3. Security audits are generated in `SECURITY-AUDIT-REPORT.md`
4. Linear issues track tasks with technical descriptions
5. Discord contains community feedback and team discussions

**Pain Points:**
1. **Developer Bottleneck**: Non-technical stakeholders (PMs, marketing, leadership, DevRel) need devs to manually explain technical work
2. **Manual Translation**: Devs spend significant time writing documentation, creating blog drafts, preparing executive summaries
3. **Context Loss**: Information is scattered across Discord, GitHub, Linear, and local files with no unified access
4. **Stale Documentation**: Docs quickly become outdated because manual updates are slow and error-prone
5. **Ad-Hoc Questions**: Constant Slack/Discord interruptions asking "what's the status?" or "can you explain this feature?"
6. **Slow Releases**: Documentation bottleneck delays product releases and reduces overall quality

### Root Cause

**Technical artifacts are not programmatically accessible or translatable:**
- Documents are stored locally or in developer-centric formats (Markdown in repos)
- No automated transformation pipeline from "developer technical report" to "stakeholder-friendly summary"
- No centralized storage system (Google Docs) with proper organization and permissions
- No self-service interface for stakeholders to query information

### User Impact

**For Developers:**
- Constant context switching to answer questions
- Forced to write documentation instead of coding
- Slowed down by manual translation work

**For Product Managers:**
- Blocked waiting for devs to explain technical decisions
- Can't access sprint status or technical details independently
- Delays in creating product documentation and technical articles

**For Marketing:**
- Can't generate blog drafts or social posts without dev help
- Miss opportunities for timely content because of delays
- Lack of technical context for marketing materials

**For Leadership:**
- No programmatic access to executive summaries
- Difficult to track progress across products and sprints
- Requires meetings to get status updates instead of async access

**For DevRel:**
- Can't create technical tutorials without extensive dev consultation
- Lack of accessible technical materials for community education
- Delays in publishing developer-facing content

---

## Vision & Goals

### Vision Statement

**"Enable every stakeholder to access the technical information they need, in the format they need, when they need it—without developers being a bottleneck."**

The Onomancer Bot transforms the agentic-base development workflow into a programmatic knowledge distribution system. When sprints complete, audits finish, or PRs merge, technical documents are automatically translated into persona-specific summaries and made accessible through a conversational Discord interface. Developers focus on building; stakeholders self-serve documentation.

### Primary Goal

**Increase release velocity** by removing the documentation bottleneck and enabling parallel workflows where documentation, marketing, and product management can proceed independently of developer availability.

### Secondary Goals

1. **Reduce developer time spent on documentation** from ~20% to <5% of work time
2. **Increase stakeholder self-service adoption** - 80% of information requests handled by bot, not developers
3. **Improve documentation quality and freshness** - Automated generation ensures completeness and timeliness
4. **Enable async-first knowledge access** - Stakeholders in any timezone can query information instantly
5. **Preserve context across tools** - Unify information from Discord, GitHub, Linear, local docs

### Success Criteria

1. **Release Velocity**: Measurable reduction in time-to-market for products with complete documentation
2. **Dev Time Saved**: Developers spend <5% of time on documentation/explanations (down from ~20%)
3. **Self-Service Adoption**: 80% of stakeholder information needs met by bot without asking developers
4. **Documentation Completeness**: 100% of sprints have automated translations for all personas within 24 hours
5. **Stakeholder Satisfaction**: 8/10 satisfaction score for information accessibility

---

## User Personas & Stakeholders

### Primary Users

#### 1. Product Managers
**Role:** Create product documentation and technical articles
**Needs:**
- Sprint status and technical details without asking devs
- PRD and SDD summaries for product planning
- Linear issue context for roadmap planning
- Technical decisions explained in accessible language

**Pain Points:**
- Blocked waiting for devs to explain features
- Outdated documentation makes planning difficult
- Manual work to extract information from Linear/GitHub

**Use Cases:**
- Query sprint status: `/exec-summary sprint-1`
- Get feature explanation: `/translate @docs/sdd.md for product-managers`
- Access Linear issue summary: `/task-summary THJ-123`

#### 2. Marketing Team
**Role:** Create blog posts, social media content, product announcements
**Needs:**
- Blog draft generation from sprint reports
- Feature announcements from PRD/SDD
- Product updates from Linear project completions
- Technical content translated to marketing language

**Pain Points:**
- Can't create content without extensive dev consultation
- Miss timely opportunities due to documentation delays
- Lack of technical context for marketing materials

**Use Cases:**
- Generate blog draft: `/blog-draft sprint-1`
- Get product announcement: `/translate @SECURITY-AUDIT-REPORT.md for marketing`
- Weekly digest: `/digest weekly`

#### 3. Leadership (Executives, Board, Investors)
**Role:** Strategic decision-making, progress tracking, risk assessment
**Needs:**
- Executive summaries of sprint progress
- Security audit results in business terms
- High-level architecture decisions and rationale
- Risk assessments and mitigation strategies

**Pain Points:**
- No programmatic access to project status
- Meetings required for status updates (not async)
- Technical jargon makes reports difficult to parse

**Use Cases:**
- Get executive summary: `/exec-summary sprint-1`
- Security audit summary: `/translate @SECURITY-AUDIT-REPORT.md for leadership`
- Weekly digest: `/digest weekly`

#### 4. DevRel (Developer Relations)
**Role:** Create technical tutorials, community education, developer advocacy
**Needs:**
- Accessible technical materials for tutorials
- Sprint implementation details for developer guides
- Architecture context for community education
- Code examples and implementation patterns

**Pain Points:**
- Lack of technical context without dev consultation
- Delays in publishing developer-facing content
- Manual extraction of technical details from repos

**Use Cases:**
- Get technical tutorial draft: `/translate @docs/a2a/reviewer.md for devrel`
- Query implementation details: `/task-summary THJ-123`
- Access architecture context: `/translate @docs/sdd.md for devrel`

### Secondary Users

#### 5. Developers
**Role:** Write code, generate technical reports, review implementation
**Needs:**
- Automated document transformation (no manual work)
- Manual trigger for ad-hoc translations
- Feedback on what stakeholders need

**Pain Points:**
- Constant interruptions to explain technical work
- Manual documentation writing takes time from coding
- Context switching between code and stakeholder communication

**Use Cases:**
- Trigger automatic transformation: Complete sprint with `/review-sprint` approval
- Manual translation: `/translate @docs/sprint.md for executives`
- Query bot status: `/show-sprint`

#### 6. Documentation Writers
**Role:** Create comprehensive product documentation
**Needs:**
- Technical source material for docs
- Context from PRDs, SDDs, sprint reports
- Access to Linear issues and GitHub PRs

**Pain Points:**
- Outdated documentation due to manual updates
- Lack of technical context from developers
- Difficult to track changes across GitHub/Linear

**Use Cases:**
- Get documentation source: `/translate @docs/sdd.md for documentation`
- Query feature details: `/task-summary THJ-123`
- Weekly updates: `/digest weekly`

---

## Functional Requirements

### 1. Google Workspace Setup & Terraform Infrastructure (CRITICAL)

**User Story:** As a system administrator, I need a brand new Google Workspace organization with Terraform-managed folder structure and permissions so that documents are organized, secure, and infrastructure is version-controlled.

**Requirements:**
- **FR-1.1**: Create brand new Google Workspace organization for "The Honey Jar"
- **FR-1.2**: Implement Terraform IaC for complete workspace management (folders, permissions, service accounts)
- **FR-1.3**: Define folder structure following Option A (by product/project with audience subfolders):
  ```
  /The Honey Jar
    /Products
      /MiBera
        /PRD
          /Executive Summaries
            - leadership.md
            - product-managers.md
            - marketing.md
            - devrel.md
          - prd.md (original PRD from docs/prd.md)
        /SDD
          /Executive Summaries
            - leadership.md
            - product-managers.md
            - marketing.md
            - devrel.md
          - sdd.md (original SDD from docs/sdd.md)
        /Sprints
          /Sprint-1
            /Executive Summaries
              - leadership.md
              - product-managers.md
              - marketing.md
              - devrel.md
            - sprint-report.md (original from docs/sprint.md)
            - implementation-report.md (original from docs/a2a/reviewer.md)
        /Audits
          /2025-12-10-Sprint-1-Audit
            /Executive Summaries
              - leadership.md
              - product-managers.md
              - marketing.md
              - devrel.md
            - audit-report.md (original audit report)
            - remediation-report.md (if audit required fixes)
      /FatBera
        ... (same structure: PRD, SDD, Sprints, Audits)
      /Interpol
        ... (same structure: PRD, SDD, Sprints, Audits)
      /Set & Forgetti
        ... (same structure: PRD, SDD, Sprints, Audits)
    /Shared
      /Weekly Digests
        /2025-12-10
          /Executive Summaries
            - leadership.md
            - product-managers.md
            - marketing.md
            - devrel.md
      /Templates
        - prd-template.md
        - sdd-template.md
        - sprint-template.md
  ```
- **FR-1.4**: Set up service account with Google Docs API permissions (read/write)
- **FR-1.5**: Configure stakeholder group permissions:
  - Leadership: Read access to all Executive Summaries
  - Product Managers: Read access to PRDs, SDDs, Sprint Reports
  - Marketing: Read access to Blog Drafts, Marketing summaries
  - DevRel: Read access to DevRel summaries, Technical Documentation
  - Developers: Read/Write access to all folders
- **FR-1.6**: Version control all Terraform configurations in `devrel-integration/terraform/`
- **FR-1.7**: Implement Terraform state management (remote backend, state locking)

**Acceptance Criteria:**
- [ ] Google Workspace organization created and configured
- [ ] Terraform code creates complete folder structure programmatically
- [ ] Service account can create/read/update documents via Google Docs API
- [ ] Stakeholder permissions enforced and testable
- [ ] Terraform state stored remotely with locking enabled
- [ ] `terraform apply` is idempotent and can be run repeatedly safely

**Priority:** CRITICAL (all other features depend on this)

---

### 2. Document Transformation Pipeline (CRITICAL)

**User Story:** As a stakeholder, I need technical documents automatically transformed into summaries appropriate for my role so that I can understand technical progress without developer translation.

**Requirements:**
- **FR-2.1**: Integrate devrel-translator agent with Onomancer bot backend
  - Agent persona: DevRel character archetype
  - Agent prompt: Reference `context-engineering-expert` and Hivemind methodology
- **FR-2.2**: Implement transformation logic using existing `SecureTranslationInvoker`
  - Content sanitization (prompt injection defense) - ALREADY BUILT
  - Secret scanning and redaction - ALREADY BUILT
  - Output validation - ALREADY BUILT
  - Manual review queue for suspicious content - ALREADY BUILT
- **FR-2.3**: Support multiple output formats per document:
  - **Leadership**: Executive summary (1-2 pages, business-focused, plain language)
    - Key achievements and milestones
    - Business impact and metrics
    - Risk assessment (honest, transparent)
    - Next steps and decision points
  - **Product Managers**: Technical article (detailed, product-focused)
    - Feature descriptions and capabilities
    - User stories and acceptance criteria
    - Technical decisions and tradeoffs
    - Implementation timeline and dependencies
  - **Marketing**: Blog draft or social post (engaging, customer-focused)
    - Customer benefits and value propositions
    - Feature highlights and use cases
    - Product announcements and releases
    - Community impact and testimonials
  - **DevRel**: Technical tutorial (code-level, developer-focused)
    - Implementation details and code examples
    - API documentation and usage patterns
    - Architecture context and design decisions
    - Developer best practices and gotchas
- **FR-2.4**: Implement context aggregation from multiple sources:
  - Local files: `docs/sprint.md`, `docs/a2a/reviewer.md`, `docs/prd.md`, `docs/sdd.md`, `SECURITY-AUDIT-REPORT.md`
  - Linear API: Issues, comments, projects, initiatives (via existing Linear MCP integration)
  - GitHub API: PRs, commits, code comments (via existing GitHub MCP integration)
  - Discord: Feedback messages, thread context (via Onomancer bot message history)
  - Hivemind LEARNINGS: Historical context from completed work (via Linear documents API)
- **FR-2.5**: Store all transformed documents in Google Docs:
  - Original document stored in root folder (e.g., `/Products/MiBera/Sprints/Sprint-1/sprint-report.md`)
  - Persona-specific summaries stored in `/Executive Summaries` subfolder
  - Documents created with proper metadata (title, created date, source links)
  - Link original document to summaries (bidirectional references)
- **FR-2.6**: Generate document metadata frontmatter (using existing `ContextAssembler` schema):
  ```yaml
  ---
  sensitivity: internal
  title: "Sprint 1 Implementation Report - Executive Summary"
  description: "Executive summary of Sprint 1 progress for MiBera product"
  version: "1.0"
  created: "2025-12-10"
  updated: "2025-12-10"
  owner: "Onomancer Bot"
  department: "Engineering"
  tags: ["sprint-1", "mibera", "executive-summary", "leadership"]
  source_documents:
    - "docs/sprint.md"
    - "docs/a2a/reviewer.md"
    - "Linear:THJ-123"
  audience: "leadership"
  requires_approval: false
  ---
  ```
- **FR-2.7**: Preserve audit trail:
  - Log all transformations (source document, target audience, timestamp, requester)
  - Store transformation metadata in document properties
  - Track document versions in Google Docs version history

**Acceptance Criteria:**
- [ ] devrel-translator agent successfully integrated with Onomancer bot
- [ ] Transformation generates 4 persona-specific summaries from single technical document
- [ ] Context aggregation pulls data from Linear, GitHub, Discord, local files
- [ ] All documents stored in correct Google Docs folders with proper permissions
- [ ] Document frontmatter includes complete metadata (sensitivity, tags, source links)
- [ ] Audit trail logs all transformations with full context
- [ ] Secret scanning prevents sensitive data in summaries (using existing scanner)

**Priority:** CRITICAL

---

### 3. Automated Transformation Triggers (HIGH)

**User Story:** As a developer, I need documents automatically transformed when sprints/audits complete so that stakeholders have up-to-date information without manual work.

**Requirements:**
- **FR-3.1**: **Trigger on `/review-sprint` approval** (Phase 5 completion)
  - Listen for "All good" written to `docs/a2a/engineer-feedback.md`
  - Aggregate context from:
    - `docs/sprint.md` (sprint plan with tasks)
    - `docs/a2a/reviewer.md` (implementation report)
    - Linear issues (all tasks in sprint via API)
    - GitHub PRs (linked to Linear issues)
    - Discord feedback (captured via 📌 reactions, stored in Linear issue descriptions)
  - Generate 4 persona summaries (leadership, product, marketing, devrel)
  - Store in `/Products/{ProductName}/Sprints/Sprint-{N}/Executive Summaries/`
  - Post notification to Discord: "Sprint 1 summaries ready! Query with `/exec-summary sprint-1`"

- **FR-3.2**: **Trigger on `/audit-sprint` completion** (Phase 5.5 audit generation)
  - Listen for audit report creation in `docs/a2a/auditor-sprint-feedback.md`
  - Aggregate context from:
    - Audit report (CRITICAL/HIGH/MEDIUM/LOW findings)
    - Sprint implementation report (`docs/a2a/reviewer.md`)
    - Code diff (GitHub PR)
  - Generate 4 persona summaries (leadership, product, marketing, devrel)
    - Leadership: Risk assessment and security posture
    - Product: Impact on product features and timeline
    - Marketing: Customer-facing security messaging (if applicable)
    - DevRel: Technical security best practices and fixes
  - Store in `/Products/{ProductName}/Audits/{Date}-Sprint-{N}-Audit/Executive Summaries/`
  - Post notification to Discord: "Sprint 1 audit complete! Query with `/audit-summary sprint-1`"

- **FR-3.3**: **Trigger on `/audit-sprint` approval** (audit remediation completion)
  - Listen for "APPROVED - LETS FUCKING GO" in `docs/a2a/auditor-sprint-feedback.md`
  - Aggregate context from:
    - Original audit report
    - Remediation report (updated `docs/a2a/reviewer.md`)
    - Code changes (GitHub commits)
  - Generate 4 persona summaries emphasizing "security issues resolved"
  - Store in `/Products/{ProductName}/Audits/{Date}-Sprint-{N}-Audit/Remediation-Report/Executive Summaries/`
  - Post notification to Discord: "Sprint 1 security audit approved! All issues resolved. Query with `/audit-summary sprint-1-remediation`"

- **FR-3.4**: **Weekly digest generation** (automated summary of all activity)
  - Cron job: Every Monday at 9am UTC
  - Aggregate context from past 7 days:
    - Discord: Feedback messages, discussions, questions (via bot message history)
    - GitHub: Merged PRs, commits, code reviews (via GitHub API)
    - Linear: Completed issues, new initiatives, project updates (via Linear API)
    - LEARNINGS: New learnings added to library (via Linear documents API)
  - Generate unified digest with sections:
    - **This Week's Highlights**: Top 3 achievements
    - **Community Feedback**: Discord feedback summary
    - **Development Progress**: GitHub/Linear activity
    - **Learnings**: New patterns and knowledge captured
    - **Next Week's Focus**: Upcoming sprints/initiatives
  - Generate 4 persona-specific digest versions
  - Store in `/Shared/Weekly Digests/{Date}/Executive Summaries/`
  - Post notification to Discord: "Weekly digest ready! Query with `/digest weekly`"

- **FR-3.5**: **Trigger on PRD generation** (Phase 1 completion)
  - Listen for `docs/prd.md` file creation or update (via file system watcher)
  - Detect project name from PRD header or filename (e.g., `docs/prd-mibera.md` or extract from content)
  - Generate 4 persona summaries:
    - **Leadership**: Executive summary (business case, goals, success metrics, risks)
    - **Product**: Detailed requirements summary (functional/non-functional requirements, scope)
    - **Marketing**: Product vision and value propositions (problem statement, benefits)
    - **DevRel**: Technical requirements overview (tech stack, integrations, APIs)
  - Store in `/Products/{Project}/PRD/Executive Summaries/`
  - Post notification to Discord: "MiBera PRD ready! Query with `/translate mibera @prd for [audience]`"

- **FR-3.6**: **Trigger on SDD generation** (Phase 2 completion)
  - Listen for `docs/sdd.md` file creation or update (via file system watcher)
  - Detect project name from SDD header or filename
  - Generate 4 persona summaries:
    - **Leadership**: Architecture overview (high-level design, tech decisions, cost implications)
    - **Product**: System capabilities and constraints (what the system can/can't do)
    - **Marketing**: Technical differentiators (what makes the product technically superior)
    - **DevRel**: Deep technical dive (architecture diagrams, API design, integration patterns)
  - Store in `/Products/{Project}/SDD/Executive Summaries/`
  - Post notification to Discord: "MiBera SDD ready! Query with `/translate mibera @sdd for [audience]`"

- **FR-3.7**: **Trigger on Sprint Plan generation** (Phase 3 completion)
  - Listen for `docs/sprint.md` file creation or update (via file system watcher)
  - Detect project name and sprint number from sprint.md content
  - Generate 4 persona summaries:
    - **Leadership**: Sprint objectives and timeline (what will be delivered, when)
    - **Product**: Feature breakdown and acceptance criteria (what users will be able to do)
    - **Marketing**: Marketing-ready feature descriptions (customer benefits, use cases)
    - **DevRel**: Technical implementation roadmap (developer-facing changes, API updates)
  - Store in `/Products/{Project}/Sprints/Sprint-{N}/Executive Summaries/`
  - Post notification to Discord: "MiBera Sprint 1 plan ready! Query with `/translate mibera @sprint for [audience]`"

**Acceptance Criteria:**
- [ ] PRD generation automatically triggers transformation within 5 minutes
- [ ] SDD generation automatically triggers transformation within 5 minutes
- [ ] Sprint plan generation automatically triggers transformation within 5 minutes
- [ ] Sprint approval automatically triggers transformation within 5 minutes
- [ ] Audit completion automatically triggers transformation within 5 minutes
- [ ] Audit approval (remediation) automatically triggers transformation within 5 minutes
- [ ] Weekly digest generated every Monday at 9am UTC without manual intervention
- [ ] All triggers aggregate context from Linear, GitHub, Discord, local files
- [ ] Notifications posted to configured Discord channel after each transformation
- [ ] Error handling: Failed transformations logged and retried automatically
- [ ] File system watcher detects document creation/updates within 10 seconds

**Priority:** HIGH

---

### 4. Discord Slash Commands (HIGH)

**User Story:** As a stakeholder, I need Discord slash commands to query and access documents on-demand so that I can self-serve information needs without asking developers.

**Requirements:**

- **FR-4.1**: `/exec-summary <sprint-id>` - Get executive summary for specific sprint
  - Example: `/exec-summary sprint-1` or `/exec-summary mibera-sprint-1`
  - Bot responds with link to Google Doc for user's role
  - Automatically detects user role from Discord permissions/roles
  - Falls back to asking user: "Which summary? [Leadership | Product | Marketing | DevRel]"

- **FR-4.2**: `/audit-summary <sprint-id>` - Get security audit summary
  - Example: `/audit-summary sprint-1` or `/audit-summary sprint-1-remediation`
  - Bot responds with audit report summary for user's role
  - Includes severity breakdown (CRITICAL/HIGH/MEDIUM/LOW)
  - Links to original audit report in Google Docs

- **FR-4.3**: `/blog-draft <sprint-id|linear-issue-id>` - Generate blog post draft
  - Example: `/blog-draft sprint-1` or `/blog-draft THJ-123`
  - Uses existing `BlogDraftGenerator` (already built)
  - Generates blog draft from sprint report or Linear issue
  - Stores in Google Docs and responds with link
  - Requires manual review and approval (security control - already enforced)

- **FR-4.4**: `/translate <project> <@document> for <audience>` - Manual translation trigger
  - Example: `/translate mibera @docs/sdd.md for executives`
  - Example: `/translate mibera @prd for leadership`
  - Example: `/translate fatbera @sprint.md for marketing`
  - Example: `/translate mibera @docs/a2a/reviewer.md for devrel`
  - **Required arguments:**
    - `<project>`: Project name (mibera, fatbera, interpol, etc.)
    - `<@document>`: Document reference (see FR-4.9 for supported documents)
    - `for <audience>`: Target audience (leadership, product, marketing, devrel)
  - Accepts local file path, document shorthand (prd, sdd, sprint), or Google Docs link
  - Generates summary for specified audience
  - Stores result in `/Products/{Project}/Executive Summaries/{Audience}/{DocumentType}.md`
  - Responds with link to generated document
  - **Document shorthand supported:**
    - `@prd` → `docs/prd.md`
    - `@sdd` → `docs/sdd.md`
    - `@sprint` or `@sprint.md` → `docs/sprint.md`
    - `@reviewer` → `docs/a2a/reviewer.md`
    - `@audit` → `SECURITY-AUDIT-REPORT.md` (latest)
    - Full paths also accepted: `@docs/a2a/engineer-feedback.md`

- **FR-4.9**: **Make ALL agentic-base workflow documents accessible via `/translate`**
  - **User Story:** As a stakeholder, I need access to ALL documents generated by the agentic-base workflow (PRD, SDD, sprint plans, implementation reports, A2A documents) so that I can understand the complete product development lifecycle, not just final sprint results.
  - **Supported documents:**
    - `docs/prd.md` - Product Requirements Document (Phase 1)
    - `docs/sdd.md` - Software Design Document (Phase 2)
    - `docs/sprint.md` - Sprint plan with tasks and acceptance criteria (Phase 3)
    - `docs/a2a/reviewer.md` - Implementation report from engineer (Phase 4)
    - `docs/a2a/engineer-feedback.md` - Review feedback from senior lead (Phase 5)
    - `docs/a2a/auditor-sprint-feedback.md` - Security audit feedback (Phase 5.5)
    - `docs/a2a/deployment-report.md` - Infrastructure reports from DevOps (Phase 6)
    - `SECURITY-AUDIT-REPORT.md` - Comprehensive security audit (Ad-hoc)
    - Any other markdown files in `docs/` directory
  - **Project context:**
    - Project name used to organize documents in Google Docs folder structure
    - Example: `/translate mibera @prd for leadership` stores in `/Products/MiBera/PRD/Executive Summaries/Leadership-PRD.md`
    - Example: `/translate fatbera @sdd for devrel` stores in `/Products/FatBera/SDD/Executive Summaries/DevRel-SDD.md`
  - **Benefits:**
    - **Leadership** can query PRD to understand business case: `/translate mibera @prd for leadership`
    - **Product Managers** can query SDD for technical architecture: `/translate mibera @sdd for product`
    - **Marketing** can query sprint plans for feature timelines: `/translate mibera @sprint for marketing`
    - **DevRel** can query implementation reports for technical deep-dives: `/translate mibera @reviewer for devrel`
  - **Automatic transformation:**
    - When agentic-base agents generate these documents (PRD, SDD, sprint.md), automatically trigger transformation to all 4 personas
    - Store in `/Products/{Project}/{DocumentType}/Executive Summaries/`
    - Post Discord notification: "MiBera PRD ready! Query with `/translate mibera @prd for [audience]`"

- **FR-4.5**: `/digest <timeframe>` - Get activity digest
  - Example: `/digest weekly` or `/digest monthly`
  - Responds with link to weekly/monthly digest for user's role
  - If digest doesn't exist, generates on-demand (may take 30-60s)

- **FR-4.6**: `/task-summary <linear-issue-id>` - Get Linear issue summary
  - Example: `/task-summary THJ-123`
  - Fetches Linear issue details via API
  - Generates persona-specific summary
  - Includes context from related Discord feedback, GitHub PRs
  - Responds with summary (ephemeral message or Google Docs link)

- **FR-4.7**: `/show-sprint [sprint-id]` - Get current sprint status
  - Example: `/show-sprint` (current sprint) or `/show-sprint sprint-1`
  - Responds with high-level status from Linear API:
    - In Progress tasks (count + assignees)
    - Completed tasks (count)
    - Blocked tasks (count + blockers)
    - Sprint timeline (start/end dates)
  - Links to full sprint report in Google Docs

- **FR-4.8**: `/my-notifications` - Configure notification preferences
  - User can enable/disable:
    - Daily digest notifications
    - Sprint completion notifications
    - Audit completion notifications
    - Feedback updates (when their feedback is addressed)
  - Uses existing `user-preferences.json` system (already built)

**Acceptance Criteria:**
- [ ] All slash commands registered with Discord API and functional
- [ ] Commands detect user role automatically (Discord role → persona mapping)
- [ ] All commands respond within 10 seconds (or show "generating..." message)
- [ ] Google Docs links have correct permissions (user can access)
- [ ] Error handling: Invalid input shows helpful error message
- [ ] `/translate` command requires project name as first argument
- [ ] `/translate` command supports document shorthand (@prd, @sdd, @sprint, @reviewer, @audit)
- [ ] `/translate` command integrates with existing `SecureTranslationInvoker`
- [ ] `/blog-draft` command integrates with existing `BlogDraftGenerator`
- [ ] ALL agentic-base documents (PRD, SDD, sprint.md, A2A docs) accessible via `/translate` (FR-4.9)
- [ ] Document shorthand resolver correctly maps @prd → docs/prd.md, @sdd → docs/sdd.md, etc.

**Priority:** HIGH

---

### 5. Hivemind Methodology Integration (MEDIUM)

**User Story:** As a developer, I need the transformation pipeline to understand Hivemind methodology so that context from LEARNINGS library, User Truth Canvas, and Product Home is included in summaries.

**Requirements:**

- **FR-5.1**: Query LEARNINGS library for historical context
  - Before generating summaries, query Linear LEARNINGS team for relevant learnings
  - Search by tags, product name, feature keywords
  - Include relevant learnings in summaries (e.g., "Based on past experiments, we learned...")
  - Cite LEARNINGS sources in document references

- **FR-5.2**: Extract context from User Truth Canvas
  - Parse User Truth Canvas issues (jobs, pains, gains)
  - Include user context in product manager and marketing summaries
  - Link to original User Truth Canvas in Linear

- **FR-5.3**: Reference Product Home for product evolution context
  - Query Product Home project documents (changelog, retrospectives)
  - Include product history in summaries (e.g., "This sprint builds on previous work where...")
  - Link to Product Home for deeper context

- **FR-5.4**: Integrate CX Triage feedback
  - Pull feedback from CX Triage backlog (captured via 📌 reactions)
  - Highlight community feedback that drove sprint work
  - Show feedback → implementation traceability

- **FR-5.5**: Respect Hivemind "What NOT to Automate" principles
  - Never auto-assign Linear issues without CX Lead review
  - Never force template fields in Linear
  - Never auto-move items between teams (FinTech/CultureTech)
  - Never generate LEARNINGS without human validation
  - Document transformations are **assistive only** - humans review and approve

**Acceptance Criteria:**
- [ ] Summaries include relevant LEARNINGS library context
- [ ] User Truth Canvas context included in product/marketing summaries
- [ ] Product Home changelog referenced for product evolution context
- [ ] CX Triage feedback highlighted in summaries
- [ ] No violations of "What NOT to Automate" principles
- [ ] All Hivemind context cited with Linear links

**Priority:** MEDIUM

---

### 6. Security & Compliance (CRITICAL)

**User Story:** As a security officer, I need all transformations to be secure and compliant so that sensitive data never leaks and audit trails are complete.

**Requirements:**

- **FR-6.1**: Secret scanning (ALREADY BUILT - use existing `SecretScanner`)
  - Scan all documents before transformation
  - Automatically redact secrets in summaries
  - Block generation if CRITICAL secrets detected
  - Log all secret detections with context

- **FR-6.2**: Content sanitization (ALREADY BUILT - use existing `ContentSanitizer`)
  - Defend against prompt injection attacks
  - Remove suspicious patterns before sending to LLM
  - Log all sanitization actions

- **FR-6.3**: Output validation (ALREADY BUILT - use existing `OutputValidator`)
  - Validate generated content for secrets
  - Check for PII leakage
  - Ensure content matches expected format

- **FR-6.4**: Manual review queue (ALREADY BUILT - use existing `ReviewQueue`)
  - Flag suspicious transformations for human review
  - Require approval before publishing to Google Docs
  - Track review status and approver

### 6.5. Agent Linear Integration for Audit Trail (CRITICAL - v1.3 - IMPLEMENTED ✅)

**User Story:** As a stakeholder, I need all agent work automatically tracked in Linear with complete audit trails so that I can see what's being built, by whom, and why without asking developers.

**Context:** This requirement was discovered during PRD-implementation alignment analysis (2025-12-11). The feature was fully implemented during Phases 1-5 of the Linear integration but never documented in the PRD. FR-7 (Build Status & Process Reporting) depends on this foundational capability but the dependency was not explicit.

**Why Critical:** Without agents creating Linear issues, stakeholders have nothing to query via Discord commands (`/show-issue`, `/list-issues`). This is the foundation that makes real-time build visibility (FR-7) possible.

**Implementation Status:** ✅ **FULLY IMPLEMENTED** (Phases 1-5, 2025-12-06 to 2025-12-07)

**Requirements:**

- **FR-6.5.1**: **Linear Label Taxonomy Setup** ✅ IMPLEMENTED
  - Implement base label system with 18 labels across 4 categories:
    - **Agent labels** (who): `agent:implementer`, `agent:devops`, `agent:auditor`, `agent:architect`, `agent:planner`, `agent:reviewer`
    - **Type labels** (what): `type:feature`, `type:bugfix`, `type:infrastructure`, `type:security`, `type:audit-finding`, `type:documentation`
    - **Source labels** (where): `source:discord`, `source:github`, `source:internal`, `source:audit`
    - **Priority labels** (urgency): `priority:critical`, `priority:high`, `priority:medium`, `priority:low`
  - Script: `devrel-integration/scripts/setup-linear-labels.ts`
  - Labels created in Linear workspace (team-specific or workspace-wide)
  - Idempotent script (safe to run multiple times)

- **FR-6.5.2**: **sprint-task-implementer Linear Integration** ✅ IMPLEMENTED
  - Agent file: `.claude/agents/sprint-task-implementer.md` (Lines 156-573: Phase 0.5)
  - **Parent issue creation:**
    - Create Linear parent issue for each sprint task at start of implementation
    - Title format: `[Sprint {N}] {Task Title}`
    - Labels: `agent:implementer`, `type:feature`, `sprint:sprint-{N}`, `source:internal`
    - Initial status: `Todo`
    - Links to sprint plan in description
  - **Sub-issue creation:**
    - Create sub-issues for major components (routes, services, database, tests)
    - Sub-issues linked to parent via Linear parent-child relationship
    - Each sub-issue tracks specific implementation component
  - **Status transitions:**
    - `Todo` → `In Progress` when agent starts implementation
    - `In Progress` → `In Review` when implementation complete, report written
    - `In Review` → `Done` when senior tech lead approves (`/review-sprint`)
  - **Implementation notes:**
    - Agent adds comments to Linear issue during implementation
    - Comments include technical decisions, blockers, context
    - Links to GitHub PRs and commits in issue description
  - **A2A integration:**
    - Report path written to `docs/a2a/reviewer.md` includes Linear issue links
    - Senior tech lead can query Linear for implementation status
    - Feedback loop: Review → Fix → Update Linear status

- **FR-6.5.3**: **devops-crypto-architect Linear Integration** ✅ IMPLEMENTED
  - Agent file: `.claude/agents/devops-crypto-architect.md` (Lines 441-907: Phase 0.5)
  - **Dual-mode support:**
    - **Integration mode**: Infrastructure for organizational integrations (Discord bot, webhooks)
    - **Deployment mode**: Production infrastructure (IaC, CI/CD, monitoring)
  - **Parent issue creation:**
    - Create Linear parent issue for infrastructure work
    - Title format: `[Infrastructure] {Work Title}`
    - Labels: `agent:devops`, `type:infrastructure`, `source:internal`
  - **Sub-issue creation:**
    - Infrastructure components tracked as sub-issues
    - Examples: Terraform modules, Docker configs, CI/CD pipelines, monitoring setup
  - **Status transitions:**
    - Same workflow as sprint-task-implementer
    - `Todo` → `In Progress` → `In Review` → `Done`
  - **Integration with existing workflow:**
    - Invoked via `/implement-org-integration` or `/deploy-production`
    - Linear issues track infrastructure as code changes
    - Links to deployment reports in `docs/deployment/`

- **FR-6.5.4**: **paranoid-auditor Linear Integration** ✅ IMPLEMENTED
  - Agent file: `.claude/agents/paranoid-auditor.md` (Lines 291-737: Phase 0.5)
  - **Parent issue creation:**
    - Create Linear parent issue for each security audit
    - Title format: `[Security Audit] {Sprint/Component Name}`
    - Labels: `agent:auditor`, `type:security`, `source:audit`
    - Links to audit report (`SECURITY-AUDIT-REPORT.md` or sprint-specific)
  - **Severity-based sub-issues:**
    - Create sub-issues for each finding by severity:
      - CRITICAL findings → `priority:critical` label, immediate sub-issue
      - HIGH findings → `priority:high` label, individual sub-issue
      - MEDIUM findings → `priority:medium` label, grouped sub-issues
      - LOW findings → `priority:low` label, grouped sub-issues
  - **Finding format:**
    - Each sub-issue title: `[SEVERITY] Finding Title`
    - Description includes:
      - Vulnerability description
      - Impact assessment
      - Affected code/files
      - Remediation guidance
      - OWASP category (if applicable)
  - **Bidirectional linking:**
    - Audit report links to Linear parent issue
    - Linear parent issue links to audit report
    - Sub-issues link to specific code locations (file paths, line numbers)
  - **Status tracking:**
    - Findings start in `Todo` status
    - Engineer assigns to self when starting remediation
    - Transitions to `In Progress` → `In Review` → `Done` as fixes are implemented
    - Auditor verifies fixes before marking `Done`
  - **Remediation workflow:**
    - Engineer reads audit finding from Linear issue
    - Implements fix and updates Linear issue with remediation notes
    - Auditor reviews fix and approves or requests changes
    - Cycle continues until approved

- **FR-6.5.5**: **Feedback Capture Linear Integration** ✅ IMPLEMENTED
  - File: `devrel-integration/src/handlers/feedbackCapture.ts`
  - **Discord 📌 reaction → Linear draft issue:**
    - User reacts with 📌 emoji to Discord message
    - Bot captures message content, thread context, author info
    - Creates Linear draft issue in CX Triage or detected project
    - Auto-detects project from channel name (e.g., #mibera-feedback → MiBera project)
    - Labels: `source:discord`, `type:feedback`
  - **Priority setting via emoji reactions:**
    - 🔴 → `priority:critical`
    - 🟠 → `priority:high`
    - 🟡 → `priority:medium`
    - 🟢 → `priority:low`
  - **Discord commands for issue management:**
    - `/tag-issue <issue-id> <project> [priority]` - Tag issue with project and priority
    - `/show-issue <issue-id>` - Display issue details
    - `/list-issues [filter]` - List issues grouped by status

- **FR-6.5.6**: **Discord Command Integration** ✅ IMPLEMENTED
  - File: `devrel-integration/src/handlers/commands.ts` (Lines 447-691)
  - **Linear query commands:**
    - `/show-issue <issue-id>` - Display issue details (status, assignee, labels, description)
    - `/list-issues [filter]` - List issues grouped by status (Todo, In Progress, In Review, Done)
    - `/tag-issue <issue-id> <project> [priority]` - Tag issues with project labels
  - **Permission gating:**
    - Commands restricted to users with developer or admin roles
    - Non-authenticated users receive permission error
  - **Response format:**
    - Discord embeds with formatted issue information
    - Clickable Linear issue links
    - Status indicators and priority badges
    - Assignee mentions (if applicable)

- **FR-6.5.7**: **Issue Hierarchy and Linking**
  - **Parent-child relationships:**
    - Agent parent issue → Component sub-issues
    - Audit parent issue → Finding sub-issues
    - Discord feedback → Implementation issue (reference link)
  - **Cross-references:**
    - Linear issues link to GitHub PRs (in description)
    - Linear issues link to Discord messages (via message URL)
    - Linear issues link to local documents (docs/sprint.md, docs/a2a/reviewer.md)
    - Audit reports link to Linear issues
    - Sprint reports link to Linear issues

**Acceptance Criteria:**
- [x] ✅ Label taxonomy script creates 18 base labels in Linear
- [x] ✅ sprint-task-implementer creates parent + sub-issues for sprint tasks
- [x] ✅ devops-crypto-architect creates issues for infrastructure work
- [x] ✅ paranoid-auditor creates issues for audit findings with severity-based hierarchy
- [x] ✅ Discord 📌 reaction creates Linear draft issues with auto project detection
- [x] ✅ Priority emoji reactions (🔴🟠🟡🟢) update Linear issue priority
- [x] ✅ Discord commands query Linear issues (`/show-issue`, `/list-issues`, `/tag-issue`)
- [x] ✅ All agents transition issue statuses throughout workflow (Todo → In Progress → In Review → Done)
- [x] ✅ Issue descriptions include links to related documents (GitHub PRs, Discord messages, local files)
- [x] ✅ Parent-child relationships maintained for organized tracking
- [x] ✅ Agents add comments to issues during work for audit trail

**Priority:** CRITICAL (foundation for FR-7 stakeholder visibility)

**Dependencies:**
- FR-7 (Build Status & Process Reporting) **DEPENDS ON** FR-6.5
  - Without agents creating Linear issues, stakeholders have nothing to query via `/show-issue`, `/list-issues`
  - Proactive notifications (FR-7.2) depend on agents updating issue statuses
  - Build dashboard (FR-7.3) queries issues created by agents
  - Linear webhooks (FR-7.4) trigger on agent-created issue updates

**Implementation Files:**
- `.claude/agents/sprint-task-implementer.md` (Lines 156-573)
- `.claude/agents/devops-crypto-architect.md` (Lines 441-907)
- `.claude/agents/paranoid-auditor.md` (Lines 291-737)
- `devrel-integration/scripts/setup-linear-labels.ts`
- `devrel-integration/src/handlers/feedbackCapture.ts`
- `devrel-integration/src/handlers/commands.ts` (Lines 447-691)
- `devrel-integration/src/services/linearService.ts`

**Documentation:**
- `devrel-integration/docs/LINEAR_INTEGRATION.md` (500+ line comprehensive guide)
- `docs/LINEAR_INTEGRATION_PRD_ALIGNMENT.md` (Gap analysis that identified this missing requirement)

---

- **FR-6.6**: Audit logging
  - Log all transformation requests (who, what, when, why)
  - Log all Google Docs operations (create, read, update)
  - Log all Discord commands (user, command, result)
  - Store logs in append-only format (Winston logger - already configured)

- **FR-6.7**: Permissions validation (NEW - use existing `DrivePermissionValidator`)
  - Verify user has permission to access requested document
  - Enforce role-based access control (RBAC)
  - Deny access if user role doesn't match document audience

- **FR-6.8**: Rate limiting (ALREADY BUILT - use existing `ApiRateLimiter`)
  - Limit transformation requests per user (10/hour)
  - Limit Google Docs API calls (avoid quota exhaustion)
  - Implement exponential backoff for failures

**Acceptance Criteria:**
- [ ] All transformations pass secret scanning (no secrets in output)
- [ ] Prompt injection attempts blocked by content sanitizer
- [ ] Suspicious transformations flagged for manual review
- [ ] Complete audit trail for all operations (queryable logs)
- [ ] RBAC enforced for Google Docs access
- [ ] Rate limiting prevents abuse and quota exhaustion
- [x] ✅ Agent Linear integration fully functional (FR-6.5) - ALREADY IMPLEMENTED

**Priority:** CRITICAL (security is non-negotiable)

---

### 7. Build Status & Process Reporting (CRITICAL - v1.2)

**User Story:** As a stakeholder, I need real-time visibility into what's being built while it's being built so that I can prepare marketing materials, provide feedback early, and stay aligned with the team without constantly asking developers for updates.

**Context:** Stakeholder feedback (LAB-513, LAB-508) revealed that current visibility is limited to milestone completions. Teams need **continuous updates during the build process**, not just notifications when sprints complete.

**Requirements:**

- **FR-7.1**: **Real-Time Linear Integration Dashboard**
  - Embed Linear issue tracking into Discord via commands
  - Show in-progress tasks with real-time status updates
  - Display task assignments, priorities, and blockers
  - Commands:
    - `/show-issue <issue-id>` - Display issue details with status, assignee, labels, description
    - `/list-issues [filter]` - List issues grouped by status (Todo, In Progress, In Review, Done)
    - `/tag-issue <issue-id> <project> [priority]` - Human team members can tag issues with project labels

- **FR-7.2**: **Proactive Build Notifications**
  - Notify stakeholders when agents **START** work (not just when they finish)
  - Notification format: "🔨 Sprint-task-implementer started working on Issue THJ-123: Implement user authentication"
  - Notification triggers:
    - Agent creates Linear parent issue → "📋 New task created: [Issue Title]"
    - Agent updates issue to "In Progress" → "🔨 Work started on: [Issue Title]"
    - Agent completes component (sub-issue) → "✅ Component completed: [Component Name]"
    - Agent updates issue to "In Review" → "👁️ Ready for review: [Issue Title]"
    - Agent completes work (issue Done) → "🎉 Completed: [Issue Title]"
  - Configurable per-user notification preferences (via `/my-notifications`)

- **FR-7.3**: **Build Progress Dashboard**
  - Generate dynamic progress report on-demand
  - Command: `/build-status [project|sprint]`
  - Shows:
    - Overall sprint progress (% complete)
    - Tasks in progress (who's working on what)
    - Completed tasks (what's done)
    - Blocked tasks (what needs attention)
    - Estimated completion timeline (based on task velocity)
  - Visual progress indicators (progress bars in Discord embeds)

- **FR-7.4**: **Linear Webhook Integration**
  - Listen to Linear webhooks for issue updates
  - Trigger notifications in Discord when:
    - Issue created by agent
    - Issue status changed (Todo → In Progress → In Review → Done)
    - Issue assigned/reassigned
    - Issue priority changed
    - Comment added by agent (implementation notes)
  - Webhook endpoint: `/webhooks/linear`
  - Security: Verify webhook signature

- **FR-7.5**: **Sprint Timeline Visualization**
  - Generate Gantt-chart-style timeline for sprint tasks
  - Command: `/sprint-timeline [sprint-id]`
  - Shows:
    - Task dependencies (what blocks what)
    - Start/end dates for each task
    - Critical path highlighted
    - Resource allocation (who's assigned to what)
  - Export as image (PNG) or Google Doc
  - Update automatically as Linear issues change

**Acceptance Criteria:**
- [ ] Discord commands for Linear integration functional (`/show-issue`, `/list-issues`, `/tag-issue`)
- [ ] Linear webhook endpoint receives and processes issue updates
- [ ] Proactive notifications sent when agents start/complete work
- [ ] Build status dashboard shows real-time progress
- [ ] Sprint timeline visualization generates accurate Gantt charts
- [ ] Notifications configurable per-user via `/my-notifications`

**Priority:** CRITICAL (addresses top stakeholder feedback - continuous build visibility)

---

### 8. Comprehensive Knowledge Base (CRITICAL - v1.2)

**User Story:** As a stakeholder, I need a constantly updated knowledge base that includes ALL decisions, discussions, product specs, technical details, and rationale so that I can understand not just WHAT was built, but WHY it was built that way.

**Context:** Stakeholder feedback (LAB-513, LAB-509, LAB-508) revealed that current documentation is incomplete. Teams need "a full product" including "instructions, manual, hazards, expiration dates" - not just code.

**Requirements:**

- **FR-8.1**: **Product Specification Repository**
  - For each product, maintain comprehensive specification documents:
    - **Product Overview** (`/Products/{Product}/Overview.md`)
      - What the product is and does
      - Target users and use cases
      - Key features and capabilities
      - Product evolution history (changelog)
    - **Technical Specifications** (`/Products/{Product}/Technical-Specs.md`)
      - Architecture overview and diagrams
      - Tech stack and dependencies
      - API endpoints and data models
      - Integration points and external services
    - **Design Specifications** (`/Products/{Product}/Design-Specs.md`)
      - Asset requirements (sizes, formats, dimensions)
      - File naming conventions
      - Color palettes and brand guidelines
      - UI/UX patterns and components
    - **Operational Manual** (`/Products/{Product}/Operations.md`)
      - Deployment procedures
      - Monitoring and alerts
      - Troubleshooting guides
      - Incident response playbooks
    - **User Documentation** (`/Products/{Product}/User-Guide.md`)
      - How to use the product (instructions manual)
      - Common tasks and workflows
      - FAQs and troubleshooting
      - Known limitations and workarounds
  - Auto-generated from sprint reports, PRD, SDD, A2A docs
  - Continuously updated as work progresses
  - Version-controlled with change history

- **FR-8.2**: **Decision Log**
  - Capture ALL technical and product decisions with rationale
  - Format: `ADR-{Number}: {Decision Title}`
  - Structure:
    ```markdown
    # ADR-001: Use OAuth 2.0 for Authentication

    ## Status
    Accepted (2025-12-10)

    ## Context
    Users need secure login without managing passwords...

    ## Decision
    We will implement OAuth 2.0 using Passport.js...

    ## Consequences
    **Positive:**
    - Industry-standard security
    - No password management overhead

    **Negative:**
    - Dependency on third-party OAuth providers
    - Additional complexity for self-hosted deployments

    ## Alternatives Considered
    1. Username/password auth (rejected - security burden)
    2. Magic links (rejected - poor UX for frequent use)
    ```
  - Auto-generated from SDD technical decisions
  - Linked from related documents (PRD, sprint reports)
  - Searchable via Discord: `/decision-search <keyword>`

- **FR-8.3**: **Change History Tracking**
  - Track WHAT changed, WHEN, WHY for every product update
  - Format: Structured changelog in `/Products/{Product}/Changelog.md`
  - Structure:
    ```markdown
    # MiBera Changelog

    ## [v1.2.0] - 2025-12-11

    ### Added
    - OAuth 2.0 authentication flow (#THJ-123)
    - JWT token validation middleware (#THJ-124)

    ### Changed
    - Updated session TTL from 7 days to 30 days (#THJ-125)
    - Reason: User feedback requested longer sessions

    ### Technical Details
    - Using Passport.js for OAuth integration
    - JWT tokens signed with RS256 algorithm
    - Redis for session storage

    ### Migration Notes
    - Users need to re-authenticate after upgrade
    - Old session tokens invalidated
    ```
  - Auto-generated from Linear issues and sprint reports
  - Includes both user-facing changes and technical details
  - Links to related Linear issues, PRs, commits

- **FR-8.4**: **Discord Discussion Archive**
  - Capture important Discord discussions and decisions
  - When feedback is captured (📌 reaction), also capture thread context
  - Store in `/Shared/Discussions/{Date}/{Topic}.md`
  - Include:
    - Original message and thread
    - Participants and timestamps
    - Resolution or decision made
    - Link to Linear issue created (if any)
  - Searchable via `/discussion-search <keyword>`

- **FR-8.5**: **Pre-Work Clarification Documents**
  - Before agents start implementation, generate clarification documents
  - Triggered when sprint planning completes
  - For each task, create `/Products/{Product}/Sprints/Sprint-{N}/Clarifications/{Task}.md`
  - Include:
    - Acceptance criteria detailed explanation
    - Technical constraints and requirements
    - Design specifications (if applicable)
    - Integration points and dependencies
    - Success criteria and testing approach
  - Reviewed by stakeholders before work begins
  - Discord command: `/clarify <task-id>` to request clarification document

- **FR-8.6**: **Marketing Asset Specifications**
  - Maintain comprehensive asset spec repository
  - `/Shared/Asset-Specs/`
    - Image specs (sizes, formats, dimensions)
    - Video specs (resolution, codecs, aspect ratios)
    - Copy specs (character limits, tone guidelines)
    - File naming conventions
  - Command: `/asset-spec <type>` to query specs
  - Example: `/asset-spec twitter-image` → "1200x675px, PNG or JPG, <5MB, file naming: {project}-{purpose}-{date}.{ext}"

**Acceptance Criteria:**
- [ ] Product specification repository auto-generated for each product
- [ ] Decision log captures all ADRs with rationale and alternatives
- [ ] Change history tracking includes both user-facing and technical changes
- [ ] Discord discussion archive captures important conversations
- [ ] Pre-work clarification documents generated before implementation
- [ ] Marketing asset specifications accessible via Discord command
- [ ] All documents continuously updated as work progresses
- [ ] Documents cross-referenced and searchable

**Priority:** CRITICAL (addresses top stakeholder feedback - comprehensive knowledge base)

---

### 9. Marketing & Communications Support (HIGH - v1.2)

**User Story:** As a marketing team member, I need custom data extraction, technical accuracy validation, and structured content so that I can create marketing materials confidently without constantly consulting developers.

**Context:** Stakeholder feedback (LAB-513, LAB-509) revealed marketing needs that current system doesn't address: custom data, technical validation, asset specs.

**Requirements:**

- **FR-9.1**: **Custom Data Extraction Service**
  - Extract specific data from codebase, Linear, or on-chain sources for marketing materials
  - Command: `/extract-data <data-type> <parameters>`
  - Examples:
    - `/extract-data user-stats MiBera last-30-days` → Total users, active users, new signups
    - `/extract-data feature-usage voting last-quarter` → Voting participation metrics
    - `/extract-data on-chain-metrics token-holders` → Token holder count, distribution
  - Supports common marketing data needs:
    - User metrics (signups, active users, retention)
    - Feature usage (most popular features, adoption rates)
    - Performance metrics (response times, uptime)
    - On-chain metrics (token holders, transaction volume, TVL)
  - Returns formatted data ready for marketing copy
  - Includes data source and timestamp for attribution

- **FR-9.2**: **Technical Accuracy Validation Service**
  - Validate marketing materials for technical correctness before publishing
  - Command: `/validate-content <google-docs-link>` or paste content in Discord
  - Bot analyzes content and flags:
    - Incorrect technical claims
    - Outdated information (feature removed, metrics stale)
    - Missing disclaimers (risks, limitations)
    - Misleading language (overpromising)
  - Returns validation report:
    - ✅ Technically accurate
    - ⚠️ Minor issues found (suggestions)
    - ❌ Major issues found (must fix)
  - Suggests corrections with citations

- **FR-9.3**: **RACI Matrix Generation**
  - Generate RACI (Responsible, Accountable, Consulted, Informed) matrices for product launches
  - Command: `/generate-raci <product> <initiative>`
  - Analyzes sprint plan and team structure to propose RACI
  - Format: Table showing tasks × team members with RACI assignments
  - Editable in Google Docs, shareable with team
  - Example output:
    ```
    | Task                | Marketing | DevRel | Engineering | Leadership |
    |---------------------|-----------|--------|-------------|------------|
    | Write blog post     | R         | C      | I           | I          |
    | Technical review    | I         | R      | A           | I          |
    | Publish             | A         | I      | I           | I          |
    ```

- **FR-9.4**: **A/B Testing Data Dashboard** (MEDIUM priority - Phase 2)
  - Collect and present A/B testing data for design decisions
  - Command: `/ab-test-data <test-name>`
  - Shows:
    - Test variants and metrics
    - Statistical significance
    - Winning variant recommendation
  - Integrated with existing product analytics (if available)
  - Deferred to Phase 2 (requires analytics infrastructure)

**Acceptance Criteria:**
- [ ] Custom data extraction service supports common marketing data needs
- [ ] Technical accuracy validation identifies incorrect claims and outdated info
- [ ] RACI matrix generation creates sensible assignments based on team structure
- [ ] All services accessible via Discord commands
- [ ] Data sources cited for transparency
- [ ] Validation reports actionable with specific corrections

**Priority:** HIGH (high impact, low effort)

---

## Technical Requirements

### Architecture Components

**TR-1: Google Workspace Infrastructure**
- Google Workspace organization (brand new)
- Terraform IaC for all workspace resources
- Service account with Google Docs API access
- OAuth 2.0 authentication flow for users
- Remote Terraform state with state locking

**TR-2: Onomancer Bot (Discord)**
- Discord.js v14 (already installed)
- Slash command registration
- Message history access (for context aggregation)
- Role-based command permissions
- Ephemeral messages for sensitive data

**TR-3: devrel-translator Agent Integration**
- Invoke via Claude Code `/translate` slash command OR
- Embed agent logic directly in bot backend (TBD during architecture phase)
- Agent persona: DevRel character archetype
- Agent prompt engineering: Reference Hivemind, agentic-base context

**TR-4: Context Aggregation Layer**
- Linear SDK (@linear/sdk v21.0.0 - already installed)
- GitHub API via MCP (already configured)
- Discord message history API
- Local file system access (read `docs/` directory)
- Unified context assembly using existing `ContextAssembler`

**TR-5: Document Storage & Retrieval**
- Google Docs API (googleapis npm package)
- Document metadata storage (frontmatter in docs)
- Version control (Google Docs native versioning)
- Search/indexing (Google Drive search API)

**TR-6: Transformation Pipeline**
- SecureTranslationInvoker (already built)
- BlogDraftGenerator (already built)
- ContentSanitizer (already built)
- SecretScanner (already built)
- OutputValidator (already built)

**TR-7: Monitoring & Observability**
- Winston logger (already configured)
- Google Docs API usage monitoring
- Transformation success/failure metrics
- Discord bot uptime monitoring
- Error alerting (Discord channel or Slack)

### Technology Stack

**Infrastructure:**
- Terraform (latest stable version)
- Google Workspace Admin API
- Google Cloud Platform (for service accounts)

**Backend:**
- Node.js 18+ LTS (already installed)
- TypeScript 5.3+ (already installed)
- Express (already installed)

**Discord Bot:**
- Discord.js v14 (already installed)
- node-cron for scheduled jobs (already installed)

**External APIs:**
- Google Docs API (googleapis)
- Linear API (@linear/sdk - already installed)
- GitHub API (via MCP - already configured)

**Security:**
- bcryptjs (already installed)
- validator (already installed)
- DOMPurify (already installed)
- speakeasy (already installed)

**Storage:**
- Google Docs (primary storage)
- SQLite (bot state, user preferences - already configured)
- Redis (caching - already configured with ioredis)

**Testing:**
- Jest (already installed)
- ts-jest (already installed)

### Integration Points

**IP-1: Linear Integration (EXISTING)**
- Read sprint tasks via Linear SDK
- Read issue comments and descriptions
- Read project documents (Product Home, LEARNINGS)
- Update issue statuses (optional)

**IP-2: GitHub Integration (EXISTING - via MCP)**
- Read PR descriptions and code diffs
- Read commit messages
- Link PRs to Linear issues (via PR description parsing)

**IP-3: Discord Integration (EXISTING)**
- Read message history for context
- Capture feedback via 📌 reactions (already implemented)
- Post notifications to channels
- Respond to slash commands

**IP-4: Google Docs Integration (NEW)**
- Create documents programmatically
- Set document permissions by user/group
- Update document content
- Query documents by metadata

**IP-5: Terraform Integration (NEW)**
- Manage Google Workspace resources as code
- Version control infrastructure changes
- Automate folder creation and permissions

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     AUTOMATED TRIGGER                            │
│  (/review-sprint approval, /audit-sprint completion, weekly cron)│
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                  CONTEXT AGGREGATION LAYER                       │
│  • Read local files (docs/sprint.md, docs/a2a/reviewer.md)      │
│  • Query Linear API (issues, comments, projects)                │
│  • Query GitHub API (PRs, commits)                              │
│  • Read Discord history (feedback, discussions)                 │
│  • Query LEARNINGS library (historical context)                 │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                 TRANSFORMATION PIPELINE                          │
│  • SecureTranslationInvoker (prompt injection defense)          │
│  • SecretScanner (detect/redact secrets)                        │
│  • ContentSanitizer (sanitize input)                            │
│  • devrel-translator agent (generate summaries)                 │
│  • OutputValidator (validate output)                            │
│  • ReviewQueue (flag suspicious content)                        │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│               GOOGLE DOCS STORAGE LAYER                          │
│  • Store original document in root folder                        │
│  • Store 4 persona summaries in /Executive Summaries/           │
│  • Set permissions by audience (leadership, product, etc.)      │
│  • Add document metadata (frontmatter)                          │
│  • Create bidirectional links (original ↔ summaries)            │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                  DISCORD NOTIFICATION                            │
│  • Post message: "Sprint 1 summaries ready!"                    │
│  • Include query command: `/exec-summary sprint-1`              │
│  • Tag relevant roles (@leadership, @product, etc.)             │
└─────────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│              STAKEHOLDER SELF-SERVICE ACCESS                     │
│  User: /exec-summary sprint-1                                   │
│  Bot: Detects user role → Returns appropriate Google Doc link   │
│  User: Opens Google Doc in browser                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## Non-Functional Requirements

### Performance
- **NFR-1**: Transformation latency <60 seconds per document (from trigger to Google Docs storage)
- **NFR-2**: Discord command response time <10 seconds (or "generating..." message)
- **NFR-3**: Weekly digest generation <5 minutes
- **NFR-4**: Google Docs API rate limit <80% utilization (avoid quota exhaustion)
- **NFR-5**: Bot uptime >99% (excluding planned maintenance)

### Scalability
- **NFR-6**: Support 10+ products with 5+ sprints each (50+ document sets)
- **NFR-7**: Handle 100+ Discord users querying concurrently
- **NFR-8**: Process 50+ transformations per day without degradation
- **NFR-9**: Store 1000+ documents in Google Docs with fast search
- **NFR-10**: Scale to 10+ developers working concurrently (no lock contention)

### Reliability
- **NFR-11**: Automatic retry for failed transformations (3 retries with exponential backoff)
- **NFR-12**: Circuit breaker for external API failures (Linear, GitHub, Google Docs)
- **NFR-13**: Graceful degradation: Bot responds with cached data if APIs unavailable
- **NFR-14**: Error notifications posted to Discord admin channel
- **NFR-15**: Complete audit trail for debugging failures

### Security
- **NFR-16**: Secret scanning blocks 100% of credential leaks
- **NFR-17**: Prompt injection attacks blocked by content sanitizer
- **NFR-18**: RBAC enforced for all Google Docs access (users see only their permitted docs)
- **NFR-19**: Audit logs append-only and tamper-evident
- **NFR-20**: Secrets stored in encrypted `.env.local` file (gitignored)

### Usability
- **NFR-21**: Discord commands follow intuitive syntax (verb-noun pattern)
- **NFR-22**: Error messages are clear and actionable (e.g., "Sprint not found. Try `/show-sprint` to list available sprints")
- **NFR-23**: Google Docs have descriptive titles and folder organization
- **NFR-24**: Document metadata (frontmatter) is human-readable
- **NFR-25**: Bot responses include helpful hints (e.g., "Tip: Use `/digest weekly` for weekly updates")

### Maintainability
- **NFR-26**: Terraform code is modular and reusable (modules for folders, permissions, etc.)
- **NFR-27**: Bot code follows single responsibility principle (services, handlers, utils)
- **NFR-28**: Configuration externalized in YAML/JSON files (no hardcoded values)
- **NFR-29**: Comprehensive logging for debugging (info, warn, error levels)
- **NFR-30**: Code coverage >80% for critical paths (transformation, security)

---

## Scope & Prioritization

### In Scope (MVP - Phase 1 + v1.2 Enhancements)

**CRITICAL (Must Have for MVP v1.3):**
1. ✅ Google Workspace organization creation
2. ✅ Terraform IaC for folder structure and permissions (includes PRD, SDD, Sprints, Audits folders)
3. ✅ Document transformation pipeline (4 persona summaries)
4. ✅ Automated triggers: PRD generation, SDD generation, sprint plan generation, `/review-sprint` approval, `/audit-sprint` completion
5. ✅ Discord slash commands: `/exec-summary`, `/audit-summary`, `/translate <project> <@document> for <audience>`
6. ✅ Security controls: Secret scanning, content sanitization, output validation
7. ✅ Audit logging
8. ✅ **Agent Linear Integration** (FR-6.5): Label taxonomy, issue hierarchy, status transitions, sprint-task-implementer, devops-crypto-architect, paranoid-auditor integrations - **FULLY IMPLEMENTED**
9. 🆕 **Real-time build visibility** (FR-7.1-7.5): Linear integration dashboard, proactive notifications, build status reporting, webhooks, Gantt chart timelines
10. 🆕 **Comprehensive knowledge base** (FR-8.1-8.6): Product specs, decision logs, change history, Discord archive, pre-work clarifications, asset specs

**HIGH (Should Have for MVP v1.3):**
11. ✅ Weekly digest generation (cron job)
12. ✅ Context aggregation from Linear, GitHub, Discord
13. ✅ **ALL agentic-base documents accessible**: `/translate` works for PRD, SDD, sprint.md, A2A docs (FR-4.9)
14. ✅ Document shorthand support: `@prd`, `@sdd`, `@sprint`, `@reviewer`, `@audit`
15. ✅ Blog draft generation: `/blog-draft <sprint-id>`
16. ✅ Discord command: `/show-sprint`
17. ✅ **Linear Discord commands**: `/show-issue`, `/list-issues`, `/tag-issue` - **FULLY IMPLEMENTED**
18. ✅ **Feedback capture**: 📌 emoji reaction → Linear draft issue with auto project detection - **FULLY IMPLEMENTED**
19. ✅ **Priority management**: Emoji reactions (🔴🟠🟡🟢) set Linear issue priority - **FULLY IMPLEMENTED**
20. 🆕 **Marketing & communications support** (FR-9.1-9.3): Custom data extraction, technical validation, RACI generation
21. 🆕 **Notification preferences**: `/my-notifications` (configurable build notifications)

**MEDIUM (Nice to Have for MVP):**
19. ⚠️ Hivemind LEARNINGS library integration
20. ⚠️ User Truth Canvas context extraction
21. ⚠️ Product Home changelog referencing
22. ⚠️ A/B testing data dashboard (FR-9.4)

### Out of Scope (Phase 2)

**Deferred to Later Phases:**
1. ❌ Migration from old files/folders (defer until Phase 2)
2. ❌ Twitter/Telegram integration (defer to Phase 3)
3. ❌ Advanced NLP for natural language queries (defer to Phase 3)
4. ❌ Automated blog publishing (manual approval only for MVP)
5. ❌ Real-time document editing (read-only access for MVP)
6. ❌ Mobile app (Discord mobile app sufficient for MVP)
7. ❌ Multi-language support (English only for MVP)
8. ❌ Advanced analytics dashboard (basic logging sufficient for MVP)

### Explicitly Out of Scope (Never)

**Will NOT Build:**
1. 🚫 Auto-publishing to external platforms (Twitter, Medium, etc.) - Manual approval required for security
2. 🚫 Auto-assignment of Linear issues without human review (violates Hivemind principles)
3. 🚫 Direct code execution or modification (read-only bot)
4. 🚫 Public-facing API (internal tool only)
5. 🚫 Customer-facing documentation (internal stakeholders only)

### Prioritization Framework

**Priority Levels:**
- **CRITICAL**: Blocks all other work, security vulnerability, core functionality
- **HIGH**: Significant business impact, user-facing feature, blocks phase completion
- **MEDIUM**: Nice to have, improves UX, deferred if time-constrained
- **LOW**: Future enhancement, experimental, can be skipped

**Trade-off Decisions:**
- **Quality over Speed**: Security and correctness are non-negotiable, even if it slows development
- **MVP over Feature Completeness**: Ship core functionality first, iterate based on feedback
- **Automated over Manual**: Prefer automation for repetitive tasks, but humans approve high-stakes actions

---

## Success Metrics

### Primary Metrics

**M-1: Release Velocity (PRIMARY GOAL)**
- **Baseline**: Current average time-to-release with manual documentation
- **Target**: 30% reduction in time-to-release within 3 months of deployment
- **Measurement**: Time from `/review-sprint` approval to product release announcement
- **Success Criteria**: Measurable reduction in release cycle time

**M-2: Developer Time Saved**
- **Baseline**: Developers spend ~20% of time on documentation/explanations (via time tracking survey)
- **Target**: Reduce to <5% within 3 months
- **Measurement**: Weekly time-tracking survey + audit log analysis (transformation count × estimated manual time)
- **Success Criteria**: Developers report significant reduction in documentation workload

**M-3: Stakeholder Self-Service Adoption**
- **Baseline**: 0% of information requests handled by bot (all go to developers)
- **Target**: 80% of information requests handled by bot within 6 months
- **Measurement**: Discord message analysis (bot queries vs. developer pings)
- **Success Criteria**: Majority of stakeholders query bot instead of asking developers

### Secondary Metrics

**M-4: Documentation Completeness**
- **Target**: 100% of approved sprints have automated transformations within 24 hours
- **Measurement**: Audit log analysis (sprint approvals vs. transformation completions)
- **Success Criteria**: No sprints missing documentation

**M-5: Documentation Timeliness**
- **Target**: Summaries available <60 seconds after sprint approval
- **Measurement**: Audit log timestamps (trigger time → Google Docs creation time)
- **Success Criteria**: 95th percentile latency <60 seconds

**M-6: Stakeholder Satisfaction**
- **Target**: 8/10 satisfaction score for information accessibility
- **Measurement**: Quarterly survey (5-question NPS-style)
- **Success Criteria**: Majority of stakeholders report improved access to information

**M-7: Bot Uptime**
- **Target**: >99% uptime (excluding planned maintenance)
- **Measurement**: Bot health checks every 5 minutes
- **Success Criteria**: <1% downtime per month

**M-8: Security Incidents**
- **Target**: 0 secret leaks in generated documents
- **Measurement**: Secret scanner alerts + manual audit of sample documents
- **Success Criteria**: No secrets leaked in production

### Monitoring & Reporting

**Weekly Reports:**
- Transformation count (by trigger type)
- Discord command usage (by command type)
- Average transformation latency
- Error rate and top failure reasons

**Monthly Reports:**
- Release velocity trend (time-to-release over time)
- Developer time saved (survey + audit log analysis)
- Self-service adoption rate (bot queries vs. developer pings)
- Stakeholder satisfaction score (survey results)

**Quarterly Reviews:**
- Comprehensive metrics review with leadership
- User feedback and feature requests
- Roadmap planning for next quarter
- Technical debt assessment

---

## Risks & Dependencies

### High Risks

**R-1: Google Workspace Setup Complexity (HIGH IMPACT, MEDIUM PROBABILITY)**
- **Risk**: Terraform IaC for Google Workspace is complex and may require extensive configuration
- **Impact**: Delays all development (everything depends on Google Docs storage)
- **Mitigation**: Allocate extra time in architecture phase, consult Google Workspace experts, use Terraform modules from community
- **Contingency**: Manual Google Workspace setup for MVP, automate with Terraform in Phase 2

**R-2: API Rate Limits (MEDIUM IMPACT, MEDIUM PROBABILITY)**
- **Risk**: Google Docs API, Linear API, or GitHub API rate limits exhausted during high usage
- **Impact**: Bot becomes unusable, transformations fail
- **Mitigation**: Implement rate limiting, caching, circuit breakers (already built), exponential backoff
- **Contingency**: Request higher quota from API providers, implement request queuing

**R-3: Secret Leakage (HIGH IMPACT, LOW PROBABILITY)**
- **Risk**: Secret scanner fails to detect new secret pattern, credentials leak in summaries
- **Impact**: Security breach, reputational damage, credential rotation required
- **Mitigation**: Multi-layer defense (secret scanner, output validator, manual review queue), regular scanner updates, human approval for sensitive content
- **Contingency**: Immediate document takedown, credential rotation, incident postmortem

**R-4: Context Aggregation Failures (MEDIUM IMPACT, MEDIUM PROBABILITY)**
- **Risk**: Linear/GitHub APIs unavailable, local files missing, context incomplete
- **Impact**: Summaries are low-quality or inaccurate
- **Mitigation**: Graceful degradation (use cached data), retry logic, error notifications
- **Contingency**: Manual fallback (developers provide context), queue for retry when APIs recover

**R-5: devrel-translator Agent Integration Complexity (MEDIUM IMPACT, MEDIUM PROBABILITY)**
- **Risk**: Integrating devrel-translator agent persona with Onomancer bot backend is architecturally complex
- **Impact**: Delays Phase 2 (Architecture), may require rework
- **Mitigation**: Architecture phase will propose multiple integration options (slash command invocation vs. embedded logic), prototype both approaches
- **Contingency**: Simplify to direct LLM API calls for MVP, integrate agent persona in Phase 2

### Medium Risks

**R-6: Google Docs Permissions Complexity (MEDIUM IMPACT, MEDIUM PROBABILITY)**
- **Risk**: RBAC for Google Docs is complex, users may get incorrect permissions
- **Impact**: Users can't access documents or see documents they shouldn't
- **Mitigation**: Thorough testing of permission model, use Google Groups for role-based access
- **Contingency**: Manual permission fixes by admin, document permission audits

**R-7: Transformation Quality (MEDIUM IMPACT, MEDIUM PROBABILITY)**
- **Risk**: LLM-generated summaries are low-quality, inaccurate, or miss key information
- **Impact**: Stakeholders don't trust summaries, continue asking developers
- **Mitigation**: Prompt engineering, few-shot examples, human review queue for flagged content, iterative refinement based on feedback
- **Contingency**: Manual review and editing of all summaries (manual bottleneck returns temporarily)

**R-8: Hivemind Methodology Understanding (LOW IMPACT, MEDIUM PROBABILITY)**
- **Risk**: Transformation pipeline doesn't properly integrate Hivemind concepts (LEARNINGS, User Truth Canvas)
- **Impact**: Summaries lack important context, miss opportunities for knowledge reuse
- **Mitigation**: Thorough review of Hivemind docs during architecture phase, consultation with Hivemind experts (Eileen, Soju)
- **Contingency**: Defer Hivemind integration to Phase 2, focus on basic transformation for MVP

### Low Risks

**R-9: Migration from Old Files (LOW IMPACT, LOW PROBABILITY)**
- **Risk**: Migrating old files to new Google Workspace is time-consuming and error-prone
- **Impact**: Delays Phase 2, old documents temporarily inaccessible
- **Mitigation**: Explicitly out of scope for MVP, defer to Phase 2
- **Contingency**: Keep old files in original location, link to them from new docs

**R-10: Weekly Digest Noise (LOW IMPACT, MEDIUM PROBABILITY)**
- **Risk**: Weekly digests are too noisy or not useful, users ignore them
- **Impact**: Low engagement with digest feature
- **Mitigation**: Iterative refinement based on user feedback, customizable digest preferences
- **Contingency**: Disable digest feature, focus on on-demand queries

### Dependencies

**D-1: Google Workspace Account (CRITICAL)**
- **Owner**: System Administrator
- **Status**: Not yet created (Phase 1 task)
- **Blocker**: All development blocked until Google Workspace org exists
- **Action**: Create Google Workspace org ASAP, assign to technical champion

**D-2: Terraform Expertise (HIGH)**
- **Owner**: DevOps team or external consultant
- **Status**: TBD
- **Blocker**: Google Workspace IaC blocked without Terraform expertise
- **Action**: Identify Terraform expert or allocate time for learning

**D-3: devrel-translator Agent Persona Definition (HIGH)**
- **Owner**: Product team + DevRel team
- **Status**: Agent exists in CLAUDE.md, needs implementation details
- **Blocker**: Transformation pipeline personality and prompt engineering
- **Action**: Define agent persona, communication style, prompt templates in Architecture phase

**D-4: Discord Roles and Permissions (MEDIUM)**
- **Owner**: Discord server administrator
- **Status**: Existing Discord server roles may need refinement
- **Blocker**: Role-based command permissions and document access
- **Action**: Audit Discord roles, map to personas (leadership, product, marketing, devrel)

**D-5: Stakeholder Feedback (MEDIUM)**
- **Owner**: Product team
- **Status**: Need to gather requirements for digest format, command preferences
- **Blocker**: UX decisions for slash commands and digest content
- **Action**: Conduct stakeholder interviews during sprint planning phase

---

## Open Questions

### Critical Questions (Need Answers Before Architecture Phase)

**Q-1: devrel-translator Agent Integration Approach**
- Should devrel-translator agent be invoked via Claude Code `/translate` slash command (external agent)?
- Or should agent logic be embedded directly in Onomancer bot backend (internal implementation)?
- **Decision Owner**: Technical Architect
- **Timeline**: Decide in Architecture phase (Phase 2)

**Q-2: Google Workspace Organization Structure**
- Should we create a new Google Workspace organization or use existing one?
- Who will be the Google Workspace admin?
- What is the billing/pricing model?
- **Decision Owner**: System Administrator
- **Timeline**: Before Phase 2 (Architecture)

**Q-3: Terraform State Management**
- Where should Terraform state be stored (local, Google Cloud Storage, Terraform Cloud)?
- Who will have access to Terraform state?
- **Decision Owner**: DevOps lead
- **Timeline**: Before Phase 3 (Sprint Planning)

### High-Priority Questions (Need Answers During Sprint Planning)

**Q-4: Discord Role Mapping**
- How should Discord roles map to personas (leadership, product, marketing, devrel)?
- Should we create new Discord roles or use existing ones?
- **Decision Owner**: Discord server admin + Product team
- **Timeline**: During Sprint Planning (Phase 3)

**Q-5: Notification Preferences**
- Should notifications be opt-in or opt-out by default?
- Which Discord channel should receive notifications (dedicated bot channel or existing channels)?
- **Decision Owner**: Product team + stakeholders
- **Timeline**: During Sprint Planning (Phase 3)

**Q-6: Document Retention**
- How long should documents be retained in Google Docs?
- Should old documents be archived or deleted?
- **Decision Owner**: Compliance team + product team
- **Timeline**: During Sprint Planning (Phase 3)

### Medium-Priority Questions (Can Be Answered During Implementation)

**Q-7: Weekly Digest Content**
- What should be included in weekly digest (all activity or highlights only)?
- Should digest be customizable per user?
- **Decision Owner**: Product team based on user feedback
- **Timeline**: After MVP launch, iterate based on feedback

**Q-8: Blog Draft Approval Workflow**
- Who approves blog drafts before publishing (marketing lead, DevRel lead, both)?
- How should approval be tracked (Google Docs comments, Linear issue, separate workflow)?
- **Decision Owner**: Marketing team + DevRel team
- **Timeline**: During Sprint 1 (Implementation)

**Q-9: Error Handling UX**
- When transformation fails, should bot retry automatically or ask user to retry manually?
- Should error messages include technical details or be user-friendly only?
- **Decision Owner**: Technical Architect + Product team
- **Timeline**: During Sprint 1 (Implementation)

### Low-Priority Questions (Nice to Know, Not Blocking)

**Q-10: Multi-Language Support**
- Should summaries support multiple languages in the future (Spanish, Japanese, etc.)?
- **Decision Owner**: Product team
- **Timeline**: Phase 2 or later (out of scope for MVP)

**Q-11: Analytics Dashboard**
- Should we build a web dashboard for metrics visualization or use Discord bot commands only?
- **Decision Owner**: Product team
- **Timeline**: Phase 2 or later (out of scope for MVP)

**Q-12: Mobile App**
- Is Discord mobile app sufficient or do stakeholders need a dedicated mobile app?
- **Decision Owner**: Product team based on user feedback
- **Timeline**: Phase 3 or later (out of scope for MVP)

---

## Appendix

### A. Related Documents

- **Hivemind Laboratory Methodology**: https://github.com/0xHoneyJar/agentic-base/blob/main/docs/hivemind/HIVEMIND-LABORATORY-METHODOLOGY.md
- **Integration Architecture**: https://github.com/0xHoneyJar/agentic-base/blob/main/docs/integration-architecture.md
- **Linear Integration PRD Alignment Analysis**: https://github.com/0xHoneyJar/agentic-base/blob/main/docs/LINEAR_INTEGRATION_PRD_ALIGNMENT.md
- **Onomancer Bot README**: https://github.com/0xHoneyJar/agentic-base/blob/main/devrel-integration/README.md
- **Linear Integration Documentation**: https://github.com/0xHoneyJar/agentic-base/blob/main/devrel-integration/docs/LINEAR_INTEGRATION.md
- **Agentic-Base CLAUDE.md**: https://github.com/0xHoneyJar/agentic-base/blob/main/CLAUDE.md
- **Agentic-Base PROCESS.md**: https://github.com/0xHoneyJar/agentic-base/blob/main/PROCESS.md

### B. Personas Reference (from Hivemind)

**Product Managers:**
- **Need**: Documentation and technical articles
- **Format**: Detailed technical articles with user stories, acceptance criteria, implementation details
- **Technical Level**: Medium (understands product and some technical concepts)
- **Length**: 1000-2000 words
- **Focus**: Features, user impact, technical decisions, dependencies

**Marketing:**
- **Need**: Blog drafts and social posts
- **Format**: Engaging blog posts or short social posts, customer-focused language
- **Technical Level**: Low (non-technical, customer-facing)
- **Length**: 500-1000 words (blog), 100-280 characters (social)
- **Focus**: Customer benefits, product announcements, value propositions, use cases

**Leadership (Executives, Board, Investors):**
- **Need**: Executive summaries
- **Format**: 1-2 page summaries, plain language, business-focused
- **Technical Level**: Very low (non-technical, strategic focus)
- **Length**: 500-1000 words
- **Focus**: Achievements, business impact, metrics, risks, next steps, decision points

**DevRel (Developer Relations):**
- **Need**: Technical tutorials and developer materials
- **Format**: Technical tutorials with code examples, API docs, implementation guides
- **Technical Level**: High (developer-facing, code-level)
- **Length**: 1500-3000 words
- **Focus**: Implementation details, code examples, architecture, best practices, gotchas

### C. Document Transformation Examples

**Example 1: Sprint Report Transformation**

**Source Document**: `docs/sprint.md` (Sprint 1 for MiBera)
```markdown
# Sprint 1: User Authentication Implementation

## Tasks Completed
- THJ-123: Implement OAuth 2.0 login flow
- THJ-124: Add JWT token validation middleware
- THJ-125: Create user session management

## Technical Implementation
- Used Passport.js for OAuth integration
- JWT tokens signed with RS256 algorithm
- Redis for session storage (30-day TTL)

## Security Considerations
- All tokens expire after 24 hours
- Refresh token rotation implemented
- Rate limiting on auth endpoints (5 req/min)

## Next Steps
- Phase 2: Add MFA support
- Phase 3: Implement social login (Google, Twitter)
```

**Leadership Summary**: `Leadership-Sprint-1.md`
```markdown
# Sprint 1 Executive Summary: User Authentication

## Key Achievement
Successfully implemented secure user authentication system for MiBera product, enabling users to log in safely and maintain persistent sessions.

## Business Impact
- **User Experience**: Seamless login experience with industry-standard OAuth
- **Security Posture**: Enterprise-grade security with token expiration and rate limiting
- **Compliance**: Meets security audit requirements for user authentication

## Timeline & Delivery
- Sprint completed on schedule (2 weeks)
- All acceptance criteria met
- Security audit passed with zero critical findings

## Risks & Mitigation
- **Risk**: Potential scalability issues with session storage
- **Mitigation**: Using Redis for high-performance session management, can scale horizontally

## Next Steps
- **Phase 2** (2 weeks): Add multi-factor authentication (MFA) for enhanced security
- **Phase 3** (2 weeks): Integrate social login (Google, Twitter) for user convenience

**Decision Required**: None - proceeding to Phase 2 as planned.

---
Source: docs/sprint.md | Generated: 2025-12-10 | Product: MiBera
```

**Marketing Summary**: `Marketing-Sprint-1.md`
```markdown
# 🎉 New Feature: Secure Login for MiBera

## What's New
MiBera now has a secure, easy-to-use login system! Users can sign in safely and stay logged in across sessions, making the experience seamless and secure.

## Key Benefits for Users
- **One-Click Login**: Industry-standard OAuth makes logging in fast and familiar
- **Stay Logged In**: Users don't need to re-enter credentials every time
- **Enterprise Security**: Bank-level security with automatic logout after 24 hours

## Why This Matters
User security is our top priority. This update ensures that MiBera users have a safe, reliable way to access their accounts while maintaining the convenience they expect from modern web apps.

## Coming Soon
- **Multi-Factor Authentication (MFA)**: Extra security layer for enhanced account protection
- **Social Login**: Sign in with Google or Twitter for even faster access

## Customer Testimonial Opportunity
This is a great time to reach out to early users for testimonials about security and ease of use!

---
💡 **Blog Draft Available**: Ready to turn this into a customer-facing announcement? Ask for `/blog-draft sprint-1`

Source: docs/sprint.md | Generated: 2025-12-10 | Product: MiBera
```

### D. Glossary

**Agentic-Base**: AI-driven development framework that orchestrates product lifecycle from requirements to deployment using specialized agents.

**CX Triage**: Linear backlog where all community feedback lands initially (from Discord via Onomancer bot).

**devrel-translator Agent**: Specialized agent that translates technical documents into stakeholder-friendly summaries. Character archetype: DevRel personality.

**Hivemind Laboratory**: Knowledge management methodology that converts ephemeral Discord conversations into permanent organizational intelligence stored in Linear.

**LEARNINGS Library**: Special Linear team for storing permanent organizational knowledge (patterns, decisions, retrospectives).

**Linear**: Project management tool for tracking issues, projects, and initiatives.

**Onomancer Bot**: Discord bot that represents the devrel-translator agent persona. Enables stakeholders to access technical documentation via conversational interface.

**Persona**: Target audience for document transformation (leadership, product managers, marketing, devrel).

**Product Home**: Linear project template tracking product evolution (changelog, retrospectives, health checks).

**Sprint Report**: Technical document generated during Phase 4-5 of agentic-base workflow (`docs/sprint.md`, `docs/a2a/reviewer.md`).

**Terraform**: Infrastructure-as-code tool for managing Google Workspace resources programmatically.

**User Truth Canvas**: Linear issue template defining user jobs, pains, gains, and development boundaries (from Hivemind).

---

### E. Bibliography & References

This section provides absolute URLs to all resources referenced throughout this PRD, organized by category for easy navigation.

#### Stakeholder Feedback Sources (Linear Issues)

**Note:** The following Linear issues informed v1.2 stakeholder requirements (FR-7, FR-8, FR-9). Linear URLs require authentication to access.

- **LAB-507**: Team feedback on build process visibility - https://linear.app/honeyjarlabs/issue/LAB-507
- **LAB-508**: Comprehensive documentation requirements - https://linear.app/honeyjarlabs/issue/LAB-508
- **LAB-509**: Marketing support needs - https://linear.app/honeyjarlabs/issue/LAB-509
- **LAB-512**: Developer workflow improvements - https://linear.app/honeyjarlabs/issue/LAB-512
- **LAB-513**: Continuous build visibility and knowledge base - https://linear.app/honeyjarlabs/issue/LAB-513
- **LAB-515**: Product quality standards - https://linear.app/honeyjarlabs/issue/LAB-515

#### Agent Definitions (GitHub)

These agents implement the Linear integration documented in FR-6.5:

- **sprint-task-implementer**: https://github.com/0xHoneyJar/agentic-base/blob/main/.claude/agents/sprint-task-implementer.md
  - Linear integration: Lines 156-573 (Phase 0.5: Linear Issue Creation and Tracking)
- **devops-crypto-architect**: https://github.com/0xHoneyJar/agentic-base/blob/main/.claude/agents/devops-crypto-architect.md
  - Linear integration: Lines 441-907 (Phase 0.5: Infrastructure Work Tracking)
- **paranoid-auditor**: https://github.com/0xHoneyJar/agentic-base/blob/main/.claude/agents/paranoid-auditor.md
  - Linear integration: Lines 291-737 (Phase 0.5: Security Audit Finding Tracking)
- **prd-architect**: https://github.com/0xHoneyJar/agentic-base/blob/main/.claude/agents/prd-architect.md
- **architecture-designer**: https://github.com/0xHoneyJar/agentic-base/blob/main/.claude/agents/architecture-designer.md
- **sprint-planner**: https://github.com/0xHoneyJar/agentic-base/blob/main/.claude/agents/sprint-planner.md
- **senior-tech-lead-reviewer**: https://github.com/0xHoneyJar/agentic-base/blob/main/.claude/agents/senior-tech-lead-reviewer.md
- **context-engineering-expert**: https://github.com/0xHoneyJar/agentic-base/blob/main/.claude/agents/context-engineering-expert.md

#### Implementation Files (GitHub)

Code implementations referenced in FR-6.5:

- **feedbackCapture.ts** (Discord 📌 reaction → Linear draft issues): https://github.com/0xHoneyJar/agentic-base/blob/main/devrel-integration/src/handlers/feedbackCapture.ts
- **commands.ts** (Linear Discord commands): https://github.com/0xHoneyJar/agentic-base/blob/main/devrel-integration/src/handlers/commands.ts
  - `/show-issue`, `/list-issues`, `/tag-issue` handlers: Lines 447-691
- **linearService.ts** (Linear API wrapper): https://github.com/0xHoneyJar/agentic-base/blob/main/devrel-integration/src/services/linearService.ts
- **bot.ts** (Discord bot entry point): https://github.com/0xHoneyJar/agentic-base/blob/main/devrel-integration/src/bot.ts

#### Scripts (GitHub)

- **setup-linear-labels.ts** (Label taxonomy setup, FR-6.5.1): https://github.com/0xHoneyJar/agentic-base/blob/main/devrel-integration/scripts/setup-linear-labels.ts

#### Documentation (GitHub)

- **LINEAR_INTEGRATION.md** (500+ line comprehensive guide): https://github.com/0xHoneyJar/agentic-base/blob/main/devrel-integration/docs/LINEAR_INTEGRATION.md
- **LINEAR_INTEGRATION_PRD_ALIGNMENT.md** (Gap analysis that identified FR-6.5): https://github.com/0xHoneyJar/agentic-base/blob/main/docs/LINEAR_INTEGRATION_PRD_ALIGNMENT.md
- **Integration Architecture**: https://github.com/0xHoneyJar/agentic-base/blob/main/docs/integration-architecture.md
- **Onomancer Bot README**: https://github.com/0xHoneyJar/agentic-base/blob/main/devrel-integration/README.md
- **Hivemind Laboratory Methodology**: https://github.com/0xHoneyJar/agentic-base/blob/main/docs/hivemind/HIVEMIND-LABORATORY-METHODOLOGY.md
- **CLAUDE.md** (Project overview for Claude Code): https://github.com/0xHoneyJar/agentic-base/blob/main/CLAUDE.md
- **PROCESS.md** (Workflow documentation): https://github.com/0xHoneyJar/agentic-base/blob/main/PROCESS.md

#### Configuration Files (GitHub)

- **discord-digest.yml**: https://github.com/0xHoneyJar/agentic-base/blob/main/devrel-integration/config/discord-digest.yml
- **linear-sync.yml**: https://github.com/0xHoneyJar/agentic-base/blob/main/devrel-integration/config/linear-sync.yml
- **review-workflow.yml**: https://github.com/0xHoneyJar/agentic-base/blob/main/devrel-integration/config/review-workflow.yml
- **bot-commands.yml**: https://github.com/0xHoneyJar/agentic-base/blob/main/devrel-integration/config/bot-commands.yml
- **.claude/settings.local.json** (MCP server configuration): https://github.com/0xHoneyJar/agentic-base/blob/main/.claude/settings.local.json

#### External Resources

- **Linear API Documentation**: https://developers.linear.app/docs
- **Linear SDK (@linear/sdk)**: https://www.npmjs.com/package/@linear/sdk
- **Discord.js Documentation**: https://discord.js.org/docs
- **Google Workspace Admin API**: https://developers.google.com/admin-sdk
- **Google Docs API**: https://developers.google.com/docs/api
- **Terraform Documentation**: https://developer.hashicorp.com/terraform/docs
- **GitHub REST API**: https://docs.github.com/en/rest
- **MCP (Model Context Protocol)**: https://modelcontextprotocol.io/introduction

#### Organizational Meta Knowledge Base (THJ)

**Repository**: https://github.com/0xHoneyJar/thj-meta-knowledge (Private - requires authentication)
**Local Path**: `/home/merlin/Documents/thj/code/thj-meta-knowledge/`

Central documentation hub for The Honey Jar ecosystem. Single source of truth for architecture, contracts, services, infrastructure, and organizational knowledge. Designed for both human and AI consumption.

**Core Documentation**:
- **Repository Overview & Navigation**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/README.md
- **Ecosystem Architecture**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/ecosystem/OVERVIEW.md
- **Data Flow Patterns**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/ecosystem/DATA_FLOW.md
- **Terminology Glossary**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/TERMINOLOGY.md
- **Links Registry** (all product URLs): https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/LINKS.md
- **Contract Registry** (smart contract addresses): https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/contracts/REGISTRY.md
- **AI Navigation Guide**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/.meta/RETRIEVAL_GUIDE.md

**Architecture Decision Records (ADRs)**:
- **ADR Index**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/decisions/INDEX.md
- **ADR Template**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/decisions/TEMPLATE.md
- **ADR-001**: Envio Indexer Consolidation - https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/decisions/ADR-001-envio-indexer-consolidation.md
- **ADR-002**: Supabase Database Platform - https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/decisions/ADR-002-database-platform-supabase-over-convex.md
- **ADR-003**: Dynamic Authentication Provider - https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/decisions/ADR-003-authentication-provider-dynamic-over-alternatives.md
- **ADR-004**: Internal-First CubQuests Strategy - https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/decisions/ADR-004-internal-first-cubquests.md
- **ADR-005**: Resource System as Core Mechanic - https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/decisions/ADR-005-resource-system-core-mechanic.md

**Products** (8 documented products):
- **CubQuests** (Quest platform): https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/products/cubquests/README.md
- **Mibera** (NFT marketplace): https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/products/mibera/README.md
- **Henlo** (Memecoin arcade): https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/products/henlo/README.md
- **Set & Forgetti** (DeFi vaults): https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/products/set-and-forgetti/README.md
- **fatBERA** (Liquid staking): https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/products/fatbera/README.md
- **apDAO** (Governance): https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/products/apdao/README.md
- **InterPoL** (LP locker): https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/products/interpol/README.md
- **BeraFlip**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/products/beraflip/README.md

**Knowledge Captures** (tacit knowledge from developer interviews):
- **Soju's Captures** (primary domain expert):
  - CubQuests: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/knowledge/soju/cubquests.md
  - Mibera: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/knowledge/soju/mibera.md
  - Henlo: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/knowledge/soju/henlo.md
  - Discord Bots: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/knowledge/soju/discord-bots.md
- **Zergucci's Captures** (smart contracts):
  - Set & Forgetti Contracts: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/knowledge/ZERGUCCI/sf-contracts.md
  - fatBERA Contracts: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/knowledge/ZERGUCCI/fatbera-contracts.md
- **Merlin's Captures**:
  - Agentic Base: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/knowledge/merlin/agentic-base.md
  - Score Words: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/knowledge/merlin/score-words.md

**Operational Documentation**:
- **Technical Debt Registry**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/debt/INDEX.md
- **Services Inventory**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/services/INVENTORY.md
- **Infrastructure Documentation**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/infrastructure/
- **Environment Variables**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/infrastructure/ENV_VARS.md
- **Deployments**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/infrastructure/DEPLOYMENTS.md
- **FAQ & Troubleshooting**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/operations/FAQ.md

**Interview Prompts** (for knowledge capture):
- **Knowledge Capture Prompt**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/prompts/KNOWLEDGE_CAPTURE.md
- **ADR Capture Prompt**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/prompts/ADR_CAPTURE.md
- **Service Deep Dive Prompt**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/prompts/SERVICE_DEEP_DIVE.md
- **Runbook Capture Prompt**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/prompts/RUNBOOK_CAPTURE.md
- **Audit Capture Prompt**: https://github.com/0xHoneyJar/thj-meta-knowledge/blob/main/prompts/AUDIT_CAPTURE.md

**Note**: This is a living documentation repository, continuously updated through developer interviews and audits. All documents include YAML frontmatter with metadata for AI-friendly navigation. See `.meta/RETRIEVAL_GUIDE.md` for navigation strategies.

#### Discord Server

**The Honey Jar Discord** (referenced for community feedback capture):
- Server ID: Configured in `DISCORD_GUILD_ID` environment variable
- Feedback capture channels: Various project-specific channels (e.g., #mibera-feedback)
- Bot integration: Onomancer Bot with 📌 emoji reaction capture

#### Package Dependencies

Key npm packages used in implementation:

- **@linear/sdk** (v21.0.0+): https://www.npmjs.com/package/@linear/sdk
- **discord.js** (v14+): https://www.npmjs.com/package/discord.js
- **express** (latest): https://www.npmjs.com/package/express
- **googleapis**: https://www.npmjs.com/package/googleapis
- **winston** (logging): https://www.npmjs.com/package/winston
- **node-cron** (scheduling): https://www.npmjs.com/package/node-cron
- **ioredis** (Redis client): https://www.npmjs.com/package/ioredis
- **helmet** (security headers): https://www.npmjs.com/package/helmet

#### Repository Information

- **GitHub Repository**: https://github.com/0xHoneyJar/agentic-base
- **Branch for Linear Integration**: `trrfrm-ggl`
- **Main Branch**: `main`
- **License**: Same as parent agentic-base project
- **Contributors**: The Honey Jar team + Claude (AI assistant)

#### Change History

PRD version history with commit references:

- **v1.0** (2025-12-10): Initial PRD - Commit hash: TBD
- **v1.1** (2025-12-10): Document accessibility updates - Commit hash: TBD
- **v1.2** (2025-12-11): Stakeholder feedback integration - Commit hash: TBD
- **v1.3** (2025-12-11): FR-6.5 alignment fix - Commit: `4c83f27`
  - Commit URL: https://github.com/0xHoneyJar/agentic-base/commit/4c83f27

#### Related PRDs and Design Documents

- **Software Design Document (SDD)**: `docs/sdd.md` (to be generated in Phase 2)
- **Sprint Plan**: `docs/sprint.md` (to be generated in Phase 3)
- **Implementation Reports**: `docs/a2a/reviewer.md` (Phase 4)
- **Review Feedback**: `docs/a2a/engineer-feedback.md` (Phase 5)
- **Deployment Documentation**: `docs/deployment/` (Phase 6)

---

## Approval

**PRD Status**: ✅ **APPROVED v1.3 - Ready for Architecture Phase (v1.3 alignment update complete)**

**Approvers**:
- Product Manager: PRD Architect Agent (2025-12-10 - v1.0, updated to v1.1 same day, updated to v1.2 on 2025-12-11, updated to v1.3 on 2025-12-11)
- Technical Lead: TBD (will review in Architecture phase)
- Stakeholders: TBD (will review after Architecture phase)

**v1.1 Updates Approved:**
- ✅ Project name required in `/translate` command
- ✅ ALL agentic-base documents accessible (PRD, SDD, sprint.md, A2A docs)
- ✅ Document shorthand support (@prd, @sdd, @sprint, @reviewer, @audit)
- ✅ Automated triggers for PRD/SDD/sprint plan generation (FR-3.5, FR-3.6, FR-3.7)
- ✅ Expanded Google Docs folder structure to include PRD/SDD folders
- ✅ Added FR-4.9 for complete workflow document access

**v1.2 Updates Approved:**
- ✅ **Stakeholder feedback integrated** from 7 Linear issues (LAB-507 through LAB-515)
- ✅ **Build status & process reporting** (FR-7.x): Real-time Linear integration, proactive notifications, build dashboards, webhooks, Gantt charts
- ✅ **Comprehensive knowledge base** (FR-8.x): Product specs, decision logs, change history, Discord archive, pre-work clarifications, asset specs
- ✅ **Marketing & communications support** (FR-9.x): Custom data extraction, technical validation, RACI generation
- ✅ **New Discord commands**: `/show-issue`, `/list-issues`, `/tag-issue`, `/build-status`, `/sprint-timeline`, `/extract-data`, `/validate-content`, `/generate-raci`, `/decision-search`, `/discussion-search`, `/clarify`, `/asset-spec`
- ✅ **Enhanced notification system**: Configurable per-user preferences, proactive agent activity alerts

**v1.3 Updates (Alignment Fix):**
- ✅ **Added FR-6.5: Agent Linear Integration for Audit Trail** - Documents already-implemented feature from Phases 1-5
- ✅ **Critical dependency documented**: FR-7 (stakeholder visibility) depends on FR-6.5 (agents creating Linear issues)
- ✅ **Implementation status verified**: All agent integrations (sprint-task-implementer, devops-crypto-architect, paranoid-auditor) fully functional
- ✅ **Gap closed**: PRD now accurately reflects implemented Linear integration capabilities
- ✅ **Stakeholder access confirmed**: Discord commands (`/show-issue`, `/list-issues`, `/tag-issue`) work because agents create issues

**Key Value Adds in v1.3:**
1. **Closes critical documentation gap**: FR-7 requires FR-6.5 but dependency was implicit, now explicit
2. **Verifies implementation completeness**: All Phase 1-5 agent integrations documented and validated
3. **Enables informed architecture**: Architect can design FR-7 (webhooks, notifications) knowing FR-6.5 foundation exists
4. **Stakeholder clarity**: PRD now shows what's implemented ✅ vs. what's planned 🆕

**Implementation Status Summary:**
- ✅ **FR-6.5 (Agent Linear Integration)**: FULLY IMPLEMENTED (Phases 1-5, documented in v1.3)
- ✅ **FR-7.1 (Linear Discord Commands)**: FULLY IMPLEMENTED (`/show-issue`, `/list-issues`, `/tag-issue`)
- ⏳ **FR-7.2 (Proactive Notifications)**: PARTIAL - Agents create issues but webhooks not implemented
- ⏳ **FR-7.3 (Build Dashboard)**: NOT IMPLEMENTED - `/build-status` command planned but not built
- ⏳ **FR-7.4 (Linear Webhooks)**: NOT IMPLEMENTED - Webhook endpoint needed for proactive notifications
- ⏳ **FR-7.5 (Gantt Timeline)**: NOT IMPLEMENTED - `/sprint-timeline` command planned but not built

**Next Steps**:
1. ✅ PRD v1.3 complete and saved to `docs/prd.md`
2. ✅ Alignment analysis complete (`docs/LINEAR_INTEGRATION_PRD_ALIGNMENT.md`)
3. ⏭️ Proceed to Phase 2: Architecture (`/architect`) - architect will review v1.3 requirements
4. ⏭️ Software architect designs system architecture for remaining FR-7 features (webhooks, dashboards, timelines)
5. ⏭️ Generate Software Design Document (SDD) at `docs/sdd.md`

**Estimated Timeline (Updated for v1.3):**
- **Phase 2 (Architecture)**: 2-3 days
- **Phase 3 (Sprint Planning)**: 1-2 days
- **Phase 4-6 (Implementation + Review + Deployment)**: 2-4 weeks (reduced scope - FR-6.5 already done, focus on FR-7.2-7.5, FR-8, FR-9)

---

*Generated by: PRD Architect Agent (agentic-base)*
*Date: 2025-12-10 (v1.0), Updated: 2025-12-10 (v1.1), Updated: 2025-12-11 (v1.2, v1.3)*
*Version: 1.3*
