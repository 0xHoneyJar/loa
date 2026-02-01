# Word-for-Word Citation Protocol

**Version**: 1.0
**Status**: Active
**Last Updated**: 2025-12-27

---

## Overview

This protocol enforces word-for-word code citations in all agent outputs to ensure claims are properly grounded in actual code, not assumptions or references without evidence.

**Problem**: File:line references alone are insufficient - reviewers cannot verify claims without seeing actual code quotes.

**Solution**: Mandatory word-for-word code snippets with absolute paths for every architectural claim.

**Source**: PRD FR-5.3

---

## Citation Format Template

Every architectural claim must include exact code snippet:

```markdown
"<claim>: `<exact_code_snippet>` [<absolute_path>:<line>]"
```

### Format Components

| Component | Description | Example |
|-----------|-------------|---------|
| **Claim** | Architectural statement | "The system uses JWT validation" |
| **Code Quote** | Word-for-word snippet from code | `export async function validateToken(token: string)` |
| **Absolute Path** | Full path from PROJECT_ROOT | `/home/user/project/src/auth/jwt.ts` |
| **Line Number** | Exact line where code appears | `45` |

---

## Examples

### ❌ INSUFFICIENT (Reference Only)

These will be **REJECTED** by reviewing-code agent:

```markdown
"The system uses JWT [src/auth/jwt.ts:45]"
```

**Why rejected**: No code quote, relative path, cannot verify claim without opening file

---

### ✅ REQUIRED (Word-for-Word Quote)

These will be **ACCEPTED**:

```markdown
"The system uses JWT: `export async function validateToken(token: string): Promise<TokenPayload>` [/home/user/project/src/auth/jwt.ts:45]"
```

**Why accepted**: Exact code quote, absolute path, claim is verifiable immediately

---

### More Examples

#### Configuration Citation

❌ **INSUFFICIENT**:
```markdown
"Auth uses bcrypt cost factor 12 [src/config/auth.ts:8]"
```

✅ **REQUIRED**:
```markdown
"Auth uses bcrypt cost factor 12: `const BCRYPT_ROUNDS = 12;` [/abs/path/src/config/auth.ts:8]"
```

#### Middleware Citation

❌ **INSUFFICIENT**:
```markdown
"All routes protected by auth middleware [src/server.ts:23]"
```

✅ **REQUIRED**:
```markdown
"All routes protected by auth middleware: `app.use('/api', authMiddleware);` [/abs/path/src/server.ts:23]"
```

#### Function Signature Citation

❌ **INSUFFICIENT**:
```markdown
"Login function takes email and password [src/auth/login.ts:15]"
```

✅ **REQUIRED**:
```markdown
"Login function takes email and password: `async function login(email: string, password: string): Promise<User>` [/abs/path/src/auth/login.ts:15]"
```

---

## Requirements

### Mandatory Elements

Every citation MUST include:

1. **Claim**: Clear architectural statement
2. **Code Quote**: Exact code snippet (no paraphrasing)
3. **Absolute Path**: `${PROJECT_ROOT}/...` format
4. **Line Number**: Exact line where code appears

### Code Quote Guidelines

**Length**:
- **Minimum**: Function signature or variable declaration
- **Maximum**: 2-3 lines (core logic only)
- **If longer**: Use ellipsis `...` to indicate truncation

**Example with ellipsis**:
```markdown
"User validation uses email regex: `const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/; ... return emailRegex.test(email);` [/abs/path/src/validation.ts:12-15]"
```

**Formatting**:
- Use backticks for inline code: \`code here\`
- Preserve original indentation (not required in citation)
- Include function name, parameters, return type (if available)
- NO paraphrasing - exact word-for-word match

---

## Path Format

### Absolute Paths Only

**Why**: Models frequently struggle with relative paths after navigating directories.

**Setup**:
```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
```

**Examples**:

❌ **RELATIVE** (will be rejected):
```markdown
`export function validate()` [src/auth/validation.ts:45]
```

✅ **ABSOLUTE** (required):
```markdown
`export function validate()` [/home/user/project/src/auth/validation.ts:45]
```

✅ **ABSOLUTE** (with variable):
```markdown
`export function validate()` [${PROJECT_ROOT}/src/auth/validation.ts:45]
```

---

## Integration with Trajectory Logging

### Cite Phase

After extracting code quotes, log to trajectory:

```jsonl
{
  "ts": "2025-12-27T10:30:10Z",
  "agent": "implementing-tasks",
  "phase": "cite",
  "citations": [
    {
      "claim": "System uses JWT validation",
      "code": "export async function validateToken(token: string): Promise<TokenPayload>",
      "path": "/abs/path/src/auth/jwt.ts",
      "line": 45,
      "score": 0.89,
      "grounding": "citation"
    }
  ]
}
```

### Grounding Field

All citations must have `"grounding": "citation"` in trajectory log.

---

## Multi-Line Citations

For functions with complex signatures or important logic:

```markdown
"Login validates credentials and creates session: 
`async function login(email: string, password: string): Promise<Session> {
  const user = await User.findByEmail(email);
  if (!user || !await bcrypt.compare(password, user.passwordHash)) throw new AuthError();
  return SessionManager.create(user.id);
}` [/abs/path/src/auth/login.ts:15-20]"
```

**Note**: Use line range format `15-20` for multi-line quotes.

---

## Citation in Different Contexts

### In PRD/SDD Documents

When writing requirements or design docs:

```markdown
## Authentication Architecture

The system implements JWT-based authentication with token validation: `export async function validateToken(token: string)` [/abs/path/src/auth/jwt.ts:45]

Tokens expire after 1 hour: `const TOKEN_EXPIRY = 3600;` [/abs/path/src/config/auth.ts:12]
```

### In Implementation Reports

When documenting completed work:

```markdown
## Task 3.1: Implement JWT Validation

