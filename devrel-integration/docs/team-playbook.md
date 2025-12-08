# Team Playbook: Agentic-Base with Organizational Integration

**Document Version:** 1.0
**Last Updated:** 2025-12-07
**Audience:** All team members (developers, researchers, product owners)

## Overview

This playbook explains how to use the integrated agentic-base framework with your team's existing Discord, Linear, and GitHub workflows. Whether you're a code-literate developer or non-technical researcher, this guide shows you how to collaborate effectively with AI agents and team members.

## Quick Start by Role

### For Researchers/Product Owners

**What you do:** Provide feedback on designs, previews, and documentation

**Your workflow:**
1. Review artifacts (docs, Vercel previews, prototypes)
2. Post feedback naturally in Discord
3. See when your feedback is addressed
4. Test implementations and confirm fixes

**Key commands:**
- No commands needed for giving feedback - just post in Discord!
- `/my-notifications` - Configure when you want to be notified
- `/show-sprint` - See what the team is working on
- `/preview THJ-123` - Get link to test a specific feature

### For Developers

**What you do:** Implement features, run agents, review code

**Your workflow:**
1. Pick up Linear tasks assigned to you
2. Run `/implement THJ-123` to have agent help with implementation
3. Run `/review-sprint THJ-123` for automated code review
4. Address feedback, iterate, deploy

**Key commands:**
- `/implement THJ-123` - Start implementing a Linear task
- `/review-sprint THJ-123` - Get agent code review
- `/my-tasks` - See all your assigned Linear tasks
- `/show-sprint` - View full sprint status

## Daily Workflows

### Morning Routine (All Team Members)

1. **Check Discord #sprint-updates channel**
   - Daily digest posts at 9am with sprint status
   - See what's in progress, completed, blocked
   - See new feedback captured yesterday

2. **Review your notifications**
   - Tasks assigned to you
   - Feedback you provided that was addressed
   - Previews ready for testing

### Developer Morning Routine

```bash
# Check your assigned Linear tasks
Open Linear → Filter by "Assigned to: Me"

# Check sprint status in Discord
/show-sprint

# Check if any feedback needs addressing
Look for "Changes Requested" tasks in Linear

# Start working on a task
Assign yourself a Linear issue → /implement THJ-123
```

### Researcher Morning Routine

```
# Check daily digest in #sprint-updates
See what was completed yesterday

# Check for previews ready to test
Look for "Preview deployed" notifications

# Test previews and provide feedback
Visit Vercel preview URLs
Post feedback in Discord (no special format needed)
```

## Workflows by Scenario

### Scenario 1: Researcher Gives Feedback on a Preview

**Step 1: Researcher tests preview**
```
Researcher visits: https://myapp-abc123.vercel.app
Notices: "Login button is too small on mobile"
```

**Step 2: Researcher posts feedback in Discord**
```
In #design-feedback channel:

"The login button on the Vercel preview is too small on mobile.
I had to zoom in to click it. Can we make it bigger?
Preview: https://myapp-abc123.vercel.app"
```

**Step 3: Developer captures feedback**
```
Developer reacts to message with 📌 emoji
Bot replies: "✅ Feedback captured as draft Linear issue THJ-150"
```

**Step 4: Developer reviews and assigns**
```
Developer opens Linear → Reviews draft issues
Edits THJ-150 if needed → Publishes → Assigns to self
Linear status: Todo → In Progress
```

**Step 5: Developer implements fix**
```
Developer runs: /implement THJ-150

Agent:
- Reads Linear issue THJ-150
- Sees original Discord feedback context
- Implements larger login button
- Updates Linear status: In Progress → In Review
- Generates implementation report
```

**Step 6: Developer reviews and deploys**
```
Developer runs: /review-sprint THJ-150

Agent reviews code → Approves
Linear status: In Review → Done ✅
Developer creates PR → Merges → Vercel deploys
```

**Step 7: Researcher is notified**
```
Bot notifies researcher (per their preferences):
"✅ Your feedback on login button size has been addressed!
Preview: https://myapp-xyz789.vercel.app"
```

**Step 8: Researcher tests and confirms**
```
Researcher tests new preview
Posts: "Looks great, thanks! 👍"
```

