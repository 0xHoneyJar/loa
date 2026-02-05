# Safe File Creation Protocol

> **Protocol Version**: 1.0.0
> **Last Updated**: 2026-02-06
> **Issue Reference**: #197

## Overview

This protocol prevents silent file corruption when using Bash heredocs to create source files containing template literal syntax (`${...}`).

**The Problem**: Bash heredocs with unquoted delimiters perform shell variable expansion. Template literals in JSX/TypeScript use identical syntax, causing `${variable}` to be replaced with empty strings (or undefined shell variables).

**Impact**: Silent corruption of production code during autonomous runs.

---

## Decision Tree

```
Creating a file?
│
├─► Is it a SOURCE FILE? (.tsx, .jsx, .ts, .js, .vue, .svelte, etc.)
│   │
│   └─► YES ─────────────────────────────────────────────────────────┐
│                                                                    │
│       ┌────────────────────────────────────────────────────────────┤
│       │                                                            │
│       ▼                                                            │
│   ╔═══════════════════════════════════════════════════════════╗   │
│   ║  USE WRITE TOOL (PREFERRED)                               ║   │
│   ║  Content is passed exactly as-is, no shell interpretation ║   │
│   ╚═══════════════════════════════════════════════════════════╝   │
│                                                                    │
└─► NO (shell script, config, etc.)                                  │
    │                                                                │
    ├─► Does content contain ${...} that should be LITERAL?          │
    │   │                                                            │
    │   └─► YES ─► Use QUOTED heredoc (<<'EOF') ◄────────────────────┘
    │
    └─► NO (shell expansion is INTENTIONAL)
        │
        └─► Unquoted heredoc (<< EOF) is acceptable
```

---

## Method Comparison

| Method | Shell Expansion | Content Integrity | Recommended For |
|--------|-----------------|-------------------|-----------------|
| **Write tool** | None | Guaranteed | Source files (PREFERRED) |
| **`<<'EOF'`** (quoted) | None | Guaranteed | Shell scripts with literal `${...}` |
| **`<< EOF`** (unquoted) | Yes | Risk of corruption | Shell scripts needing expansion |

---

## High-Risk File Extensions

These extensions commonly contain `${...}` template literal syntax:

| Extension | Language/Framework | Risk |
|-----------|-------------------|------|
| `.tsx`, `.jsx` | React/JSX | HIGH - Template expressions |
| `.ts`, `.mts`, `.cts` | TypeScript | HIGH - Template literals |
| `.js`, `.mjs`, `.cjs` | JavaScript | HIGH - Template literals |
| `.vue` | Vue.js | HIGH - Template syntax |
| `.svelte` | Svelte | HIGH - Template syntax |
| `.astro` | Astro | HIGH - Template syntax |
| `.graphql`, `.gql` | GraphQL | MEDIUM - Variable syntax |
| `.sql` | SQL | MEDIUM - Interpolation |
| `.md` | Markdown | MEDIUM - Code blocks |
| `.html` | HTML | LOW - Rare template use |

---

## Examples

### SAFE: Write Tool (PREFERRED)

```
Use the Write tool to create file.tsx with content:

export function Button({ active }: { active: boolean }) {
  return (
    <button className={`btn ${active ? 'active' : ''}`}>
      Click me
    </button>
  );
}
```

The Write tool passes content exactly as written. No shell interpretation occurs.

### SAFE: Quoted Heredoc

```bash
cat > file.tsx <<'EOF'
export function Button({ active }: { active: boolean }) {
  return (
    <button className={`btn ${active ? 'active' : ''}`}>
      Click me
    </button>
  );
}
EOF
```

The **quoted** `'EOF'` delimiter prevents shell expansion. `${active}` is preserved literally.

### DANGEROUS: Unquoted Heredoc

```bash
# ⚠️ DANGEROUS - DO NOT USE FOR SOURCE FILES
cat > file.tsx << EOF
export function Button({ active }: { active: boolean }) {
  return (
    <button className={`btn ${active ? 'active' : ''}`}>
      Click me
    </button>
  );
}
EOF
```

**Result**: `${active}` becomes empty string (undefined shell variable).

**Actual output**:
```tsx
<button className={`btn  ? 'active' : ''`}>
```

This is **silently corrupted** - no error is raised, but the code is broken.

---

## Pre-Write Checklist

Before creating any file, verify:

- [ ] **Extension checked**: Is this a high-risk source file?
- [ ] **Method selected**: Write tool (preferred) or quoted heredoc?
- [ ] **Content scanned**: Does content contain `${...}` syntax?
- [ ] **Expansion intentional?**: If heredoc, should `${...}` expand?

---

## Why This Matters

### Silent Failure Mode

Unlike syntax errors that fail loudly, heredoc expansion failures are **silent**:

1. The command succeeds (exit code 0)
2. The file is created
3. The content is corrupted
4. No error message is shown
5. The build may even succeed (with wrong behavior)

### Autonomous Run Risk

During `/run` mode:
- Human is not watching
- Agent assumes file was created correctly
- Corrupted code may pass linting (valid syntax)
- Bug only discovered at runtime or review

### Token/Time Cost

Debugging corrupted output:
- Requires re-reading generated files
- Requires re-implementing the fix
- Wastes context window and tokens
- Delays sprint completion

---

## Integration Points

### implementing-tasks Skill

The implementing-tasks skill includes file creation safety guidance and adds this to the pre-implementation checklist.

### CLAUDE.loa.md

Main instructions include a brief reference to this protocol for quick access.

---

## Related

- **Issue**: https://github.com/0xHoneyJar/loa/issues/197
- **Bash Manual**: [Here Documents](https://www.gnu.org/software/bash/manual/bash.html#Here-Documents)
- **Similar Pattern**: PR #199 (macOS date compatibility - silent failure)
