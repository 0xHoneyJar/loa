# Linear Integration PRD Alignment Analysis

**Purpose:** Verify that PRD v1.2 properly reflects the Linear audit trail integration already implemented in Phases 1-5, and ensure stakeholders have full visibility into agent work via Discord.

**Date:** 2025-12-11
**Status:** Gap Analysis Complete - PRD Updates Needed

---

## Executive Summary

**FINDING:** The PRD v1.2 includes requirements for stakeholder visibility (FR-7) but **does not explicitly document the agent Linear integration** that makes this visibility possible. This creates a disconnect where FR-7 depends on agent behavior that isn't formally specified in the PRD.

**IMPACT:**
- Stakeholders reading the PRD won't understand that agents automatically create Linear issues
- Future architects/implementers may miss the critical dependency
- The "how" of build visibility (agents create issues) is not documented, only the "what" (stakeholders see issues)

**RECOMMENDATION:** Add new **FR-6.5: Agent Linear Integration** that explicitly documents the agent audit trail system, then update FR-7 to reference this as a dependency.

---

## What We've Built (Phases 1-5)

### Phase 1: Linear Label Setup
**Status:** ✅ Implemented
**Files:**
- `devrel-integration/scripts/setup-linear-labels.ts`
- `devrel-integration/scripts/README.md`

**Features:**
- 18 base labels across 4 categories:
  - Agent labels: `agent:implementer`, `agent:devops`, `agent:auditor`
  - Type labels: `type:feature`, `type:bugfix`, `type:infrastructure`, `type:security`, `type:audit-finding`, `type:refactor`, `type:docs`
  - Source labels: `source:discord`, `source:github`, `source:internal`
  - Priority labels: `priority:critical`, `priority:high`, `priority:normal`, `priority:low`
- Script creates labels if they don't exist
- Comprehensive documentation in scripts/README.md

**PRD Coverage:** ❌ Not mentioned in PRD

---

### Phase 2: sprint-task-implementer Linear Integration
**Status:** ✅ Implemented
**Files:**
- `.claude/agents/sprint-task-implementer.md` (lines 156-573)

**Features:**
- **Phase 0.5** section: Linear Issue Creation and Tracking
- Creates parent Linear issue for each sprint task
- Creates sub-issues for major components (>3 files, complex logic, external integrations)
- Automatic status transitions:
  - Creates issue → Status: Todo
  - Starts work → Status: In Progress
  - Completes component → Sub-issue: Done
  - Completes all work → Parent: In Review
  - Senior lead approves → Parent: Done
- Labels: `agent:implementer`, `type:feature`, `sprint:sprint-N`, `source:discord` (if applicable)
- Links to Discord source discussion if feedback-driven
- Adds Linear tracking section to implementation reports (`docs/a2a/reviewer.md`)

**PRD Coverage:** ❌ Not mentioned in PRD

---

### Phase 3: devops-crypto-architect Linear Integration
**Status:** ✅ Implemented
**Files:**
- `.claude/agents/devops-crypto-architect.md` (lines 441-907)

**Features:**
- **Phase 0.5** section: Linear Issue Creation for Infrastructure Work
- Dual mode support:
  - **Integration Mode:** Creates issues for Discord bots, webhooks, sync scripts
  - **Deployment Mode:** Creates issues for infrastructure components (compute, database, networking, monitoring, security, CI/CD)
- Parent issue + component sub-issues
- Labels: `agent:devops`, `type:infrastructure`, `sprint:sprint-N`
- Deployment report integration with Linear issue references

**PRD Coverage:** ❌ Not mentioned in PRD

---

### Phase 4: paranoid-auditor Linear Integration
**Status:** ✅ Implemented
**Files:**
- `.claude/agents/paranoid-auditor.md` (lines 291-737)