### Scenario 2: Planning a New Sprint

**Step 1: Product discussions (Discord)**
```
Team discusses new features in Discord threads
Key decisions documented in Google Docs
```

**Step 2: Create PRD**
```
Developer runs: /plan-and-analyze

prd-architect agent:
- Asks discovery questions
- Generates docs/prd.md
```

**Step 3: Design architecture**
```
Developer runs: /architect

architecture-designer agent:
- Reads docs/prd.md
- Generates docs/sdd.md with technical design
```

**Step 4: Break down into sprint tasks**
```
Developer runs: /sprint-plan

sprint-planner agent:
- Reads docs/prd.md and docs/sdd.md
- Generates docs/sprint.md
- Creates draft Linear issues (THJ-201, THJ-202, etc.)
- Embeds Linear IDs in docs/sprint.md

Example sprint.md output:

## Sprint 1: Core Authentication

### Sprint 1, Task 1: Set up authentication database schema
**Linear Issue:** THJ-201
**Status:** Draft
**Assignee:** Unassigned
**Estimated Effort:** 2 days

### Sprint 1, Task 2: Implement JWT token generation
**Linear Issue:** THJ-202
**Status:** Draft
**Assignee:** Unassigned
**Estimated Effort:** 1 day
```

**Step 5: Team reviews and assigns tasks**
```
Team reviews draft Linear issues in Linear workspace
Developers edit descriptions if needed
Publish issues (remove "draft" label)
Assign tasks to team members
```

**Step 6: Start implementing**
```
Developer 1: Assigns THJ-201 → /implement THJ-201
Developer 2: Assigns THJ-202 → /implement THJ-202

Both work concurrently without conflicts
Linear shows who's working on what
Daily digest shows progress
```

### Scenario 3: Developer Implements a Task

**Step 1: Assign task in Linear**
```
Developer opens Linear
Finds task: THJ-125 "Implement user profile API"
Clicks "Assign to me"
Linear status: Todo → In Progress (automatic)
```

**Step 2: Run implementation agent**
```
Developer runs: /implement THJ-125

sprint-task-implementer agent:
1. Reads Linear API for THJ-125:
   - Description, acceptance criteria
   - Any dependencies or blockers
   - Original feedback context if present
2. Checks for previous review feedback in docs/a2a/engineer-feedback.md
3. Implements the feature:
   - Writes code
   - Runs tests
   - Validates acceptance criteria
4. Generates implementation report: docs/a2a/reviewer.md
5. Updates Linear status: In Progress → In Review
```

**Step 3: Review implementation**
```
Developer runs: /review-sprint THJ-125

senior-tech-lead-reviewer agent:
1. Reviews code against acceptance criteria
2. Checks test coverage
3. Validates best practices

IF APPROVED:
  - Writes "All good" to docs/a2a/engineer-feedback.md
  - Updates Linear status: In Review → Done
  - Marks docs/sprint.md task with ✅

IF CHANGES NEEDED:
  - Writes detailed feedback to docs/a2a/engineer-feedback.md
  - Updates Linear status: In Review → Changes Requested
```

**Step 4: Address feedback if needed**
```
IF changes were requested:

Developer reads docs/a2a/engineer-feedback.md
Runs: /implement THJ-125 again

Agent:
- Reads previous feedback
- Addresses each issue
- Generates updated report
- Updates Linear: Changes Requested → In Review

Developer runs: /review-sprint THJ-125 again
Repeat until approved
```

**Step 5: Create PR and deploy**
```
After agent approval:

Developer creates GitHub PR
Human teammate reviews (optional additional review)
Merge to main
Vercel deploys automatically
```

### Scenario 4: Two Developers Work Concurrently

**Developer A:**
```
Assigns Linear issue THJ-301 "Payment integration"
Runs: /implement THJ-301
Works on payment code...
```

**Developer B:**
```
Assigns Linear issue THJ-302 "Email notifications"
Runs: /implement THJ-302
Works on email code...
```

**No conflicts because:**
- Linear shows each task is "In Progress" with assignee
- Daily digest shows both tasks with assignees
- `/show-sprint` in Discord shows real-time status
- Different tasks touch different code files

