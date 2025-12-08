# DevRel Integration Architecture

**Purpose**: Automated stakeholder communication via devrel-translator agent
**Scope**: Weekly digests, ad-hoc translations, multi-format output for internal stakeholders
**Last Updated**: 2025-12-08

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Stakeholder Ecosystem](#stakeholder-ecosystem)
3. [Current State & Pain Points](#current-state--pain-points)
4. [Architecture Components](#architecture-components)
5. [Configuration Schema](#configuration-schema)
6. [Data Flow Diagrams](#data-flow-diagrams)
7. [Security & Permissions](#security--permissions)
8. [Scalability & Maintenance](#scalability--maintenance)
9. [Implementation Roadmap](#implementation-roadmap)

---

## System Overview

### Purpose

Transform siloed technical documentation into proactive, accessible stakeholder communications. The devrel-translator integration automates the generation of executive summaries, marketing briefs, and educational content from technical artifacts (PRDs, SDDs, sprint updates, audit reports).

### Key Capabilities

- **Automated Weekly Digests**: Scan Google Docs for changes, generate context-aware summaries, distribute to stakeholders
- **Department-Specific Formats**: Auto-detect user department, generate appropriate technical depth and focus
- **Manual On-Demand Generation**: CLI and Discord commands for ad-hoc translation requests
- **Multi-Platform Distribution**: Google Docs (review), Discord (discussion), Mirror/Paragraph (blog publishing)
- **YAML-Driven Configuration**: All settings adjustable without code deployments

### Design Principles

1. **Proactive Education**: Transform reactive Q&A into proactive information sharing
2. **Layered Documentation**: Summaries → detailed docs → deep technical (readers choose depth)
3. **Configuration Over Code**: YAML configs enable non-technical adjustments
4. **Review Before Distribution**: Human approval gate before stakeholder communication
5. **Incremental Adoption**: Start simple (weekly Discord digest), add capabilities over time

---

## Stakeholder Ecosystem

### Internal Stakeholders

| Stakeholder | Technical Level | Information Needs | Preferred Format |
|------------|----------------|-------------------|------------------|
| **Product Manager** | Medium (ethnographer-style, deeply involved) | User impact, technical constraints, next steps | 2-page detailed summary |
| **COO** | Low | Business value, risks, timeline, costs | 1-page executive summary |
| **Head of BD** | Low | Feature capabilities, competitive positioning, partnerships | 1-page executive summary |
| **Marketing Team** | Low | Feature descriptions, value props, positioning, technical constraints | 1-page marketing brief |
| **Data Analytics Team** | High | Technical details, architecture, data models, APIs | 3-page technical deep-dive |

### Communication Patterns

- **Product Manager**: Needs regular updates (weekly), involved in decisions, reviews all digests
- **Executives**: Need high-level context (weekly/monthly), focus on business impact
- **Marketing**: Ad-hoc requests when features launch, need positioning guidance
- **Data Analytics**: Ad-hoc technical deep-dives, prefer direct access to technical docs

---

## Current State & Pain Points

### How Technical Information Flows Today

1. **Technical artifacts created**: PRDs, SDDs, sprint updates live in Google Docs (directory per project)
2. **Information silos**: Also stored in GitHub, Linear, not reaching wider org
3. **Reactive communication**: Stakeholders ask questions in Discord, get partial answers
4. **No proactive education**: Missing opportunities for tutorials, blogs, exec summaries

### Pain Points

- ❌ **Delayed stakeholder awareness**: Execs learn about technical decisions weeks late
- ❌ **Repeated explanations**: Engineers answer same questions multiple times in Discord
- ❌ **Lost educational opportunities**: Technical work doesn't become tutorials/blogs
- ❌ **Context gaps**: Stakeholders get isolated facts without wider context
- ❌ **Manual summary burden**: Someone has to manually write exec summaries (if at all)

### Desired Future State

- ✅ **Weekly automated digests**: Stakeholders proactively receive context-aware summaries
- ✅ **Layered documentation**: Summaries link to fuller docs for interested readers
- ✅ **Educational content pipeline**: Technical work automatically becomes tutorials/blogs
- ✅ **Self-service information**: Stakeholders can request custom format summaries on-demand
- ✅ **Centralized communication**: Discord "exec-summary" channel as single source of truth

---

## Architecture Components

### 1. Google Docs Integration Layer

**Purpose**: Monitor Google Docs for changes, fetch technical documents for processing

**Components**:
- **MCP Server**: `@modelcontextprotocol/server-gdrive` (or equivalent)
- **Authentication**: OAuth2 service account with read access to monitored folders
- **Monitored Folders**: Project directories (e.g., `Engineering/Projects/*`, `Product/PRDs`, `Security/Audits`)
- **Change Detection**: Track last-modified timestamps, identify docs changed in past 7 days

**Key Operations**:
```typescript
// Pseudocode
class GoogleDocsMonitor {
  async scanForChanges(windowDays: number): Promise<Document[]>
  async fetchDocument(docId: string): Promise<DocumentContent>
  async classifyDocument(doc: Document): Promise<DocType> // PRD, SDD, sprint, audit
  async getRelatedDocuments(doc: Document): Promise<Document[]> // For context
}
```

**Configuration** (from YAML):
```yaml
google_docs:
  monitored_folders:
    - "Engineering/Projects/*"
    - "Product/PRDs"
    - "Security/Audits"
  exclude_patterns:
    - "**/Meeting Notes/**"
    - "**/Draft/**"
  change_detection_window_days: 7
```

**Document Organization Structure** (recommended):
```
Google Drive/
├── Engineering/
│   └── Projects/
│       ├── Project-A/
│       │   ├── PRD - Project A.gdoc
│       │   ├── SDD - Project A.gdoc
│       │   └── Sprint Updates/
│       │       ├── Sprint 1 - Project A.gdoc
│       │       └── Sprint 2 - Project A.gdoc
│       └── Project-B/
│           └── ...
├── Product/
│   └── PRDs/
│       ├── PRD - Feature X.gdoc
│       └── PRD - Feature Y.gdoc
├── Security/
│   └── Audits/
│       └── Security Audit - 2025-12-08.gdoc
└── Executive Summaries/  # Auto-generated output folder
    ├── Weekly Digest - 2025-12-06.gdoc
    └── Weekly Digest - 2025-12-13.gdoc
```

---

### 2. Document Processing Pipeline

**Purpose**: Filter, classify, and prepare technical documents for translation

**Components**:
- **Change Filter**: Select docs modified in past N days (configurable)
- **Document Classifier**: Auto-detect doc type (PRD, SDD, sprint, audit) from title/content
- **Context Assembler**: Gather related docs to provide "wider context"
- **Content Selector**: Filter by YAML-defined inclusion rules

**Key Operations**:
```typescript
class DocumentProcessor {
  async gatherWeeklyDocs(): Promise<Document[]>
  async assembleContext(doc: Document): Promise<Context>
  async prepareTranslationInput(doc: Document, context: Context): Promise<Input>
}
```

**Configuration** (from YAML):
```yaml
digest_content:
  include_doc_types:
    - "prd"
    - "sdd"
    - "sprint"
    - "audit"
    - "deployment"
  summary_focus:
    - "features_shipped"
    - "projects_completed"
    - "architectural_decisions"
    - "security_updates"
  context_sources:
    - "previous_digests"
    - "roadmap_docs"
    - "okr_docs"
```

**Context Assembly Strategy**:
1. **For sprint updates**: Gather related PRD, SDD, previous sprint updates
2. **For PRDs**: Gather related SDDs, roadmap docs, OKRs
3. **For audit reports**: Gather related deployment docs, previous audits
4. **For all docs**: Include previous weekly digest for continuity

---

### 3. Translation Engine

**Purpose**: Invoke devrel-translator agent with department-specific prompts

**Components**:
- **Agent Invoker**: Call devrel-translator via Claude Code API or slash command
- **Prompt Templates**: Department-specific prompt files (executive, marketing, product, engineering, unified)
- **Format Variants**: Different outputs for different audiences
- **Context Injection**: Include related docs and wider context in prompts

**Key Operations**:
```typescript
class TranslationEngine {
  async translateDocument(doc: Document, format: FormatType): Promise<Translation>
  async loadPromptTemplate(format: FormatType): Promise<string>
  async invokeDevRelTranslator(input: Input, prompt: string): Promise<string>
}
```

**Prompt Template Structure**:
```
config/prompts/
├── executive.md        # 1-page, business focus, low technical
├── marketing.md        # 1-page, features & value props
├── product.md          # 2-page, user impact & constraints
├── engineering.md      # 3-page, technical deep-dive
└── unified.md          # 2-page, medium technical, all audiences
```

**Format Specifications** (from YAML):
```yaml
output_formats:
  unified:
    audience: "all"
    length: "2_pages"
    technical_level: "medium"
  executive:
    audience: ["COO", "Head of BD"]
    length: "1_page"
    technical_level: "low"
    focus: ["business_value", "risks", "timeline"]
  marketing:
    audience: "marketing_team"
    length: "1_page"
    technical_level: "low"
    focus: ["features", "user_value", "positioning"]
  product:
    audience: "product_manager"
    length: "2_pages"
    technical_level: "medium"
    focus: ["user_impact", "technical_constraints", "next_steps"]
  engineering:
    audience: "data_analytics"
    length: "3_pages"
    technical_level: "high"
    focus: ["technical_details", "architecture", "data_models"]
```

**Translation Flow**:
1. Load prompt template for target format
2. Inject document content + context
3. Invoke devrel-translator agent: `/translate @document.md for [audience]`
4. Parse and format output
5. Add metadata (date, source docs, format type)

---

### 4. Department Detection & User Mapping

**Purpose**: Auto-detect user's department to generate appropriate format

**Components**:
- **User-to-Department Mapping**: YAML config or integration with Linear/Discord roles
- **Format Resolver**: Map department → format type
- **Manual Override Support**: Allow users to request different formats

**Key Operations**:
```typescript
class DepartmentDetector {
  async detectDepartmentFromUser(userId: string): Promise<Department>
  async getFormatForDepartment(dept: Department): Promise<FormatType>
  async getFormatForUser(userId: string, override?: FormatType): Promise<FormatType>
}
```

**Configuration** (from YAML):
```yaml
department_mapping:
  user_id_to_department:
    # Option A: Auto-populated from Linear/Discord roles
    # Option B: Manually configured
    "user123": "product"
    "user456": "executive"
    "user789": "marketing"
  role_to_department:
    "@leadership": "executive"
    "@marketing": "marketing"
    "@engineering": "engineering"
  default_format: "unified"
  allow_format_override: true
```

**Detection Strategy**:
1. Check explicit user mapping in YAML
2. Fallback to Discord role detection (`@leadership` → executive)
3. Fallback to Linear role detection (if integrated)
4. Fallback to default format (unified)
5. Allow manual override via command flag

---

### 5. Output Distribution Layer

**Purpose**: Publish translated summaries to Google Docs, Discord, and optional blog platforms

#### 5.1 Google Docs Publisher

**Functionality**:
- Create new Google Doc in "Executive Summaries" folder
- Set title: "Weekly Digest - [date]" or "Summary - [doc-name]"
- Apply formatting (headings, bullet points, links)
- Share with organization (view access)
- Return shareable URL

**Key Operations**:
```typescript
class GoogleDocsPublisher {
  async createSummaryDoc(content: string, metadata: Metadata): Promise<DocUrl>
  async shareWithOrganization(docId: string): Promise<void>
  async getDocumentLink(docId: string): Promise<string>
}
```

#### 5.2 Discord Publisher

**Functionality**:
- Post to "exec-summary" channel
- Create thread with summary title
- Post summary excerpt (first 500 chars)
- Link to full Google Doc
- Mention reviewers (e.g., @product-manager)
- Add approval reaction (✅) for review workflow

**Key Operations**:
```typescript
class DiscordPublisher {
  async createSummaryThread(docUrl: string, summary: Summary): Promise<ThreadId>
  async mentionReviewers(threadId: ThreadId, reviewers: string[]): Promise<void>
  async setupApprovalReaction(threadId: ThreadId): Promise<void>
}
```

**Discord Channel Structure**:
```
Discord Server/
├── #exec-summary          # Main channel for summaries
│   ├── Thread: Weekly Digest - Dec 6, 2025
│   ├── Thread: Weekly Digest - Dec 13, 2025
│   └── Thread: Security Audit Summary
├── #engineering           # Technical discussions
├── #product              # Product discussions
└── #marketing            # Marketing discussions
```

#### 5.3 Blog Publisher (Optional)

**Functionality**:
- Publish to Mirror/Paragraph (crypto publishing platform)
- Or publish to company website CMS
- Await approval before publish (check reaction in Discord)
- Support markdown format

**Key Operations**:
```typescript
class BlogPublisher {
  async publishToMirror(content: string, metadata: Metadata): Promise<PostUrl>
  async awaitApproval(threadId: ThreadId): Promise<boolean>
  async publishToCompanyWebsite(content: string): Promise<PostUrl>
}
```

**Configuration** (from YAML):
```yaml
distribution:
  google_docs:
    output_folder: "Executive Summaries"
    sharing: "organization"
  discord:
    channel: "exec-summary"
    thread_creation: true
    mention_roles: ["@leadership"]
  blog:
    enabled: false  # Set to true when ready
    platforms:
      - "mirror"  # or "company_website"
    auto_publish: false  # Require manual approval
```

---

### 6. Manual Trigger Interface

**Purpose**: Allow team members to request ad-hoc translations on-demand

#### 6.1 Discord Bot Commands

**Command**: `/generate-summary [--format=<format>] [--docs=<doc-paths>]`

**Examples**:
```bash
# Auto-detect department, generate appropriate format
/generate-summary

# Generate specific format
/generate-summary --format=executive

# Generate for specific docs
/generate-summary --docs=sprint.md,prd.md

# Combine flags
/generate-summary --format=marketing --docs=feature-x.md
```

**Implementation**:
```typescript
// Discord bot command handler
bot.on('commandInteraction', async (interaction) => {
  if (interaction.commandName === 'generate-summary') {
    const format = interaction.options.get('format')?.value || 'auto-detect';
    const docs = interaction.options.get('docs')?.value?.split(',') || [];

    const userId = interaction.user.id;
    const department = await departmentDetector.detectDepartmentFromUser(userId);
    const resolvedFormat = format === 'auto-detect'
      ? await departmentDetector.getFormatForDepartment(department)
      : format;

    // Process and generate summary
    const summary = await translationEngine.translateDocuments(docs, resolvedFormat);
    const docUrl = await googleDocsPublisher.createSummaryDoc(summary);
    await discordPublisher.createSummaryThread(docUrl, summary);

    await interaction.reply(`Summary generated: ${docUrl}`);
  }
});
```

#### 6.2 CLI Commands

**Command**: `npm run generate-summary -- [--format=<format>] [--docs=<doc-paths>]`

**Examples**:
```bash
# Auto-detect based on current user
npm run generate-summary

# Generate executive format
npm run generate-summary -- --format=executive

# Generate for specific docs
npm run generate-summary -- --docs=docs/sprint.md,docs/prd.md

# Dry-run (don't post, just output)
npm run generate-summary -- --dry-run
```

#### 6.3 Slash Command Integration

**Existing devrel-translator slash command still works**:
```bash
/translate @docs/sprint.md for marketing team
/translate @SECURITY-AUDIT-REPORT.md for board of directors
```

This manual invocation bypasses automation and generates one-off translations.

---

### 7. Scheduling & Automation

**Purpose**: Run weekly digest generation automatically on a configurable schedule

#### 7.1 Weekly Digest Scheduler

**Trigger**: Cron job or GitHub Actions workflow
**Default Schedule**: Every Friday at 9am UTC (configurable)

**Workflow**:
1. Load configuration from `devrel-integration.config.yaml`
2. Scan Google Docs for changes (past 7 days)
3. Filter and classify documents
4. Assemble context for each document
5. Generate translations (unified format + department-specific variants)
6. Create Google Doc with summary
7. Post to Discord "exec-summary" channel
8. Log completion and metrics

**Configuration** (from YAML):
```yaml
schedule:
  weekly_digest: "0 9 * * FRI"  # Cron format: Every Friday 9am
  timezone: "UTC"
```

#### 7.2 GitHub Actions Workflow

**File**: `.github/workflows/weekly-digest.yml`

```yaml
name: Weekly DevRel Digest

on:
  schedule:
    - cron: '0 9 * * FRI'  # Every Friday 9am UTC
  workflow_dispatch:  # Allow manual trigger

jobs:
  generate-digest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - run: npm ci
      - name: Generate Weekly Digest
        env:
          GOOGLE_APPLICATION_CREDENTIALS: ${{ secrets.GOOGLE_SERVICE_ACCOUNT_KEY }}
          DISCORD_BOT_TOKEN: ${{ secrets.DISCORD_BOT_TOKEN }}
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: npm run weekly-digest
      - name: Post Results
        if: failure()
        run: npm run notify-failure
```

---

### 8. Review & Approval Workflow

**Purpose**: Human-in-the-loop review before stakeholder distribution

**Workflow Steps**:
1. **Generation**: System generates summary, creates Google Doc
2. **Posting**: Discord thread created in "exec-summary" channel with doc link
3. **Review**: Product manager reviews Google Doc, discusses in Discord thread
4. **Iteration** (if needed): Feedback in thread, manual `/generate-summary` to regenerate
5. **Approval**: Product manager reacts with ✅ emoji in Discord thread
6. **Distribution** (optional): If blog publishing enabled, approved summaries auto-post to Mirror/website

**Configuration** (from YAML):
```yaml
review_workflow:
  require_approval: true
  reviewers: ["product_manager"]  # User IDs or role names
  approval_channel: "exec-summary"
  approval_emoji: "✅"
```

**Implementation**:
```typescript
// Discord bot reaction handler
bot.on('messageReactionAdd', async (reaction, user) => {
  if (reaction.emoji.name === '✅' && reaction.message.channel.name === 'exec-summary') {
    const isReviewer = await checkIfReviewer(user.id);
    if (isReviewer) {
      // Extract Google Doc URL from message
      const docUrl = extractDocUrl(reaction.message.content);

      // If blog publishing enabled, publish to blog
      if (config.distribution.blog.enabled && !config.distribution.blog.auto_publish) {
        await blogPublisher.publishApprovedSummary(docUrl);
      }

      // Log approval
      logger.info(`Summary approved by ${user.username}: ${docUrl}`);
    }
  }
});
```

---

## Configuration Schema

**File**: `config/devrel-integration.config.yaml`

```yaml
# Weekly digest schedule
schedule:
  weekly_digest: "0 9 * * FRI"  # Cron format
  timezone: "UTC"

# Google Docs integration
google_docs:
  monitored_folders:
    - "Engineering/Projects/*"
    - "Product/PRDs"
    - "Security/Audits"
  exclude_patterns:
    - "**/Meeting Notes/**"
    - "**/Draft/**"
    - "**/Archive/**"
  change_detection_window_days: 7

# Content selection for weekly digest
digest_content:
  include_doc_types:
    - "prd"
    - "sdd"
    - "sprint"
    - "audit"
    - "deployment"
  summary_focus:
    - "features_shipped"
    - "projects_completed"
    - "architectural_decisions"
    - "security_updates"
  context_sources:
    - "previous_digests"
    - "roadmap_docs"
    - "okr_docs"

# Output format definitions
output_formats:
  unified:
    audience: "all"
    length: "2_pages"
    technical_level: "medium"

  executive:
    audience: ["COO", "Head of BD"]
    length: "1_page"
    technical_level: "low"
    focus: ["business_value", "risks", "timeline"]

  marketing:
    audience: "marketing_team"
    length: "1_page"
    technical_level: "low"
    focus: ["features", "user_value", "positioning"]

  product:
    audience: "product_manager"
    length: "2_pages"
    technical_level: "medium"
    focus: ["user_impact", "technical_constraints", "next_steps"]

  engineering:
    audience: "data_analytics"
    length: "3_pages"
    technical_level: "high"
    focus: ["technical_details", "architecture", "data_models"]

# Distribution channels
distribution:
  google_docs:
    output_folder: "Executive Summaries"
    sharing: "organization"

  discord:
    channel: "exec-summary"
    thread_creation: true
    mention_roles: ["@leadership", "@product"]

  blog:
    enabled: false  # Set to true when ready
    platforms:
      - "mirror"  # or "company_website"
    auto_publish: false  # Require manual approval

# Department-to-format mapping
department_mapping:
  user_id_to_department:
    # Manually configure or auto-populate from Linear/Discord
    # Example:
    # "user123": "product"
    # "user456": "executive"

  role_to_department:
    "@leadership": "executive"
    "@product": "product"
    "@marketing": "marketing"
    "@engineering": "engineering"

  default_format: "unified"
  allow_format_override: true

# Review and approval workflow
review_workflow:
  require_approval: true
  reviewers: ["product_manager"]
  approval_channel: "exec-summary"
  approval_emoji: "✅"

# Monitoring and logging
monitoring:
  log_level: "info"
  metrics_enabled: true
  alert_on_failure: true
  alert_webhook: "https://discord.com/api/webhooks/..."
```

---

## Data Flow Diagrams

### Weekly Digest Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         WEEKLY DIGEST FLOW                          │
└─────────────────────────────────────────────────────────────────────┘

1. TRIGGER
   ┌──────────────┐
   │ Cron/GitHub  │
   │   Actions    │ ─── Every Friday 9am UTC
   └──────┬───────┘
          │
          v
2. SCAN GOOGLE DOCS
   ┌──────────────────┐
   │ Google Docs API  │
   │                  │ ─── Scan monitored folders
   │ • Filter changed │ ─── Last 7 days
   │ • Classify docs  │ ─── PRD, SDD, sprint, audit
   └──────┬───────────┘
          │
          v
3. ASSEMBLE CONTEXT
   ┌──────────────────┐
   │ Context Builder  │
   │                  │ ─── Gather related docs
   │ • Related PRDs   │ ─── Previous digests
   │ • Roadmap docs   │ ─── OKR docs
   └──────┬───────────┘
          │
          v
4. GENERATE TRANSLATIONS
   ┌──────────────────────┐
   │ devrel-translator    │
   │                      │ ─── Generate unified format
   │ • Load prompt        │ ─── + department variants
   │ • Invoke agent       │ ─── (exec, marketing, etc.)
   │ • Parse output       │
   └──────┬───────────────┘
          │
          v
5. CREATE GOOGLE DOC
   ┌──────────────────┐
   │ Google Docs API  │
   │                  │ ─── Create in "Executive Summaries"
   │ • Format content │ ─── Apply styling
   │ • Share with org │ ─── Get shareable URL
   └──────┬───────────┘
          │
          v
6. POST TO DISCORD
   ┌──────────────────┐
   │ Discord Bot      │
   │                  │ ─── Post to "exec-summary" channel
   │ • Create thread  │ ─── Title: "Weekly Digest - [date]"
   │ • Post excerpt   │ ─── First 500 chars
   │ • Link to doc    │ ─── Google Doc URL
   │ • Mention PMs    │ ─── @product-manager
   │ • Add ✅ reaction│ ─── For approval
   └──────┬───────────┘
          │
          v
7. AWAIT REVIEW & APPROVAL
   ┌──────────────────┐
   │ Review Workflow  │
   │                  │ ─── PM reviews Google Doc
   │ • Team discusses │ ─── In Discord thread
   │ • PM reacts ✅   │ ─── Approval
   └──────┬───────────┘
          │
          v
8. OPTIONAL: PUBLISH TO BLOG
   ┌──────────────────┐
   │ Blog Publisher   │
   │                  │ ─── If enabled & approved
   │ • Publish Mirror │ ─── Or company website
   └──────────────────┘
```

### Manual Trigger Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        MANUAL TRIGGER FLOW                          │
└─────────────────────────────────────────────────────────────────────┘

1. USER INVOKES COMMAND
   ┌──────────────────────────────────────┐
   │ Discord: /generate-summary           │
   │ CLI: npm run generate-summary        │
   │                                      │
   │ Flags:                               │
   │ --format=<format>  (optional)        │
   │ --docs=<paths>     (optional)        │
   └──────┬───────────────────────────────┘
          │
          v
2. DETECT DEPARTMENT
   ┌──────────────────┐
   │ Department       │
   │ Detector         │ ─── Check user ID mapping
   │                  │ ─── Check Discord roles
   │ • Auto-detect    │ ─── Fallback to default
   │ • Allow override │
   └──────┬───────────┘
          │
          v
3. LOAD FORMAT CONFIG
   ┌──────────────────┐
   │ Config Loader    │
   │                  │ ─── Load YAML
   │ • Get format     │ ─── executive, marketing, etc.
   │ • Load prompt    │ ─── From config/prompts/
   └──────┬───────────┘
          │
          v
4. GATHER SPECIFIED DOCS (or latest)
   ┌──────────────────┐
   │ Document Fetcher │
   │                  │ ─── If --docs specified, fetch those
   │ • Fetch from GD  │ ─── Otherwise, latest changed docs
   │ • Assemble ctx   │
   └──────┬───────────┘
          │
          v
5. INVOKE devrel-translator
   ┌──────────────────┐
   │ Translation      │
   │ Engine           │ ─── Generate summary
   │                  │ ─── In requested format
   └──────┬───────────┘
          │
          v
6. CREATE OUTPUT & DISTRIBUTE
   ┌──────────────────┐
   │ Same as weekly   │
   │ digest flow:     │ ─── Create Google Doc
   │ • Google Doc     │ ─── Post Discord thread
   │ • Discord thread │
   └──────────────────┘
```

### Review & Approval Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                     REVIEW & APPROVAL FLOW                          │
└─────────────────────────────────────────────────────────────────────┘

1. SUMMARY GENERATED
   ┌──────────────────┐
   │ Google Doc       │
   │ created          │ ─── "Executive Summaries/Weekly Digest - [date]"
   └──────┬───────────┘
          │
          v
2. DISCORD NOTIFICATION
   ┌──────────────────┐
   │ Thread posted    │
   │ in exec-summary  │ ─── Title: "Weekly Digest - [date]"
   │                  │ ─── Excerpt + Google Doc link
   │ @product-manager │ ─── Mention reviewer
   │ ✅ reaction added│
   └──────┬───────────┘
          │
          v
3. TEAM DISCUSSION
   ┌──────────────────┐
   │ Discord thread   │
   │                  │ ─── PM reviews Google Doc
   │ • Questions      │ ─── Team asks clarifications
   │ • Feedback       │ ─── Suggestions for changes
   └──────┬───────────┘
          │
          ├─── If changes needed ───┐
          │                          v
          │                   ┌──────────────────┐
          │                   │ Manual re-gen    │
          │                   │                  │
          │                   │ /generate-summary│
          │                   └──────┬───────────┘
          │                          │
          v                          v
4. APPROVAL                          (Loop back to step 1)
   ┌──────────────────┐
   │ PM reacts with ✅│ ─── In Discord thread
   └──────┬───────────┘
          │
          v
5. OPTIONAL: AUTO-PUBLISH TO BLOG
   ┌──────────────────┐
   │ If blog.enabled  │
   │ and approved:    │ ─── Publish to Mirror/website
   │                  │
   │ • Export markdown│
   │ • Post to blog   │
   └──────────────────┘
```

---

## Security & Permissions

### Google Drive Access

- **Authentication**: OAuth2 service account
- **Permissions**: Read-only access to monitored folders
- **Scope**: `https://www.googleapis.com/auth/drive.readonly`
- **Credentials**: JSON key file stored securely (environment variable)
- **Best Practice**: Create dedicated service account specifically for this integration

### Discord Bot Permissions

- **Required Permissions**:
  - Send Messages
  - Create Public Threads
  - Add Reactions
  - Read Message History
- **Token Storage**: Environment variable (`DISCORD_BOT_TOKEN`)
- **Channel Access**: Restrict bot to "exec-summary" channel only

### MCP Server Configuration

**File**: `.claude/settings.local.json`

```json
{
  "mcpServers": {
    "gdrive": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-gdrive"],
      "env": {
        "GOOGLE_APPLICATION_CREDENTIALS": "/path/to/service-account-key.json"
      }
    },
    "discord": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-discord"],
      "env": {
        "DISCORD_BOT_TOKEN": "${DISCORD_BOT_TOKEN}"
      }
    }
  }
}
```

### Secrets Management

**Environment Variables** (`.env`):
```bash
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json
DISCORD_BOT_TOKEN=your_discord_bot_token
ANTHROPIC_API_KEY=your_anthropic_api_key
MIRROR_API_KEY=your_mirror_api_key  # Optional, for blog publishing
```

**GitHub Secrets** (for GitHub Actions):
- `GOOGLE_SERVICE_ACCOUNT_KEY` - Base64-encoded service account JSON
- `DISCORD_BOT_TOKEN` - Discord bot token
- `ANTHROPIC_API_KEY` - Anthropic API key

### Access Control

- **Who can trigger manual summaries?**: All team members (department-based formatting)
- **Who can approve summaries?**: Product manager (configurable in YAML)
- **Who can access Google Docs?**: Organization members (Google Drive sharing settings)
- **Who can read Discord summaries?**: Members of "exec-summary" channel

---

## Scalability & Maintenance

### YAML-Driven Configuration

**No code changes needed for**:
- Schedule adjustments (`schedule.weekly_digest`)
- Adding monitored folders (`google_docs.monitored_folders`)
- New doc types (`digest_content.include_doc_types`)
- New departments (`department_mapping`)
- New output formats (`output_formats`)
- Distribution channels (`distribution.*`)

### Adding New Stakeholders

1. Add user to `department_mapping.user_id_to_department` in YAML
2. Or add Discord role to `department_mapping.role_to_department`
3. No code deployment needed

### Adding New Output Formats

1. Add format definition to `output_formats` in YAML:
```yaml
output_formats:
  new_format:
    audience: "new_stakeholder"
    length: "1_page"
    technical_level: "medium"
    focus: ["key_topics"]
```
2. Create prompt template: `config/prompts/new_format.md`
3. No code deployment needed

### Adjusting Schedule

1. Update `schedule.weekly_digest` in YAML (cron format)
2. If using GitHub Actions, update `.github/workflows/weekly-digest.yml`

### Monitoring & Alerts

**Metrics to Track**:
- Documents processed per week
- Translation generation time
- Approval rate (% of summaries approved)
- Error rate (failed translations, API errors)
- Stakeholder engagement (Discord thread replies)

**Alerts** (via Discord webhook):
- Weekly digest failure
- Google Docs API errors
- Translation timeout
- Missing approvals (reminder after 48 hours)

**Configuration** (from YAML):
```yaml
monitoring:
  log_level: "info"
  metrics_enabled: true
  alert_on_failure: true
  alert_webhook: "https://discord.com/api/webhooks/..."
```

---

## Implementation Roadmap

### Phase 1: Core Infrastructure (Week 1)

**Goal**: Basic weekly digest generation and posting to Discord

**Tasks**:
- [ ] Setup Google Docs MCP integration
- [ ] Create configuration system (YAML loader)
- [ ] Implement document scanner and classifier
- [ ] Setup Discord bot foundation
- [ ] Implement basic translation invocation

**Deliverables**:
- Google Docs monitoring working
- Weekly digest manually triggered via CLI
- Posted to Discord "exec-summary" channel

---

### Phase 2: Translation Pipeline (Week 2)

**Goal**: Department-specific formats and automated translation

**Tasks**:
- [ ] Create prompt template system
- [ ] Implement department detection
- [ ] Create format variants (executive, marketing, product, engineering, unified)
- [ ] Implement context assembly (related docs, wider context)
- [ ] Add manual trigger commands (`/generate-summary`)

**Deliverables**:
- Department auto-detection working
- Manual `/generate-summary` command functional
- Multiple format outputs available

---

### Phase 3: Output Distribution (Week 3)

**Goal**: Multi-platform distribution and review workflow

**Tasks**:
- [ ] Implement Google Docs publisher
- [ ] Implement Discord thread creation
- [ ] Setup approval workflow (reaction handling)
- [ ] Implement blog publisher (Mirror/Paragraph)
- [ ] Add review gate before blog publishing

**Deliverables**:
- Summaries created as Google Docs
- Discord threads with approval workflow
- Optional blog publishing (disabled by default)

---

### Phase 4: Scheduling & Automation (Week 4)

**Goal**: Automated weekly digest generation

**Tasks**:
- [ ] Implement weekly digest scheduler
- [ ] Create GitHub Actions workflow
- [ ] Setup cron job (or equivalent)
- [ ] Add dry-run mode for testing
- [ ] Implement failure alerts

**Deliverables**:
- Weekly digest runs automatically every Friday
- GitHub Actions workflow operational
- Alerts on failure

---

### Phase 5: Testing & Refinement (Week 5)

**Goal**: Testing, documentation, and pilot rollout

**Tasks**:
- [ ] Write integration tests
- [ ] Test with pilot users (Product Manager)
- [ ] Gather feedback and iterate
- [ ] Create user documentation (tool-setup.md, team-playbook.md)
- [ ] Monitor metrics and refine configs

**Deliverables**:
- Tested and validated system
- Documentation complete
- Pilot feedback incorporated
- Ready for full rollout

---

## Adoption & Change Management Plan

### Week 1: Pilot with Product Manager

- **Goal**: Validate weekly digest content and format
- **Activities**:
  - Setup infrastructure
  - Run first manual digest generation
  - PM reviews Google Doc and provides feedback
  - Iterate on YAML config (content focus, format length)
- **Success Criteria**: PM finds digest valuable and accurate

### Week 2: Add Executives

- **Goal**: Expand to COO and Head of BD
- **Activities**:
  - Add execs to Discord "exec-summary" channel
  - Generate executive format variant
  - Train on reading summaries and asking questions in threads
- **Success Criteria**: Execs read summaries and engage in threads

### Week 3: Enable Marketing & Data Analytics

- **Goal**: Full stakeholder coverage
- **Activities**:
  - Add marketing and data analytics teams
  - Train on `/generate-summary` commands
  - Enable department-specific format requests
- **Success Criteria**: Teams use manual trigger commands successfully

### Week 4: Enable Blog Publishing (Optional)

- **Goal**: Transform summaries into public content
- **Activities**:
  - Enable blog publishing in config
  - Test approval → publish workflow
  - Publish first blog post to Mirror/website
- **Success Criteria**: First blog post published successfully

### Week 5: Full Rollout & Optimization

- **Goal**: Mainstream adoption and refinement
- **Activities**:
  - Monitor engagement metrics
  - Gather stakeholder feedback
  - Refine YAML configs based on usage patterns
  - Document lessons learned
- **Success Criteria**: >80% of stakeholders reading weekly digests

---

## Success Metrics

### Quantitative Metrics

- **Stakeholder Engagement**: % of stakeholders reading weekly digests
- **Approval Rate**: % of summaries approved on first review
- **Time Savings**: Hours saved per week on manual summary writing
- **Ad-hoc Requests**: Number of `/generate-summary` commands used
- **Response Time**: Time from summary posting to questions in Discord thread

### Qualitative Metrics

- **Stakeholder Satisfaction**: Survey feedback on summary quality and usefulness
- **Context Accuracy**: Stakeholders report summaries include necessary wider context
- **Educational Value**: Stakeholders request deeper technical docs after reading summaries
- **Communication Culture**: Shift from reactive Q&A to proactive information sharing

---

## Next Steps

1. **Review this architecture**: Validate design decisions with team
2. **Finalize YAML config**: Fill in user mappings, department definitions
3. **Run `/implement-org-integration`**: Launch devops-crypto-architect to build the integration
4. **Pilot with PM**: Test first weekly digest with Product Manager
5. **Iterate and expand**: Gather feedback, refine, roll out to all stakeholders

---

## Appendix

### Document Type Classification

**How the system detects document types**:

| Doc Type | Detection Pattern | Example Title |
|----------|------------------|---------------|
| **PRD** | Title contains "PRD" or "Product Requirements" | "PRD - User Authentication Feature" |
| **SDD** | Title contains "SDD" or "Software Design" | "SDD - Authentication Architecture" |
| **Sprint** | Title contains "Sprint" or folder is "Sprint Updates" | "Sprint 1 - Authentication" |
| **Audit** | Title contains "Audit" or "Security" | "Security Audit - 2025-12-08" |
| **Deployment** | Title contains "Deployment" or "Infrastructure" | "Deployment Guide - Production" |

### Example Prompt Templates

**Executive Format** (`config/prompts/executive.md`):
```markdown
You are translating technical documentation into a 1-page executive summary for business leaders (COO, Head of BD).

**Audience**: Non-technical executives who need to understand business impact and risks
**Length**: 1 page (500-700 words)
**Technical Level**: Low (avoid jargon, use analogies)
**Focus**: Business value, risks, timeline, costs

**Structure**:
1. **Executive Summary** (2-3 sentences): What was done and why it matters
2. **Business Impact**: Revenue/cost/time savings, competitive advantage
3. **Key Decisions Made**: High-level architectural or product decisions
4. **Risks & Mitigation**: What could go wrong and how we're addressing it
5. **Next Steps**: What happens next and when

**Source Documents**:
{{documents}}

**Context**:
{{context}}

Generate the executive summary:
```

**Marketing Format** (`config/prompts/marketing.md`):
```markdown
You are translating technical documentation into a 1-page marketing brief for the marketing team.

**Audience**: Marketing team who needs to communicate features to customers
**Length**: 1 page (500-700 words)
**Technical Level**: Low (customer-friendly language)
**Focus**: Features, user value, positioning, competitive differentiation

**Structure**:
1. **Feature Overview** (2-3 sentences): What shipped and who it's for
2. **User Value Proposition**: Why customers care (pain solved, benefit gained)
3. **Key Capabilities**: Bulleted list of what users can do
4. **Technical Constraints**: Limitations or caveats to be aware of
5. **Positioning & Messaging**: How to talk about this feature

**Source Documents**:
{{documents}}

**Context**:
{{context}}

Generate the marketing brief:
```

---

**End of DevRel Integration Architecture Document**
