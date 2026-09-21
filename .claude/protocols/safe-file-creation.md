# Safe File Creation Protocol

## Overview

This protocol prevents silent file corruption when using Bash heredocs to create source files containing template literal syntax (`${...}`).

**The Problem**: Bash heredocs with unquoted delimiters perform shell variable expansion. Template literals in JSX/TypeScript use identical syntax, causing `${variable}` to be replaced with empty strings (or undefined shell variables).

**Impact**: Silent corruption of production code during autonomous runs.

---

## Decision Tree

Source file (`.tsx`, `.jsx`, `.ts`, `.js`, `.vue`, `.svelte`, …) → Write tool. Anything else whose content must keep a literal `${...}` → quoted heredoc (`<<'EOF'`). Content where shell expansion is intended → unquoted heredoc (`<< EOF`).

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

The failure is silent: the command exits 0, the file exists, the build may pass, and the corruption surfaces only at runtime or review — in a `/run` session nobody is watching, and the rework costs context and time.

---

## Related

- **Bash Manual**: [Here Documents](https://www.gnu.org/software/bash/manual/bash.html#Here-Documents)

## Provenance

Protocol v1.0.0 (2026-02-06) for issue #197; the same silent-failure class as PR #199 (macOS date compatibility).
