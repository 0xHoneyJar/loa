# Discovery Context

Place any existing documentation here before running `/plan-and-analyze`.
The PRD architect will read these files and only ask questions about gaps.

## Suggested Files (all optional)

| File | Contents |
|------|----------|
| `vision.md` | Product vision, mission, problem statement, goals |
| `users.md` | User personas, research findings, interview notes |
| `requirements.md` | Feature lists, user stories, acceptance criteria |
| `technical.md` | Tech stack preferences, constraints, integrations |
| `competitors.md` | Competitive analysis, market positioning |
| `meetings/*.md` | Stakeholder interview notes, meeting summaries |

## Directory Structure

```
grimoires/loa/context/
├── README.md           # This file
├── vision.md           # Product vision, mission, goals
├── users.md            # User personas, research, interviews
├── requirements.md     # Existing requirements, feature lists
├── technical.md        # Technical constraints, stack preferences
├── competitors.md      # Competitive analysis, market research
├── meetings/           # Meeting notes, stakeholder interviews
│   ├── kickoff.md
│   └── stakeholder-interview.md
└── references/         # External docs, specs, designs
    └── *.*
```

## Tips

- **Raw notes are fine** - Claude will synthesize and organize
- **Include contradictions** - Claude will ask for clarification
- **More context = fewer questions** - The more you provide, the less you'll be asked
- **Empty directory = full interview** - That's okay too!
- **Nested directories supported** - Organize however makes sense

## What Happens

When you run `/plan-and-analyze`:

1. Claude scans this directory for `.md` files
2. Reads and categorizes content by discovery phase
3. Presents a summary of what was learned (with citations)
4. Only asks questions about gaps or ambiguities
5. Generates PRD with full source tracing

## Example

If you have a `vision.md` with your product vision, Claude will:

```markdown
## What I've Learned From Your Documentation

### Problem & Vision
> From vision.md:12-15: "We're building a platform that..."

I understand the core problem is [X]. The vision is [Y].

### What I Still Need to Understand
1. **Success Metrics**: What outcomes define success?
2. **Timeline**: Key milestones and deadlines?

Should I proceed with these clarifying questions?
```
