---
parallel_threshold: 2000
timeout_minutes: 480
zones:
  system:
    path: .claude
    permission: read
  state:
    paths: [grimoires/loa, .beads, .run]
    permission: read-write
  app:
    paths: [src, lib, app]
    permission: read-write
---

# Run Bridge — Autonomous Excellence Loop

## Overview

The Run Bridge skill orchestrates an iterative improvement loop:

1. Execute sprint plan via `/run sprint-plan`
2. Invoke Bridgebuilder review on the resulting changes
3. Parse findings into structured JSON
4. Generate a new sprint plan from findings
5. Repeat until findings "flatline" (kaironic termination)

Each iteration leaves a GitHub trail (PR comments, vision links) and captures
speculative insights in the Vision Registry. On completion, Grounded Truth is
regenerated and RTFM validation runs as a final gate.

## Workflow

### Phase 0: Input Guardrails

Check danger level (high) — requires explicit opt-in:
- `run_bridge.enabled: true` in `.loa.config.yaml`
- Not on a protected branch

### Phase 1: Argument Parsing

| Argument | Flag | Default |
|----------|------|---------|
| depth | `--depth N` | 3 (max 5) |
| per_sprint | `--per-sprint` | false |
| resume | `--resume` | false |
| from | `--from PHASE` | — |

### Phase 2: Orchestrator Invocation

Invoke `bridge-orchestrator.sh` with translated flags:

```bash
.claude/scripts/bridge-orchestrator.sh \
  --depth "$depth" \
  ${per_sprint:+--per-sprint} \
  ${resume:+--resume} \
  ${from:+--from "$from"}
```

The orchestrator manages the state machine:

```
PREFLIGHT → JACK_IN → ITERATING ↔ ITERATING → FINALIZING → JACKED_OUT
                         ↓                        ↓
                       HALTED                    HALTED
```

### Phase 3: Iteration Loop

For each iteration, the orchestrator emits SIGNAL lines that this skill
interprets and acts on:

| Signal | Action |
|--------|--------|
| `GENERATE_SPRINT_FROM_FINDINGS` | Create sprint plan from parsed findings |
| `RUN_SPRINT_PLAN` | Execute `/run sprint-plan` |
| `RUN_PER_SPRINT` | Execute per-sprint mode |
| `BRIDGEBUILDER_REVIEW` | Invoke Bridgebuilder on changes |
| `VISION_CAPTURE` | Check findings for VISION/SPECULATION severity → invoke `bridge-vision-capture.sh` (gated by `vision_registry.bridge_auto_capture`) |
| `GITHUB_TRAIL` | Run `bridge-github-trail.sh` |
| `FLATLINE_CHECK` | Evaluate flatline condition |
| `LORE_DISCOVERY` | Run `lore-discover.sh` → call `vision_check_lore_elevation()` for visions with refs > 0 (v1.42.0) |

#### VISION_CAPTURE → LORE_DISCOVERY Chain (v1.42.0)

After `BRIDGEBUILDER_REVIEW` completes and findings are parsed:

1. **VISION_CAPTURE** (conditional):
   - Only fires when `vision_registry.bridge_auto_capture: true` in `.loa.config.yaml`
   - Filters parsed findings for VISION or SPECULATION severity
   - Invokes `bridge-vision-capture.sh` with findings JSON path
   - Creates vision entries in `grimoires/loa/visions/entries/`
   - Updates `grimoires/loa/visions/index.md`

2. **LORE_DISCOVERY** (always after VISION_CAPTURE):
   - Invokes `lore-discover.sh` to extract patterns from bridge reviews
   - Sources `vision-lib.sh` and calls `vision_check_lore_elevation()` for each vision with `refs > 0`
   - If elevation threshold met, calls `vision_generate_lore_entry()` and `vision_append_lore_entry()`
   - Logs elevation events to trajectory JSONL

Data flow: `bridge finding JSON → vision entry → index update → lore elevation check`

### Phase 3.1: Enriched Bridgebuilder Review

When the `BRIDGEBUILDER_REVIEW` signal fires, execute this 10-step workflow:

1. **Persona Integrity Check**: Read persona path from config
   (`yq '.run_bridge.bridgebuilder.persona_path' .loa.config.yaml`, default: `.claude/data/bridgebuilder-persona.md`).
   Compare `sha256sum <persona_path>` against the base-branch version
   (`git show origin/main:<persona_path> | sha256sum`).
   If hashes differ, log WARNING and fall back to the base-branch version.
   If base-branch version doesn't exist (first deployment), proceed with local copy.

