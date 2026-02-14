# Vision 002: Bash Template Rendering Anti-Pattern

## Source
- Bridge: bridge-20260213-c012rt, Iteration 1
- PR: #317
- Finding Severity: 8/10

## Insight

Bash parameter expansion (`${var//pattern/replacement}`) is fundamentally unsafe for template rendering when replacement content may contain:
1. **Template markers** — causes cascading substitution (template injection)
2. **Backslashes/special chars** — mangled by bash string operations
3. **Large content** — O(n*m) performance causes OOM on documents >100KB

## Pattern

**Anti-pattern:**
```bash
content="${content//\{\{VAR\}\}/$replacement}"  # UNSAFE
```

**Safe pattern:**
```bash
# File-based replacement via awk — no shell escaping issues
awk -v marker="{{VAR}}" -v file="$replacement_file" '
    index($0, marker) { while ((getline line < file) > 0) print line; close(file); next }
    { print }
' "$template" > "$output"
```

## Applicability

Any Loa script that renders templates with user-provided or file-based content. Particularly relevant for:
- Flatline prompt templates
- Red team attack/counter-design templates
- Bridge review prompts

## Connection

This pattern is an instance of the broader "shell as string processor" anti-pattern. The Unix philosophy of "everything is a text stream" breaks down when text contains metacharacters of the processing tool itself. See also: SQL injection (same category of confusion between data and code).
