# Transformation Pipeline Documentation

## Prerequisites

### System Requirements
- Node.js >= 18.0.0
- npm >= 9.0.0

### Sprint 1 Infrastructure Dependencies

The transformation pipeline requires Google Workspace infrastructure from Sprint 1:

1. **Service Account Credentials**
   - File: `secrets/google-service-account-key.json`
   - Source: Google Cloud Console → IAM → Service Accounts
   - Required scopes: Google Docs API, Google Drive API

   Example template available at `secrets/google-service-account-key.json.example`

2. **Folder IDs Configuration**
   - File: `config/folder-ids.json`
   - Source: Terraform outputs or manual Google Drive folder creation
   - Required folders: leadership, product, marketing, devrel, originals

   Example template available at `config/folder-ids.json.example`

### Installation

```bash
cd devrel-integration
npm install
npm run build
```

### Verification

Verify dependencies are installed:
```bash
ls node_modules | grep -E "(googleapis|google-auth)"
# Should output: google-auth-library, googleapis
```

Verify TypeScript compilation:
```bash
npm run build
# Should complete without errors
```

---

## Overview

The Transformation Pipeline is a secure, multi-stage document processing system that transforms technical documents into persona-specific summaries and stores them in Google Docs. It integrates with the existing security infrastructure (content sanitization, secret scanning, output validation) and supports aggregating context from multiple sources (filesystem, Linear, GitHub, Discord).

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Transformation Pipeline                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐              │
│  │   Source     │───▶│   Context    │───▶│   Content    │              │
│  │  Document    │    │ Aggregator   │    │  Sanitizer   │              │
│  └──────────────┘    └──────────────┘    └──────────────┘              │
│                                                   │                     │
│                                                   ▼                     │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐              │
│  │   Output     │◀───│  Translation │◀───│   Secret     │              │
│  │  Validator   │    │   Invoker    │    │   Scanner    │              │
│  └──────────────┘    └──────────────┘    └──────────────┘              │
│         │                    │                                          │
│         ▼                    │                                          │
│  ┌──────────────┐            │         ┌──────────────┐                │
│  │   Google     │◀───────────┴────────▶│   Review     │                │
│  │   Docs       │                      │    Queue     │                │
│  └──────────────┘                      └──────────────┘                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Google Docs Storage Service

**File:** `src/services/google-docs-storage.ts`

Provides Google Docs API integration with service account authentication.

**Key Features:**
- Service account authentication (from Terraform-provisioned credentials)
- Document CRUD operations (create, read, update, delete)
- Permission management (user, domain, anyone)
- Search within folders
- Bidirectional document linking
- Retry handling with exponential backoff
- Circuit breaker integration

**Usage:**
```typescript
import { GoogleDocsStorageService } from './services/google-docs-storage';

const docsService = new GoogleDocsStorageService({
  credentialsPath: './config/service-account.json',
});

// Create a document
const result = await docsService.createDocument({
  title: 'PRD Summary for Leadership',
  content: '# Executive Summary\n\nKey points...',
  folderId: 'folder-id-from-terraform',
  metadata: {
    sourceDocPath: '/docs/prd.md',
    persona: 'leadership',
    projectName: 'Onomancer Bot',
    documentType: 'prd',
    createdAt: new Date(),
  },
});

console.log(`Document created: ${result.url}`);
```

### 2. Persona Transformation Prompts

**File:** `src/prompts/persona-prompts.ts`

Defines persona-specific transformation prompts for four audiences.

**Personas:**

| Persona | Audience | Focus | Output Length |
|---------|----------|-------|---------------|
| `leadership` | C-suite, Board | Strategic decisions, ROI, risk | 1-2 pages |
| `product` | Product managers | Features, priorities, roadmap | 2-3 pages |
| `marketing` | Marketing team | Messaging, value props, stories | 1-2 pages |
| `devrel` | Developer community | Technical accuracy, integration | 2-4 pages |

**Usage:**
```typescript
import { generatePersonaPrompt, PersonaType } from './prompts/persona-prompts';

const prompt = generatePersonaPrompt('leadership', {
  documentType: 'prd',
  projectName: 'Onomancer Bot',
  sourceContent: prdContent,
  additionalContext: {
    linearIssues: recentIssues,
    githubPRs: recentPRs,
  },
});
```

### 3. Unified Context Aggregator

**File:** `src/services/unified-context-aggregator.ts`