**Features:**
- **Severity-based issue hierarchy:**
  - **CRITICAL/HIGH:** Standalone parent issues with priority:critical/high labels
  - **MEDIUM:** Grouped by category with sub-issues
  - **LOW:** Comments on related implementation issues
- Labels: `agent:auditor`, `type:security`, `type:audit-finding`, `priority:{severity}`
- Bidirectional linking: Audit findings linked to implementation issues
- Remediation tracking: Updates issues when fixes verified
- Comprehensive descriptions with:
  - OWASP/CWE references
  - Proof of Concept code
  - Exact remediation steps
  - Component file:line references

**PRD Coverage:** ❌ Not mentioned in PRD

---

### Phase 5: Discord Bot Linear Commands
**Status:** ✅ Implemented
**Files:**
- `devrel-integration/src/handlers/commands.ts` (lines 447-691)
- `devrel-integration/src/handlers/feedbackCapture.ts` (enhanced)
- `devrel-integration/src/bot.ts` (reaction handlers)

**Features:**
- **Three new Discord commands:**
  1. `/tag-issue <issue-id> <project-name> [priority]` - Tag issues with project labels
  2. `/show-issue <issue-id>` - Display issue details with formatted output
  3. `/list-issues [filter]` - List issues grouped by status

- **Enhanced feedback capture:**
  - Auto-detect project from channel name (`#project-{name}`, `#{name}-feedback`, `#{name}-dev`)
  - Automatically add labels: `source:discord`, `project:{name}`
  - Add priority emoji reactions (🔴🟠🟡🟢) to confirmation message
  - Handle priority reactions to update Linear issue priority

- **Bot features:**
  - Permission-gated (requires developer/admin role)
  - Input validation and error handling
  - Rate limiting
  - Audit logging

**PRD Coverage:** ✅ **PARTIAL** - FR-7.1 mentions the three commands but doesn't explain:
- How feedback capture creates Linear issues
- How priority emoji reactions work
- Auto project detection from channel names

---

## What the PRD Currently Says

### FR-7: Build Status & Process Reporting (CRITICAL - v1.2)

**FR-7.1: Real-Time Linear Integration Dashboard**
```
- Embed Linear issue tracking into Discord via commands
- Show in-progress tasks with real-time status updates
- Display task assignments, priorities, and blockers
- Commands:
  - `/show-issue <issue-id>` - Display issue details
  - `/list-issues [filter]` - List issues grouped by status
  - `/tag-issue <issue-id> <project> [priority]` - Tag issues with project labels
```
✅ **Matches implementation** - These three commands exist

**FR-7.2: Proactive Build Notifications**
```
- Notify stakeholders when agents START work (not just when they finish)
- Notification format: "🔨 Sprint-task-implementer started working on Issue THJ-123"
- Notification triggers:
  - Agent creates Linear parent issue → "📋 New task created"
  - Agent updates issue to "In Progress" → "🔨 Work started"
  - Agent completes component → "✅ Component completed"
  - Agent updates to "In Review" → "👁️ Ready for review"
  - Agent completes work → "🎉 Completed"
```
⚠️ **PARTIAL** - Agents create issues and update status, but webhook notifications NOT implemented

**FR-7.3: Build Progress Dashboard**
```
- Command: `/build-status [project|sprint]`
- Shows: progress %, tasks in progress, completed, blocked, timeline
```
❌ **NOT IMPLEMENTED** - This command doesn't exist yet

**FR-7.4: Linear Webhook Integration**
```
- Listen to Linear webhooks for issue updates
- Trigger notifications in Discord when issues change
- Webhook endpoint: `/webhooks/linear`
```
❌ **NOT IMPLEMENTED** - Webhook endpoint doesn't exist yet

**FR-7.5: Sprint Timeline Visualization**
```
- Command: `/sprint-timeline [sprint-id]`
- Generate Gantt chart with dependencies, critical path
```
❌ **NOT IMPLEMENTED** - This command doesn't exist yet

---

## Critical Gap: Agent Integration Not Documented