**Implementation**: Created token validation function: `export async function validateToken()` [/abs/path/src/auth/jwt.ts:45]

**Integration**: Added middleware to all API routes: `app.use('/api', authMiddleware);` [/abs/path/src/server.ts:23]
```

### In Code Reviews

When providing feedback:

```markdown
## Issue: Hardcoded Salt Rounds

**Problem**: Code uses hardcoded bcrypt rounds: `bcrypt.hash(password, 10)` [/abs/path/src/auth/register.ts:34]

**Expected**: Should use config constant: `const BCRYPT_ROUNDS = 12;` [/abs/path/src/config/auth.ts:8]

**Recommendation**: Update to `bcrypt.hash(password, BCRYPT_ROUNDS)`
```

---

## Edge Cases

### Case 1: Code Snippet Not Available (File Not Found)

If file doesn't exist or line not found:

**Action**:
1. Flag as `[ASSUMPTION]` instead of citation
2. Mark claim for verification
3. Log to trajectory as `"grounding": "assumption"`

**Example**:
```markdown
"System likely validates JWT tokens [ASSUMPTION: src/auth/jwt.ts:45 not found, requires verification]"
```

### Case 2: Code is Very Long (>10 lines)

If core logic spans many lines:

**Action**:
1. Extract most critical 2-3 lines
2. Use ellipsis `...` to show truncation
3. Include line range in citation

**Example**:
```markdown
"Login function performs multi-step validation: `async function login(email, password) { ... const user = await User.findByEmail(email); ... if (!await bcrypt.compare(password, user.hash)) throw AuthError(); ... }` [/abs/path/src/auth/login.ts:15-35]"
```

### Case 3: Multiple Files Implement Same Pattern

If pattern appears in multiple files:

**Action**:
1. Cite the primary implementation
2. Reference others parenthetically

**Example**:
```markdown
"Authentication middleware pattern: `export const authMiddleware = async (req, res, next) => {...}` [/abs/path/src/auth/middleware.ts:12] (also used in /abs/path/src/admin/middleware.ts:8)"
```

### Case 4: Code Changed Since Search

If code was modified after search results:

**Action**:
1. Re-read file to get current code
2. Update citation with latest code
3. Log discrepancy to trajectory if significant

**Trajectory log**:
```jsonl
{
  "ts": "2025-12-27T11:15:00Z",
  "agent": "reviewing-code",
  "phase": "citation_update",
  "path": "/abs/path/src/auth/jwt.ts",
  "line": 45,
  "original_code": "export function validateToken()",
  "updated_code": "export async function validateToken()",
  "reason": "Code changed to async after initial search"
}
```

---

## Self-Audit Checklist

Before completing any task, verify citations:

- [ ] Every claim has code quote (not just file:line)
- [ ] All quotes are word-for-word (no paraphrasing)
- [ ] All paths are absolute (${PROJECT_ROOT}/...)
- [ ] All line numbers are accurate
- [ ] Multi-line quotes use line ranges (45-50)
- [ ] Citations logged to trajectory with `"grounding": "citation"`
- [ ] Zero unflagged [ASSUMPTION] claims

---

## Validation

Test citation compliance:

### Test 1: Check for Backticks

```bash
# All citations should have backticks (code quotes)
grep -E '\[.*:.*\]' document.md | grep -v '`' || echo "All citations have code quotes"
```

### Test 2: Check for Absolute Paths

```bash
# All citations should have absolute paths (start with /)
grep -E '\[.*:.*\]' document.md | grep -v '^\[/' && echo "ERROR: Relative paths found" || echo "All paths absolute"
```

### Test 3: Verify Line Numbers

```bash
# Extract citation and verify line number matches
citation_path="/abs/path/src/auth/jwt.ts"
citation_line=45
actual_line=$(sed -n '45p' "$citation_path")
# Compare citation code with actual line
```

---

## Communication Guidelines

### What Agents Should Say (User-Facing)

✅ **CORRECT**:
- "The system uses JWT validation as shown in the code quote above."
- "All claims are backed by word-for-word code citations."
- "Implementation verified against actual code at src/auth/jwt.ts:45"

❌ **INCORRECT** (exposing protocol details):
- "I'm following the word-for-word citation protocol..."
- "Let me add backticks to meet citation requirements..."
- "Logging citations to trajectory with grounding type..."

---

## Troubleshooting

### Symptom: Citations rejected by reviewing-code agent

**Diagnosis**: Missing code quotes or using relative paths
**Fix**: Add word-for-word quotes, convert to absolute paths
**Check**: Verify citation format matches template

### Symptom: Code quotes don't match actual file

**Diagnosis**: Code changed after search or incorrect line number
**Fix**: Re-read file, update citation with current code
**Check**: `sed -n '<line>p' <file>` to verify line content

### Symptom: Too many code quotes (output verbose)

**Diagnosis**: Over-citing, including non-critical details
**Fix**: Cite only architectural decisions, not every line
**Check**: Focus on function signatures, key logic, configuration

---

## Related Protocols

- **Trajectory Evaluation** (`.claude/protocols/trajectory-evaluation.md`) - Log citations to trajectory
- **Self-Audit Checkpoint** (`.claude/protocols/self-audit-checkpoint.md`) - Verify citation compliance
- **Tool Result Clearing** (`.claude/protocols/tool-result-clearing.md`) - Extract citations during synthesis
- **EDD Verification** (`.claude/protocols/edd-verification.md`) - Require citations for test scenarios

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-27 | Initial protocol creation (Sprint 3) |

---

**Status**: ✅ Protocol Complete
**Next**: Integrate into agent skills (Sprint 4)
