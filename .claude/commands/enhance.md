---
name: enhance
description: Enhance a prompt for better outputs
agent: enhancing-prompts
agent_path: skills/enhancing-prompts
enhance: false  # Explicitly disable invisible enhancement to prevent recursion
---

# /enhance

Analyzes and enhances your prompt to improve output quality using the PTCF framework (Persona + Task + Context + Format).

## Usage

```
/enhance <your prompt here>
/enhance --analyze-only <prompt>
/enhance --task-type code_review <prompt>
```

## Options

| Option | Description |
|--------|-------------|
| `--analyze-only` | Show analysis without enhancement |
| `--task-type <type>` | Force a specific task type |

## Task Types

| Type | Use For |
|------|---------|
| `debugging` | Fixing errors, bugs, issues |
| `code_review` | Reviewing code quality |
| `refactoring` | Improving code structure |
| `summarization` | Condensing information |
| `research` | Investigating topics |
| `generation` | Creating new content |
| `general` | Everything else (fallback) |

## Examples

### Basic Enhancement

```
/enhance review the code
```

Output shows:
- Quality score before/after
- Detected components
- Task type classification
- Enhanced prompt with additions
- Suggestions for next time

### Analysis Only

```
/enhance --analyze-only review the code
```

Output shows analysis without enhancement - useful for learning.

### Force Task Type

```
/enhance --task-type security review auth.ts
```

Uses security-focused code review template.

## Quality Scoring

| Score | Quality |
|-------|---------|
| 0-1 | Invalid (no task verb) |
| 2-3 | Minimal (task only) |
| 4-5 | Acceptable (task + context) |
| 6-7 | Good (task + context + format) |
| 8-10 | Excellent (all components) |

## Configuration

See `.loa.config.yaml`:

```yaml
prompt_enhancement:
  enabled: true
  auto_enhance_threshold: 4
  show_analysis: true
```
