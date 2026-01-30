# EARS Requirements Template

EARS (Easy Approach to Requirements Syntax) is a structured notation for writing clear, unambiguous requirements. Use this format when precision is critical.

## EARS Patterns

### 1. Ubiquitous (Always Active)

Requirements that are always true, with no trigger or condition.

**Format**: `The system shall [action]`

**Examples**:
```markdown
- The system shall encrypt all data at rest using AES-256
- The system shall log all authentication attempts
- The system shall validate input against XSS patterns
```

### 2. Event-Driven

Requirements triggered by a specific event.

**Format**: `When [trigger], the system shall [action]`

**Examples**:
```markdown
- When a user submits the login form, the system shall validate credentials within 2 seconds
- When a file is uploaded, the system shall scan for malware before storage
- When the session expires, the system shall redirect to the login page
```

### 3. State-Driven

Requirements active only while in a specific state.

**Format**: `While [state], the system shall [action]`

**Examples**:
```markdown
- While in maintenance mode, the system shall reject new connections
- While the user is authenticated, the system shall refresh the session token every 15 minutes
- While processing a transaction, the system shall prevent duplicate submissions
```

### 4. Conditional

Requirements with a precondition that must be true.

**Format**: `If [condition], the system shall [action]`

**Examples**:
```markdown
- If the password is incorrect 3 times, the system shall lock the account for 30 minutes
- If the user has admin role, the system shall display the admin panel
- If the API rate limit is exceeded, the system shall return HTTP 429
```

### 5. Optional (Feature-Dependent)

Requirements that depend on feature flags or configuration.

**Format**: `Where [feature enabled], the system shall [action]`

**Examples**:
```markdown
- Where two-factor authentication is enabled, the system shall require OTP verification
- Where audit logging is enabled, the system shall record all database queries
- Where dark mode is selected, the system shall apply the dark theme stylesheet
```

### 6. Complex (Combined)

Requirements combining multiple patterns.

**Format**: `While [state], when [trigger], if [condition], the system shall [action]`

**Examples**:
```markdown
- While the user is authenticated, when they click "Delete Account", if they confirm the action, the system shall schedule account deletion in 30 days
- While in production mode, when an error occurs, if the error is unhandled, the system shall log to the error tracking service and display a generic error page
```

---

## Acceptance Criteria Format

Each requirement should have acceptance criteria using Given-When-Then:

```markdown
### REQ-001: User Login

**Requirement**: When a user submits valid credentials, the system shall authenticate and redirect to the dashboard.

**Acceptance Criteria**:
- Given a registered user with valid credentials
- When they submit the login form
- Then they are redirected to /dashboard within 2 seconds
- And a session token is created
- And the last_login timestamp is updated

**Edge Cases**:
- Given invalid credentials → display error message, increment attempt counter
- Given locked account → display "Account locked" with unlock instructions
- Given expired password → redirect to password reset flow
```

---

## PRD Section Template

```markdown
## Functional Requirements

### Authentication

| ID | Type | Requirement | Priority |
|----|------|-------------|----------|
| REQ-AUTH-001 | Event | When a user submits the login form, the system shall validate credentials | P0 |
| REQ-AUTH-002 | Conditional | If credentials are invalid 3 times, the system shall lock the account | P0 |
| REQ-AUTH-003 | Optional | Where MFA is enabled, the system shall require OTP verification | P1 |

### REQ-AUTH-001: User Login
[Full acceptance criteria as above]

### REQ-AUTH-002: Account Lockout
[Full acceptance criteria]
```

---

## When to Use EARS

**Use EARS when**:
- Requirements are ambiguous in natural language
- Multiple stakeholders interpret requirements differently
- Regulatory compliance requires precise documentation
- Security-critical features need explicit triggers and conditions

**Skip EARS when**:
- Requirements are straightforward and well-understood
- Rapid prototyping where flexibility is needed
- The team prefers user story format exclusively

---

## References

- [EARS: Easy Approach to Requirements Syntax](https://www.iaria.org/conferences2009/filesICCGI09/ICCGI_2009_Tutorial_Terzakis.pdf) - NASA/Rolls Royce methodology
- [Kiro.dev Specs System](https://kiro.dev/docs/getting-started/first-project/) - EARS in practice
