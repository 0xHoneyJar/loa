# Word-for-Word Citation Protocol

**Version**: 1.0
**Status**: Active
**Last Updated**: 2025-12-27

---

## Overview

This protocol enforces word-for-word code citations in all agent outputs so claims are grounded in actual code, not assumptions or references without evidence.

**Problem**: File:line references alone are insufficient - reviewers cannot verify claims without seeing actual code quotes.

**Solution**: Mandatory word-for-word code snippets with absolute paths for every architectural claim.

**Source**: PRD FR-5.3

---

## Citation Format Template

Every architectural claim includes an exact code snippet:

```markdown
"<claim>: `<exact_code_snippet>` [<absolute_path>:<line>]"
```

| Component | Description | Example |
|-----------|-------------|---------|
| **Claim** | Architectural statement | "The system uses JWT validation" |
| **Code Quote** | Word-for-word snippet from code | `export async function validateToken(token: string)` |
| **Absolute Path** | Full path from PROJECT_ROOT | `/home/user/project/src/auth/jwt.ts` |
| **Line Number** | Exact line where code appears | `45` |

---

## Examples

❌ **INSUFFICIENT** (rejected by reviewing-code - no code quote, relative path, claim unverifiable without opening the file):
```markdown
"The system uses JWT [src/auth/jwt.ts:45]"
```

✅ **REQUIRED** (exact code quote, absolute path, verifiable immediately):
```markdown
"The system uses JWT: `export async function validateToken(token: string): Promise<TokenPayload>` [/home/user/project/src/auth/jwt.ts:45]"
```

The same template applies for every kind of claim - configuration values, middleware wiring, function signatures - and in every document type: PRDs/SDDs, implementation reports, code reviews. Only the claim and the quoted code change; the shape never does.

For code longer than ~10 lines, extract the 2-3 most critical lines, mark the truncated middle with `...`, and cite the full line range:

```markdown
"Login function performs multi-step validation: `async function login(email, password) { ... const user = await User.findByEmail(email); ... if (!await bcrypt.compare(password, user.hash)) throw AuthError(); ... }` [/abs/path/src/auth/login.ts:15-35]"
```

Use the same line-range format (`15-20`) whenever a citation quotes a multi-line function body rather than a single signature.

---

## Requirements

Every citation MUST include: a clear architectural claim, an exact code quote (no paraphrasing), an absolute path (`${PROJECT_ROOT}/...`), and the exact line number.

**Code quote length**: minimum is the function signature or variable declaration; maximum is 2-3 lines of core logic; anything longer uses `...` with a line range.

**Formatting**: backticks for inline code; include function name, parameters, and return type where available; no paraphrasing - exact word-for-word match.

---

## Path Format

