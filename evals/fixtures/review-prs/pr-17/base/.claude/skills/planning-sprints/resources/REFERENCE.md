# Sprint Planner Reference

## Sprint Structure Checklist

### Per Sprint Requirements
- [ ] Sprint number and descriptive theme
- [ ] Duration (2.5 days) with specific dates
- [ ] Sprint Goal (1 sentence)
- [ ] Deliverables with checkboxes and measurable outcomes
- [ ] Acceptance Criteria (testable) with checkboxes
- [ ] Technical Tasks (specific) with checkboxes
- [ ] Dependencies explicitly stated
- [ ] Risks with probability, impact, and mitigation
- [ ] Success Metrics (quantifiable)

### Overall Plan Requirements
- [ ] Executive Summary with MVP scope
- [ ] Total sprint count and timeline
- [ ] Sprint overview table
- [ ] Risk register
- [ ] Success metrics summary
- [ ] Dependencies map
- [ ] PRD feature mapping
- [ ] SDD component mapping

## Quality Assurance Checklist

Before finalizing sprint plan:
- [ ] All MVP features from PRD are accounted for
- [ ] Sprints build logically on each other
- [ ] Each sprint is feasible within 2.5 days
- [ ] All deliverables have checkboxes for tracking
- [ ] Acceptance criteria are clear and testable
- [ ] Technical approach aligns with SDD
- [ ] Risks are identified and mitigation strategies defined
- [ ] Dependencies are explicitly called out
- [ ] Plan provides clear guidance for engineers

## Clarifying Questions Checklist

### Priority & Scope
- [ ] Are there any priority conflicts between features?
- [ ] What features are must-have vs nice-to-have for MVP?
- [ ] Are there any hard deadlines or milestones?

### Technical
- [ ] Any technical uncertainties that impact effort estimation?
- [ ] Are there any proof-of-concept items needed?
- [ ] What's the testing strategy and coverage expectations?

### Resources
- [ ] What's the team size and composition?
- [ ] Are there any resource constraints?
- [ ] Who are the subject matter experts?

### Dependencies
- [ ] What external dependencies exist?
- [ ] Are there any third-party integrations?
- [ ] What internal teams/services need to be coordinated with?

### Risks
- [ ] What could delay or block the project?
- [ ] What are the fallback plans if key assumptions fail?
- [ ] Are there any compliance or security concerns?

## Task Sizing Guidelines

### Small (< 0.5 day)
- Single function implementation
- Unit tests for one module
- Configuration changes
- Documentation updates

### Medium (0.5-1 day)
- Feature implementation (single component)
- Integration with existing service
- Database migration (simple)
- API endpoint implementation

### Large (1-2 days)
- Full feature with multiple components
- Complex integration
- New service setup
- Major refactoring

### Too Large (needs splitting)
- Cross-cutting concerns
- Multiple team dependencies
- Undefined requirements
- High uncertainty

## Sprint Sequencing Principles

1. **Foundation First**
   - Infrastructure setup
   - Database schema
   - Authentication
   - Core utilities

2. **High-Risk Early**
   - Technical spikes
   - Proof of concepts
   - Integration testing
   - Performance validation

3. **Dependencies Respected**
   - Backend before frontend (when dependent)
   - Data models before business logic
   - Core features before enhancements

4. **Value Incremental**
   - Each sprint delivers working functionality
   - Demo-able progress after each sprint
   - User feedback opportunities

## Common Anti-Patterns

### Vague Tasks
- BAD: "Set up database"
- GOOD: "Create PostgreSQL schema with users, sessions, and audit_logs tables per SDD §3.2"

### Missing Acceptance Criteria
- BAD: "User can log in"
- GOOD: "User can log in with email/password, receives JWT token, session stored in Redis with 24h TTL"

### Unquantified Metrics
- BAD: "System is fast"
- GOOD: "Login API responds in <200ms p99, handles 100 concurrent requests"

### Hidden Dependencies
- BAD: (Sprint 3 silently needs Sprint 1's work)
- GOOD: "Depends on Sprint 1: Auth middleware must be complete"

### Overloaded Sprints
- BAD: 5 days of work in 2.5 day sprint
- GOOD: Conservative estimates with buffer for unknowns


# Beads NOT_INSTALLED fallback + Sprint-Ledger Step 0 (cycle-121 split from SKILL.md)

### If NOT_INSTALLED or NOT_INITIALIZED

1. **Check for valid opt-out**:
   ```bash
   opt_out=$(.claude/scripts/beads/update-beads-state.sh --opt-out-check 2>/dev/null || echo "NO_OPT_OUT")
   ```

2. **If no valid opt-out**, present HITL gate using AskUserQuestion:

   ```
   Beads Preflight Check
   ════════════════════════════════════════════════════════════

   Status: {status}

   Beads is not available. Task tracking is the EXPECTED DEFAULT
   for safe, auditable agent workflows.

   "We're building spaceships. Safety of operators and users is paramount."

   Options:
   [1] Install beads (Recommended)
       └─ .claude/scripts/beads/install-br.sh
       └─ Or: cargo install beads_rust

   [2] Initialize beads
       └─ br init

   [3] Continue without beads (24h acknowledgment)
       └─ Requires reason for audit trail

   [4] Abort
   ```

3. **If "Continue without beads" selected**:
   - Require reason (configurable via `beads.opt_out.require_reason`)
   - Record opt-out: `.claude/scripts/beads/update-beads-state.sh --opt-out "Reason"`
   - Log to trajectory: `grimoires/loa/a2a/trajectory/beads-preflight-{date}.jsonl`
   - Opt-out expires after 24h (configurable)

4. **Update state after health check**:
   ```bash
   .claude/scripts/beads/update-beads-state.sh --health "$status"
   ```


### Step 0: Check for Sprint Ledger (NEW in v1.8.0)

Check if `grimoires/loa/ledger.json` exists:

```bash
[ -f "grimoires/loa/ledger.json" ] && echo "EXISTS" || echo "MISSING"
```

**If MISSING**, use AskUserQuestion to offer creation:

```
No Sprint Ledger found at grimoires/loa/ledger.json

A Sprint Ledger provides:
• Global sprint numbering across development cycles
• Cycle tracking with PRD/SDD references
• Sprint history and metrics for retrospectives

Options:
[1] Create ledger (recommended)
[2] Continue without ledger
```

**If user selects "Create ledger":**

Create `grimoires/loa/ledger.json` with initial schema:

```json
{
  "version": "1.0.0",
  "next_sprint_number": 1,
  "active_cycle": "cycle-001",
  "cycles": [
    {
      "id": "cycle-001",
      "label": null,
      "status": "active",
      "created_at": "<ISO timestamp>",
      "prd": "grimoires/loa/prd.md",
      "sdd": "grimoires/loa/sdd.md",
      "sprints": []
    }
  ]
}
```

Log creation to trajectory: `{"action": "ledger_created", "path": "grimoires/loa/ledger.json"}`

**If EXISTS**, proceed to Step 1.