**Coordination:**
```
Daily digest at 9am:

📊 Daily Sprint Update

🚀 In Progress (2 tasks)
• THJ-301: Payment integration - @alice (since 10h ago)
• THJ-302: Email notifications - @bob (since 6h ago)

Both developers see each other's progress without manual updates
```

## Discord Commands Reference

### For Everyone (Researchers + Developers)

#### `/show-sprint`
**What it does:** Shows current sprint status summary

**Example:**
```
You: /show-sprint

Bot replies:
📊 Sprint Status - Sprint 1: Core Auth

🚀 In Progress (3 tasks)
• THJ-201: Database schema - @alice (2d)
• THJ-202: JWT tokens - @bob (1d)
• THJ-203: Password reset - @charlie (4h)

✅ Completed (2 tasks)
• THJ-199: Setup project
• THJ-200: Configure ESLint

🔄 In Review (1 task)
• THJ-198: Login UI - @alice

⚠️ Blocked (0 tasks)

Use /task <ID> for details on any task.
```

#### `/preview <issue-id>`
**What it does:** Get Vercel preview URL for a task

**Example:**
```
You: /preview THJ-201

Bot replies:
🚀 Preview for THJ-201: Database schema
https://myapp-abc123.vercel.app

Status: In Progress by @alice
Last updated: 2 hours ago
```

#### `/doc <type>`
**What it does:** Get link to project documents

**Options:** `prd`, `sdd`, `sprint`

**Example:**
```
You: /doc prd

Bot replies:
📄 Product Requirements Document
Path: docs/prd.md

View in GitHub or open locally.
```

#### `/task <issue-id>`
**What it does:** Show summary of a Linear task

**Example:**
```
You: /task THJ-201

Bot replies:
📋 THJ-201: Set up authentication database schema

Status: In Progress
Assignee: @alice
Started: 2 days ago
Sprint: Sprint 1

Description:
Create database schema for user authentication including
users, sessions, and password reset tokens.

Acceptance Criteria:
✅ Schema includes users table
✅ Schema includes sessions table
⬜ Schema includes password_reset_tokens table
⬜ Migrations are tested

View in Linear: https://linear.app/team/issue/THJ-201
```

#### `/my-notifications`
**What it does:** Configure your notification preferences

**Example:**
```
You: /my-notifications

Bot replies:
📬 Your Notification Preferences

Daily Digest: ✅ Enabled (9am in #sprint-updates)
My Feedback Updates: ✅ Enabled
Vercel Previews: ✅ Enabled
Review Requests: ❌ Disabled

React to change:
📊 = Toggle daily digest
🔔 = Toggle feedback updates
🚀 = Toggle Vercel previews
👀 = Toggle review requests

Or use commands:
/notifications digest off
/notifications feedback-updates on
```

#### Natural Language Queries
**What it does:** Ask questions naturally, bot detects intent

**Examples:**
```
You: "What's the status on the login work?"

Bot: 🔍 Found these login-related tasks:
• THJ-198: Login UI - In Review by @alice
• THJ-201: Login API - In Progress by @bob

---

You: "Is the dashboard ready to test?"

Bot: 🔍 Dashboard preview is ready:
• THJ-205: Dashboard UI - Done ✅
Preview: https://myapp-xyz789.vercel.app
```

### For Developers Only

#### `/my-tasks`
**What it does:** Show all Linear tasks assigned to you

**Example:**
```
You: /my-tasks

Bot replies:
📋 Your Tasks (3 active)

In Progress:
• THJ-201: Database schema (2d ago)

In Review:
• THJ-198: Login UI (4h ago)

Todo:
• THJ-210: Add error handling (not started)

Use /implement <ID> to work on a task.
```

#### `/implement-status <issue-id>`
**What it does:** Check if someone is already working on a task

**Example:**
```
You: /implement-status THJ-201

Bot replies:
🔍 Implementation Status for THJ-201

Current Status: In Progress
Assigned to: @alice
Started: 2 days ago
Last activity: 30 minutes ago

⚠️ This task is actively being worked on.
Consider coordinating with @alice before starting.
```

#### `/feedback @user`
**What it does:** Show all captured feedback from a specific user

