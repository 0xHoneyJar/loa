# Sprint Plan: Onomancer Bot Phase 1 MVP
# DevRel Documentation Automation System

**Project:** Onomancer Bot (DevRel Integration)
**Sprint Planner:** Sprint Planner Agent
**Date:** 2025-12-11
**Version:** 1.0
**Status:** Ready for Implementation

---

## Table of Contents

1. [Sprint Overview](#sprint-overview)
2. [MVP Definition](#mvp-definition)
3. [Team Composition](#team-composition)
4. [Sprint 1: Google Workspace Foundation](#sprint-1-google-workspace-foundation)
5. [Sprint 2: Transformation Pipeline Core](#sprint-2-transformation-pipeline-core)
6. [Sprint 3: Discord Commands Integration](#sprint-3-discord-commands-integration)
7. [Sprint 4: Security Controls & Testing](#sprint-4-security-controls--testing)
8. [Required API Keys & Credentials](#required-api-keys--credentials)
9. [Dependencies & Blockers](#dependencies--blockers)
10. [Success Metrics](#success-metrics)
11. [Risk Register](#risk-register)

---

## Sprint Overview

### Project Context

The Onomancer Bot transforms agentic-base's technical documentation into stakeholder-appropriate summaries stored in Google Workspace. This Phase 1 MVP (Option C - Bare Minimum) implements ONLY the core infrastructure and manual triggers, deferring automated triggers and advanced features to Phase 2.

**Why This Matters:** Technical work is trapped in developer-centric formats. Marketing, product managers, and leadership depend on developers to manually translate work. This creates a bottleneck that slows releases and prevents parallel workflows.

**Solution:** Discord bot + devrel-translator agent + Google Workspace = Self-service documentation access for all stakeholders.

### Current State Analysis

**Existing Implementation** (`/home/merlin/Documents/thj/code/agentic-base/devrel-integration/`):
- ✅ Discord bot infrastructure (bot.ts, commands, handlers)
- ✅ Linear integration with feedback capture and issue management
- ✅ Security controls (SecureTranslationInvoker, ContentSanitizer, SecretScanner, OutputValidator, ReviewQueue)
- ✅ `/translate` command with document resolution and validation
- ✅ Comprehensive logging and error handling
- ⚠️ **NOT IMPLEMENTED:** Google Workspace integration, Terraform IaC, automated transformation triggers

**Gap Analysis:**
- Google Workspace organization does NOT exist yet (needs creation)
- Google Docs API integration is NOT implemented (only stubbed references)
- Terraform infrastructure is NOT created (no `/terraform` directory)
- Automated file system watchers are NOT implemented
- Weekly digest cron job exists but NOT integrated with Google Docs
- `/exec-summary`, `/audit-summary`, `/blog-draft` commands NOT implemented

### Sprint Strategy

**Total Sprints:** 4 sprints × 10 days = 40 calendar days
**Sprint Duration:** 10 days (2 weeks) per sprint
**Team Size:** 4 developers (Jani, Soju, Zergucci, Zerker)
**Approach:** Infrastructure-first → Integration → Commands → Validation

**Sprint Sequence Rationale:**
1. **Sprint 1**: Foundation - Must create Google Workspace and Terraform before anything else
2. **Sprint 2**: Core Pipeline - Transform technical docs to personas, store in Google Docs
3. **Sprint 3**: User Interface - Discord commands for stakeholder self-service
4. **Sprint 4**: Security & Quality - Testing, validation, production readiness

### MVP Definition (Phase 1 - Option C)

**IN SCOPE:**
- ✅ Google Workspace organization creation (FR-1)
- ✅ Terraform IaC for folder structure and permissions (FR-1.2-1.7)
- ✅ Document transformation pipeline with 4 personas (FR-2)
- ✅ Discord slash commands: `/exec-summary`, `/audit-summary`, `/translate`, `/show-sprint` (FR-4.1, FR-4.2, FR-4.4, FR-4.7)
- ✅ Security controls (FR-6.1-6.6) - **Already implemented**, integrate with Google Docs
- ✅ Manual triggers ONLY (user invokes `/translate`)

**OUT OF SCOPE (Deferred to Phase 2):**
- ❌ Automated triggers (FR-3.4-3.7): PRD/SDD/sprint plan file watchers, `/review-sprint` listener, weekly digest automation
- ❌ Build visibility (FR-7): Linear webhooks, real-time notifications
- ❌ Knowledge base (FR-8): Discord archive, decision logs
- ❌ Marketing support (FR-9): Custom data extraction, RACI generation
- ❌ Hivemind integration (FR-5): LEARNINGS library, User Truth Canvas

---

## MVP Definition

### Phase 1 Scope (Option C - Bare Minimum)

**MUST HAVE (Phase 1):**
1. Google Workspace organization created with proper configuration
2. Terraform IaC managing folder structure (`/Products/{Project}/PRD|SDD|Sprints|Audits`, `/Shared/Weekly Digests`)
3. Document transformation pipeline using devrel-translator agent (4 personas: Leadership, Product, Marketing, DevRel)
4. Google Docs API integration (create, read, update documents with permissions)
5. Discord slash commands:
   - `/translate <project> <@document> for <audience>` - Manual translation trigger
   - `/exec-summary <sprint-id>` - Get executive summary
   - `/audit-summary <sprint-id>` - Get security audit summary
   - `/show-sprint [sprint-id]` - Get sprint status
6. Security controls integrated with Google Docs:
   - Secret scanning before storing in Google Docs
   - Content sanitization before LLM invocation
   - Output validation before publishing
   - Manual review queue for flagged content
7. Basic testing and production deployment

**OUT OF SCOPE (Phase 2):**
- Automated triggers (file watchers, webhook listeners, cron jobs beyond basic structure)
- Real-time build visibility and Linear webhooks
- Knowledge base features
- Marketing-specific features
- Hivemind LEARNINGS integration

### Success Criteria

Phase 1 is successful when:
- [ ] Google Workspace organization exists and Terraform can manage it
- [ ] `/translate` command generates 4 persona summaries and stores them in Google Docs
- [ ] Stakeholders can query summaries via Discord and access Google Docs links
- [ ] All security controls prevent secrets/PII from reaching Google Docs
- [ ] System is deployed and operational for team use

---

## Team Composition

**Total Team Size:** 11 people (4 developers focused on Onomancer Bot)

### Development Team (Onomancer Bot)

1. **Jani (DevOps/SysAdmin)**
   - Role: Infrastructure, Google Workspace setup, Terraform, deployment
   - Responsibilities: Sprint 1 lead, Terraform IaC, Google Workspace configuration, API credentials
   - Expertise: DevOps, SysAdmin, infrastructure automation

2. **Soju (CTO - Backend + Frontend)**
   - Role: Backend architecture, API integrations, transformation pipeline
   - Responsibilities: Sprint 2 lead, Google Docs API integration, transformation service
   - Expertise: Full-stack development, system architecture

3. **Zergucci (Smart Contracts + Backend/Frontend)**
   - Role: Discord bot enhancements, command handlers, security integration
   - Responsibilities: Sprint 3 lead, Discord commands, security controls integration
   - Expertise: Smart contracts, backend/frontend, Discord bot development

4. **Zerker (Frontend + Backend)**
   - Role: Testing, validation, documentation, UI polish
   - Responsibilities: Sprint 4 lead, comprehensive testing, production readiness
   - Expertise: Frontend development, testing, quality assurance

### Supporting Team Members

5. **Tian** - Data analyst
6. **Eileen & Lily** - Marketing communications
7. **Umeshu** - Business Development
8. **Jnova (COO)** - Operations leadership
9. **Cory** - Operations
10. **Gumi** - Head of Creative Design

**Note:** Supporting team members will be stakeholders who USE the Onomancer Bot once deployed.

---

## Sprint 1: Google Workspace Foundation ✅ COMPLETED
**Duration:** 10 days (2 weeks)
**Dates:** Sprint 1 Start Date → +10 days
**Lead:** Jani (DevOps/SysAdmin)
**Goal:** Establish Google Workspace organization and Terraform infrastructure for programmatic document management
**Status:** ✅ APPROVED by Senior Technical Lead (2025-12-12)

### Sprint Goal

Create brand new Google Workspace organization for "The Honey Jar" and implement Terraform IaC to manage folder structure, permissions, and service accounts. This is the foundation upon which all document transformation features depend.

### Why This Sprint Comes First

**Critical Dependency:** Cannot store documents in Google Docs without Google Workspace. Cannot manage infrastructure without Terraform. All subsequent sprints (transformation pipeline, Discord commands) depend on this foundation.

**Risk Mitigation:** Google Workspace setup involves external dependencies (domain verification, billing, API quotas). Completing this first allows maximum time for resolving provisioning issues.

### Deliverables

- [ ] Google Workspace organization created and configured for "The Honey Jar"
- [ ] Domain configured and verified (if custom domain used)
- [ ] Terraform project structure created in `/devrel-integration/terraform/`
- [ ] Terraform IaC manages folder structure programmatically
- [ ] Service account created with Google Docs API permissions
- [ ] Stakeholder group permissions configured
- [ ] Terraform state management configured (remote backend + locking)
- [ ] Documentation: Terraform setup guide, workspace configuration runbook

### Technical Tasks

#### Task 1.1: Google Workspace Provisioning (Jani, 2 days)

**Description:** Create brand new Google Workspace organization for "The Honey Jar" including domain setup, billing, and initial configuration.

**Acceptance Criteria:**
- [ ] Google Workspace organization exists with organization name "The Honey Jar"
- [ ] Primary admin account created (Jani's account)
- [ ] Billing configured and payment method added (Jani coordinates with finance)
- [ ] Domain configured (either use existing thehoneyjar.xyz or create new)
- [ ] Domain verification completed (DNS TXT records added)
- [ ] Organization-level settings configured (2FA enforcement, external sharing policies)

**Estimated Effort:** 2 days (includes waiting for domain verification propagation)

**Assigned To:** Jani

**Dependencies:**
- Budget approval (already confirmed)
- Domain access (if using existing domain, need DNS access)
- Credit card for billing setup

**Testing Requirements:**
- Verify admin account can access Google Workspace Admin Console
- Verify domain verification status shows "Verified"
- Verify can create test user accounts
- Verify can access Google Drive API in Google Cloud Console

**Documentation:**
- Document admin credentials in secure vault
- Document organization ID and domain name
- Create runbook for adding new users

---

#### ✅ Task 1.2: Terraform Project Bootstrap (Jani + Soju, 2 days)

**Description:** Initialize Terraform project structure and configure providers for Google Workspace and Google Cloud Platform.

**Acceptance Criteria:**
- [x] Terraform project created in `/devrel-integration/terraform/`
- [x] Directory structure organized:
  ```
  terraform/
  ├── main.tf                 # Root configuration
  ├── variables.tf            # Input variables
  ├── outputs.tf              # Output values
  ├── versions.tf             # Provider versions
  ├── backend.tf              # Remote state configuration
  ├── modules/
  │   ├── workspace/          # Google Workspace resources
  │   │   ├── folders.tf      # Drive folder structure
  │   │   ├── permissions.tf  # IAM and sharing settings
  │   │   └── service-accounts.tf
  │   └── monitoring/         # Optional: Logging and monitoring
  ├── environments/
  │   ├── dev/                # Development environment
  │   │   └── terraform.tfvars
  │   └── prod/               # Production environment
  │       └── terraform.tfvars
  └── README.md               # Setup and usage guide
  ```
- [x] Providers configured:
  - `google` provider for GCP resources
  - `google-workspace` provider for Workspace resources (if available)
  - Alternative: Use `google` provider with Drive API + custom scripts
- [x] Remote state backend configured (Google Cloud Storage bucket)
- [x] State locking enabled (using GCS bucket metadata)
- [x] Terraform version pinned (>= 1.6.0)
- [x] `.gitignore` configured to exclude sensitive files (`.tfstate`, `*.tfvars` with secrets)

**Estimated Effort:** 2 days

**Assigned To:** Jani (lead), Soju (code review and architecture input)

**Dependencies:**
- Google Workspace organization created (Task 1.1)
- GCP project created for Terraform state storage
- Terraform installed locally (version 1.6.0+)

**Testing Requirements:**
- `terraform init` succeeds without errors
- `terraform plan` shows no resources to create (empty initial state)
- Can run `terraform plan` and `terraform apply` without authentication errors
- Remote state stored in GCS bucket and accessible across team

**Documentation:**
- Document Terraform setup steps in `/terraform/README.md`
- Document provider authentication methods
- Document state backend configuration

---

#### ✅ Task 1.3: Service Account & API Credentials (Jani, 1 day)

**Description:** Create GCP service account with Google Drive and Google Docs API permissions. Generate and securely store credentials for bot access.

**Acceptance Criteria:**
- [x] GCP service account created: `onomancer-bot@{project-id}.iam.gserviceaccount.com`
- [x] Google Drive API enabled in GCP project
- [x] Google Docs API enabled in GCP project
- [x] Service account granted necessary IAM roles:
  - `roles/drive.admin` or custom role with specific permissions
- [x] Service account JSON key generated and downloaded
- [x] Credentials stored securely in `/devrel-integration/secrets/.env.local`:
  ```bash
  GOOGLE_SERVICE_ACCOUNT_EMAIL="onomancer-bot@{project-id}.iam.gserviceaccount.com"
  GOOGLE_SERVICE_ACCOUNT_KEY_PATH="/path/to/service-account-key.json"
  # OR
  GOOGLE_SERVICE_ACCOUNT_KEY_JSON='{"type":"service_account","project_id":"..."}'
  ```
- [x] Secrets file permissions set to 600 (read/write owner only)
- [x] Service account added to Google Workspace with domain-wide delegation (if needed)

**Estimated Effort:** 1 day

**Assigned To:** Jani

**Dependencies:**
- Google Workspace organization created (Task 1.1)
- GCP project exists

**Testing Requirements:**
- Verify service account can authenticate to Google Drive API using credentials
- Test API call: List files in root Google Drive folder
- Test API call: Create test document in Google Drive
- Verify service account has permissions to create folders and documents

**Documentation:**
- Document service account email and project ID
- Document API scopes required
- Document credential rotation process
- Add credentials to team password manager (not in git)

---

#### ✅ Task 1.4: Terraform Folder Structure (Soju + Jani, 3 days)

**Description:** Implement Terraform configuration to programmatically create Google Drive folder structure following PRD spec (Option A: by product/project with audience subfolders).

**Acceptance Criteria:**
- [x] Terraform code creates complete folder hierarchy:
  ```
  /The Honey Jar (root)
    /Products
      /MiBera
        /PRD
          /Executive Summaries
        /SDD
          /Executive Summaries
        /Sprints
          /Sprint-1 (example)
            /Executive Summaries
        /Audits
          /2025-12-10-Sprint-1-Audit (example)
            /Executive Summaries
      /FatBera
        ... (same structure)
      /Interpol
        ... (same structure)
      /Set & Forgetti
        ... (same structure)
    /Shared
      /Weekly Digests
        /2025-12-10 (example)
          /Executive Summaries
      /Templates
  ```
- [x] Folders created using Google Drive API via Terraform
- [x] Folder IDs captured as Terraform outputs for bot runtime use
- [x] Terraform code is idempotent (can run multiple times safely)
- [x] Variables allow easy addition of new products/projects
- [x] Each `/Executive Summaries` subfolder has 4 subfolders:
  - `Leadership`
  - `Product`
  - `Marketing`
  - `DevRel`

**Estimated Effort:** 3 days

**Assigned To:** Soju (lead Terraform development), Jani (infrastructure review and testing)

**Dependencies:**
- Service account and API credentials configured (Task 1.3)
- Terraform project initialized (Task 1.2)

**Testing Requirements:**
- Run `terraform plan` shows folder creation resources
- Run `terraform apply` successfully creates all folders
- Verify folders visible in Google Drive UI (logged in as admin)
- Run `terraform apply` again (idempotency test) - no changes detected
- Run `terraform destroy` (in dev environment) successfully removes folders
- Verify folder IDs output by Terraform are accessible via API

**Implementation Notes:**
- Use `google_drive_folder` resource (if using custom provider) or `google_storage_bucket` + Drive API
- Alternative: Use `null_resource` with `local-exec` provisioner calling Drive API via `curl` or `gcloud`
- Store folder IDs in Terraform output and export to JSON file for bot runtime
- Consider using Terraform `for_each` to iterate over product list for DRY code

**Documentation:**
- Document folder structure in Terraform comments
- Document how to add new products (update variables)
- Document folder ID export process

---

#### ✅ Task 1.5: Stakeholder Permissions (Jani, 2 days)

**Description:** Configure Google Drive folder permissions for stakeholder groups (Leadership, Product, Marketing, DevRel, Developers) using Terraform or Google Workspace Admin APIs.

**Acceptance Criteria:**
- [x] Google Groups created in Google Workspace for each stakeholder group:
  - `leadership@thehoneyjar.xyz` (read access to all Executive Summaries)
  - `product@thehoneyjar.xyz` (read access to PRDs, SDDs, Sprint Reports)
  - `marketing@thehoneyjar.xyz` (read access to Marketing summaries)
  - `devrel@thehoneyjar.xyz` (read access to DevRel summaries, Technical Docs)
  - `developers@thehoneyjar.xyz` (read/write access to all folders)
- [x] Permissions configured on folders:
  - `/Executive Summaries/Leadership/` → `leadership@` has Reader access
  - `/Executive Summaries/Product/` → `product@` has Reader access
  - `/Executive Summaries/Marketing/` → `marketing@` has Reader access
  - `/Executive Summaries/DevRel/` → `devrel@` has Reader access
  - All folders → `developers@` has Editor access
  - Service account → Owner access to all folders
- [x] Permissions managed via Terraform (or documented manual process)
- [x] External sharing disabled for all folders (internal only)
- [x] Link sharing disabled (must have explicit permission to access)

**Estimated Effort:** 2 days

**Assigned To:** Jani

**Dependencies:**
- Folder structure created (Task 1.4)
- Google Workspace organization configured (Task 1.1)

**Testing Requirements:**
- Add test user to each Google Group
- Verify test users can access appropriate folders
- Verify test users CANNOT access folders outside their permissions
- Verify service account can create documents in all folders
- Test external user cannot access shared links

**Implementation Notes:**
- Google Groups may need to be created manually in Google Workspace Admin Console (not easily managed by Terraform)
- Document manual Google Groups setup in runbook
- Use `google_drive_file_permission` resource (if available) or Drive API for permissions
- Consider using Terraform `for_each` to iterate over permission mappings

**Documentation:**
- Document Google Groups and their members
- Document permission model (who can access what)
- Document process for adding new stakeholders to groups
- Create runbook for permission audits

---

### Sprint 1 Dependencies

**External Dependencies:**
- Google Workspace signup approval (typically instant, but may require billing verification)
- Domain verification DNS propagation (up to 48 hours, typically 1-2 hours)
- GCP API quotas and limits (unlikely to hit in MVP, but monitor)

**Internal Dependencies:**
- Budget approval for Google Workspace subscription (confirmed)
- Jani has access to DNS management for domain verification
- Team has GCP project or can create one

### Sprint 1 Risks & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Domain verification delays (DNS propagation) | Blocks Google Workspace setup (2 days delay) | Medium | Start domain verification on Day 1. Have alternative domain ready. |
| Google Workspace API quota limits | Blocks folder creation (1 day delay) | Low | Request quota increase proactively. Use exponential backoff in API calls. |
| Terraform Google Workspace provider limitations | Increases implementation complexity (2 days delay) | High | Accept hybrid approach (Terraform + manual setup). Document manual steps. |
| Team unfamiliar with Terraform | Slower development (1-2 days delay) | Medium | Jani leads with Soju shadowing. Use Terraform documentation and examples. |
| Service account permission issues | Blocks API access (1 day delay) | Medium | Test service account permissions incrementally. Document troubleshooting steps. |

### Sprint 1 Success Metrics

**Primary Metrics:**
- [ ] Google Workspace organization operational and accessible
- [ ] Terraform `apply` successfully creates all folders without errors
- [ ] Service account can create test document in every folder
- [ ] All stakeholder groups can access appropriate folders

**Secondary Metrics:**
- [ ] Terraform code reviewed and approved by Soju
- [ ] Documentation complete and reviewed
- [ ] Zero manual steps required after initial Google Workspace signup (all automated via Terraform)

**Technical Debt:**
- If Terraform Google Workspace provider is insufficient, document manual setup steps as technical debt for Phase 2 improvement

---

## Sprint 2: Transformation Pipeline Core ✅ REVIEW APPROVED
**Duration:** 10 days (2 weeks)
**Dates:** Sprint 2 Start Date → +10 days
**Lead:** Soju (Backend + Frontend)
**Goal:** Implement document transformation pipeline that converts technical documents to persona-specific summaries and stores them in Google Docs with proper metadata
**Status:** ✅ APPROVED by Senior Technical Lead (2025-12-13) - Ready for Security Audit

### Sprint Goal

Build the core transformation pipeline using the devrel-translator agent and existing security controls (SecureTranslationInvoker, ContentSanitizer, SecretScanner). Integrate with Google Docs API to create, store, and link persona-specific summaries. This enables manual translation via `/translate` command.

### Why This Sprint Comes Second

**Dependency:** Requires Google Workspace infrastructure (Sprint 1) to store documents. This sprint implements the "transformation engine" that powers all Discord commands in Sprint 3.

**Value:** Once complete, developers can manually test transformation pipeline before exposing to stakeholders via Discord commands.

### Deliverables

- [x] Google Docs API client library integrated (`googleapis` npm package)
- [x] `GoogleDocsStorageService` implemented (create, read, update documents with permissions)
- [x] Transformation pipeline integrated with Google Docs (output saved to correct folders)
- [x] Context aggregation from Linear, GitHub, local files working
- [x] 4 persona-specific transformation prompts implemented (Leadership, Product, Marketing, DevRel)
- [x] Document metadata frontmatter generated for all outputs
- [x] Bidirectional linking (original document ↔ persona summaries)
- [x] Comprehensive error handling and retry logic
- [x] Unit tests for Google Docs integration and transformation pipeline
- [x] Manual testing script to verify end-to-end transformation

### Technical Tasks

#### Task 2.1: Google Docs API Client Integration (Soju, 2 days)

**Description:** Integrate `googleapis` npm package and implement `GoogleDocsStorageService` for creating, reading, and updating Google Docs with proper authentication.

**Acceptance Criteria:**
- [ ] `googleapis` npm package added to dependencies
- [ ] Service account authentication configured using credentials from Sprint 1
- [ ] `GoogleDocsStorageService` class implemented in `/src/services/google-docs-storage.ts`:
  ```typescript
  interface GoogleDocsStorageService {
    // Create new document in specified folder
    createDocument(params: {
      title: string;
      content: string; // Markdown or plain text
      folderId: string; // From Terraform outputs
      metadata?: DocumentMetadata;
    }): Promise<{ documentId: string; webViewLink: string }>;

    // Read document content
    getDocument(documentId: string): Promise<{ title: string; content: string }>;

    // Update existing document
    updateDocument(documentId: string, content: string): Promise<void>;

    // Set document permissions
    setPermissions(documentId: string, permissions: Permission[]): Promise<void>;

    // Search for documents by folder and name
    searchDocuments(folderId: string, query: string): Promise<Document[]>;
  }
  ```
- [ ] Error handling for API rate limits (exponential backoff + retry)
- [ ] Error handling for authentication failures
- [ ] Error handling for insufficient permissions
- [ ] Logging for all API operations (success and failure)

**Estimated Effort:** 2 days

**Assigned To:** Soju

**Dependencies:**
- Service account credentials from Sprint 1 (Task 1.3)
- Folder IDs from Terraform outputs (Task 1.4)

**Testing Requirements:**
- Unit tests:
  - Test document creation with valid parameters
  - Test authentication with service account credentials
  - Test error handling for invalid folder ID
  - Test retry logic for rate limit errors
- Integration tests:
  - Create test document in Google Drive
  - Read created document and verify content
  - Update document content
  - Set permissions and verify via Drive UI
  - Search for documents by name
- Manual tests:
  - Verify created documents visible in Google Drive UI
  - Verify document permissions match configuration
  - Verify markdown formatting preserved

**Implementation Notes:**
- Use `google-auth-library` for service account authentication
- Use `drive.files.create` API for document creation
- Use `docs.documents.get` and `docs.documents.batchUpdate` for content operations
- Consider using `google-drive-uploader` wrapper for simpler API
- Handle markdown-to-Google Docs formatting (basic support: headers, lists, code blocks)
- Store folder ID mapping (product → folder ID) in configuration or environment variables

**Documentation:**
- Document Google Docs API authentication setup
- Document rate limits and quota management
- Document error codes and troubleshooting
- Add JSDoc comments to all public methods

---

#### Task 2.2: Persona Transformation Prompts (Soju + Zergucci, 2 days)

**Description:** Implement 4 persona-specific transformation prompts for the devrel-translator agent (Leadership, Product, Marketing, DevRel) with tone, length, and focus variations.

**Acceptance Criteria:**
- [ ] Prompt templates implemented for each persona in `/src/prompts/persona-prompts.ts`:
  - **Leadership:** Executive summary (1-2 pages, business-focused, plain language, metrics-driven)
  - **Product:** Technical article (2-3 pages, feature-focused, user stories, acceptance criteria)
  - **Marketing:** Blog draft (1-2 pages, customer-focused, benefits, use cases, engaging tone)
  - **DevRel:** Technical tutorial (3-4 pages, code-level, implementation details, architecture)
- [ ] Each prompt includes:
  - Role context: "You are a {persona} translator for technical documentation"
  - Audience description: "Your audience is {audience characteristics}"
  - Output format: "Generate a {length} {format} with {structure}"
  - Tone guidelines: "Use {tone} language, avoid {things to avoid}"
  - Content guidelines: "Focus on {key points}, include {required sections}"
  - Example structure provided
- [ ] Prompt templates use variables for dynamic content:
  ```typescript
  interface PersonaPromptParams {
    documentType: 'prd' | 'sdd' | 'sprint' | 'audit' | 'reviewer';
    projectName: string;
    sourceContent: string;
    additionalContext?: {
      linearIssues?: LinearIssue[];
      githubPRs?: GitHubPR[];
      discordFeedback?: DiscordMessage[];
    };
  }
  ```
- [ ] Prompts tested with devrel-translator agent using Anthropic API
- [ ] Output quality reviewed by team (tone, length, relevance)

**Estimated Effort:** 2 days

**Assigned To:** Soju (lead prompt engineering), Zergucci (review and test outputs)

**Dependencies:**
- None (can be developed in parallel with Task 2.1)

**Testing Requirements:**
- Unit tests:
  - Test prompt template variable substitution
  - Test prompt length validation (ensure within API token limits)
- Integration tests:
  - Generate sample output for each persona using real PRD/SDD
  - Review output for tone, length, and content quality
  - Compare outputs across personas (should be distinct)
- Manual tests:
  - Team review of generated summaries
  - Stakeholder review (optional: share with Leadership/Product/Marketing for feedback)

**Implementation Notes:**
- Use existing `SecureTranslationInvoker` service (already implements Anthropic API calls)
- Prompts should be stored as string templates or files (easy to update without code changes)
- Consider using YAML or JSON for prompt configuration (easier for non-developers to edit)
- Include examples in prompts to guide model output (few-shot learning)
- Test with Claude Sonnet 3.5 (primary model) and Claude Haiku (fallback for cost optimization)

**Prompt Design Principles:**
- **Leadership:** Focus on business impact, risks, decisions, metrics, timeline
- **Product:** Focus on features, user stories, acceptance criteria, dependencies, roadmap
- **Marketing:** Focus on customer benefits, value propositions, use cases, storytelling
- **DevRel:** Focus on technical implementation, code examples, architecture, API usage

**Documentation:**
- Document prompt design decisions
- Document how to update prompts
- Document expected output format for each persona
- Include sample outputs in documentation

---

#### Task 2.3: Context Aggregation Integration (Soju, 2 days)

**Description:** Extend existing `ContextAssembler` service to aggregate data from Linear API, GitHub API, Discord message history, and local filesystem for richer transformation context.

**Acceptance Criteria:**
- [ ] `ContextAssembler.assemble()` extended to support multiple source types:
  ```typescript
  interface UnifiedContext {
    sourceDocuments: Array<{ name: string; content: string; path: string }>;
    linearIssues?: LinearIssue[];
    githubPRs?: GitHubPR[];
    discordFeedback?: DiscordMessage[];
    hivemindLearnings?: Learning[]; // Optional for Phase 2
    metadata: {
      projectName: string;
      sprintId?: string;
      aggregatedAt: Date;
      sources: string[];
    };
  }
  ```
- [ ] Linear API integration:
  - Query issues by project, sprint, or labels
  - Include issue titles, descriptions, status, assignees
  - Include issue comments (optional: limit to recent)
  - Use existing Linear MCP integration
- [ ] GitHub API integration:
  - Query PRs by repository and branch
  - Include PR titles, descriptions, status, commits
  - Use existing GitHub MCP integration
- [ ] Discord message history integration:
  - Query messages by channel ID and date range
  - Include feedback messages (captured via 📌 reactions)
  - Filter for relevant context (not all messages)
- [ ] Local filesystem integration:
  - Read documents from `docs/` directory
  - Support document shorthand resolution (@prd → docs/prd.md)
  - Use existing `DocumentResolver` service
- [ ] Context size limits enforced (to avoid API token limits):
  - Max 50 Linear issues per aggregation
  - Max 20 GitHub PRs per aggregation
  - Max 100 Discord messages per aggregation
  - Total context < 100,000 tokens (leave room for prompt + output)

**Estimated Effort:** 2 days

**Assigned To:** Soju

**Dependencies:**
- Linear MCP integration (already exists)
- GitHub MCP integration (already exists)
- Discord bot message history access (already exists)

**Testing Requirements:**
- Unit tests:
  - Test context aggregation with mock data
  - Test context size limit enforcement
  - Test error handling for API failures
- Integration tests:
  - Aggregate context for real project (e.g., MiBera)
  - Verify Linear issues fetched correctly
  - Verify GitHub PRs fetched correctly
  - Verify Discord messages fetched correctly
  - Verify total context size within limits
- Manual tests:
  - Review aggregated context for completeness
  - Verify context relevance (not too much noise)

**Implementation Notes:**
- Use existing Linear and GitHub MCP tools (don't rewrite API clients)
- Cache aggregated context for 5 minutes to avoid redundant API calls
- Log context aggregation statistics (sources used, item counts, total size)
- Implement graceful degradation (if one source fails, continue with others)

**Documentation:**
- Document context aggregation logic
- Document API rate limits and caching strategy
- Document how to configure context sources
- Document context size optimization strategies

---

#### Task 2.4: Transformation Pipeline Integration (Soju + Zergucci, 3 days)

**Description:** Integrate Google Docs storage, persona prompts, and context aggregation into a unified transformation pipeline. Generate 4 persona-specific summaries from a single technical document and store in Google Docs.

**Acceptance Criteria:**
- [ ] `TransformationPipeline` service implemented in `/src/services/transformation-pipeline.ts`:
  ```typescript
  interface TransformationPipeline {
    transform(params: {
      sourceDocument: { name: string; content: string; path: string };
      projectName: string;
      documentType: 'prd' | 'sdd' | 'sprint' | 'audit' | 'reviewer';
      aggregateContext?: boolean; // If true, fetch Linear/GitHub/Discord context
    }): Promise<TransformationResult>;
  }

  interface TransformationResult {
    personaSummaries: {
      leadership: { documentId: string; webViewLink: string };
      product: { documentId: string; webViewLink: string };
      marketing: { documentId: string; webViewLink: string };
      devrel: { documentId: string; webViewLink: string };
    };
    originalDocument: { documentId: string; webViewLink: string };
    metadata: {
      generatedAt: Date;
      sourceDocuments: string[];
      transformationDurationMs: number;
      warnings: string[];
    };
  }
  ```
- [ ] Pipeline orchestrates:
  1. Read source document(s) from filesystem or Google Docs
  2. Aggregate context from Linear, GitHub, Discord (optional)
  3. For each persona (Leadership, Product, Marketing, DevRel):
     - Sanitize content using `ContentSanitizer` (existing)
     - Scan for secrets using `SecretScanner` (existing)
     - Generate summary using `SecureTranslationInvoker` with persona prompt
     - Validate output using `OutputValidator` (existing)
     - Store in Google Docs using `GoogleDocsStorageService`
     - Set permissions based on persona (Leadership → leadership@thehoneyjar.xyz)
  4. Store original document in Google Docs (if not already there)
  5. Create bidirectional links (original ↔ summaries)
  6. Return document IDs and web view links
- [ ] Security controls integrated:
  - Sanitization before LLM invocation
  - Secret scanning before storing in Google Docs
  - Output validation before publishing
  - Manual review queue for flagged content (use existing `ReviewQueue`)
- [ ] Error handling:
  - Retry failed LLM API calls (exponential backoff)
  - Retry failed Google Docs API calls
  - Graceful degradation (if one persona fails, continue with others)
  - Rollback on critical errors (delete partially created documents)
- [ ] Logging and audit trail:
  - Log each transformation step (source, target, duration)
  - Log security scan results (sanitization, secrets detected)
  - Log API errors and retries
  - Store transformation metadata in Google Docs document properties

**Estimated Effort:** 3 days

**Assigned To:** Soju (lead integration), Zergucci (security controls review and testing)

**Dependencies:**
- Google Docs API client (Task 2.1)
- Persona prompts (Task 2.2)
- Context aggregation (Task 2.3)
- Existing security services (ContentSanitizer, SecretScanner, OutputValidator, ReviewQueue)

**Testing Requirements:**
- Unit tests:
  - Test transformation pipeline with mock services
  - Test error handling and retry logic
  - Test graceful degradation (partial failures)
  - Test security controls integration
- Integration tests:
  - Transform real PRD document to 4 persona summaries
  - Verify all 4 summaries created in correct Google Docs folders
  - Verify bidirectional links work (click link in summary → navigate to original)
  - Verify permissions set correctly (Leadership folder → leadership@ can access)
  - Transform document with secrets → verify secrets redacted
  - Transform document with suspicious content → verify flagged for review
- Load tests:
  - Transform 10 documents concurrently (test API rate limits)
  - Measure transformation duration (target: <60 seconds per document)
- Manual tests:
  - Team review of generated summaries for quality
  - Verify Google Docs formatting is readable
  - Verify links and permissions work as expected

**Implementation Notes:**
- Use existing `SecureTranslationInvoker` service (don't rewrite security controls)
- Consider using job queue (Bull, BullMQ) for async transformation (optional: defer to Phase 2)
- Store folder ID mapping in configuration (projectName → folderId) loaded from Terraform outputs
- Implement transformation as atomic transaction where possible (rollback on failure)
- Use TypeScript interfaces for strong typing and IDE autocomplete

**Documentation:**
- Document transformation pipeline architecture
- Document security controls integration
- Document error handling and retry logic
- Document performance optimization strategies
- Add sequence diagram showing transformation flow

---

#### Task 2.5: Testing & Documentation (Zerker + Soju, 1 day)

**Description:** Comprehensive testing of transformation pipeline end-to-end and documentation of setup, usage, and troubleshooting.

**Acceptance Criteria:**
- [ ] Unit tests written for all new services (Google Docs, persona prompts, pipeline)
- [ ] Integration tests cover end-to-end transformation (source document → 4 Google Docs summaries)
- [ ] Test coverage > 80% for new code
- [ ] Manual testing checklist completed:
  - Transform PRD document → verify 4 summaries created
  - Transform SDD document → verify 4 summaries created
  - Transform sprint report → verify 4 summaries created
  - Transform with context aggregation → verify Linear/GitHub/Discord data included
  - Transform with secrets → verify secrets redacted
  - Transform with suspicious content → verify flagged for manual review
- [ ] Performance benchmarks documented:
  - Transformation duration (target: <60 seconds)
  - API rate limit handling (no errors under normal load)
  - Memory usage (should not exceed 512MB per transformation)
- [ ] Documentation updated:
  - `/devrel-integration/docs/TRANSFORMATION_PIPELINE.md` created
  - Setup guide: How to configure transformation pipeline
  - Usage guide: How to trigger transformation manually
  - Troubleshooting guide: Common errors and solutions
  - Architecture diagram: Transformation pipeline components

**Estimated Effort:** 1 day

**Assigned To:** Zerker (lead testing), Soju (code review and documentation)

**Dependencies:**
- Transformation pipeline implemented (Task 2.4)

**Testing Requirements:**
- Run all unit tests: `npm run test`
- Run integration tests: `npm run test:integration`
- Run manual testing checklist
- Performance testing: `npm run test:load`
- Code coverage report: `npm run test:coverage`

**Documentation Requirements:**
- Architecture diagram showing transformation pipeline flow
- Setup guide with step-by-step instructions
- Usage examples with code snippets
- Troubleshooting guide with error codes and solutions
- Performance optimization tips

---

### Sprint 2 Dependencies

**External Dependencies:**
- Google Docs API rate limits (1000 requests/100 seconds per user)
- Anthropic API rate limits (varies by tier, monitor usage)
- Linear/GitHub API rate limits (existing MCP tools handle this)

**Internal Dependencies:**
- Google Workspace infrastructure from Sprint 1
- Existing security services (ContentSanitizer, SecretScanner, OutputValidator, ReviewQueue)
- Linear and GitHub MCP integrations (already implemented)

### Sprint 2 Risks & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Google Docs API formatting limitations (markdown → Google Docs) | Reduced output quality (low impact) | High | Accept basic formatting only. Document limitations. Consider HTML→Docs conversion library. |
| Anthropic API rate limits (high volume transformations) | Transformation failures (medium impact) | Medium | Implement exponential backoff. Use job queue for async processing. Monitor API usage. |
| Transformation quality issues (bad prompts) | Stakeholders unhappy with summaries (high impact) | Medium | Iterate on prompts with team feedback. Include examples in prompts. Use Claude Sonnet 3.5 (best quality). |
| Context aggregation too slow (many API calls) | Transformation timeout (medium impact) | Low | Cache aggregated context. Implement parallel API calls. Set aggressive timeouts. |
| Security controls block legitimate content (false positives) | Manual review overhead (medium impact) | Medium | Tune secret scanner patterns. Implement whitelist for common false positives. Document review process. |

### Sprint 2 Success Metrics

**Primary Metrics:**
- [ ] Can transform any technical document to 4 persona summaries
- [ ] All summaries stored in correct Google Docs folders with correct permissions
- [ ] Transformation completes in <60 seconds per document
- [ ] Zero secrets leaked to Google Docs (100% blocked by scanner)

**Secondary Metrics:**
- [ ] Test coverage > 80%
- [ ] All integration tests passing
- [ ] Documentation complete and reviewed by team
- [ ] Stakeholders review sample summaries and provide feedback (positive)

**Technical Debt:**
- Document any markdown formatting limitations
- Document any performance bottlenecks
- Document any API rate limit workarounds

---

## Sprint 3: Discord Commands Integration
**Duration:** 10 days (2 weeks)
**Dates:** Sprint 3 Start Date → +10 days
**Lead:** Zergucci (Backend/Frontend + Discord bot)
**Goal:** Implement Discord slash commands for stakeholder self-service document access, enabling manual transformation triggers and summary queries

### Sprint Goal

Build Discord slash commands that expose transformation pipeline to stakeholders. Implement `/translate`, `/exec-summary`, `/audit-summary`, and `/show-sprint` commands with role-based access control, error handling, and helpful UX.

### Why This Sprint Comes Third

**Dependency:** Requires transformation pipeline (Sprint 2) to generate summaries. This sprint is the "user interface" layer that makes the system accessible to non-technical stakeholders.

**Value:** Enables stakeholders to self-serve documentation needs without asking developers. Demonstrates MVP value immediately.

### Deliverables

- [ ] `/translate <project> <@document> for <audience>` command implemented
- [ ] `/exec-summary <sprint-id>` command implemented
- [ ] `/audit-summary <sprint-id>` command implemented
- [ ] `/show-sprint [sprint-id]` command implemented
- [ ] Role-based access control (Discord roles → persona mapping)
- [ ] Document shorthand resolution (@prd → docs/prd.md, etc.)
- [ ] Error handling and user-friendly error messages
- [ ] Command help and usage examples
- [ ] Discord command registration and deployment
- [ ] Testing with real Discord server and users
- [ ] User documentation for commands

### Technical Tasks

#### Task 3.1: Update Slash Command Definitions (Zergucci, 1 day)

**Description:** Add new command definitions to `/src/commands/definitions.ts` for MVP commands (`/translate`, `/exec-summary`, `/audit-summary`). Update existing `/show-sprint` command if needed.

**Acceptance Criteria:**
- [ ] `/translate` command defined:
  ```typescript
  new SlashCommandBuilder()
    .setName('translate')
    .setDescription('Generate stakeholder summary from technical document')
    .addStringOption(option =>
      option.setName('project')
        .setDescription('Project name (e.g., mibera, fatbera)')
        .setRequired(true)
    )
    .addStringOption(option =>
      option.setName('document')
        .setDescription('Document reference (e.g., @prd, @sdd, docs/sprint.md)')
        .setRequired(true)
    )
    .addStringOption(option =>
      option.setName('audience')
        .setDescription('Target audience')
        .setRequired(true)
        .addChoices(
          { name: 'Leadership', value: 'leadership' },
          { name: 'Product', value: 'product' },
          { name: 'Marketing', value: 'marketing' },
          { name: 'DevRel', value: 'devrel' }
        )
    )
  ```
- [ ] `/exec-summary` command defined:
  ```typescript
  new SlashCommandBuilder()
    .setName('exec-summary')
    .setDescription('Get executive summary for a sprint')
    .addStringOption(option =>
      option.setName('sprint-id')
        .setDescription('Sprint identifier (e.g., sprint-1, mibera-sprint-1)')
        .setRequired(true)
    )
  ```
- [ ] `/audit-summary` command defined:
  ```typescript
  new SlashCommandBuilder()
    .setName('audit-summary')
    .setDescription('Get security audit summary for a sprint')
    .addStringOption(option =>
      option.setName('sprint-id')
        .setDescription('Sprint identifier (e.g., sprint-1, sprint-1-remediation)')
        .setRequired(true)
    )
  ```
- [ ] `/show-sprint` command updated (if needed) to match new format
- [ ] Command definitions exported and ready for registration

**Estimated Effort:** 1 day

**Assigned To:** Zergucci

**Dependencies:**
- None (can be done in parallel with other tasks)

**Testing Requirements:**
- Run `npm run register-commands` to register commands with Discord
- Verify commands appear in Discord UI with correct options
- Verify autocomplete works for audience choices

**Documentation:**
- Document command registration process
- Document how to add new commands

---

#### Task 3.2: Implement `/translate` Command Handler (Zergucci + Soju, 3 days)

**Description:** Implement command handler for `/translate <project> <@document> for <audience>` that validates input, resolves document references, triggers transformation pipeline, and responds with Google Docs link.

**Acceptance Criteria:**
- [ ] Command handler implemented in `/src/handlers/translation-commands.ts`:
  ```typescript
  async function handleTranslateSlashCommand(interaction: CommandInteraction): Promise<void> {
    // 1. Extract and validate parameters
    const project = interaction.options.getString('project', true);
    const documentRef = interaction.options.getString('document', true);
    const audience = interaction.options.getString('audience', true);

    // 2. Validate project name (must match existing product in Google Drive)
    // 3. Resolve document reference (@prd → docs/prd.md, etc.)
    // 4. Check user permissions (via Discord roles)
    // 5. Trigger transformation pipeline
    // 6. Respond with Google Docs link or error message
  }
  ```
- [ ] Parameter validation:
  - Project name validated against known projects (MiBera, FatBera, Interpol, Set & Forgetti)
  - Document reference resolved using existing `DocumentResolver` service
  - Audience validated (leadership, product, marketing, devrel)
- [ ] Document shorthand resolution implemented:
  - `@prd` → `docs/prd.md`
  - `@sdd` → `docs/sdd.md`
  - `@sprint` → `docs/sprint.md`
  - `@reviewer` → `docs/a2a/reviewer.md`
  - `@audit` → Latest `SECURITY-AUDIT-REPORT.md`
  - Full paths also accepted: `@docs/a2a/engineer-feedback.md`
- [ ] Integration with transformation pipeline:
  - Call `TransformationPipeline.transform()` with resolved document
  - Pass project name and audience to pipeline
  - Aggregate context (Linear/GitHub/Discord) optional based on document type
- [ ] Response handling:
  - Success: Respond with Google Docs link and summary metadata
  - Error: Respond with user-friendly error message and troubleshooting hints
  - Loading: Show "Generating summary... this may take up to 60 seconds" message
  - Update response when complete (use interaction.editReply())
- [ ] Permission checking:
  - Check user has appropriate Discord role for transformation
  - Optional: Check user has permission to access Google Docs folder
- [ ] Error handling:
  - Invalid project name → suggest valid projects
  - Document not found → suggest valid document references
  - Transformation failed → show error details and retry instructions
  - Security scan blocked → explain why and show manual review process

**Estimated Effort:** 3 days

**Assigned To:** Zergucci (lead implementation), Soju (code review and pipeline integration)

**Dependencies:**
- Transformation pipeline (Sprint 2, Task 2.4)
- Document resolver (already exists, may need updates)
- Slash command definitions (Task 3.1)

**Testing Requirements:**
- Unit tests:
  - Test parameter validation
  - Test document shorthand resolution
  - Test error handling
- Integration tests:
  - Test `/translate mibera @prd for leadership`
  - Test `/translate fatbera @sdd for devrel`
  - Test with invalid project name
  - Test with invalid document reference
  - Test with document that doesn't exist
  - Test permission checking
- Manual tests:
  - Invoke command in Discord server
  - Verify loading message appears
  - Verify response updates with Google Docs link
  - Click Google Docs link and verify access
  - Test with different personas (leadership, product, marketing, devrel)

**Implementation Notes:**
- Use existing `SecureTranslationInvoker` for transformation (don't reimplement)
- Use existing `DocumentResolver` for path resolution
- Store project→folder ID mapping in configuration (load from Terraform outputs)
- Implement timeout handling (transformation may take 30-60 seconds)
- Use Discord interaction deferReply() for long-running operations
- Add command to interaction handler in `/src/handlers/interactions.ts`

**User Experience:**
```
User: /translate mibera @prd for leadership
Bot: 🔄 Generating leadership summary for MiBera PRD... This may take up to 60 seconds.

[30 seconds later]

Bot: ✅ **Leadership Summary Generated**

**Document:** MiBera PRD
**Audience:** Leadership
**Generated:** 2025-12-11 14:30 UTC

📄 [View Summary in Google Docs](https://docs.google.com/document/d/...)

**Summary Preview:**
> MiBera is a decentralized finance protocol that enables...

**Metadata:**
  • Source: docs/prd.md
  • Context: 15 Linear issues, 5 GitHub PRs
  • Generated in 28 seconds
  • ✅ Security scan passed
```

**Documentation:**
- Document command usage with examples
- Document document shorthand references
- Document error messages and troubleshooting

---

#### Task 3.3: Implement `/exec-summary` Command Handler (Zergucci, 2 days)

**Description:** Implement command handler for `/exec-summary <sprint-id>` that fetches pre-generated executive summary for a sprint and responds with Google Docs link.

**Acceptance Criteria:**
- [ ] Command handler implemented in `/src/handlers/summary-commands.ts`:
  ```typescript
  async function handleExecSummary(interaction: CommandInteraction): Promise<void> {
    // 1. Extract sprint-id parameter
    // 2. Parse sprint-id to extract project and sprint number (e.g., "mibera-sprint-1" or "sprint-1")
    // 3. Detect user role (via Discord roles)
    // 4. Search Google Docs for matching summary document
    // 5. Respond with Google Docs link or "not found" message
  }
  ```
- [ ] Sprint ID parsing:
  - Support formats: `sprint-1`, `mibera-sprint-1`, `Sprint-1`, `sprint1`
  - Extract project name (if provided) and sprint number
  - Default to current project if not specified (configurable)
- [ ] User role detection:
  - Map Discord roles to personas (e.g., `@Leadership` role → leadership persona)
  - Default to "unified" summary if role not detected
  - Allow user to override persona with optional parameter (future enhancement)
- [ ] Google Docs search:
  - Search folder: `/Products/{Project}/Sprints/Sprint-{N}/Executive Summaries/{Persona}/`
  - Look for document named `{Persona}-Sprint-{N}.md` or similar
  - Use `GoogleDocsStorageService.searchDocuments()`
- [ ] Response handling:
  - Success: Respond with Google Docs link and summary preview
  - Not found: Suggest running `/translate` to generate summary
  - Multiple matches: Show list and ask user to clarify
- [ ] Error handling:
  - Invalid sprint ID format → show expected format
  - Sprint not found → suggest valid sprint IDs
  - Permission denied → explain permission requirements

**Estimated Effort:** 2 days

**Assigned To:** Zergucci

**Dependencies:**
- Google Docs storage service (Sprint 2, Task 2.1)
- Slash command definitions (Task 3.1)
- Pre-generated summaries from transformation pipeline (Sprint 2)

**Testing Requirements:**
- Unit tests:
  - Test sprint ID parsing
  - Test user role detection
  - Test Google Docs search
- Integration tests:
  - Test with pre-generated summary (create test summary in Google Docs)
  - Test with non-existent sprint ID
  - Test with different Discord roles (map to correct persona)
  - Test permission checking
- Manual tests:
  - Invoke command in Discord server
  - Verify correct summary returned based on user role
  - Click Google Docs link and verify access

**Implementation Notes:**
- Store sprint ID → folder ID mapping in database or configuration
- Consider caching Google Docs search results (5 minute TTL)
- Implement graceful fallback if role detection fails

**User Experience:**
```
User: /exec-summary sprint-1
Bot: ✅ **Sprint 1 Executive Summary**

**Project:** MiBera
**Sprint:** Sprint 1
**Your Role:** Leadership

📄 [View Executive Summary in Google Docs](https://docs.google.com/document/d/...)

**Summary Preview:**
> Sprint 1 delivered the core authentication system with JWT tokens...

**Key Achievements:**
  • Implemented user authentication (FR-1.1)
  • Completed database migration (FR-1.2)
  • Security audit passed with 0 critical issues

**Next Steps:**
  • Sprint 2 begins on 2025-12-15
```

**Documentation:**
- Document command usage with examples
- Document sprint ID format
- Document role detection logic

---

#### Task 3.4: Implement `/audit-summary` Command Handler (Zergucci, 1 day)

**Description:** Implement command handler for `/audit-summary <sprint-id>` that fetches pre-generated security audit summary and responds with Google Docs link and severity breakdown.

**Acceptance Criteria:**
- [ ] Command handler implemented in `/src/handlers/summary-commands.ts`:
  ```typescript
  async function handleAuditSummary(interaction: CommandInteraction): Promise<void> {
    // 1. Extract sprint-id parameter
    // 2. Parse sprint-id (support "sprint-1" or "sprint-1-remediation")
    // 3. Detect user role
    // 4. Search Google Docs for audit summary
    // 5. Respond with Google Docs link and severity breakdown
  }
  ```
- [ ] Sprint ID parsing:
  - Support formats: `sprint-1`, `sprint-1-remediation`, `mibera-sprint-1-audit`
  - Distinguish between initial audit and remediation report
- [ ] Google Docs search:
  - Search folder: `/Products/{Project}/Audits/{Date}-Sprint-{N}-Audit/Executive Summaries/{Persona}/`
  - Look for `{Persona}-Audit-Sprint-{N}.md` or similar
- [ ] Severity breakdown display:
  - Parse audit report for CRITICAL/HIGH/MEDIUM/LOW counts
  - Display summary: "5 issues found (0 CRITICAL, 1 HIGH, 3 MEDIUM, 1 LOW)"
  - Highlight CRITICAL and HIGH issues
- [ ] Response handling:
  - Success: Respond with Google Docs link and severity breakdown
  - Not found: Explain audit hasn't been performed yet
  - Multiple audits: Show list with dates
- [ ] Error handling similar to `/exec-summary`

**Estimated Effort:** 1 day

**Assigned To:** Zergucci

**Dependencies:**
- Google Docs storage service (Sprint 2, Task 2.1)
- Slash command definitions (Task 3.1)
- Pre-generated audit summaries (Sprint 2)

**Testing Requirements:**
- Integration tests:
  - Test with pre-generated audit summary
  - Test with remediation report
  - Test with non-existent audit
- Manual tests:
  - Verify severity breakdown displayed correctly
  - Verify Google Docs link access

**User Experience:**
```
User: /audit-summary sprint-1
Bot: ✅ **Sprint 1 Security Audit Summary**

**Project:** MiBera
**Sprint:** Sprint 1
**Audit Date:** 2025-12-10

📄 [View Audit Summary in Google Docs](https://docs.google.com/document/d/...)

**Severity Breakdown:**
  • 🔴 CRITICAL: 0 issues
  • 🟠 HIGH: 1 issue
  • 🟡 MEDIUM: 3 issues
  • 🟢 LOW: 5 issues

**Status:** ✅ All CRITICAL and HIGH issues resolved

**Top Issue:**
  • HIGH-001: Insufficient input validation on user registration endpoint
```

**Documentation:**
- Document command usage
- Document audit report format

---

#### Task 3.5: Update `/show-sprint` Command (Zergucci, 1 day)

**Description:** Update existing `/show-sprint` command to integrate with Google Docs summaries and provide link to full sprint report.

**Acceptance Criteria:**
- [ ] Existing `/show-sprint` command enhanced:
  - Fetch sprint status from Linear API (existing functionality)
  - Add Google Docs link to full sprint report
  - Add link to executive summary (if generated)
  - Improve formatting and UX
- [ ] Optional parameter: `sprint-id` (default to current sprint)
- [ ] Response includes:
  - In Progress tasks (count + assignees)
  - Completed tasks (count)
  - Blocked tasks (count + blockers)
  - Sprint timeline (start/end dates)
  - 📄 Link to full sprint report in Google Docs
  - 📊 Link to executive summary (if available)

**Estimated Effort:** 1 day

**Assigned To:** Zergucci

**Dependencies:**
- Google Docs storage service (Sprint 2, Task 2.1)
- Existing `/show-sprint` command (already implemented)

**Testing Requirements:**
- Integration tests:
  - Test with active sprint
  - Test with completed sprint
  - Test with non-existent sprint
- Manual tests:
  - Verify sprint status displayed correctly
  - Verify Google Docs links work

**User Experience:**
```
User: /show-sprint
Bot: 📊 **Sprint 1 Status** (MiBera)

**Timeline:**
  • Started: 2025-12-01
  • Ends: 2025-12-11 (2 days remaining)

**Progress:**
  • ✅ Completed: 8 tasks
  • 🔄 In Progress: 3 tasks (Soju, Zergucci, Jani)
  • 🚫 Blocked: 1 task (waiting on API approval)

**Documents:**
  • 📄 [Sprint Plan](https://docs.google.com/document/d/...)
  • 📊 [Executive Summary](https://docs.google.com/document/d/...)

**Next Steps:**
  • Review sprint completion criteria
  • Schedule retrospective meeting
```

---

#### Task 3.6: Role-Based Access Control (Zergucci, 1 day)

**Description:** Implement Discord role → persona mapping for automatic audience detection. Users with `@Leadership` role automatically get leadership summaries.

**Acceptance Criteria:**
- [ ] Role mapping configuration in `/config/role-mapping.yml`:
  ```yaml
  role_mappings:
    # Discord Role ID → Persona
    "1234567890": "leadership"  # @Leadership role
    "0987654321": "product"     # @Product role
    "1122334455": "marketing"   # @Marketing role
    "5566778899": "devrel"      # @DevRel role
    "9988776655": "devrel"      # @Developer role → devrel summaries
  default_persona: "product"  # Fallback if role not matched
  ```
- [ ] `RoleMapper` service implemented in `/src/services/role-mapper.ts`:
  ```typescript
  class RoleMapper {
    detectPersona(user: Discord.User, guild: Discord.Guild): Persona {
      // Get user's roles
      // Check role mapping configuration
      // Return matching persona or default
    }
  }
  ```
- [ ] Integration with command handlers:
  - `/exec-summary` uses detected persona
  - `/audit-summary` uses detected persona
  - `/translate` can override detected persona (explicit audience parameter)
- [ ] Fallback logic:
  - If user has no matching role, use default persona ("product")
  - If user has multiple roles, use highest priority role (Leadership > Product > Marketing > DevRel)
- [ ] Testing with different Discord roles

**Estimated Effort:** 1 day

**Assigned To:** Zergucci

**Dependencies:**
- Discord bot role access (already exists)

**Testing Requirements:**
- Unit tests:
  - Test role detection with different Discord roles
  - Test fallback logic
  - Test priority handling for multiple roles
- Integration tests:
  - Test `/exec-summary` with different user roles
  - Verify correct persona summaries returned
- Manual tests:
  - Assign test users different roles
  - Verify persona detection works correctly

**Implementation Notes:**
- Use Discord.js `GuildMember.roles` to get user roles
- Cache role mappings in memory (reload on bot restart)
- Log role detection for debugging

**Documentation:**
- Document role mapping configuration
- Document how to add new roles
- Document persona priority logic

---

#### Task 3.7: Command Registration & Deployment (Zergucci + Jani, 1 day)

**Description:** Register new slash commands with Discord API and deploy updated bot to development environment for testing.

**Acceptance Criteria:**
- [ ] Command registration script updated in `/src/commands/register.ts`
- [ ] New commands registered with Discord API:
  - `/translate`
  - `/exec-summary`
  - `/audit-summary`
  - Updated `/show-sprint`
- [ ] Commands visible in Discord UI with autocomplete
- [ ] Bot deployed to development Discord server for testing
- [ ] All commands tested end-to-end by team
- [ ] Production deployment checklist prepared (for Sprint 4)

**Estimated Effort:** 1 day

**Assigned To:** Zergucci (command registration), Jani (deployment)

**Dependencies:**
- All command handlers implemented (Tasks 3.2-3.6)

**Testing Requirements:**
- Run `npm run register-commands` successfully
- Verify commands appear in Discord UI
- Test each command in development Discord server
- Verify autocomplete works
- Verify error messages are user-friendly

**Documentation:**
- Document command registration process
- Document deployment process for development environment
- Document testing checklist

---

### Sprint 3 Dependencies

**External Dependencies:**
- Discord API command registration (typically instant)
- Google Docs API for document search (rate limits monitored)

**Internal Dependencies:**
- Transformation pipeline from Sprint 2
- Google Docs storage service from Sprint 2
- Existing Discord bot infrastructure

### Sprint 3 Risks & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Discord command registration delays or errors | Blocks testing (1 day delay) | Low | Test command registration early. Have fallback to legacy text commands. |
| User role detection fails (role IDs change) | Wrong persona summaries delivered (medium impact) | Medium | Implement robust role mapping with fallback. Log role detection. Document role setup. |
| Commands timeout (transformation takes >15s) | Poor user experience (low impact) | Medium | Use Discord interaction.deferReply(). Show loading message. Set expectation (<60s). |
| Permission errors accessing Google Docs | Users can't access summaries (high impact) | Medium | Test permissions thoroughly. Implement retry with permission adjustment. Log permission errors. |
| Command parameter validation too strict | Users frustrated by errors (medium impact) | Low | Test with real users. Provide helpful error messages. Document valid inputs. |

### Sprint 3 Success Metrics

**Primary Metrics:**
- [ ] All 4 commands (`/translate`, `/exec-summary`, `/audit-summary`, `/show-sprint`) functional
- [ ] Commands tested by team with positive feedback
- [ ] Role-based access control working correctly (right persona for right role)
- [ ] Zero command timeout errors (<60 second response time)

**Secondary Metrics:**
- [ ] User-friendly error messages for all error cases
- [ ] Command help documentation complete
- [ ] Team trained on command usage
- [ ] Positive feedback from early testing

**Technical Debt:**
- Document any Discord API limitations
- Document any permission edge cases
- Document any UX improvements needed

---

## Sprint 4: Security Controls & Testing
**Duration:** 10 days (2 weeks)
**Dates:** Sprint 4 Start Date → +10 days
**Lead:** Zerker (Frontend + Backend, Testing focus)
**Goal:** Comprehensive testing, security validation, production deployment preparation, and MVP launch

### Sprint Goal

Validate entire system end-to-end with security focus, comprehensive testing, performance optimization, and production deployment. Ensure MVP is production-ready, secure, and delivers on success criteria.

### Why This Sprint Comes Fourth

**Quality Gate:** Cannot deploy to production without thorough testing and security validation. This sprint ensures the system is reliable, secure, and meets stakeholder needs.

**Risk Mitigation:** Discover and fix issues before stakeholders use the system. Production deployment requires confidence in stability and security.

### Deliverables

- [ ] Comprehensive security audit of complete system
- [ ] Integration testing of end-to-end workflows
- [ ] Performance testing and optimization
- [ ] Production deployment scripts and runbooks
- [ ] Monitoring and alerting configured
- [ ] User documentation and training materials
- [ ] Production deployment completed
- [ ] MVP success criteria validation
- [ ] Retrospective and Phase 2 planning

### Technical Tasks

#### Task 4.1: Security Audit & Validation (Zerker + Zergucci, 3 days)

**Description:** Comprehensive security audit of complete Onomancer Bot system focusing on secrets management, API security, permission controls, and data privacy.

**Acceptance Criteria:**
- [ ] Security checklist completed:
  - **Secrets Management:**
    - [ ] All secrets stored in `/secrets/.env.local` with 600 permissions
    - [ ] No secrets committed to git (verify .gitignore)
    - [ ] Service account key securely stored
    - [ ] Google Workspace credentials properly secured
    - [ ] Anthropic API key not exposed in logs
  - **API Security:**
    - [ ] Google Docs API calls use service account authentication
    - [ ] Rate limiting implemented for all external APIs
    - [ ] API error handling prevents information disclosure
    - [ ] Retry logic with exponential backoff
  - **Access Control:**
    - [ ] Discord role-based access control functional
    - [ ] Google Docs permissions enforced (stakeholder groups)
    - [ ] Service account has minimum necessary permissions
    - [ ] No over-permissioned roles
  - **Input Validation:**
    - [ ] All Discord command inputs validated
    - [ ] Document paths validated (no path traversal)
    - [ ] Project names validated against whitelist
    - [ ] Audience parameter validated
  - **Content Security:**
    - [ ] Secret scanner blocks secrets before storing in Google Docs
    - [ ] Content sanitizer prevents prompt injection
    - [ ] Output validator checks for PII leakage
    - [ ] Manual review queue functional for flagged content
  - **Audit Logging:**
    - [ ] All transformations logged with timestamp and user
    - [ ] All security scan results logged
    - [ ] All API errors logged
    - [ ] Logs stored securely with limited access
- [ ] Security scan using existing audit tools:
  - Run `/audit` command on devrel-integration codebase
  - Address CRITICAL and HIGH findings
  - Document MEDIUM and LOW findings as technical debt
- [ ] Penetration testing:
  - Test prompt injection attacks
  - Test path traversal attempts
  - Test permission bypass attempts
  - Test secret leakage scenarios
- [ ] Security documentation updated:
  - Document threat model
  - Document security controls
  - Document incident response procedures

**Estimated Effort:** 3 days

**Assigned To:** Zerker (lead security testing), Zergucci (code review and remediation)

**Dependencies:**
- All features implemented (Sprints 1-3)

**Testing Requirements:**
- Run automated security scans (npm audit, eslint-plugin-security)
- Manual penetration testing with attack scenarios
- Review all CRITICAL and HIGH security findings from `/audit` command
- Verify all security controls functional

**Documentation:**
- Document security audit results
- Document remediation actions taken
- Document residual risks accepted
- Document security monitoring procedures

---

#### Task 4.2: Integration & End-to-End Testing (Zerker + Soju, 2 days)

**Description:** Comprehensive integration testing of complete workflows from Discord command to Google Docs summary, including error paths and edge cases.

**Acceptance Criteria:**
- [ ] End-to-end test scenarios implemented:
  - **Happy Path 1:** User runs `/translate mibera @prd for leadership`
    - Verify document resolved correctly
    - Verify transformation generates leadership summary
    - Verify summary stored in correct Google Docs folder
    - Verify user can access Google Docs link
    - Verify permissions correct (leadership@ group has access)
  - **Happy Path 2:** User runs `/exec-summary sprint-1`
    - Verify sprint ID parsed correctly
    - Verify user role detected (e.g., Leadership)
    - Verify correct persona summary returned
    - Verify Google Docs link accessible
  - **Happy Path 3:** User runs `/audit-summary sprint-1`
    - Verify audit summary found
    - Verify severity breakdown displayed
    - Verify Google Docs link accessible
  - **Error Path 1:** User runs `/translate` with invalid project name
    - Verify helpful error message
    - Verify suggestions for valid project names
  - **Error Path 2:** User runs `/translate` with non-existent document
    - Verify helpful error message
    - Verify suggestions for valid document references
  - **Error Path 3:** Transformation fails (API error)
    - Verify graceful error handling
    - Verify retry logic triggered
    - Verify user notified with clear message
  - **Error Path 4:** Secret scanner detects secrets in document
    - Verify transformation blocked
    - Verify user notified about security issue
    - Verify flagged for manual review
  - **Edge Case 1:** User runs `/translate` during high load
    - Verify rate limiting functional
    - Verify queuing or backoff
  - **Edge Case 2:** Multiple users run commands concurrently
    - Verify no race conditions
    - Verify all transformations complete correctly
- [ ] Automated integration test suite:
  - Tests run via `npm run test:integration`
  - All scenarios covered with assertions
  - Test coverage report generated
- [ ] Manual testing with real users:
  - Invite team members to test in development Discord server
  - Collect feedback on UX, error messages, performance
  - Document bugs and issues found

**Estimated Effort:** 2 days

**Assigned To:** Zerker (lead testing), Soju (test automation support)

**Dependencies:**
- All features implemented (Sprints 1-3)

**Testing Requirements:**
- Run automated integration tests: `npm run test:integration`
- Run manual testing checklist with team
- Collect feedback from 5+ team members
- Document all bugs and prioritize fixes

**Documentation:**
- Document integration testing approach
- Document test scenarios and expected results
- Document bugs found and fixes applied

---

#### Task 4.3: Performance Testing & Optimization (Soju + Zerker, 2 days)

**Description:** Performance testing of transformation pipeline, API calls, and Discord commands under realistic load. Optimize bottlenecks.

**Acceptance Criteria:**
- [ ] Performance benchmarks measured:
  - **Transformation Duration:**
    - Target: <60 seconds per document transformation
    - Measure: Median, p95, p99 latency
    - Test: Transform 20 documents and measure duration
  - **API Response Time:**
    - Target: Google Docs API calls <5 seconds p95
    - Target: Anthropic API calls <30 seconds p95
    - Measure: API call latency for each service
  - **Discord Command Response Time:**
    - Target: <15 seconds initial response (with "loading" message)
    - Target: <60 seconds final response (with Google Docs link)
    - Measure: Time from command invocation to response
  - **Concurrent Load:**
    - Test: 10 concurrent transformations
    - Target: All complete successfully without errors
    - Measure: Success rate, error rate, latency
  - **Memory Usage:**
    - Target: Bot process <512MB memory under normal load
    - Target: No memory leaks (stable memory over 1 hour)
    - Measure: Memory usage over time
- [ ] Performance optimization:
  - Identify bottlenecks (slowest operations)
  - Optimize slow API calls (caching, batching)
  - Optimize context aggregation (parallel API calls)
  - Optimize Google Docs API calls (batch operations)
  - Implement caching where appropriate (5 minute TTL)
- [ ] Load testing:
  - Use k6, Artillery, or similar tool
  - Simulate 10 concurrent users running commands
  - Measure throughput, latency, error rate
  - Verify system stable under load
- [ ] Performance documentation:
  - Document performance benchmarks
  - Document optimization strategies applied
  - Document performance monitoring recommendations

**Estimated Effort:** 2 days

**Assigned To:** Soju (lead optimization), Zerker (load testing)

**Dependencies:**
- All features implemented (Sprints 1-3)

**Testing Requirements:**
- Run performance benchmarks: `npm run test:performance`
- Run load tests with k6 or Artillery
- Monitor API rate limits during testing
- Verify memory usage stable over 1 hour

**Documentation:**
- Document performance benchmarks
- Document optimization strategies
- Document performance monitoring procedures

---

#### Task 4.4: Production Deployment & Monitoring (Jani + Zerker, 2 days)

**Description:** Deploy Onomancer Bot to production environment with monitoring, alerting, and operational runbooks.

**Acceptance Criteria:**
- [ ] Production environment configured:
  - Production Discord server (or use existing)
  - Production Google Workspace (from Sprint 1)
  - Production secrets configured in `/secrets/.env.local`
  - Production Terraform state (separate from dev)
  - Production environment variables set
- [ ] Deployment method selected and documented:
  - Option A: PM2 (recommended for simple deployment)
  - Option B: Docker + Docker Compose
  - Option C: Kubernetes (if existing K8s cluster available)
- [ ] Deployment scripts created:
  - Build script: `npm run build`
  - Start script: `npm start` (or PM2 ecosystem.config.js)
  - Stop script: Graceful shutdown
  - Health check script: Verify bot running
- [ ] Monitoring configured:
  - Log aggregation (Winston to file or external service)
  - Health check endpoint: `GET /health` (already exists)
  - Metrics endpoint: `GET /metrics` (already exists)
  - Alerting for critical errors (email or Slack integration)
  - Uptime monitoring (UptimeRobot, Pingdom, or similar)
- [ ] Operational runbooks created:
  - How to deploy new version
  - How to rollback deployment
  - How to restart bot
  - How to check logs
  - How to respond to alerts
  - How to add new commands
  - How to rotate secrets
- [ ] Production deployment executed:
  - Deploy bot to production server/environment
  - Verify bot connects to Discord
  - Verify bot can access Google Docs
  - Verify slash commands registered
  - Verify commands functional
  - Verify monitoring operational
- [ ] Backup and disaster recovery:
  - Document backup procedures for Google Workspace
  - Document backup procedures for Terraform state
  - Document disaster recovery procedures

**Estimated Effort:** 2 days

**Assigned To:** Jani (lead deployment), Zerker (monitoring setup and testing)

**Dependencies:**
- All features tested and approved (Tasks 4.1-4.3)
- Production environment provisioned

**Testing Requirements:**
- Test deployment to staging environment first
- Test rollback procedure
- Test health check and monitoring
- Test alerting (trigger test alert)
- Verify logs accessible and readable

**Deployment Checklist:**
- [ ] Production secrets configured
- [ ] Terraform applied to production
- [ ] Bot deployed and running
- [ ] Discord commands registered
- [ ] Health check passing
- [ ] Monitoring configured
- [ ] Alerting tested
- [ ] Runbooks documented
- [ ] Team trained on operations

**Documentation:**
- Document production deployment process
- Document monitoring and alerting setup
- Document operational runbooks
- Document backup and disaster recovery procedures

---

#### Task 4.5: User Documentation & Training (Zerker + Zergucci, 1 day)

**Description:** Create user-facing documentation for stakeholders explaining how to use Onomancer Bot commands, what to expect, and how to get help.

**Acceptance Criteria:**
- [ ] User documentation created in `/devrel-integration/docs/USER_GUIDE.md`:
  - **Introduction:** What is Onomancer Bot and why use it
  - **Getting Started:** How to access bot in Discord
  - **Commands:**
    - `/translate <project> <@document> for <audience>` - Manual translation
    - `/exec-summary <sprint-id>` - Get sprint executive summary
    - `/audit-summary <sprint-id>` - Get security audit summary
    - `/show-sprint [sprint-id]` - Get sprint status
  - **Examples:** Real-world usage examples with screenshots
  - **Document References:** Supported document shorthand (@prd, @sdd, etc.)
  - **Personas:** What each persona summary contains (Leadership, Product, Marketing, DevRel)
  - **Troubleshooting:** Common errors and solutions
  - **FAQ:** Frequently asked questions
  - **Support:** How to get help (contact developer team)
- [ ] Quick reference card:
  - 1-page cheat sheet with common commands
  - Printable or shareable as image
  - Post in Discord channel for easy access
- [ ] Video walkthrough (optional):
  - 5-minute demo video showing command usage
  - Record screen and narrate
  - Upload to internal wiki or YouTube (unlisted)
- [ ] Team training session:
  - Schedule 30-minute training session with team
  - Demo all commands live
  - Q&A session
  - Collect feedback
- [ ] Feedback mechanism:
  - Create Discord channel for bot feedback
  - Document how users can report bugs or request features
  - Assign team member to monitor feedback channel

**Estimated Effort:** 1 day

**Assigned To:** Zerker (lead documentation), Zergucci (review and training session)

**Dependencies:**
- All features tested and deployed (Tasks 4.1-4.4)

**Testing Requirements:**
- Have non-technical team member review documentation
- Test documentation by following steps exactly
- Verify screenshots accurate and helpful

**Documentation:**
- User guide in Markdown format
- Quick reference card (PDF or image)
- Video walkthrough (optional)
- Training session slides (optional)

---

### Sprint 4 Dependencies

**External Dependencies:**
- Production server/environment access
- Production Google Workspace operational
- Team availability for training session

**Internal Dependencies:**
- All features from Sprints 1-3 implemented and tested
- Security controls functional
- Performance optimization complete

### Sprint 4 Risks & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Security vulnerabilities discovered late | Blocks production deployment (2-3 days delay) | Medium | Run security audit early in sprint. Prioritize CRITICAL and HIGH findings. Accept MEDIUM/LOW as technical debt. |
| Performance issues under load | Poor user experience or outages (high impact) | Medium | Load test early. Optimize bottlenecks proactively. Have rollback plan. |
| Production deployment issues (environment, permissions) | Delays MVP launch (1-2 days) | Low | Deploy to staging first. Test thoroughly. Have rollback procedure. |
| User training insufficient | Low adoption or misuse | Medium | Create comprehensive documentation. Hold live training. Monitor feedback channel. |
| Monitoring/alerting gaps | Outages not detected promptly | Low | Test monitoring thoroughly. Trigger test alerts. Document monitoring procedures. |

### Sprint 4 Success Metrics

**Primary Metrics:**
- [ ] All CRITICAL and HIGH security findings remediated
- [ ] All integration tests passing (100% pass rate)
- [ ] Performance benchmarks met (transformation <60s, commands <15s initial response)
- [ ] Production deployment successful (bot running, commands functional)
- [ ] Team trained and documentation published

**Secondary Metrics:**
- [ ] Zero production incidents in first 48 hours
- [ ] Positive feedback from team training session
- [ ] User documentation complete and reviewed
- [ ] Monitoring and alerting operational

**MVP Success Validation:**
- [ ] Stakeholders can self-serve documentation via Discord commands
- [ ] Transformation pipeline generates 4 persona summaries correctly
- [ ] Google Docs links accessible with correct permissions
- [ ] Security controls prevent secrets/PII leakage
- [ ] System deployed and operational for team use

**Technical Debt:**
- Document all MEDIUM and LOW security findings for Phase 2
- Document performance optimization opportunities for Phase 2
- Document UX improvements suggested by team

---

## Required API Keys & Credentials

**Google Cloud Platform & Google Workspace:**
1. Google Workspace organization ID
2. Google Workspace admin account credentials
3. GCP project ID
4. Service account email and JSON key file
5. Google Drive API enabled
6. Google Docs API enabled
7. Terraform state GCS bucket name

**Discord:**
1. Discord bot token (already exists)
2. Discord application ID
3. Discord guild (server) ID
4. Developer role ID
5. Admin role ID

**Anthropic (Claude API):**
1. Anthropic API key (already exists)
2. API organization ID (if applicable)

**Linear (already configured):**
1. Linear API token
2. Linear team ID

**GitHub (already configured):**
1. GitHub personal access token
2. GitHub organization name

**Configuration Files:**
- `/devrel-integration/secrets/.env.local` (all secrets stored here)
- `/devrel-integration/config/role-mapping.yml` (Discord role → persona mapping)
- `/devrel-integration/terraform/terraform.tfvars` (Terraform variables)

**Who Obtains Credentials:**
- **Jani:** Google Workspace organization setup, service account, GCP project
- **Jani:** Production secrets configuration
- **Team:** Anthropic, Discord, Linear, GitHub credentials (already have)

---

## Dependencies & Blockers

### External Dependencies

1. **Google Workspace Signup** (Sprint 1, Day 1)
   - Risk: Billing verification may take 1-2 business days
   - Mitigation: Start signup process immediately
   - Owner: Jani

2. **Domain Verification** (Sprint 1, Day 1-2)
   - Risk: DNS propagation may take up to 48 hours
   - Mitigation: Use existing domain if possible, have backup domain ready
   - Owner: Jani

3. **Google Cloud Platform Project** (Sprint 1, Day 2)
   - Risk: GCP quota limits or approval delays
   - Mitigation: Use existing GCP project if available, request quota increase proactively
   - Owner: Jani

4. **Anthropic API Rate Limits** (Sprint 2)
   - Risk: High volume transformations may hit rate limits
   - Mitigation: Implement exponential backoff, monitor API usage, request rate limit increase if needed
   - Owner: Soju

5. **Production Server/Environment** (Sprint 4)
   - Risk: Server provisioning delays
   - Mitigation: Provision server early, have cloud hosting option as backup (DigitalOcean, AWS, etc.)
   - Owner: Jani

### Internal Dependencies

1. **Terraform Expertise** (Sprint 1)
   - Dependency: Jani and Soju familiar with Terraform
   - Risk: Learning curve may slow development
   - Mitigation: Jani leads with Soju shadowing, use Terraform documentation and examples
   - Owner: Jani

2. **Google Docs API Familiarity** (Sprint 2)
   - Dependency: Team familiar with Google Docs API
   - Risk: API complexity may slow integration
   - Mitigation: Use googleapis npm package, reference official examples, allocate buffer time
   - Owner: Soju

3. **Existing Security Services** (Sprint 2)
   - Dependency: ContentSanitizer, SecretScanner, OutputValidator, ReviewQueue already implemented
   - Risk: Integration issues or bugs
   - Mitigation: Review existing code, test thoroughly, fix bugs as discovered
   - Owner: Zergucci

4. **Team Availability** (All Sprints)
   - Dependency: 4 developers (Jani, Soju, Zergucci, Zerker) available for 10-day sprints
   - Risk: Team members unavailable due to other priorities
   - Mitigation: Confirm availability upfront, have backup developers identified
   - Owner: Jnova (COO)

### Cross-Sprint Dependencies

1. **Sprint 2 depends on Sprint 1:**
   - Google Workspace infrastructure must be operational before building transformation pipeline
   - Blocker: Cannot store documents in Google Docs without Google Workspace
   - Mitigation: Ensure Sprint 1 completes before starting Sprint 2

2. **Sprint 3 depends on Sprint 2:**
   - Transformation pipeline must be functional before exposing via Discord commands
   - Blocker: Discord commands useless without working transformation pipeline
   - Mitigation: Test transformation pipeline thoroughly in Sprint 2 before starting Sprint 3

3. **Sprint 4 depends on Sprints 1-3:**
   - Cannot deploy to production without complete, tested system
   - Blocker: Production deployment requires all features implemented and validated
   - Mitigation: Do not rush Sprints 1-3, prioritize quality over speed

### Critical Path

**Critical path (longest dependency chain):**
1. Sprint 1: Google Workspace setup (10 days)
2. Sprint 2: Transformation pipeline (10 days)
3. Sprint 3: Discord commands (10 days)
4. Sprint 4: Testing & deployment (10 days)
**Total: 40 days**

**Parallel work opportunities:**
- Sprint 1: Terraform IaC (Jani) can happen in parallel with service account setup (Soju assisting)
- Sprint 2: Persona prompts (Soju) can be developed in parallel with Google Docs API client (Soju, sequential)
- Sprint 3: Command definitions (Zergucci) can happen in parallel with role mapping (Zergucci, sequential)
- Sprint 4: Documentation (Zerker) can happen in parallel with performance testing (Soju)

**No opportunities to shorten overall timeline without adding developers or reducing scope.**

---

## Success Metrics

### MVP Success Criteria

**Phase 1 is successful when:**
1. [ ] Google Workspace organization operational and Terraform manages folder structure
2. [ ] `/translate <project> <@document> for <audience>` command generates 4 persona summaries and stores them in Google Docs
3. [ ] `/exec-summary <sprint-id>` command returns pre-generated executive summary with Google Docs link
4. [ ] `/audit-summary <sprint-id>` command returns audit summary with severity breakdown
5. [ ] `/show-sprint [sprint-id]` command returns sprint status with Google Docs links
6. [ ] All security controls prevent secrets/PII from reaching Google Docs (100% blocked)
7. [ ] Stakeholders can access Google Docs links with correct permissions (role-based)
8. [ ] System deployed to production and operational for team use
9. [ ] Zero CRITICAL or HIGH security vulnerabilities in production
10. [ ] Team trained and documentation published

### Primary Metrics

**M-1: Transformation Pipeline Functionality**
- **Target:** 100% of transformations generate 4 persona summaries successfully
- **Measurement:** Audit log analysis (transformation success rate)
- **Success Criteria:** Zero transformation failures due to bugs (API failures acceptable)

**M-2: Security Controls Effectiveness**
- **Target:** 100% of secrets blocked before storing in Google Docs
- **Measurement:** Secret scanner logs (detections vs. blocks)
- **Success Criteria:** Zero secrets leaked to Google Docs in testing or production

**M-3: Command Response Time**
- **Target:** <15 seconds initial response (with loading message), <60 seconds final response
- **Measurement:** Command execution logs (timestamp analysis)
- **Success Criteria:** 95% of commands meet target response time

**M-4: Production Stability**
- **Target:** Zero critical outages in first 7 days of production
- **Measurement:** Uptime monitoring, incident logs
- **Success Criteria:** 99.9% uptime (less than 10 minutes downtime in 7 days)

### Secondary Metrics

**M-5: Stakeholder Adoption (Early Signal)**
- **Target:** 80% of team uses at least one Discord command in first 7 days
- **Measurement:** Discord audit logs (unique users invoking commands)
- **Success Criteria:** Majority of team tries Onomancer Bot

**M-6: Documentation Completeness**
- **Target:** All required documentation published and reviewed
- **Measurement:** Documentation checklist
- **Success Criteria:** User guide, setup guide, runbooks, training materials complete

**M-7: Test Coverage**
- **Target:** >80% code coverage for new code
- **Measurement:** Jest coverage report
- **Success Criteria:** All critical paths covered by tests

**M-8: Team Satisfaction**
- **Target:** 8/10 satisfaction score from team training session
- **Measurement:** Post-training survey
- **Success Criteria:** Positive feedback, willingness to use bot

### Long-Term Metrics (Phase 2 & Beyond)

**M-9: Developer Time Saved**
- **Baseline:** Developers spend ~20% of time on documentation/explanations
- **Target:** Reduce to <5% within 3 months of Phase 2 completion (automated triggers)
- **Measurement:** Weekly time-tracking survey + audit log analysis

**M-10: Stakeholder Self-Service Adoption**
- **Baseline:** 0% of information requests handled by bot (all go to developers)
- **Target:** 80% of information requests handled by bot within 6 months
- **Measurement:** Discord message analysis (bot queries vs. developer pings)

**M-11: Release Velocity Improvement**
- **Baseline:** Current time-to-release with manual documentation
- **Target:** 30% reduction in time-to-release within 3 months of full deployment
- **Measurement:** Time from `/review-sprint` approval to product release announcement

---

## Risk Register

### Critical Risks (High Impact, Medium-High Probability)

| Risk ID | Risk | Impact | Probability | Mitigation | Owner | Status |
|---------|------|--------|-------------|------------|-------|--------|
| R-1 | Google Workspace domain verification delays (DNS propagation 24-48 hours) | Blocks Sprint 1 by 1-2 days | Medium | Start domain verification on Day 1. Have backup domain ready. | Jani | Open |
| R-2 | Terraform Google Workspace provider limitations (may not support all features) | Increases Sprint 1 complexity, requires manual setup | High | Accept hybrid approach (Terraform + manual). Document manual steps. Test early. | Jani | Open |
| R-3 | Anthropic API rate limits hit during high-volume transformations | Transformation failures, poor UX | Medium | Implement exponential backoff. Use job queue. Monitor API usage. Request rate increase. | Soju | Open |
| R-4 | Transformation quality issues (bad prompts, irrelevant content) | Stakeholders unhappy with summaries, low adoption | Medium | Iterate on prompts with team feedback. Use Claude Sonnet 3.5. Include examples in prompts. | Soju | Open |
| R-5 | Security vulnerabilities discovered late (Sprint 4) | Delays production deployment by 2-3 days | Medium | Run security audit early in Sprint 4. Prioritize CRITICAL/HIGH fixes. Accept MEDIUM/LOW as debt. | Zerker | Open |
| R-6 | Team members unavailable (competing priorities, illness) | Sprint delays, reduced capacity | Medium | Confirm availability upfront. Have backup developers. Reduce scope if needed. | Jnova | Open |

### High Risks (Medium Impact, Medium Probability)

| Risk ID | Risk | Impact | Probability | Mitigation | Owner | Status |
|---------|------|--------|-------------|------------|-------|--------|
| R-7 | Google Docs API complexity (markdown conversion, formatting) | Development delays, reduced output quality | Medium | Use googleapis package. Accept basic formatting. Document limitations. | Soju | Open |
| R-8 | Discord command timeout (transformations take >15s) | Poor UX, user frustration | Medium | Use Discord deferReply(). Show loading message. Set expectation <60s. | Zergucci | Open |
| R-9 | Permission errors accessing Google Docs (misconfigured groups) | Users can't access summaries | Medium | Test permissions thoroughly. Implement retry with permission adjustment. Log errors. | Jani | Open |
| R-10 | Context aggregation too slow (many API calls to Linear/GitHub) | Transformation timeout | Low | Cache aggregated context (5 min TTL). Parallel API calls. Aggressive timeouts. | Soju | Open |
| R-11 | Production deployment issues (environment, secrets, permissions) | Delays MVP launch by 1-2 days | Low | Deploy to staging first. Test thoroughly. Have rollback procedure. | Jani | Open |

### Medium Risks (Low-Medium Impact, Low-Medium Probability)

| Risk ID | Risk | Impact | Probability | Mitigation | Owner | Status |
|---------|------|--------|-------------|------------|-------|--------|
| R-12 | User role detection fails (Discord role IDs change, misconfigured) | Wrong persona summaries delivered | Medium | Robust role mapping with fallback. Log role detection. Document role setup. | Zergucci | Open |
| R-13 | Security controls block legitimate content (false positives) | Manual review overhead, delays | Medium | Tune secret scanner patterns. Implement whitelist. Document review process. | Zergucci | Open |
| R-14 | Load testing reveals performance bottlenecks | Delays Sprint 4, optimization needed | Low | Load test early. Profile code. Optimize bottlenecks. Have rollback plan. | Soju | Open |
| R-15 | User adoption low (stakeholders don't use bot) | MVP fails to deliver business value | Low | Comprehensive documentation. Training session. Feedback channel. Proactive outreach. | Zerker | Open |
| R-16 | Documentation insufficient or unclear | Low adoption, support overhead | Low | Have non-technical team member review docs. Iterate based on feedback. Hold training. | Zerker | Open |

### Risk Management Strategy

**Risk Monitoring:**
- Review risk register at end of each sprint
- Update probabilities based on actual experience
- Escalate to COO (Jnova) if critical risks materialize

**Risk Response:**
- **Avoid:** Change approach to eliminate risk (e.g., use existing domain for verification)
- **Mitigate:** Reduce probability or impact (e.g., implement exponential backoff for API calls)
- **Accept:** Acknowledge risk and have contingency plan (e.g., accept Terraform limitations, document manual steps)
- **Transfer:** Shift risk to third party (e.g., use managed hosting to reduce deployment risk)

**Contingency Plans:**
- If Google Workspace domain verification delays: Use temporary domain or proceed with manual folder creation
- If Terraform limitations block progress: Accept hybrid approach with documented manual steps
- If Anthropic API rate limits hit: Implement job queue for async processing, request rate increase
- If security vulnerabilities found: Delay production deployment, prioritize fixes, accept technical debt for MEDIUM/LOW
- If team members unavailable: Reduce scope, extend sprints, recruit backup developers

---

## Notes & Considerations

### Phase 1 Scope Decisions

**Why Option C (Bare Minimum)?**
- **Focus on core value:** Manual transformation pipeline proves MVP value before investing in automation
- **Faster to market:** Can deliver working system in 40 days vs. 60-80 days for full Phase 1
- **Validate assumptions:** Stakeholders may prefer different workflow than automated triggers
- **Risk mitigation:** Automated triggers add complexity; manual triggers reduce risk of bugs and failures
- **Technical debt acceptable:** Phase 2 can add automated triggers once manual workflow proven

**What's Deferred to Phase 2:**
- Automated triggers (FR-3.4-3.7): File system watchers, webhook listeners, weekly digest cron
- Real-time build visibility (FR-7): Linear webhooks, proactive notifications, build status reporting
- Comprehensive knowledge base (FR-8): Discord archive, decision logs, change history
- Marketing support (FR-9): Custom data extraction, RACI generation, A/B testing data
- Hivemind integration (FR-5): LEARNINGS library, User Truth Canvas context

**Why These Features Deferred:**
- **Complexity:** Automated triggers require file system watchers, webhook infrastructure, error handling for async failures
- **Dependencies:** Build visibility requires Linear webhook setup and Discord notification infrastructure
- **Uncertain value:** Knowledge base and marketing features may not be needed immediately; validate with stakeholders first
- **Hivemind scope:** Integrating LEARNINGS and User Truth Canvas adds significant context aggregation complexity

### Team Assignments Rationale

**Sprint 1 (Jani lead):**
- Jani has DevOps/SysAdmin background → best fit for infrastructure work
- Google Workspace and Terraform require sysadmin expertise
- Jani handles accounts, credentials, DNS, infrastructure

**Sprint 2 (Soju lead):**
- Soju is CTO with backend expertise → best fit for API integration and architecture
- Google Docs API integration requires backend development skills
- Transformation pipeline is core technical challenge requiring senior engineer

**Sprint 3 (Zergucci lead):**
- Zergucci has Discord bot experience → best fit for command implementation
- Discord.js knowledge from existing bot implementation
- Can extend existing command handlers efficiently

**Sprint 4 (Zerker lead):**
- Zerker has frontend + testing focus → best fit for comprehensive testing and UX validation
- Testing requires attention to detail and user perspective
- Documentation benefits from frontend developer's UX sensibility

### Technical Decisions

**Why Terraform for Infrastructure?**
- **Infrastructure as Code:** Version-controlled, repeatable, auditable
- **Idempotency:** Can run multiple times safely
- **State Management:** Tracks resources, prevents drift
- **Alternative considered:** Manual setup → rejected due to lack of repeatability and auditability

**Why Google Docs API (not Google Apps Script)?**
- **Programmatic control:** Full API access from Node.js bot
- **Consistency:** Same tech stack (TypeScript) as existing bot
- **Security:** Service account authentication, no OAuth flow
- **Alternative considered:** Google Apps Script → rejected due to limited integration with bot

**Why Existing Security Services?**
- **Already implemented:** ContentSanitizer, SecretScanner, OutputValidator, ReviewQueue exist and are tested
- **Don't reinvent:** Security is hard, reuse proven implementations
- **Integration straightforward:** Services designed to be composable
- **Alternative considered:** Build new security layer → rejected due to time and risk

**Why Manual Triggers Only (Phase 1)?**
- **Faster MVP:** Automated triggers add complexity (file watchers, webhooks, error handling)
- **Validate value first:** Prove transformation pipeline works before investing in automation
- **Risk mitigation:** Manual triggers easier to debug and troubleshoot
- **User feedback:** May discover stakeholders prefer different workflow
- **Alternative considered:** Full automation → deferred to Phase 2

### Open Questions for Phase 2

1. **Automated Triggers:**
   - Which file system watcher library? (chokidar, fs.watch, watchman)
   - How to handle file system events reliability? (debouncing, deduplication)
   - How to retry failed transformations? (job queue, exponential backoff)

2. **Build Visibility:**
   - Which Linear webhook events to subscribe to? (issue created, updated, completed)
   - How to filter noise? (only relevant events, not all Linear activity)
   - Which Discord channel for notifications? (dedicated channel or existing)

3. **Knowledge Base:**
   - How to structure Discord archive? (by channel, by date, by topic)
   - How to extract decisions from discussions? (NLP, manual tagging, keywords)
   - Where to store knowledge base? (Google Docs, wiki, database)

4. **Marketing Support:**
   - What custom data do marketers need? (feature metrics, user feedback, A/B test results)
   - How to validate technical accuracy? (review queue, approval workflow)
   - What asset specifications? (sizes, formats, dimensions, naming conventions)

5. **Hivemind Integration:**
   - How to query LEARNINGS library? (Linear API, search by tags, full-text search)
   - How to extract User Truth Canvas data? (parse issue descriptions, structured fields)
   - How to determine relevance? (keyword matching, embeddings, manual curation)

### Success Criteria Alignment

**PRD Success Metrics → Sprint Plan Validation:**
- **M-1 Release Velocity:** Phase 1 enables self-service documentation → stakeholders stop waiting for developers → faster releases
- **M-2 Developer Time Saved:** Manual triggers reduce documentation time, automated triggers (Phase 2) eliminate it
- **M-3 Self-Service Adoption:** Discord commands enable stakeholders to query information independently
- **M-4 Documentation Completeness:** Transformation pipeline ensures all sprints have persona summaries within 24 hours (Phase 2 automated triggers)
- **M-5 Stakeholder Satisfaction:** Team training and comprehensive documentation ensure positive experience

**MVP Success = Phase 1 Success Criteria Met:**
- Google Workspace operational ✅
- Transformation pipeline functional ✅
- Discord commands accessible ✅
- Security controls enforced ✅
- Production deployment complete ✅

---

## Sprint Completion Checklist

Use this checklist to validate each sprint is complete before moving to the next.

### Sprint 1 Completion Checklist

- [ ] Google Workspace organization created and operational
- [ ] Domain verified (if custom domain used)
- [ ] Terraform project initialized and configured
- [ ] Terraform code creates complete folder structure programmatically
- [ ] Service account created with Google Docs API permissions
- [ ] Service account credentials securely stored in `/secrets/.env.local`
- [ ] Stakeholder group permissions configured (Google Groups created)
- [ ] Terraform state stored remotely with locking enabled
- [ ] `terraform apply` runs without errors and creates all folders
- [ ] Documentation complete: Terraform setup guide, workspace configuration runbook
- [ ] Code review completed by Soju
- [ ] Sprint 1 retrospective conducted

### Sprint 2 Completion Checklist

- [ ] `googleapis` npm package integrated
- [ ] `GoogleDocsStorageService` implemented and tested
- [ ] 4 persona transformation prompts implemented and reviewed
- [ ] Context aggregation working (Linear, GitHub, Discord, local files)
- [ ] Transformation pipeline integrated with Google Docs storage
- [ ] Security controls integrated (sanitization, secret scanning, output validation, review queue)
- [ ] Bidirectional linking implemented (original ↔ summaries)
- [ ] Unit tests written (>80% coverage)
- [ ] Integration tests passing (end-to-end transformation)
- [ ] Manual testing completed (team reviewed sample summaries)
- [ ] Performance benchmarks documented (<60s transformation time)
- [ ] Documentation complete: Transformation pipeline architecture, setup guide, troubleshooting
- [ ] Code review completed by Zergucci
- [ ] Sprint 2 retrospective conducted

### Sprint 3 Completion Checklist

- [x] Slash command definitions created (`/translate`, `/exec-summary`, `/audit-summary`, `/show-sprint`) ✅
- [x] `/translate` command handler implemented and tested ✅
- [x] `/exec-summary` command handler implemented and tested ✅
- [x] `/audit-summary` command handler implemented and tested ✅
- [x] `/show-sprint` command updated and tested ✅
- [x] Role-based access control implemented (Discord roles → personas) ✅
- [x] Document shorthand resolution working (@prd → docs/prd.md, etc.) ✅
- [ ] Commands registered with Discord API
- [ ] Commands visible in Discord UI with autocomplete
- [x] Error handling and user-friendly error messages implemented ✅
- [x] Unit tests written for all command handlers ✅
- [ ] Integration tests passing (commands invoked in Discord)
- [ ] Manual testing completed (team tested all commands)
- [ ] User documentation created (command usage, examples, troubleshooting)
- [x] Code review completed by Soju ✅
- [ ] Sprint 3 retrospective conducted

### Sprint 4 Completion Checklist

- [ ] Security audit completed (CRITICAL and HIGH findings remediated)
- [ ] Integration testing completed (all end-to-end workflows tested)
- [ ] Performance testing completed (benchmarks met)
- [ ] Load testing completed (10 concurrent users, no errors)
- [ ] Production deployment scripts created
- [ ] Monitoring and alerting configured (logs, health checks, uptime monitoring)
- [ ] Operational runbooks documented (deployment, rollback, restart, troubleshooting)
- [ ] Production deployment executed successfully
- [ ] Bot running and commands functional in production
- [ ] User documentation published (user guide, quick reference, FAQ)
- [ ] Team training session conducted
- [ ] Positive feedback from training session (8/10 satisfaction)
- [ ] MVP success criteria validated (all checkboxes marked)
- [ ] Sprint 4 retrospective conducted
- [ ] Phase 2 planning initiated

---

## Retrospective & Phase 2 Planning

### Sprint Retrospectives

**After each sprint:**
1. Conduct 30-minute retrospective meeting with sprint team
2. Discuss: What went well? What didn't go well? What can we improve?
3. Document lessons learned and action items
4. Update risk register based on actual experience
5. Adjust subsequent sprint plans if needed

### Phase 1 Retrospective (After Sprint 4)

**Goals:**
1. Review Phase 1 MVP success criteria (did we achieve them?)
2. Analyze metrics (transformation success rate, security scan effectiveness, command response time, production stability)
3. Collect stakeholder feedback (team training session, Discord usage)
4. Identify technical debt accumulated
5. Document lessons learned for Phase 2

**Questions to Answer:**
- Did we deliver on Phase 1 success criteria? (Yes/No for each criterion)
- What were our biggest challenges? (Technical, process, team)
- What worked well that we should continue? (Practices, tools, approaches)
- What should we change for Phase 2? (Process improvements, technical approaches)
- What technical debt did we accumulate? (Prioritized list)
- What features should be prioritized for Phase 2? (Automated triggers, build visibility, knowledge base, marketing support)

### Phase 2 Planning Kickoff

**After Phase 1 MVP Launch:**
1. Validate stakeholder adoption (M-5 metric: 80% of team uses bot in first 7 days)
2. Collect feedback from stakeholders (survey, interviews, feedback channel monitoring)
3. Prioritize Phase 2 features based on feedback:
   - Automated triggers (FR-3.4-3.7) - HIGH
   - Build visibility (FR-7) - HIGH
   - Knowledge base (FR-8) - MEDIUM
   - Marketing support (FR-9) - MEDIUM
   - Hivemind integration (FR-5) - LOW
4. Create Phase 2 PRD with refined requirements
5. Run `/sprint-plan` to generate Phase 2 sprint plan
6. Assign teams and start Phase 2 Sprint 1

**Phase 2 Timeline Estimate:**
- 4-6 sprints (40-60 days)
- Focus on automation and advanced features
- Iterative approach based on Phase 1 learnings

---

**End of Sprint Plan**

---

**Document Metadata:**
- **Created:** 2025-12-11
- **Last Updated:** 2025-12-11
- **Version:** 1.0
- **Status:** Ready for Implementation
- **Authors:** Sprint Planner Agent
- **Reviewers:** Jani (DevOps), Soju (CTO), Zergucci (Backend), Zerker (Frontend), Jnova (COO)
- **Approval:** Pending team review

**Next Steps:**
1. Team review of sprint plan (1-2 days)
2. Budget approval confirmation from Jnova
3. Kick off Sprint 1 (Google Workspace Foundation)
4. Schedule Sprint 1 kickoff meeting with Jani and team

---

**Questions or Feedback?**
- Contact: Sprint Planner Agent
- Feedback channel: Discord #onomancer-bot-feedback
- Issues: Linear project (create issue with label `sprint-plan`)