Aggregates context from multiple sources to provide rich background for transformations.

**Sources:**
- **Filesystem:** Related markdown documents (PRD, SDD, sprint plans)
- **Linear:** Project issues, states, priorities
- **GitHub:** Pull requests, commits, discussions
- **Discord:** Community feedback, discussions

**Features:**
- 5-minute LRU cache to avoid redundant API calls
- Token limiting (configurable, default 100k)
- Graceful degradation on partial failures
- Source-specific limits (50 Linear issues, 20 PRs, 100 Discord messages)

**Usage:**
```typescript
import { UnifiedContextAggregator } from './services/unified-context-aggregator';

const aggregator = new UnifiedContextAggregator();

const context = await aggregator.aggregateContext(
  '/docs/prd.md',
  'Onomancer Bot',
  {
    includeLinear: true,
    linearTeamId: 'team-123',
    includeGitHub: true,
    githubOwner: 'org',
    githubRepo: 'repo',
  }
);

const formatted = aggregator.formatContextForLLM(context);
```

### 4. Transformation Pipeline

**File:** `src/services/transformation-pipeline.ts`

Main orchestration service that coordinates all components.

**Pipeline Stages:**
1. **Context Aggregation** - Gather related documents and external context
2. **Content Sanitization** - Remove prompt injection attempts, hidden text
3. **Secret Scanning** - Detect and redact API keys, credentials, PII
4. **Persona Transformation** - Generate persona-specific summaries via LLM
5. **Output Validation** - Verify output doesn't contain secrets or injection
6. **Storage** - Save to Google Docs with proper metadata
7. **Linking** - Create bidirectional links between related documents

**Usage:**
```typescript
import { TransformationPipeline } from './services/transformation-pipeline';

const pipeline = new TransformationPipeline({
  googleDocsCredentialsPath: './config/service-account.json',
});

const result = await pipeline.transform({
  sourceDocument: {
    name: 'prd.md',
    content: prdContent,
    path: '/docs/prd.md',
  },
  projectName: 'Onomancer Bot',
  documentType: 'prd',
  targetPersonas: ['leadership', 'product', 'marketing', 'devrel'],
  aggregateContext: true,
  storeOriginal: true,
  createLinks: true,
  folderMapping: {
    leadership: 'leadership-folder-id',
    product: 'product-folder-id',
    marketing: 'marketing-folder-id',
    devrel: 'devrel-folder-id',
  },
});

console.log(`Transformed ${result.summaries.length} summaries`);
result.summaries.forEach(s => {
  console.log(`  ${s.persona}: ${s.documentUrl}`);
});
```

## Security Controls

The pipeline integrates with the existing security infrastructure:

### Content Sanitizer
- Removes zero-width characters (hidden text)
- Detects and redacts prompt injection patterns
- Flags role confusion attacks
- Normalizes Unicode

### Secret Scanner
- 50+ regex patterns for secrets (API keys, tokens, credentials)
- PII detection (emails, phone numbers, SSNs)
- Auto-redaction with configurable replacement text

### Output Validator
- Verifies transformed output doesn't leak secrets
- Checks for prompt injection in LLM responses
- Validates output structure and formatting

### Review Queue
- High-sensitivity content requires manual approval
- Audit logging for compliance
- Configurable sensitivity thresholds

## Configuration

### Environment Variables

```bash
# Google Docs API
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json

# Optional: External integrations
LINEAR_API_KEY=lin_api_xxx
GITHUB_TOKEN=ghp_xxx
DISCORD_BOT_TOKEN=xxx

# Pipeline settings
TRANSFORMATION_MAX_TOKENS=100000
TRANSFORMATION_CACHE_TTL_MS=300000
```

### Folder Structure (from Terraform)

The pipeline expects folder IDs from the Terraform-provisioned Google Drive structure:

```json
{
  "technical_docs": "folder-id-1",
  "leadership_summaries": "folder-id-2",
  "product_summaries": "folder-id-3",
  "marketing_summaries": "folder-id-4",
  "devrel_summaries": "folder-id-5"
}
```

## Testing

### Unit Tests

```bash
# Run all tests
npm test

# Run transformation pipeline tests only
npm test -- --testPathPattern="transformation-pipeline"

# Run with coverage
npm test -- --coverage
```

### Manual Testing Checklist