**Example:**
```
You: /feedback @researcher

Bot replies:
📌 Captured Feedback from @researcher (3 items)

1. THJ-145: Login button too small (In Progress)
2. THJ-150: Color contrast issue (Done ✅)
3. THJ-155: Navigation confusing (Draft)

Use /task <ID> for details.
```

## Best Practices

### For Researchers

**✅ DO:**
- Post feedback naturally in Discord (no special format needed)
- Include URLs of what you're testing (Vercel previews, docs)
- Attach screenshots or recordings when helpful
- Test previews when notified and confirm fixes
- Ask questions using natural language or `/show-sprint`

**❌ DON'T:**
- Don't worry about Linear - developers will handle task creation
- Don't use technical jargon - describe issues in plain language
- Don't wait to batch feedback - post as you find issues
- Don't delete your feedback messages - they become permanent record

**Example Good Feedback:**
```
"The signup form on https://myapp-abc123.vercel.app doesn't
work on my iPhone. When I tap 'Submit' nothing happens.
Chrome on iOS, latest version."

📎 screen-recording.mp4
```

**Example Unclear Feedback:**
```
"Signup is broken"

(No context, no URL, no device info)
```

### For Developers

**✅ DO:**
- Assign yourself tasks in Linear before running `/implement`
- Check `/show-sprint` or Linear before starting work (avoid conflicts)
- React with 📌 to capture actionable researcher feedback
- Run `/review-sprint` before creating PRs
- Address agent feedback iteratively (re-run `/implement` after changes)
- Keep Linear status updated (agents do this automatically)

**❌ DON'T:**
- Don't implement tasks assigned to other developers without coordinating
- Don't skip the agent review step - it catches issues early
- Don't ignore feedback in `docs/a2a/engineer-feedback.md`
- Don't manually update sprint.md status (agents handle this)
- Don't work directly in sprint.md - use Linear as source of truth

**Example Good Workflow:**
```
1. Linear: Assign THJ-201 to self
2. CLI: /implement THJ-201
3. Agent implements, generates report
4. CLI: /review-sprint THJ-201
5. If approved: Create PR, merge
6. If changes needed: Read feedback, run /implement THJ-201 again
```

### For the Whole Team

