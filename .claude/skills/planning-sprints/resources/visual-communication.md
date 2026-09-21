# Visual Communication

Follow `.claude/protocols/visual-communication.md` for diagram standards.

## When to Include Diagrams

Sprint plans may benefit from visual aids for:
- **Task Dependencies** (flowchart) - Show task blocking relationships
- **Sprint Workflow** (flowchart) - Illustrate sprint execution flow

## Output Format

If including diagrams, use Mermaid with preview URLs:

```markdown
## Appendix A: Task Dependencies

```mermaid
graph TD
    T1[Task 1.1] --> T2[Task 1.2]
    T1 --> T3[Task 1.3]
    T2 --> T4[Task 1.4]
    T3 --> T4
```

> **Preview**: [View diagram](https://agents.craft.do/mermaid?code=...&theme=github)
```

## Theme Configuration

Read theme from `.loa.config.yaml` visual_communication.theme setting.

Diagram inclusion is optional for sprint plans - use agent discretion.