**Problem:** FR-7 (stakeholder visibility) depends on agents creating Linear issues, but the PRD never explicitly requires agents to do this.

**Current PRD flow:**
1. FR-7.1 says "Discord commands show Linear issues" ✅
2. FR-7.2 says "Notify when agents start/complete work" ⚠️
3. **MISSING:** "Agents MUST create Linear issues for all work"

**What's missing:**
- No requirement that agents create Linear issues
- No specification of label taxonomy
- No specification of parent/child issue hierarchy
- No specification of status transition workflow
- No specification of feedback loop integration

**Impact:**
- Someone reading the PRD would not know agents create issues automatically
- Architect might design a different solution (manual issue creation, separate tracking system)
- The "how" of visibility (agent-created issues) is undocumented

---

## Alignment Checklist

### ✅ Implemented AND in PRD
- [x] `/show-issue` command (FR-7.1)
- [x] `/list-issues` command (FR-7.1)
- [x] `/tag-issue` command (FR-7.1)

### ⚠️ Partially Implemented (gaps exist)
- [x] Agent creates Linear issues (IMPLEMENTED but NOT in PRD)
- [x] Agent updates issue status (IMPLEMENTED but NOT in PRD)
- [ ] Proactive Discord notifications (agents create issues but webhooks NOT implemented)
- [x] Priority emoji reactions (IMPLEMENTED but NOT in PRD)
- [x] Project auto-detection from channel names (IMPLEMENTED but NOT in PRD)

### ❌ In PRD but NOT Implemented
- [ ] `/build-status` command (FR-7.3)
- [ ] Linear webhook endpoint `/webhooks/linear` (FR-7.4)
- [ ] Webhook-triggered Discord notifications (FR-7.4)
- [ ] `/sprint-timeline` command (FR-7.5)
- [ ] Gantt chart generation (FR-7.5)

---

## Proposed PRD Updates

### Update 1: Add FR-6.5 - Agent Linear Integration

**Location:** After FR-6.4 (Manual review queue), before FR-7

**Content:**

