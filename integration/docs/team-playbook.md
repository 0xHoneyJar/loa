# DevRel Integration Team Playbook

This playbook provides usage instructions for all team members on how to use the DevRel integration system to generate and consume stakeholder communications.

---

## Table of Contents

1. [System Overview](#system-overview)
2. [For All Team Members](#for-all-team-members)
3. [For Product Manager](#for-product-manager)
4. [For Executives (COO, Head of BD)](#for-executives-coo-head-of-bd)
5. [For Marketing Team](#for-marketing-team)
6. [For Data Analytics Team](#for-data-analytics-team)
7. [Weekly Digest Workflow](#weekly-digest-workflow)
8. [Best Practices](#best-practices)
9. [FAQs](#faqs)

---

## System Overview

### What is the DevRel Integration?

The DevRel integration automatically transforms technical documentation (PRDs, SDDs, sprint updates, audit reports) into accessible stakeholder communications. It generates:

- **Weekly digests**: Executive summaries of what shipped and why it matters
- **On-demand summaries**: Request custom format translations anytime
- **Department-specific formats**: Auto-adjusted for your role and technical level
- **Layered documentation**: Summaries link to fuller docs for deep dives

### How Does It Work?

1. **Technical docs are created**: Engineers/PMs write PRDs, SDDs, sprint updates in Google Docs
2. **Weekly digest generation**: Every Friday, the system scans for changed docs and generates summaries
3. **Review and discussion**: Summaries posted to Discord #exec-summary channel as threads
4. **Approval and distribution**: PM reviews, team discusses, PM approves (✅ reaction)
5. **Optional blog publishing**: Approved summaries can be published to Mirror/company blog

### Key Benefits

- ✅ **Proactive information sharing**: No more waiting for someone to write a summary
- ✅ **Right technical level**: Auto-adjusted for your role (exec = business-focused, analytics = technical)
- ✅ **Centralized communication**: One place (#exec-summary) for all stakeholder updates
- ✅ **Self-service**: Request custom summaries anytime with `/generate-summary`
- ✅ **Educational pipeline**: Technical work becomes tutorials, blogs, and learning materials

---

## For All Team Members

### Reading Weekly Digests

**Every Friday at 9am UTC**, a new weekly digest is posted to Discord **#exec-summary** channel.

#### How to Access

1. Open Discord
2. Navigate to **#exec-summary** channel
3. Look for the latest thread: "Weekly Digest - [date]"
4. Click the thread to read the summary

#### What You'll See

```
📋 Weekly Digest - December 13, 2025

Summary of this week's technical work:

🚀 Features Shipped:
- User authentication system (OAuth2 + JWT)
- Dashboard analytics integration
- API rate limiting

🏗️ Projects Completed:
- Sprint 3: Authentication & Security
- Infrastructure: Production deployment pipeline

📖 Read full details: https://docs.google.com/document/d/...

---
Discuss this summary in this thread 💬
```

#### Taking Action

- **Read the summary**: Get the high-level overview (500-700 words)
- **Click the Google Doc link**: Read the full detailed summary if interested
- **Ask questions**: Reply in the Discord thread with clarifying questions
- **Request custom format**: If you need different technical depth, use `/generate-summary --format=<your-dept>`

---

### Requesting On-Demand Summaries

You can generate custom summaries anytime using Discord commands.

#### Basic Command

```bash
/generate-summary
```

**What happens**: System auto-detects your department and generates appropriate format

#### Advanced Commands

```bash
# Generate specific format (override auto-detection)
/generate-summary --format=executive

# Generate for specific documents
/generate-summary --docs=sprint.md,prd.md

# Combine flags
/generate-summary --format=marketing --docs=feature-x.md
```

#### Available Formats

| Format | Technical Level | Length | Best For |
|--------|----------------|--------|----------|
| `executive` | Low (business-focused) | 1 page | COO, Head of BD, leadership |
| `marketing` | Low (customer-friendly) | 1 page | Marketing team, positioning |
| `product` | Medium (user-focused) | 2 pages | Product managers, PMs |
| `engineering` | High (technical deep-dive) | 3 pages | Data analytics, engineers |
| `unified` | Medium (balanced) | 2 pages | General audience |

#### Example Workflow

**Scenario**: You're in marketing and need a brief about the new authentication feature.

1. Open Discord #exec-summary channel
2. Type: `/generate-summary --format=marketing --docs=auth-feature.md`
3. Wait 30-60 seconds
4. System posts a new thread with:
   - Marketing-friendly summary
   - Link to full Google Doc
   - Feature overview, value prop, positioning guidance

---

### Understanding Summary Structure

All summaries follow a consistent structure tailored to your department:

#### Executive Format (COO, Head of BD)

1. **Executive Summary**: What was done and why it matters (2-3 sentences)
2. **Business Impact**: Revenue, cost savings, competitive advantage
3. **Key Decisions Made**: High-level architectural or product decisions
4. **Risks & Mitigation**: What could go wrong and how we're addressing it
5. **Next Steps**: What happens next and when

#### Marketing Format

1. **Feature Overview**: What shipped and who it's for
2. **User Value Proposition**: Why customers care (pain solved, benefit gained)
3. **Key Capabilities**: Bulleted list of what users can do
4. **Technical Constraints**: Limitations or caveats
5. **Positioning & Messaging**: How to talk about this feature

#### Product Format

1. **Product Summary**: What changed and why
2. **User Impact**: How this affects user experience
3. **Technical Constraints**: Engineering trade-offs and limitations
4. **Feedback & Iterations**: What we learned, what's next
5. **Next Steps**: Follow-up work and timeline

#### Engineering Format (Data Analytics)

1. **Technical Overview**: Architecture and implementation details
2. **Data Models & APIs**: Technical specifications
3. **Integration Points**: How this connects to existing systems
4. **Performance & Scale**: Benchmarks, capacity, limitations
5. **Technical Debt & Future Work**: What's deferred and why

---

## For Product Manager

As the Product Manager, you play a **key role in reviewing and approving summaries** before wider distribution.

### Responsibilities

1. **Review weekly digests**: Every Friday, review the generated summary in #exec-summary
2. **Validate accuracy**: Ensure technical details are correct and context is complete
3. **Provide feedback**: If summary is incomplete, ask for regeneration with more context
4. **Approve for distribution**: React with ✅ emoji to approve (triggers optional blog publishing)
5. **Answer stakeholder questions**: Monitor Discord threads and respond to questions

### Weekly Digest Review Workflow

**Every Friday at ~9:15am** (after digest is posted):

1. **Check Discord #exec-summary**:
   - New thread: "Weekly Digest - December 13, 2025"
   - You're mentioned: "@product-manager"

2. **Open the linked Google Doc**:
   - Read the full summary (2-3 pages)
   - Check for accuracy, completeness, context

3. **Provide feedback** (if needed):
   - Reply in Discord thread with specific feedback
   - Request regeneration if major issues:
     ```
     /generate-summary --docs=sprint.md,prd.md
     ```
   - System regenerates with updated content

4. **Approve when ready**:
   - React with ✅ emoji on the Discord thread message
   - This signals approval to stakeholders
   - If blog publishing is enabled, this triggers auto-publish

5. **Monitor discussion**:
   - Watch for replies in the thread
   - Answer questions from execs, marketing, analytics
   - Provide additional context as needed

### Requesting Ad-Hoc Summaries

You can generate summaries anytime for stakeholder communication:

```bash
# Generate executive summary for board meeting
/generate-summary --format=executive --docs=quarterly-progress.md

# Generate marketing brief for feature launch
/generate-summary --format=marketing --docs=new-feature-prd.md

# Generate detailed summary for yourself
/generate-summary --format=product --docs=sprint.md,architecture.md
```

### Best Practices

- ✅ **Review within 24 hours**: Stakeholders expect timely updates
- ✅ **Be specific in feedback**: "Missing context on data migration timeline" vs "Needs more detail"
- ✅ **Use Discord threads**: Keep all discussion in the thread for context
- ✅ **Approve early**: Don't block stakeholders unnecessarily
- ✅ **Proactive communication**: Request summaries before stakeholder meetings

---

## For Executives (COO, Head of BD)

As an executive, you receive **business-focused summaries** of technical work.

### What You Receive

**Weekly on Friday mornings**: Executive summary in Discord #exec-summary

**Format**:
- 1 page (500-700 words)
- Low technical jargon
- Focus on business value, risks, timeline

**Content**:
- Features shipped this week
- Projects completed
- Business impact (revenue, cost, competitive advantage)
- Risks and mitigation
- Next steps

### How to Access

1. **Check Discord every Friday**:
   - Open Discord app
   - Go to #exec-summary channel
   - Click the latest "Weekly Digest" thread

2. **Read the summary**:
   - Posted directly in the thread
   - Takes 3-5 minutes to read
   - Links to full Google Doc if you want more details

3. **Ask questions**:
   - Reply in the Discord thread
   - Product Manager and engineers will respond
   - No question is too basic

### Example Summary

```
📊 Weekly Digest - December 13, 2025

EXECUTIVE SUMMARY
This week we shipped user authentication and completed Sprint 3.
This unlocks paid features and reduces security risk by 80%.

BUSINESS IMPACT
✅ Revenue: Enables paid tier ($50k MRR projected)
✅ Security: OAuth2 implementation reduces breach risk
✅ Competitive: Feature parity with competitors A and B

KEY DECISIONS
• Chose OAuth2 over custom auth (industry standard, lower risk)
• Deferred social login (Google, Twitter) to Sprint 4
• Prioritized API rate limiting for scale

RISKS & MITIGATION
⚠️ Risk: OAuth2 adds 50ms latency
   Mitigation: Caching reduces to 10ms, acceptable for users

NEXT STEPS
• Week of Dec 16: User testing with 50 beta users
• Week of Dec 23: Launch paid tier to all users
• Q1 2026: Expand to enterprise SSO
```

### Requesting Custom Summaries

If you need a summary for a board meeting or investor update:

```bash
/generate-summary --format=executive
```

Or ask the Product Manager to generate one for you.

### Best Practices

- ✅ **Read weekly digests**: Stay informed on technical progress
- ✅ **Ask questions**: Engineers want to explain, not hide details
- ✅ **Escalate concerns early**: If you see a red flag, speak up in the thread
- ✅ **Share with board/investors**: Forward Google Doc links when relevant
- ✅ **Provide business context**: Share market insights, competitive intel in threads

---

## For Marketing Team

As a marketing team member, you receive **feature-focused summaries** for positioning and messaging.

### What You Receive

**Weekly on Friday mornings**: Marketing brief in Discord #exec-summary (if features shipped)

**Format**:
- 1 page (500-700 words)
- Customer-friendly language
- Focus on features, value props, positioning

**Content**:
- Features shipped this week
- User value proposition (why customers care)
- Key capabilities (what users can do)
- Technical constraints (limitations to know)
- Positioning guidance (how to talk about it)

### How to Access

1. **Check Discord #exec-summary** (or request on-demand):
   ```bash
   /generate-summary --format=marketing
   ```

2. **Read the marketing brief** (example below)

### Example Marketing Brief

```
📣 Marketing Brief - User Authentication Feature

FEATURE OVERVIEW
We launched user authentication with email/password login and OAuth2
(Google, GitHub). This allows users to create accounts, log in securely,
and access their saved data across devices.

USER VALUE PROPOSITION
Pain solved: Users previously had to recreate their work every session
Benefit gained: Save and resume work anytime, anywhere, on any device

KEY CAPABILITIES
✅ Create account with email and password
✅ Log in with Google or GitHub (OAuth2)
✅ Remember user across devices and sessions
✅ Secure password reset via email
✅ Two-factor authentication (coming Q1 2026)

TECHNICAL CONSTRAINTS
• Requires account creation (not anonymous anymore)
• Social login limited to Google and GitHub (Twitter, Apple in Q1)
• Free tier: 3 saved projects; Paid tier: unlimited

POSITIONING & MESSAGING
✨ Customer-facing: "Never lose your work. Sign up to save and sync
   your projects across all your devices."

🎯 Competitive: "Unlike Competitor A, we support OAuth2 for faster
   login. Unlike Competitor B, we offer 2FA for enhanced security."

⚠️ Avoid: Don't promise social login beyond Google/GitHub yet
```

### Requesting Custom Marketing Briefs

**Before a feature launch**:
```bash
/generate-summary --format=marketing --docs=new-feature-prd.md
```

**For a blog post**:
```bash
/generate-summary --format=marketing --docs=feature-x.md
```

Then use the brief to write customer-facing copy, blog posts, or social media.

### Best Practices

- ✅ **Request briefs early**: Before feature launches, not after
- ✅ **Ask about constraints**: Know what you can and can't promise
- ✅ **Provide customer feedback**: Share what customers are saying in Discord threads
- ✅ **Clarify positioning**: If unsure how to message, ask Product Manager
- ✅ **Use technical docs**: Link to full Google Docs when writing detailed content

---

## For Data Analytics Team

As a data analytics team member, you receive **technical deep-dives** with architecture and data model details.

### What You Receive

**Weekly on Friday mornings**: Engineering-focused summary in Discord #exec-summary (if relevant)

**Format**:
- 3 pages (1000-1500 words)
- High technical detail
- Focus on architecture, data models, APIs

**Content**:
- Technical architecture
- Data models and schemas
- API endpoints and specifications
- Integration points with existing systems
- Performance benchmarks and scale
- Technical debt and future work

### How to Access

1. **Check Discord #exec-summary**:
   - Weekly digests have engineering format available
   - Request on-demand:
     ```bash
     /generate-summary --format=engineering
     ```

2. **Read the technical deep-dive**

### Example Engineering Summary

```
🔧 Technical Deep-Dive - User Authentication System

TECHNICAL OVERVIEW
Implemented OAuth2 + JWT authentication with PostgreSQL user store.
Architecture follows industry best practices (OWASP, NIST guidelines).

System components:
• Auth service: Node.js/Express, JWT generation/validation
• User service: CRUD operations, password hashing (bcrypt)
• OAuth providers: Google, GitHub (via Passport.js)
• Database: PostgreSQL users table with indexes on email

DATA MODELS & SCHEMAS

Users Table:
- id (UUID, primary key)
- email (VARCHAR, unique, indexed)
- password_hash (TEXT, bcrypt rounds=12)
- oauth_provider (ENUM: google, github, null)
- oauth_id (VARCHAR, nullable)
- created_at (TIMESTAMP)
- updated_at (TIMESTAMP)

JWT Payload:
{
  "sub": "user-uuid",
  "email": "user@example.com",
  "iat": 1670000000,
  "exp": 1670086400
}

API ENDPOINTS

POST /auth/register
Request: { email, password }
Response: { user, token }

POST /auth/login
Request: { email, password }
Response: { user, token }

GET /auth/oauth/google
Response: Redirect to Google OAuth

INTEGRATION POINTS
• Frontend: Receives JWT, stores in localStorage, includes in Authorization header
• API Gateway: Validates JWT on all protected endpoints
• Database: Direct PostgreSQL connection via Sequelize ORM
• Analytics: User events streamed to Segment (user.signed_up, user.logged_in)

PERFORMANCE & SCALE
• Login latency: 10ms (50th percentile), 30ms (95th percentile)
• Registration latency: 50ms (password hashing dominates)
• OAuth latency: 200ms (external provider roundtrip)
• Database: Indexed email lookups, <5ms query time
• Scale: Tested to 10k concurrent users, no bottlenecks

TECHNICAL DEBT & FUTURE WORK
• TODO: Implement refresh tokens (currently JWT expires in 24h)
• TODO: Add rate limiting on login endpoint (prevent brute force)
• TODO: Migrate to Redis for session storage (horizontal scale)
• DEFERRED: Social login (Twitter, Apple) to Q1 2026
```

### Requesting Custom Engineering Summaries

**Before data pipeline integration**:
```bash
/generate-summary --format=engineering --docs=api-spec.md
```

**For architecture review**:
```bash
/generate-summary --format=engineering --docs=sdd.md
```

### Best Practices

- ✅ **Request early**: Before integrating with new systems
- ✅ **Ask specific questions**: "What's the data schema?" vs "Tell me about the feature"
- ✅ **Access source code**: Summaries link to GitHub repos, SDDs, API docs
- ✅ **Provide feedback**: If data models affect your pipelines, speak up
- ✅ **Collaborate in threads**: Discuss data requirements with engineers

---

## Weekly Digest Workflow

### Timeline

**Thursday evening**:
- Engineers finalize sprint updates, PRDs, SDDs in Google Docs

**Friday 9:00am UTC**:
- System scans Google Docs for changed documents (past 7 days)
- Generates unified summary + department-specific variants
- Creates Google Doc in "Executive Summaries" folder
- Posts to Discord #exec-summary channel
- Mentions @product-manager for review

**Friday 9:00am - 12:00pm**:
- Product Manager reviews Google Doc
- Provides feedback or approves (✅ emoji)

**Friday 12:00pm onwards**:
- Stakeholders read summaries
- Discuss in Discord threads
- Ask clarifying questions
- Request follow-up summaries if needed

**Saturday (optional)**:
- If blog publishing enabled and approved:
  - System publishes to Mirror/company website
  - Shared on social media, newsletters

### Participation Guide

#### For Everyone

1. **Friday morning**: Check Discord #exec-summary for new digest
2. **Read the summary**: 3-5 minute read
3. **Click for details**: Open Google Doc link if you want more
4. **Ask questions**: Reply in Discord thread
5. **Request custom format**: Use `/generate-summary` if you need different depth

#### For Product Manager

1. **Friday morning**: You're mentioned in #exec-summary
2. **Review Google Doc**: Read full summary for accuracy
3. **Provide feedback**: If issues, comment in thread or request regeneration
4. **Approve**: React with ✅ when ready
5. **Monitor discussion**: Answer questions throughout the day

#### For Executives

1. **Friday morning**: Open Discord, read summary
2. **5 minutes**: Get high-level overview
3. **Ask questions**: If anything is unclear
4. **Escalate concerns**: If you see risks or blockers

#### For Marketing

1. **Friday morning**: Check if features shipped this week
2. **Read marketing brief**: Generated automatically if relevant
3. **Request on-demand**: If you need brief for specific feature
4. **Start messaging**: Draft customer-facing copy

#### For Data Analytics

1. **Friday morning**: Check if technical changes affect your work
2. **Request engineering format**: `/generate-summary --format=engineering`
3. **Review data models**: Check if schemas changed
4. **Plan integrations**: Coordinate with engineers in threads

---

## Best Practices

### For Consuming Summaries

- ✅ **Read weekly digests consistently**: Make it a Friday morning habit
- ✅ **Ask questions early**: Don't wait, clarify immediately
- ✅ **Use layered documentation**: Summary → full doc → source code (choose your depth)
- ✅ **Engage in Discord threads**: Discussions provide valuable context
- ✅ **Request custom formats**: Don't struggle with wrong technical level

### For Requesting Summaries

- ✅ **Be specific**: Use `--docs` flag to target specific documents
- ✅ **Choose right format**: Match your audience (exec for board, marketing for customers)
- ✅ **Give context**: In Discord, explain why you need the summary
- ✅ **Review and iterate**: If first summary misses the mark, request regeneration

### For Discussions

- ✅ **Keep it in the thread**: Centralize discussion, don't DM
- ✅ **Tag relevant people**: @product-manager, @engineering for specific questions
- ✅ **Provide feedback**: If summaries are too technical/not technical enough, say so
- ✅ **Share outcomes**: If summary led to a decision, share in thread

### For Product Managers

- ✅ **Review promptly**: Don't block stakeholders, review within 24 hours
- ✅ **Be thorough**: Check accuracy, completeness, context
- ✅ **Approve liberally**: Don't perfectionism-block, approve when "good enough"
- ✅ **Proactive summaries**: Generate before meetings, not after stakeholders ask

---

## FAQs

### General Questions

**Q: How often are weekly digests generated?**
A: Every Friday at 9:00am UTC (configurable in the system config)

**Q: Can I change my department/format preference?**
A: Yes, either:
1. Ask admin to update `devrel-integration.config.yaml`
2. Use `--format` flag to override per-request

**Q: What if I miss a weekly digest?**
A: All digests are preserved in Discord threads. Scroll back through #exec-summary channel history.

**Q: Can I generate summaries for older documents?**
A: Yes, use `/generate-summary --docs=old-document.md` (specify the document path)

---

### For Product Managers

**Q: What if the summary is inaccurate?**
A: Reply in the Discord thread with specific feedback, then request regeneration:
```bash
/generate-summary --docs=sprint.md
```

**Q: How do I approve a summary?**
A: React with ✅ emoji on the Discord thread message

**Q: What happens when I approve?**
A: If blog publishing is enabled, the summary is auto-published to Mirror/website. Otherwise, it just signals approval to stakeholders.

**Q: Can I unapprove?**
A: Yes, remove your ✅ reaction. However, if blog post was already published, you'll need to manually unpublish.

---

### For Executives

**Q: Is this replacing meetings?**
A: No, this provides **asynchronous updates**. Meetings are still valuable for discussion, decision-making, and collaboration. Use summaries to prepare for meetings.

**Q: What if the summary is too technical?**
A: Request a regeneration in executive format:
```bash
/generate-summary --format=executive
```
Or ask the Product Manager to simplify.

**Q: Can I forward summaries to board members?**
A: Yes! Share the Google Doc link. All summaries are shared with the organization. For external sharing (investors, board), ask PM to review first.

---

### For Marketing

**Q: When should I request a marketing brief?**
A: **Before feature launches**, when you're writing customer-facing content (blog posts, landing pages, social media).

**Q: Can I edit the generated brief?**
A: Absolutely! The brief is a **starting point**. Edit the Google Doc or copy content to your own doc.

**Q: What if technical constraints aren't clear?**
A: Ask in the Discord thread: "Can we promise X?" or "What's the limitation on Y?"

---

### For Data Analytics

**Q: Will I be notified when data models change?**
A: Yes, if data model changes are documented in the sprint update/SDD and flagged in the config. You can also request engineering format weekly.

**Q: How do I get API documentation?**
A: Engineering format summaries include API specs. For full docs, click the Google Doc link → find linked GitHub repos or API docs.

**Q: Can I request a custom technical deep-dive?**
A: Yes:
```bash
/generate-summary --format=engineering --docs=architecture.md,api-spec.md
```

---

### Technical Questions

**Q: Where are the source documents?**
A: Google Docs (monitored folders) and GitHub (code repos). Summaries link to both.

**Q: Can I edit the generated summaries?**
A: Yes, summaries are created as editable Google Docs. Edit as needed.

**Q: What if a summary is missing context?**
A: Provide feedback in the Discord thread. The system assembles context from related docs, but it may miss something. Request regeneration with additional docs:
```bash
/generate-summary --docs=sprint.md,related-prd.md,architecture.md
```

**Q: How does department auto-detection work?**
A: The system checks:
1. User ID mapping in config file
2. Discord role (@leadership, @marketing, etc.)
3. Fallback to default format (unified)

You can always override with `--format` flag.

**Q: Can I opt out of weekly digests?**
A: You can mute the #exec-summary channel if you don't need updates. However, consider subscribing to your department-specific format instead.

---

## Getting Help

**For technical issues**:
- Check [Tool Setup Guide](tool-setup.md) for troubleshooting
- Contact the implementation team

**For content issues** (inaccurate/incomplete summaries):
- Reply in the Discord thread with feedback
- Tag @product-manager

**For workflow questions**:
- Ask in #exec-summary channel
- Review this playbook
- Check [Integration Architecture](devrel-integration-architecture.md) for design details

---

**Happy communicating!** 🚀

Use the DevRel integration to stay informed, request custom summaries, and transform technical work into accessible knowledge for all stakeholders.
