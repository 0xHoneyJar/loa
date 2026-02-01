# Ryan Carson's Auto-Compound Pattern (Concrete Implementation)

## The Two-Job Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   NIGHTLY COMPOUND CYCLE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   10:30 PM                           11:00 PM                    │
│   ┌─────────────────────┐           ┌─────────────────────┐     │
│   │ DAILY COMPOUND      │           │ AUTO COMPOUND       │     │
│   │ REVIEW              │──────────▶│ (Implementation)    │     │
│   │                     │  updated  │                     │     │
│   │ • Extract learnings │  AGENTS   │ • Clean slate       │     │
│   │ • Update AGENTS.md  │    .md    │ • Pick #1 priority  │     │
│   │                     │           │ • Create PRD        │     │
│   └─────────────────────┘           │ • Tasks → loop.sh   │     │
│                                     │ • Draft PR          │     │
│                                     └─────────────────────┘     │
│                                                                  │
│   KEY INSIGHT: Review job updates knowledge FIRST,               │
│   then implementation job benefits from fresh learnings.         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Job 1: Daily Compound Review (10:30 PM)

**Purpose**: Extract learnings from day's threads, update knowledge files.

**Flow**:
1. Scan day's work threads (Claude conversations, commits, PRs)
2. Extract patterns, mistakes, discoveries
3. Update AGENTS.md with new guidance
4. Log extraction to review history

**Output**: Updated AGENTS.md ready for next implementation job.

## Job 2: Auto-Compound (11:00 PM)

**Script Flow** (`auto-compound.sh`):

```bash
#!/bin/bash
# 1. Clean slate
git reset --hard origin/main

# 2. Find latest prioritized report
REPORT=$(ls -t reports/*.md | head -1)

# 3. Analyze and pick #1 priority
PRIORITY=$(./analyze-report.sh "$REPORT")

# 4. Create feature branch
git checkout -b "feature/$PRIORITY"

# 5. Create PRD for priority item
./create-prd.sh "$PRIORITY"

# 6. Convert PRD to tasks JSON
./prd-to-tasks.sh > tasks.json

# 7. Iterative execution (max 25 attempts per task)
./loop.sh 25

# 8. Create draft PR
gh pr create --draft --title "$PRIORITY"
```

## Scheduling (macOS launchd)

```xml
<!-- com.user.daily-compound-review.plist -->
<key>StartCalendarInterval</key>
<dict>
    <key>Hour</key><integer>22</integer>
    <key>Minute</key><integer>30</integer>
</dict>

<!-- com.user.auto-compound.plist -->
<key>StartCalendarInterval</key>
<dict>
    <key>Hour</key><integer>23</integer>
    <key>Minute</integer>0</integer>
</dict>
```

**caffeinate**: Keeps Mac awake during compound window.

## Mapping to Loa Infrastructure

| Ryan's Pattern | Loa Equivalent | Gap? |
|----------------|----------------|------|
| `reports/*.md` | `grimoires/loa/a2a/trajectory/*.jsonl` | Format differs (JSONL vs MD) |
| `analyze-report.sh` | `/retrospective` | Needs batch mode |
| `AGENTS.md` updates | `NOTES.md` + `skills-pending/` | No direct AGENTS.md update |
| `loop.sh 25` | `/run sprint-N` | Already exists ✅ |
| `launchd` scheduling | None | **GAP: No scheduler** |
| `create-prd.sh` | `/plan-and-analyze` | Already exists ✅ |
| `prd-to-tasks.sh` | `/sprint-plan` | Already exists ✅ |
| `gh pr create` | Manual | Could integrate |

## Key Gaps to Fill

### Gap 1: Scheduled Execution
Loa has no equivalent to launchd scheduling. Options:
- **A**: External cron/launchd calls `claude -p "/compound-review"`
- **B**: Built-in `/schedule` command that creates system jobs
- **C**: Heartbeat integration (if human is present)

### Gap 2: Two-Phase Ordering
The ORDER matters: review → update → implement. Loa needs:
- Clear job separation (review vs implement)
- Dependency enforcement (implement waits for review)
- Fresh knowledge loading at implement start

