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