**Communication:**
- Use Discord for real-time discussions and feedback
- Use Google Docs for design documents that need collaboration
- Use Linear for task tracking and assignment
- Let agents handle status updates (don't duplicate effort)

**Visibility:**
- Check daily digest every morning for team awareness
- Use `/show-sprint` when you need real-time status
- Configure `/my-notifications` to your preference (not too noisy)

**Feedback Loops:**
- Researcher feedback should be captured within 24 hours (📌 reaction)
- Developer should review captured feedback drafts daily
- Agent review feedback should be addressed within 1 sprint cycle

## Notification Settings Guide

### Default Settings (Recommended for Most Users)

**Researchers:**
- Daily Digest: ✅ Enabled
- My Feedback Updates: ✅ Enabled (when your feedback is addressed)
- Vercel Previews: ✅ Enabled (when previews are ready to test)
- Review Requests: ❌ Disabled (not applicable)

**Developers:**
- Daily Digest: ✅ Enabled
- My Feedback Updates: ❌ Disabled (you see this in Linear)
- Vercel Previews: ✅ Enabled
- Review Requests: ✅ Enabled (if you're a designated reviewer)

### Adjusting Notification Frequency

**If daily digest feels too noisy:**
```
/notifications digest off
```
You can still check `/show-sprint` anytime on-demand.

**If you want to be notified immediately about critical issues:**
```
# Immediate alerts are configured globally, not per-user
# Ask a developer to enable in integration/config/discord-digest.yml
```

**If you're going on vacation:**
```
/notifications feedback-updates off
/notifications vercel-previews off

(Keep digest on for catching up when you return)
```

## Troubleshooting

### "Bot doesn't respond to my commands"

**Check:**
1. Did you type the command correctly? (e.g., `/show-sprint` not `/show sprint`)
2. Is the bot online? (Check member list in Discord)
3. Does the bot have permissions in this channel?

**Fix:**
- Try the command again in #general or #sprint-updates channel
- Ask a developer to check bot logs

### "📌 reaction doesn't create Linear issue"

**Check:**
1. Did you react to your own message or someone else's?
2. Is there already a 📌 on that message?

**Fix:**
- Try removing and re-adding the 📌 reaction
- Check with developer if issue was created but bot didn't reply
- Developer can check logs: `integration/logs/discord-bot.log`

### "I didn't receive a notification I expected"

**Check:**
1. Your notification preferences: `/my-notifications`
2. The event type (feedback update, preview, etc.)

**Fix:**
- Adjust your preferences with `/notifications <type> on`
- Check #sprint-updates for daily digest
- Ask developer to verify event was triggered

### "Daily digest is missing information"

**Issue:** Digest shows "0 tasks" but Linear has tasks

**Likely cause:** Bot can't access Linear or config is wrong

**Fix:**
- Developer should check `integration/logs/discord-bot.log`
- Verify Linear API token is valid
- Check `integration/config/linear-sync.yml` team ID

### "/implement THJ-123 fails"

**Check:**
1. Is THJ-123 a valid Linear issue ID?
2. Is the task assigned to you in Linear?
3. Has the task been published (not a draft)?

**Fix:**
- Open Linear and verify the issue exists
- Assign the issue to yourself in Linear
- If draft, publish it first
- Check agent logs for specific error

## FAQ

### General Questions

**Q: Do I need to learn Linear if I'm a researcher?**
A: No! Just post feedback in Discord. Developers handle Linear.

**Q: Can I use the bot in DMs?**
A: Some commands work in DMs (like `/my-notifications`), but feedback capture requires messages in server channels.

**Q: What happens if two developers try to implement the same task?**
A: The second developer will get a warning from the agent that the task is already assigned/in-progress. Check `/implement-status THJ-123` before starting.

**Q: Can I turn off all notifications?**
A: Yes, use `/notifications digest off` and disable all update types. You can still use commands on-demand.

**Q: Where do I find old feedback I posted?**
A: Search Discord message history, or ask developer to run `/feedback @your-username`.

### Developer Questions

**Q: Do I still need to do human code review after agent review?**
A: Agent review catches common issues, but human review on GitHub PRs is still recommended for architectural decisions and team knowledge sharing.

**Q: What if the agent's implementation is wrong?**
A: Review the code manually. If needed, ask the reviewer agent for changes, or make manual edits. Agent is a helper, not a replacement for judgment.

**Q: Can I work on tasks not in Linear?**
A: Yes, but they won't be tracked in daily digest or sprint.md. For ad-hoc work, just create a PR directly.

**Q: What if I want to split a Linear task into subtasks?**
A: Create subtasks in Linear, then run `/implement` on each subtask separately.

**Q: How do I handle urgent hotfixes?**
A: Create a Linear issue with "urgent" or "hotfix" label, assign to yourself, run `/implement THJ-XXX`. Skip agent review if needed, but do human PR review.

### Workflow Questions

**Q: When should I run `/review-sprint`?**
A: After `/implement` completes and you've done a quick manual check. Agent review is fast and catches issues before human review.

**Q: Can I edit docs/sprint.md manually?**
A: You can, but Linear is the source of truth. Agents read from Linear, not sprint.md. Manual edits may be overwritten.

**Q: What if Linear and sprint.md get out of sync?**
A: Run the sync script: `npm run sync:linear-to-sprint` (see tool-setup.md). Or regenerate sprint.md from Linear.

**Q: How long does `/implement` take?**
A: Varies by task complexity. Simple tasks: 5-10 minutes. Complex tasks: 30-60 minutes. Agent works faster than human but still needs time to understand context.

## Team Rituals

### Daily Standup (9:05am)

**Format (5-10 minutes):**
1. Everyone reads daily digest in #sprint-updates (posted at 9am)
2. Each person shares:
   - Yesterday: What did you complete? (refer to digest)
   - Today: What will you work on? (check Linear assignments)
   - Blockers: Anything preventing progress?

**Example:**
```
Alice: Yesterday I completed THJ-201 (database schema). Today I'm
picking up THJ-210 (error handling). No blockers.

Bob: Yesterday I worked on THJ-202 (JWT tokens), got reviewer
feedback. Today I'm addressing that feedback and should finish.
No blockers.

Researcher: I tested the login preview from yesterday and captured
feedback on the button size. Today I'll test the signup flow when
it's ready. No blockers.
```

### Sprint Planning (Every 2 weeks)

**Agenda (1-2 hours):**
1. Review last sprint (what was completed, what wasn't)
2. Run `/plan-and-analyze` for new features (if needed)
3. Run `/architect` to design new features
4. Run `/sprint-plan` to break down into tasks
5. Team reviews draft Linear issues together
6. Assign tasks to team members
7. Publish issues and start sprint

### Sprint Review (End of sprint)

**Agenda (1 hour):**
1. Demo completed features to team + researcher
2. Researcher tests live previews
3. Collect final feedback
4. Retrospective: What went well? What to improve?
5. Update configs if needed (notification settings, digest format, etc.)

### Weekly Feedback Triage (30 minutes)

**Developer responsibility:**
1. Review all draft Linear issues (📌 captured feedback)
2. Decide: Keep as-is, merge with existing, or discard
3. Publish validated issues
4. Assign to appropriate sprint or backlog

## Customization

### Adjusting Daily Digest

Edit `integration/config/discord-digest.yml`:

**Change posting time:**
```yaml
schedule: "0 14 * * *"  # 2pm daily instead of 9am
```

**Change detail level:**
```yaml
detail_level: "summary"  # Options: minimal, summary, full
```

**Hide sections:**
```yaml
sections:
  in_progress: true
  completed_today: false  # Don't show completed tasks
  in_review: true
  blockers: true
```

### Adding New Commands

Edit `integration/config/bot-commands.yml`:

```yaml
my_custom_command:
  enabled: true
  description: "Your custom command description"
  usage: "/my-custom-command [args]"
```

Then implement in `integration/src/handlers/commands.ts`.

### Creating Team-Specific Channels

**Recommended Discord channels:**
- `#sprint-updates` - Daily digest and sprint status
- `#design-feedback` - Researcher feedback on UX/UI
- `#tech-discussions` - Architecture and technical decisions
- `#bot-commands` - Testing bot commands without noise

Configure channels in `integration/config/discord-digest.yml` and `review-workflow.yml`.

## Getting Help

**For non-technical questions:**
- Ask in Discord #general channel
- Check this playbook first
- Ask a developer if unclear

**For technical issues:**
- Check troubleshooting section above
- Check tool-setup.md for configuration issues
- Developer: Check `integration/logs/discord-bot.log`

**For feature requests:**
- Discuss with team in Discord
- Propose config changes in team meeting
- Developer can update configs without code changes

## Appendix: Command Quick Reference Card

Print or bookmark this for easy reference:

```
╔══════════════════════════════════════════════════════════╗
║          Agentic-Base Discord Bot Commands               ║
╠══════════════════════════════════════════════════════════╣
║ FOR EVERYONE                                             ║
║ /show-sprint          View sprint status                 ║
║ /preview THJ-123      Get Vercel preview URL             ║
║ /doc prd|sdd|sprint   Link to documents                  ║
║ /task THJ-123         Task details                       ║
║ /my-notifications     Configure notifications            ║
║                                                           ║
║ FOR DEVELOPERS                                           ║
║ /implement THJ-123    Start implementing task            ║
║ /review-sprint THJ-123  Get agent code review            ║
║ /my-tasks             Your assigned tasks                ║
║ /implement-status THJ-123  Check task status             ║
║ /feedback @user       Show captured feedback             ║
║                                                           ║
║ SPECIAL ACTIONS                                          ║
║ React with 📌        Capture feedback to Linear          ║
║                                                           ║
║ Need help? Ask in #general or check docs/team-playbook  ║
╚══════════════════════════════════════════════════════════╝
```

---

**Next Steps:**
1. ✅ Complete tool setup (see `docs/tool-setup.md`)
2. ✅ Review this playbook with your team
3. ✅ Configure your notification preferences: `/my-notifications`
4. ✅ Try the workflow on a pilot sprint (see `docs/adoption-plan.md`)
5. ✅ Iterate and adjust configs based on team feedback

**Feedback on this playbook?** Post in Discord or open an issue in this repo!