**Absolute paths only.** Models frequently struggle with relative paths after navigating directories, so every citation resolves from the project root:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
```

❌ Relative (rejected): `` `export function validate()` [src/auth/validation.ts:45] ``
✅ Absolute (required): `` `export function validate()` [/home/user/project/src/auth/validation.ts:45] ``

---

## Integration with Trajectory Logging

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

Every citation carries `"grounding": "citation"` in the trajectory log.

---

## Edge Cases

**File or line not found**: flag the claim as `[ASSUMPTION]` instead of citing it, mark it for verification, and log `"grounding": "assumption"` to trajectory - e.g. `"System likely validates JWT tokens [ASSUMPTION: src/auth/jwt.ts:45 not found, requires verification]"`.

**Multiple files implement the same pattern**: cite the primary implementation and reference the others parenthetically - e.g. `[/abs/path/src/auth/middleware.ts:12] (also used in /abs/path/src/admin/middleware.ts:8)`.

**Code changed since the search that found it**: re-read the file, update the citation with the current code, and log the discrepancy when it's significant:

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

Before completing any task, verify:

- [ ] Every claim has a code quote, not just file:line
- [ ] Every quote is word-for-word (no paraphrasing)
- [ ] Every path is absolute (`${PROJECT_ROOT}/...`)
- [ ] Every line number is accurate
- [ ] Multi-line quotes use line ranges (`45-50`)
- [ ] Citations are logged to trajectory with `"grounding": "citation"`
- [ ] Zero unflagged `[ASSUMPTION]` claims remain

---

## Validation

Check every citation has a code quote:
```bash
grep -E '\[.*:.*\]' document.md | grep -v '`' || echo "All citations have code quotes"
```

Check every citation uses an absolute path:
```bash
grep -E '\[.*:.*\]' document.md | grep -v '^\[/' && echo "ERROR: Relative paths found" || echo "All paths absolute"
```

Verify a line number by re-reading the cited line (`sed -n '<line>p' <file>`) and comparing it against the quoted code.

---

## Communication Guidelines

State the result, not the mechanism.

✅ "The system uses JWT validation as shown in the code quote above." / "All claims are backed by word-for-word code citations." / "Implementation verified against actual code at src/auth/jwt.ts:45."

❌ "I'm following the word-for-word citation protocol..." / "Let me add backticks to meet citation requirements..." / "Logging citations to trajectory with grounding type..."

---

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---|---|---|
| Citations rejected by reviewing-code | Missing code quotes or relative paths | Add word-for-word quotes, convert to absolute paths |
| Code quotes don't match the actual file | Code changed after search, or the line number is wrong | Re-read the file, update the citation with current code |
| Too many code quotes (verbose output) | Over-citing, including non-critical details | Cite only architectural decisions: signatures, key logic, configuration |

---

## Self-Audit Checkpoint

Before marking grounded work complete, verify against the trajectory log:

```bash
total_claims=$(grep '"phase":"cite"' trajectory.jsonl | wc -l)
grounded_claims=$(grep '"grounding":"citation"' trajectory.jsonl | wc -l)
# ratio = grounded/total — target >= 0.95
```

**Claim classification**: GROUNDED (word-for-word citation with file:line) · ASSUMPTION (explicitly `[ASSUMPTION]`-flagged) · GHOST (documented feature with zero code evidence) · SHADOW (code with zero documentation).

**Do not complete the task if**: grounding ratio < 0.95 · any unflagged assumption · relative paths in citations · citations without code quotes · Ghost Features untracked in Beads · Shadow Systems missing from drift-report.md · incomplete evidence chains. Remediate, then re-audit.

---

## Negative Grounding - claims of absence

A claim that a feature does NOT exist requires two-query verification:

1. **Query 1** - the feature's functional description from docs
2. **Query 2** - architectural/technical synonyms (a different semantic angle)

Exactly two queries - one under-tests, three over-fit.

| Code results | Doc mentions | Classification | Action |
|--------------|--------------|----------------|--------|
| 0 | 0-2 | CONFIRMED GHOST | Track in Beads, remove from docs, drift-report entry |
| 0 | 3+ | HIGH AMBIGUITY | Flag for human audit - never assert absence unilaterally |
| 1+ | any | NOT GHOST | Feature exists; verify doc alignment |

Ghost findings never count as grounded claims; log both query strings as evidence.

---

## Evidence-Driven Decisions

Non-trivial implementation decisions carry an evidence chain (a citation for each input to the decision) plus three test scenarios - happy path, edge case, error handling - each with specific assertions. A decision with unflagged `[ASSUMPTION]`s outstanding is not complete.

---

## Related Protocols

- **Trajectory Evaluation** (`.claude/protocols/trajectory-evaluation.md`) - log citations to trajectory
- **Tool Result Clearing** (`.claude/protocols/tool-result-clearing.md`) - extract citations during synthesis
- **Grounding Enforcement** (`.claude/protocols/grounding-enforcement.md`) - ratio rule and enforcement detail

---

## Provenance

Removed from rule text (kept the rules, dropped the archaeology): the "Version History" changelog table and the closing roadmap line; `cycle-121` merge notes on the Self-Audit Checkpoint, Negative Grounding, and Evidence-Driven Decisions headings (content unchanged); an inline `KF-019` taxonomy tag on the negative-grounding rule.