- [ ] Transform PRD to all 4 personas
- [ ] Verify Google Docs are created in correct folders
- [ ] Check document permissions are set correctly
- [ ] Verify bidirectional links work
- [ ] Test with Linear/GitHub context aggregation
- [ ] Verify secret redaction in transformed output
- [ ] Test circuit breaker behavior on API failures
- [ ] Verify retry logic on transient failures

## Error Handling

The pipeline uses graceful degradation:

| Error | Behavior |
|-------|----------|
| Google Docs API failure | Retry with exponential backoff, then fail gracefully |
| Linear/GitHub unavailable | Continue with filesystem-only context |
| Content flagged by sanitizer | Include in result with security flags |
| Secrets detected | Redact and continue, flag in metadata |
| Translation failure | Return partial results for successful personas |

## Monitoring

### Health Check

```typescript
const health = await pipeline.healthCheck();
console.log(health);
// {
//   healthy: true,
//   components: {
//     googleDocs: { healthy: true },
//     translationInvoker: { healthy: true },
//     circuitBreaker: { state: 'CLOSED' }
//   }
// }
```

### Metrics

The pipeline emits metrics via the existing monitoring infrastructure:
- `transformation_duration_ms` - Time for complete transformation
- `transformation_persona_count` - Number of personas transformed
- `transformation_token_count` - Estimated tokens processed
- `transformation_security_flags` - Count of security issues detected
- `google_docs_api_calls` - Google Docs API call count
- `google_docs_api_errors` - Google Docs API error count

## Troubleshooting

### Common Issues

**"API quota exceeded"**
- Check Google Cloud Console for quota usage
- Implement request batching for bulk operations
- Consider increasing quota limits

**"Permission denied" on folder**
- Verify service account has Editor access to Drive folders
- Check folder sharing settings in Google Drive
- Verify folder IDs in configuration

**"Circuit breaker open"**
- API is experiencing high failure rate
- Wait for circuit breaker to reset (default: 30 seconds)
- Check API status and credentials

**"Content flagged by sanitizer"**
- Review the source document for prompt injection patterns
- Check for hidden characters in the content
- Use `result.securityFlags` to see specific issues

## API Reference

### TransformationPipeline

```typescript
class TransformationPipeline {
  constructor(options: PipelineOptions)

  transform(input: TransformationInput): Promise<TransformationResult>
  transformForPersona(doc, project, type, persona, opts): Promise<PersonaSummary>
  healthCheck(): Promise<HealthStatus>
}

interface TransformationInput {
  sourceDocument: { name: string; content: string; path: string }
  projectName: string
  documentType: 'prd' | 'sdd' | 'sprint' | 'audit' | 'reviewer' | 'general'
  targetPersonas?: PersonaType[]
  aggregateContext?: boolean
  storeOriginal?: boolean
  createLinks?: boolean
  folderMapping?: Record<PersonaType, string>
}

interface TransformationResult {
  success: boolean
  summaries: PersonaSummary[]
  originalDocumentId?: string
  metadata: TransformationMetadata
  securityFlags?: SecurityFlag[]
}
```

### GoogleDocsStorageService

```typescript
class GoogleDocsStorageService {
  constructor(options: GoogleDocsOptions)

  createDocument(params: CreateDocumentParams): Promise<CreateDocumentResult>
  getDocument(documentId: string): Promise<Document>
  updateDocument(documentId: string, content: string): Promise<void>
  deleteDocument(documentId: string): Promise<void>
  setPermissions(documentId: string, permissions: Permission[]): Promise<void>
  searchDocuments(folderId: string, query?: string): Promise<SearchResult>
  linkDocuments(sourceId: string, targetId: string, linkText: string): Promise<void>
  healthCheck(): Promise<HealthStatus>
}
```

### UnifiedContextAggregator

```typescript
class UnifiedContextAggregator {
  constructor()

  aggregateContext(path: string, project: string, opts?: AggregationOptions): Promise<UnifiedContext>
  formatContextForLLM(context: UnifiedContext): string
}

interface AggregationOptions {
  includeLinear?: boolean
  linearTeamId?: string
  includeGitHub?: boolean
  githubOwner?: string
  githubRepo?: string
  includeDiscord?: boolean
  discordChannelId?: string
  maxTokens?: number
  maxLinearIssues?: number
  maxGitHubPRs?: number
  maxDiscordMessages?: number
}
```

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025-12-12 | Initial implementation (Sprint 2) |