2. **Persona Content Validation**: Verify all 5 required sections exist and are non-empty:
   - `# Bridgebuilder`
   - `## Identity`
   - `## Voice`
   - `## Review Output Format`
   - `## Content Policy`
   If any section is missing or empty, log WARNING and disable persona enrichment for
   this iteration (fall back to unadorned review).

3. **Lore Load**: Query lore index for relevant entries from both discovered
   patterns AND elevated visions (closing the autopoietic loop):
   ```bash
   categories=$(yq '.run_bridge.lore.categories[]' .loa.config.yaml 2>/dev/null)
   # Load from both patterns.yaml (discovered patterns) and visions.yaml (elevated visions)
   ```
   Load `short` fields inline in the review prompt. Use `context` for teaching moments.
   The visions.yaml source ensures that insights which accumulated enough references
   through the vision registry feed back into future bridge reviews.

4. **Embody Persona**: Include the persona file content in the review prompt as the
   agent's identity and voice instructions. The persona defines HOW to review, not
   WHAT to review.

5. **Dual-Stream Review**: The review agent produces two streams:
   - **Findings stream**: Structured JSON inside `<!-- bridge-findings-start/end -->` markers.
     Includes enriched fields (`faang_parallel`, `metaphor`, `teachable_moment`, `connection`)
     and PRAISE findings when warranted.
   - **Insights stream**: Rich prose surrounding the findings block — opening context,
     architectural meditations, FAANG parallels, closing reflections.

6. **Save Full Review**: Write complete review (both streams) to
   `.run/bridge-reviews/{bridge_id}-iter{N}-full.md` with 0600 permissions.

7. **Size Enforcement** (SDD 3.5.1):
   - Body ≤ 65KB: post as-is
   - Body > 65KB: truncate prose, preserve findings JSON block
   - Body > 256KB: extract findings-only fallback

8. **Content Redaction** (SDD 3.5.2, Flatline SKP-006): Apply `redact_security_content()`
   with gitleaks-inspired patterns (AWS AKIA, GitHub ghp_/gho_/ghs_/ghr_, JWT eyJ,
   generic secrets). Allowlist protects sha256 hashes in markers and base64 diagram URLs.

9. **Post-Redaction Safety Check** (Flatline SKP-006): Scan redacted output for known
   secret prefixes (`ghp_`, `gho_`, `AKIA`, `eyJ`). If any remain, **block posting**
   and log error with line reference. The full review is still available in `.run/`.

10. **Parse + Post**: Parse findings via `bridge-findings-parser.sh` (JSON path with
    legacy fallback), then post via `bridge-github-trail.sh comment`.

### Phase 4: Finalization

After loop termination (flatline or max depth):

1. **Ground Truth Update**: Run `ground-truth-gen.sh --mode checksums`
2. **RTFM Gate**: Test GT index.md, README.md, new protocol docs
   - All PASS → continue
   - FAILURE → generate 1 fix sprint, re-test (max 1 retry)
   - Second FAILURE → log warning, continue
3. **Final PR Update**: Update PR body with complete bridge summary

### Phase 5: Progress Reporting

Report final metrics from `.run/bridge-state.json`:
- Total iterations completed
- Total sprints executed
- Total files changed
- Total findings addressed
- Total visions captured
- Flatline status

## Configuration

```yaml
run_bridge:
  enabled: true
  defaults:
    depth: 3
    per_sprint: false
    flatline_threshold: 0.05
    consecutive_flatline: 2
  timeouts:
    per_iteration_hours: 4
    total_hours: 24
  github_trail:
    post_comments: true
    update_pr_body: true
  ground_truth:
    enabled: true
  vision_registry:
    enabled: true
    auto_capture: true
  rtfm:
    enabled: true
    max_fix_iterations: 1
  lore:
    enabled: true
    categories:
      - mibera
      - neuromancer
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "run_bridge.enabled is not true" | Config not set | Set `run_bridge.enabled: true` |
| "Cannot run bridge on protected branch" | On main/master | Switch to feature branch |
| "Sprint plan not found" | Missing sprint.md | Run `/sprint-plan` first |
| "Per-iteration timeout exceeded" | Single iteration too slow | Reduce sprint scope |
| "Total timeout exceeded" | Overall time limit hit | Resume with `/run-bridge --resume` |

## Constraints

- C-BRIDGE-001: ALWAYS use `/run sprint-plan` within bridge iterations
- C-BRIDGE-002: ALWAYS post Bridgebuilder review as PR comment
- C-BRIDGE-003: ALWAYS ensure GT claims cite file:line references
- C-BRIDGE-004: ALWAYS use YAML format for lore entries
- C-BRIDGE-005: ALWAYS include source bridge iteration and PR in vision entries
