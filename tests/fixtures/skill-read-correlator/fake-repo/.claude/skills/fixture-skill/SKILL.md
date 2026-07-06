---
name: fixture-skill
description: "Synthetic skill used only by tests/unit/skill-resource-read-correlator.bats"
inputs:
  - path: CLAUDE.md
    why: fixture declared input that IS read in the synthetic transcript
  - path: notes.md
    why: fixture declared input that is NEVER read in the synthetic transcript
---

Body content is irrelevant to the correlator — it never parses SKILL.md
bodies, only the `inputs:` frontmatter list and the resources/ directory
listing.