### Gap 3: AGENTS.md Updates
Loa writes to NOTES.md and skills/, not AGENTS.md directly. Options:
- **A**: Add AGENTS.md as a valid synthesis target (with approval)
- **B**: Skills get auto-consolidated into AGENTS.md guidance
- **C**: NOTES.md "Learnings" section serves same purpose

### Gap 4: Priority Selection
Ryan uses `analyze-report.sh` to pick #1 priority. Loa needs:
- Priority ranking in sprint plans or backlog
- Auto-selection logic for autonomous mode
- Integration with `/run` to pick next task

## Proposed Loa Implementation

### New Commands

```bash
# Phase 1: Compound Review (runs first)
/compound-review [--days N]
  - Scans trajectory logs from past N days
  - Extracts learnings using quality gates
  - Updates NOTES.md learnings section
  - Proposes AGENTS.md updates (with approval queue)
  - Logs review completion for Phase 2

# Phase 2: Compound Ship (runs second, depends on Phase 1)
/compound-ship [--priority ITEM]
  - Checks that compound-review ran today (or runs it)
  - Loads fresh learnings from NOTES.md
  - Creates feature branch
  - Either: picks #1 from backlog OR uses --priority
  - Runs: /plan-and-analyze → /architect → /sprint-plan → /run
  - Creates draft PR on success

# Orchestration: Run both in sequence
/compound [--review-only | --ship-only]
  - Default: runs review, then ship
  - --review-only: just extract learnings
  - --ship-only: skip review, use existing learnings
```

### Configuration (`.loa.config.yaml`)

```yaml
compound_learning:
  # Review settings
  review_lookback_days: 1          # How far back to scan
  agents_md_updates: proposal      # proposal | auto | disabled
  require_approval: true           # Human must approve AGENTS.md changes
  
  # Ship settings  
  auto_branch: true                # Create feature branch automatically
  max_task_attempts: 25            # loop.sh equivalent
  create_draft_pr: true            # Auto-create PR on success
  
  # Scheduling (external reference)
  schedule_review: "22:30"         # For documentation; actual schedule is external
  schedule_ship: "23:00"
  
  # Dependencies
  ship_requires_review: true       # Enforce ordering
  review_completion_file: ".loa-review-complete"
```

### External Scheduling Integration

Provide helper script for users to set up scheduling:

```bash
# .claude/scripts/setup-compound-schedule.sh

# Generates launchd plists (macOS) or cron entries (Linux)
# User runs once to enable nightly compound cycle

# macOS:
launchctl load ~/Library/LaunchAgents/com.loa.compound-review.plist
launchctl load ~/Library/LaunchAgents/com.loa.compound-ship.plist

# Linux:
# 30 22 * * * cd /path/to/project && claude -p "/compound-review"
# 0  23 * * * cd /path/to/project && claude -p "/compound-ship"
```

## Success Flow Example

```
22:30 - compound-review kicks off
        ├── Scans today's trajectory logs
        ├── Finds 3 debugging discoveries
        ├── Extracts 2 as skill candidates
        ├── Updates NOTES.md learnings
        ├── Proposes 1 AGENTS.md addition
        └── Writes .loa-review-complete

23:00 - compound-ship kicks off
        ├── Checks .loa-review-complete ✓
        ├── Loads fresh learnings from NOTES.md
        ├── Picks #1 priority from backlog
        ├── Creates branch: feature/add-user-auth
        ├── Runs full loa cycle with learnings applied
        └── Creates draft PR: "Add user authentication"

Next morning:
        └── Developer reviews PR with compound learnings applied
```

## Key Insight

> "The ORDER matters - review job updates knowledge files FIRST, 
> then implementation job benefits from those learnings."

This is the compound learning loop:
1. **Learn** (review extracts from past work)
2. **Apply** (ship uses fresh learnings)  
3. **Compound** (each cycle builds on previous)

Over time, AGENTS.md accumulates project-specific wisdom, and each nightly ship benefits from all previous learnings.