```markdown
### 6.5. Agent Linear Integration for Audit Trail (CRITICAL - v1.2)

**User Story:** As a stakeholder, I need all agent work automatically tracked in Linear with complete audit trails so that I can see what's being built, by whom, and why without asking developers.

**Context:** This requirement enables FR-7 (Build Status Reporting). All code-touching agents MUST create Linear issues to provide visibility into their work.

**Requirements:**

- **FR-6.5.1**: **Linear Label Taxonomy**
  - Implement base label system with 18 labels across 4 categories:
    - **Agent labels** (who): `agent:implementer`, `agent:devops`, `agent:auditor`
    - **Type labels** (what): `type:feature`, `type:bugfix`, `type:infrastructure`, `type:security`, `type:audit-finding`, `type:refactor`, `type:docs`
    - **Source labels** (where): `source:discord`, `source:github`, `source:internal`
    - **Priority labels** (urgency): `priority:critical`, `priority:high`, `priority:normal`, `priority:low`
  - Dynamic labels created as needed: `sprint:sprint-N`, `project:{name}`
  - Setup script: `scripts/setup-linear-labels.ts`
  - Documentation: `scripts/README.md`

- **FR-6.5.2**: **sprint-task-implementer Linear Integration**
  - Create parent Linear issue for each sprint task (from `docs/sprint.md`)
  - Create sub-issues for major components (>3 files, complex logic, external integrations)
  - Automatic status transitions:
    - Task starts → Create issue with Status: Todo
    - Work begins → Update to Status: In Progress
    - Component completes → Update sub-issue to Status: Done
    - All work completes → Update parent to Status: In Review
    - Senior lead approval → Update parent to Status: Done
  - Required labels: `agent:implementer`, `type:{type}`, `sprint:{sprint-name}`
  - Optional labels: `source:discord` (if feedback-driven), `project:{name}` (if tagged)
  - Link to Discord source discussion if applicable
  - Add Linear tracking section to `docs/a2a/reviewer.md` with issue IDs and status

- **FR-6.5.3**: **devops-crypto-architect Linear Integration**
  - Create parent Linear issue for infrastructure/deployment work
  - Support dual modes:
    - **Integration Mode** (Phase 0.5): Issues for Discord bots, webhooks, sync scripts
    - **Deployment Mode** (Phase 6): Issues for infrastructure (compute, database, networking, monitoring, security, CI/CD)
  - Create sub-issues for each infrastructure component
  - Required labels: `agent:devops`, `type:infrastructure`, `sprint:{sprint-name}`
  - Add Linear references to deployment reports

- **FR-6.5.4**: **paranoid-auditor Linear Integration**
  - Create Linear issues for security audit findings based on severity:
    - **CRITICAL/HIGH:** Standalone parent issues with `priority:critical` or `priority:high`
    - **MEDIUM:** Grouped by category (e.g., "MEDIUM Security Findings - Input Validation") with sub-issues per finding
    - **LOW:** Comments on related implementation issues (no standalone issues)
  - Required labels: `agent:auditor`, `type:security`, `type:audit-finding`, `priority:{severity}`
  - Bidirectional linking: Link audit findings to implementation issues
  - Comprehensive descriptions with OWASP/CWE references, Proof of Concept, remediation steps
  - Remediation tracking: Update issues when fixes verified

- **FR-6.5.5**: **Discord Feedback Capture Integration**
  - When Discord feedback captured (📌 reaction), create Linear issue
  - Auto-detect project from channel name patterns:
    - `#project-{name}` → `project:{name}`
    - `#{name}-feedback` → `project:{name}`
    - `#{name}-dev` → `project:{name}`
  - Required labels: `source:discord`, `project:{name}` (if detected)
  - Add priority emoji reactions (🔴🟠🟡🟢) to confirmation message
  - Handle priority reactions to update Linear issue priority
  - Include Discord message link and context in issue description

**Acceptance Criteria:**
- [ ] Label setup script creates 18 base labels successfully
- [ ] sprint-task-implementer creates parent + sub-issues for all sprint tasks
- [ ] devops-crypto-architect creates issues for all infrastructure work
- [ ] paranoid-auditor creates severity-based issues for all audit findings
- [ ] Discord feedback capture creates Linear issues with auto project detection
- [ ] All agents apply correct labels (agent, type, sprint, source, priority)
- [ ] Status transitions work correctly (Todo → In Progress → In Review → Done)
- [ ] Bidirectional linking between audit findings and implementation works
- [ ] Priority emoji reactions update Linear issue priority

**Priority:** CRITICAL (foundation for FR-7 build visibility)
```

### Update 2: Clarify FR-7 Dependencies

**Update FR-7 introduction:**

```markdown
### 7. Build Status & Process Reporting (CRITICAL - v1.2)

**User Story:** As a stakeholder, I need real-time visibility into what's being built while it's being built so that I can prepare marketing materials, provide feedback early, and stay aligned with the team without constantly asking developers for updates.

**Context:** Stakeholder feedback (LAB-513, LAB-508) revealed that current visibility is limited to milestone completions. Teams need **continuous updates during the build process**, not just notifications when sprints complete.

**Dependencies:**
- **Requires FR-6.5** (Agent Linear Integration) - This feature depends on agents automatically creating Linear issues. Without FR-6.5, there would be no issues for stakeholders to query.
- Leverages existing Linear MCP integration for API access
- Uses Discord bot commands for user interface
```

### Update 3: Mark Implemented vs Future Features

**Update FR-7.1:**
```markdown
- **FR-7.1**: **Real-Time Linear Integration Dashboard** ✅ **IMPLEMENTED (Phase 5)**
  - Embed Linear issue tracking into Discord via commands
  - Show in-progress tasks with real-time status updates
  - Display task assignments, priorities, and blockers
  - Commands:
    - `/show-issue <issue-id>` ✅ - Display issue details with status, assignee, labels, description
    - `/list-issues [filter]` ✅ - List issues grouped by status (Todo, In Progress, In Review, Done)
    - `/tag-issue <issue-id> <project> [priority]` ✅ - Human team members can tag issues with project labels
  - **Implementation:** `devrel-integration/src/handlers/commands.ts`
  - **Documentation:** `devrel-integration/docs/LINEAR_INTEGRATION.md`
