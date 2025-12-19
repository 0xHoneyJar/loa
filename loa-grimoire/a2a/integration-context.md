# Integration Context

This file tracks external integrations and project configuration for Loa.

---

## Linear Integration

### Team Configuration
- **Team ID**: *(configure during /setup)*
- **Project ID**: *(auto-created or linked during /setup)*

### Standard Labels

**Agent Labels**:
- `agent:implementer` - Sprint implementation work
- `agent:reviewer` - Code review work
- `agent:devops` - Infrastructure and deployment work
- `agent:auditor` - Security audit findings
- `agent:planner` - Sprint planning work

**Type Labels**:
- `type:feature` - New functionality
- `type:bugfix` - Bug fixes
- `type:refactor` - Code improvements
- `type:infrastructure` - DevOps/deployment work
- `type:security` - Security-related work
- `type:audit-finding` - Security audit findings
- `type:planning` - Planning documentation

**Priority Labels**:
- `priority:critical` - Must fix immediately (blocking)
- `priority:high` - Must fix before production

**Sprint Labels**:
- `sprint:sprint-1`, `sprint:sprint-2`, etc.

**Source Labels**:
- `source:discord` - From Discord feedback
- `source:internal` - Internal/agent-generated

---

## Hivemind Integration

### Connection Status
- **Status**: Not Connected
- **Reason**: Setup not completed

### Project Configuration
- **Project Type**: *(select during /setup)*
- **Configured At**: *(timestamp)*

### Loaded Skills
*(populated during /setup based on project type)*

---

## Product Home (Optional)

### Configuration
- **Project ID**: *(link during /setup)*
- **Project Name**: *(auto-detected)*
- **Product Labels**: *(configured)*

---

## Linked Experiment (Optional)

### Configuration
- **Experiment ID**: *(Linear issue ID)*
- **Hypothesis**: *(from experiment)*
- **Success Criteria**: *(from experiment)*
- **User Truth Canvas**: *(link if available)*

---

*This file is updated by `/setup` and referenced by all Loa agents.*
*See CLAUDE.md "Linear Documentation Requirements" for usage details.*