```

**Update FR-7.2:**
```markdown
- **FR-7.2**: **Proactive Build Notifications** ⚠️ **PARTIAL** (agents create issues, webhooks pending)
  - Notify stakeholders when agents **START** work (not just when they finish)
  - **Currently:** Agents create Linear issues when starting work (FR-6.5) ✅
  - **Pending:** Webhook integration to trigger Discord notifications ❌
  - Notification format: "🔨 Sprint-task-implementer started working on Issue THJ-123: Implement user authentication"
  - Notification triggers:
    - Agent creates Linear parent issue → "📋 New task created: [Issue Title]"
    - Agent updates issue to "In Progress" → "🔨 Work started on: [Issue Title]"
    - Agent completes component (sub-issue) → "✅ Component completed: [Component Name]"
    - Agent updates issue to "In Review" → "👁️ Ready for review: [Issue Title]"
    - Agent completes work (issue Done) → "🎉 Completed: [Issue Title]"
  - Configurable per-user notification preferences (via `/my-notifications`)
```

**Mark remaining FR-7 items as future:**
```markdown
- **FR-7.3**: **Build Progress Dashboard** ❌ **FUTURE** (not yet implemented)
  ...

- **FR-7.4**: **Linear Webhook Integration** ❌ **FUTURE** (required for FR-7.2 notifications)
  ...

- **FR-7.5**: **Sprint Timeline Visualization** ❌ **FUTURE** (not yet implemented)
  ...
```

---

## Stakeholder Discord Access Verification

### Current Stakeholder Capabilities

**What stakeholders CAN do right now:**

1. **View Linear Issues from Discord** ✅
   - `/show-issue THJ-123` - See full issue details with status, assignee, labels, description
   - `/list-issues` - See all issues grouped by status
   - `/list-issues agent:implementer` - Filter issues by agent
   - `/list-issues project:onomancer-bot` - Filter issues by project

2. **Tag Issues with Project Labels** ✅
   - `/tag-issue THJ-123 onomancer-bot high` - Tag issue with project and priority

3. **Capture Feedback as Linear Issues** ✅
   - React with 📌 on Discord message → Creates Linear issue
   - Auto project detection from channel names
   - Set priority with emoji reactions (🔴🟠🟡🟢)

4. **Track Agent Work in Real-Time** ✅
   - All agent work automatically creates Linear issues (via FR-6.5 if added to PRD)
   - Can query agent work: `/list-issues agent:implementer`
   - Can see implementation progress in Linear

**What stakeholders CANNOT do yet:**

1. **Receive Proactive Notifications** ❌
   - No Discord notifications when agents start/complete work
   - Must manually query `/list-issues` to see updates
   - **Requires:** Linear webhook integration (FR-7.4)

2. **View Build Progress Dashboard** ❌
   - No `/build-status` command
   - Can't see aggregate progress metrics (% complete, velocity)
   - **Requires:** Implementation of FR-7.3

3. **View Sprint Timeline/Gantt Chart** ❌
   - No `/sprint-timeline` command
   - Can't visualize dependencies and critical path
   - **Requires:** Implementation of FR-7.5

### Access Verification Checklist

**Discord Bot Commands:**
- [x] `/show-issue` - Command exists and functional
- [x] `/list-issues` - Command exists and functional
- [x] `/tag-issue` - Command exists and functional
- [ ] `/build-status` - Command does NOT exist yet
- [ ] `/sprint-timeline` - Command does NOT exist yet

**Linear Integration:**
- [x] Agents create Linear issues automatically (FR-6.5 if added)
- [x] Issues have correct labels (agent, type, sprint, source, priority)
- [x] Issues show correct status (Todo, In Progress, In Review, Done)
- [x] Feedback capture creates issues with project labels
- [x] Priority emoji reactions update issue priority
- [ ] Webhook notifications sent to Discord (NOT implemented)

**Permissions:**
- [x] `developer` role can use `/show-issue`, `/list-issues`, `/tag-issue`
- [x] `admin` role can use all commands
- [x] Permission checks enforced in code
- [x] Rate limiting active to prevent abuse

**Documentation:**
- [x] LINEAR_INTEGRATION.md created (500+ lines)
- [x] README.md updated with Linear Integration section
- [x] scripts/README.md documents label setup
- [ ] PRD documents agent integration (MISSING - need FR-6.5)

---

## Recommended Actions

### Immediate (PRD v1.3)

1. **Add FR-6.5: Agent Linear Integration** ✅ Priority: CRITICAL
   - Documents the agent audit trail system we've already built
   - Makes explicit that all code-touching agents create Linear issues
   - Specifies label taxonomy, issue hierarchy, status workflow
   - Foundation for FR-7 build visibility

2. **Update FR-7 to reference FR-6.5 dependency** ✅ Priority: HIGH
   - Clarify that FR-7 leverages agent-created issues from FR-6.5
   - Mark FR-7.1 as implemented ✅
   - Mark FR-7.2 as partial (agents create issues ✅, webhooks pending ❌)
   - Mark FR-7.3, FR-7.4, FR-7.5 as future work

3. **Update Scope & Prioritization section** ✅ Priority: HIGH
   - Move FR-6.5 and FR-7.1 to "IMPLEMENTED" section
   - Clarify which FR-7 sub-requirements are implemented vs future

### Short-Term (Next Sprint)

4. **Implement Linear webhook integration** (FR-7.4) ⚠️ Priority: HIGH
   - Add `/webhooks/linear` endpoint
   - Verify webhook signature
   - Trigger Discord notifications on issue updates
   - Completes FR-7.2 (proactive notifications)

5. **Implement `/build-status` command** (FR-7.3) ⚠️ Priority: MEDIUM
   - Query Linear API for sprint/project issues
   - Calculate progress metrics (% complete, velocity)
   - Display formatted dashboard in Discord

### Future (Phase 2)

6. **Implement `/sprint-timeline` command** (FR-7.5) 💡 Priority: LOW
   - Parse issue dependencies from descriptions
   - Generate Gantt chart visualization
   - Export as PNG or Google Doc

---

## Summary

**Current State:**
- ✅ **Implemented:** Agent Linear integration (Phases 1-5) providing complete audit trail
- ✅ **Implemented:** Three Discord commands for stakeholder access to Linear
- ⚠️ **Partially Implemented:** Proactive notifications (agents create issues, webhooks pending)
- ❌ **Not Implemented:** Build dashboard, sprint timeline, webhook notifications

**PRD Coverage:**
- ❌ **Critical Gap:** Agent Linear integration (FR-6.5) not documented in PRD
- ✅ **Covered:** Discord commands (FR-7.1)
- ⚠️ **Unclear:** FR-7 doesn't specify it depends on agents creating issues

**Stakeholder Access:**
- ✅ **Can:** View issues, tag issues, capture feedback from Discord
- ✅ **Can:** Track agent work in real-time (via manual queries)
- ❌ **Cannot:** Receive automatic notifications, view dashboards, see timelines

**Recommendation:** Update PRD to v1.3 with FR-6.5 (Agent Linear Integration) and clarify FR-7 dependencies. This aligns the PRD with what we've built and sets clear expectations for future work.
