# DevRel Integration Implementation Specifications

**For**: devops-crypto-architect agent (via `/implement-org-integration`)
**Purpose**: Detailed technical specifications for implementing the DevRel integration system
**Input Documents**: `docs/devrel-integration-architecture.md`, `docs/tool-setup.md`, `docs/team-playbook.md`

---

## Implementation Overview

Build a system that:
1. **Monitors Google Docs** for technical document changes (PRDs, SDDs, sprint updates, audits)
2. **Generates translations** using devrel-translator agent with department-specific formats
3. **Distributes outputs** to Google Docs, Discord, and optional blog platforms
4. **Provides manual triggers** via Discord bot commands and CLI
5. **Runs weekly automated digests** on a configurable schedule

---

## Project Structure

Create the following directory structure in the repository:

```
integration/
├── config/
│   ├── devrel-integration.config.yaml           # Main configuration
│   ├── devrel-integration.config.example.yaml   # Example for users
│   └── prompts/
│       ├── executive.md                         # Executive format prompt
│       ├── marketing.md                         # Marketing format prompt
│       ├── product.md                           # Product format prompt
│       ├── engineering.md                       # Engineering format prompt
│       └── unified.md                           # Unified format prompt
├── src/
│   ├── config/
│   │   ├── config-loader.ts                     # Load and validate YAML config
│   │   └── schemas.ts                           # JSON schemas for validation
│   ├── services/
│   │   ├── google-docs-monitor.ts               # Scan Google Docs for changes
│   │   ├── document-processor.ts                # Process and classify documents
│   │   ├── context-assembler.ts                 # Assemble related docs for context
│   │   ├── department-detector.ts               # Detect user department
│   │   ├── translation-invoker.ts               # Invoke devrel-translator agent
│   │   ├── google-docs-publisher.ts             # Create Google Docs
│   │   ├── discord-publisher.ts                 # Post to Discord
│   │   ├── blog-publisher.ts                    # Publish to Mirror/website
│   │   └── logger.ts                            # Logging service
│   ├── discord-bot/
│   │   ├── index.ts                             # Discord bot entry point
│   │   ├── commands/
│   │   │   └── generate-summary.ts              # /generate-summary command
│   │   └── handlers/
│   │       └── approval-reaction.ts             # Handle ✅ reactions
│   ├── schedulers/
│   │   └── weekly-digest.ts                     # Weekly digest scheduler
│   ├── cli/
│   │   └── generate-summary.ts                  # CLI for manual generation
│   └── types/
│       ├── config.ts                            # TypeScript types for config
│       ├── document.ts                          # Document types
│       └── translation.ts                       # Translation types
├── tests/
│   ├── integration/
│   │   ├── google-docs.test.ts
│   │   ├── discord.test.ts
│   │   └── end-to-end.test.ts
│   ├── unit/
│   │   ├── config-loader.test.ts
│   │   ├── document-processor.test.ts
│   │   └── department-detector.test.ts
│   └── mocks/
│       ├── google-docs-mock.ts
│       └── discord-mock.ts
├── scripts/
│   ├── run-weekly-digest.sh                     # Cron script
│   ├── validate-config.js                       # Validate YAML config
│   └── setup-google-docs.js                     # Setup Google Docs structure
├── .github/
│   └── workflows/
│       └── weekly-digest.yml                    # GitHub Actions workflow
├── package.json
├── tsconfig.json
├── .env.example
└── README.md
```

---

## Phase 1: Core Infrastructure (Week 1)

### 1.1 Configuration System

#### File: `integration/config/devrel-integration.config.yaml`

Create the main configuration file with all settings:

```yaml
# Schedule for automated digest generation
schedule:
  weekly_digest: "0 9 * * FRI"  # Every Friday 9am UTC
  timezone: "UTC"

# Google Docs integration
google_docs:
  monitored_folders:
    - "Engineering/Projects"
    - "Product/PRDs"
    - "Security/Audits"
  exclude_patterns:
    - "**/Meeting Notes/**"
    - "**/Draft/**"
    - "**/Archive/**"
  change_detection_window_days: 7
  output_folder: "Executive Summaries"

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
    enabled: true
    output_folder: "Executive Summaries"
    sharing: "organization"
  discord:
    enabled: true
    channel_name: "exec-summary"
    thread_creation: true
    mention_roles: ["@leadership", "@product"]
  blog:
    enabled: false
    platforms:
      - "mirror"
    auto_publish: false

# Department-to-format mapping
department_mapping:
  user_id_to_department: {}  # User fills in
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
  alert_webhook: ""  # User fills in
```

#### File: `integration/src/config/config-loader.ts`

```typescript
import * as fs from 'fs';
import * as yaml from 'js-yaml';
import * as path from 'path';
import { DevRelConfig } from '../types/config';
import { validateConfig } from './schemas';

export class ConfigLoader {
  private static instance: ConfigLoader;
  private config: DevRelConfig | null = null;
  private configPath: string;

  private constructor() {
    this.configPath = path.join(__dirname, '../../config/devrel-integration.config.yaml');
  }

  static getInstance(): ConfigLoader {
    if (!ConfigLoader.instance) {
      ConfigLoader.instance = new ConfigLoader();
    }
    return ConfigLoader.instance;
  }

  loadConfig(): DevRelConfig {
    if (this.config) {
      return this.config;
    }

    try {
      const fileContents = fs.readFileSync(this.configPath, 'utf8');
      const config = yaml.load(fileContents) as DevRelConfig;

      // Validate config against schema
      const validation = validateConfig(config);
      if (!validation.valid) {
        throw new Error(`Invalid configuration: ${validation.errors.join(', ')}`);
      }

      this.config = config;
      return config;
    } catch (error) {
      throw new Error(`Failed to load configuration: ${error.message}`);
    }
  }

  reloadConfig(): DevRelConfig {
    this.config = null;
    return this.loadConfig();
  }

  getConfig(): DevRelConfig {
    if (!this.config) {
      return this.loadConfig();
    }
    return this.config;
  }
}

export default ConfigLoader.getInstance();
```

#### File: `integration/src/config/schemas.ts`

```typescript
import { DevRelConfig } from '../types/config';

export interface ValidationResult {
  valid: boolean;
  errors: string[];
}

export function validateConfig(config: any): ValidationResult {
  const errors: string[] = [];

  // Required fields
  if (!config.schedule?.weekly_digest) {
    errors.push('schedule.weekly_digest is required');
  }

  if (!config.google_docs?.monitored_folders || config.google_docs.monitored_folders.length === 0) {
    errors.push('google_docs.monitored_folders must have at least one folder');
  }

  if (!config.output_formats) {
    errors.push('output_formats is required');
  }

  if (!config.distribution) {
    errors.push('distribution is required');
  }

  // Validate cron format
  if (config.schedule?.weekly_digest) {
    const cronRegex = /^(\*|[0-5]?[0-9])\s+(\*|[01]?[0-9]|2[0-3])\s+(\*|[0-2]?[0-9]|3[01])\s+(\*|[0-9]|1[0-2])\s+(\*|[0-6]|MON|TUE|WED|THU|FRI|SAT|SUN)$/i;
    if (!cronRegex.test(config.schedule.weekly_digest)) {
      errors.push('schedule.weekly_digest must be valid cron format');
    }
  }

  return {
    valid: errors.length === 0,
    errors
  };
}
```

#### File: `integration/src/types/config.ts`

```typescript
export interface DevRelConfig {
  schedule: {
    weekly_digest: string;
    timezone: string;
  };
  google_docs: {
    monitored_folders: string[];
    exclude_patterns: string[];
    change_detection_window_days: number;
    output_folder?: string;
  };
  digest_content: {
    include_doc_types: string[];
    summary_focus: string[];
    context_sources: string[];
  };
  output_formats: {
    [key: string]: OutputFormat;
  };
  distribution: {
    google_docs: {
      enabled: boolean;
      output_folder: string;
      sharing: string;
    };
    discord: {
      enabled: boolean;
      channel_name: string;
      thread_creation: boolean;
      mention_roles: string[];
    };
    blog: {
      enabled: boolean;
      platforms: string[];
      auto_publish: boolean;
    };
  };
  department_mapping: {
    user_id_to_department: { [key: string]: string };
    role_to_department: { [key: string]: string };
    default_format: string;
    allow_format_override: boolean;
  };
  review_workflow: {
    require_approval: boolean;
    reviewers: string[];
    approval_channel: string;
    approval_emoji: string;
  };
  monitoring: {
    log_level: string;
    metrics_enabled: boolean;
    alert_on_failure: boolean;
    alert_webhook: string;
  };
}

export interface OutputFormat {
  audience: string | string[];
  length: string;
  technical_level: string;
  focus?: string[];
}
```

### 1.2 Google Docs Integration

#### File: `integration/src/services/google-docs-monitor.ts`

```typescript
import { google } from 'googleapis';
import * as path from 'path';
import configLoader from '../config/config-loader';
import { Document, DocType } from '../types/document';
import logger from './logger';

export class GoogleDocsMonitor {
  private drive: any;
  private docs: any;

  constructor() {
    const auth = new google.auth.GoogleAuth({
      keyFile: process.env.GOOGLE_APPLICATION_CREDENTIALS,
      scopes: ['https://www.googleapis.com/auth/drive.readonly', 'https://www.googleapis.com/auth/documents.readonly'],
    });

    this.drive = google.drive({ version: 'v3', auth });
    this.docs = google.docs({ version: 'v1', auth });
  }

  /**
   * Scan monitored folders for documents changed in the past N days
   */
  async scanForChanges(windowDays: number = 7): Promise<Document[]> {
    const config = configLoader.getConfig();
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - windowDays);

    const documents: Document[] = [];

    for (const folderPath of config.google_docs.monitored_folders) {
      logger.info(`Scanning folder: ${folderPath}`);
      const folderDocs = await this.scanFolder(folderPath, cutoffDate);
      documents.push(...folderDocs);
    }

    // Filter out excluded patterns
    const filtered = documents.filter(doc => !this.isExcluded(doc.path, config.google_docs.exclude_patterns));

    logger.info(`Found ${filtered.length} documents changed since ${cutoffDate.toISOString()}`);
    return filtered;
  }

  /**
   * Scan a specific folder for changed documents
   */
  private async scanFolder(folderPath: string, cutoffDate: Date): Promise<Document[]> {
    // Note: This is a simplified implementation
    // In production, you'd need to:
    // 1. Resolve folder path to folder ID
    // 2. Recursively scan subfolders if wildcards (*) present
    // 3. Handle pagination for large folders

    const query = `modifiedTime > '${cutoffDate.toISOString()}' and mimeType = 'application/vnd.google-apps.document'`;

    try {
      const response = await this.drive.files.list({
        q: query,
        fields: 'files(id, name, modifiedTime, parents, webViewLink)',
        orderBy: 'modifiedTime desc',
      });

      const documents: Document[] = response.data.files.map((file: any) => ({
        id: file.id,
        name: file.name,
        path: folderPath,  // Simplified; in production, resolve full path
        modifiedTime: new Date(file.modifiedTime),
        webViewLink: file.webViewLink,
        type: this.classifyDocument(file.name),
      }));

      return documents;
    } catch (error) {
      logger.error(`Error scanning folder ${folderPath}:`, error);
      return [];
    }
  }

  /**
   * Fetch document content by ID
   */
  async fetchDocument(docId: string): Promise<string> {
    try {
      const response = await this.docs.documents.get({
        documentId: docId,
      });

      // Extract text from document structure
      const content = this.extractText(response.data);
      return content;
    } catch (error) {
      logger.error(`Error fetching document ${docId}:`, error);
      throw error;
    }
  }

  /**
   * Extract plain text from Google Docs API response
   */
  private extractText(doc: any): string {
    let text = '';
    if (doc.body && doc.body.content) {
      for (const element of doc.body.content) {
        if (element.paragraph) {
          for (const textRun of element.paragraph.elements || []) {
            if (textRun.textRun) {
              text += textRun.textRun.content;
            }
          }
        }
      }
    }
    return text;
  }

  /**
   * Classify document type based on title
   */
  classifyDocument(title: string): DocType {
    const lowerTitle = title.toLowerCase();

    if (lowerTitle.includes('prd') || lowerTitle.includes('product requirements')) {
      return 'prd';
    } else if (lowerTitle.includes('sdd') || lowerTitle.includes('software design')) {
      return 'sdd';
    } else if (lowerTitle.includes('sprint')) {
      return 'sprint';
    } else if (lowerTitle.includes('audit') || lowerTitle.includes('security')) {
      return 'audit';
    } else if (lowerTitle.includes('deployment') || lowerTitle.includes('infrastructure')) {
      return 'deployment';
    } else {
      return 'unknown';
    }
  }

  /**
   * Check if document path matches exclude patterns
   */
  private isExcluded(docPath: string, excludePatterns: string[]): boolean {
    for (const pattern of excludePatterns) {
      // Simple glob matching (in production, use a proper glob library like 'minimatch')
      const regex = new RegExp(pattern.replace(/\*/g, '.*').replace(/\?/g, '.'));
      if (regex.test(docPath)) {
        return true;
      }
    }
    return false;
  }
}

export default new GoogleDocsMonitor();
```

### 1.3 Discord Bot Foundation

#### File: `integration/src/discord-bot/index.ts`

```typescript
import { Client, GatewayIntentBits, REST, Routes, SlashCommandBuilder } from 'discord.js';
import { handleGenerateSummary } from './commands/generate-summary';
import { handleApprovalReaction } from './handlers/approval-reaction';
import logger from '../services/logger';

export class DiscordBot {
  private client: Client;
  private token: string;
  private clientId: string;

  constructor() {
    this.token = process.env.DISCORD_BOT_TOKEN!;
    this.clientId = process.env.DISCORD_CLIENT_ID!;

    this.client = new Client({
      intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.MessageContent,
        GatewayIntentBits.GuildMessageReactions,
      ],
    });

    this.setupEventHandlers();
  }

  private setupEventHandlers() {
    this.client.on('ready', () => {
      logger.info(`Discord bot logged in as ${this.client.user?.tag}`);
    });

    this.client.on('interactionCreate', async (interaction) => {
      if (!interaction.isChatInputCommand()) return;

      if (interaction.commandName === 'generate-summary') {
        await handleGenerateSummary(interaction);
      }
    });

    this.client.on('messageReactionAdd', async (reaction, user) => {
      if (user.bot) return;
      await handleApprovalReaction(reaction, user);
    });
  }

  async registerCommands() {
    const commands = [
      new SlashCommandBuilder()
        .setName('generate-summary')
        .setDescription('Generate a stakeholder summary from technical documents')
        .addStringOption(option =>
          option
            .setName('format')
            .setDescription('Output format (executive, marketing, product, engineering, unified)')
            .setRequired(false)
        )
        .addStringOption(option =>
          option
            .setName('docs')
            .setDescription('Comma-separated document names (e.g., sprint.md,prd.md)')
            .setRequired(false)
        ),
    ].map(command => command.toJSON());

    const rest = new REST({ version: '10' }).setToken(this.token);

    try {
      logger.info('Registering Discord slash commands...');
      await rest.put(Routes.applicationCommands(this.clientId), { body: commands });
      logger.info('Successfully registered Discord slash commands');
    } catch (error) {
      logger.error('Error registering Discord commands:', error);
    }
  }

  async start() {
    await this.registerCommands();
    await this.client.login(this.token);
  }

  getClient(): Client {
    return this.client;
  }
}

// Start bot if this file is executed directly
if (require.main === module) {
  const bot = new DiscordBot();
  bot.start().catch(error => {
    logger.error('Failed to start Discord bot:', error);
    process.exit(1);
  });
}

export default new DiscordBot();
```

#### File: `integration/src/discord-bot/commands/generate-summary.ts`

```typescript
import { ChatInputCommandInteraction } from 'discord.js';
import configLoader from '../../config/config-loader';
import departmentDetector from '../../services/department-detector';
import translationInvoker from '../../services/translation-invoker';
import googleDocsPublisher from '../../services/google-docs-publisher';
import discordPublisher from '../../services/discord-publisher';
import logger from '../../services/logger';

export async function handleGenerateSummary(interaction: ChatInputCommandInteraction) {
  await interaction.deferReply();

  try {
    const formatOption = interaction.options.getString('format');
    const docsOption = interaction.options.getString('docs');

    // Detect user's department
    const userId = interaction.user.id;
    const format = formatOption || await departmentDetector.getFormatForUser(userId);

    logger.info(`Generating summary for user ${userId} with format ${format}`);

    // Parse doc names if provided
    const docNames = docsOption ? docsOption.split(',').map(d => d.trim()) : [];

    // Generate summary (this is a placeholder - actual implementation in Phase 2)
    const summary = await translationInvoker.generateSummary(docNames, format);

    // Create Google Doc
    const docUrl = await googleDocsPublisher.createSummaryDoc(summary, {
      title: `Summary - ${new Date().toISOString().split('T')[0]}`,
      format,
      requestedBy: interaction.user.username,
    });

    // Post to Discord
    const threadUrl = await discordPublisher.createSummaryThread(docUrl, summary, interaction.channel!);

    await interaction.editReply(`✅ Summary generated!\n\n📄 Google Doc: ${docUrl}\n💬 Discussion: ${threadUrl}`);
  } catch (error) {
    logger.error('Error generating summary:', error);
    await interaction.editReply(`❌ Failed to generate summary: ${error.message}`);
  }
}
```

---

## Phase 2: Translation Pipeline (Week 2)

### 2.1 Document Processor

#### File: `integration/src/services/document-processor.ts`

```typescript
import configLoader from '../config/config-loader';
import googleDocsMonitor from './google-docs-monitor';
import contextAssembler from './context-assembler';
import { Document, ProcessedDocument } from '../types/document';
import logger from './logger';

export class DocumentProcessor {
  /**
   * Gather documents for weekly digest
   */
  async gatherWeeklyDocs(): Promise<ProcessedDocument[]> {
    const config = configLoader.getConfig();
    const windowDays = config.google_docs.change_detection_window_days;

    // Scan Google Docs for changes
    const documents = await googleDocsMonitor.scanForChanges(windowDays);

    // Filter by included doc types
    const filtered = documents.filter(doc =>
      config.digest_content.include_doc_types.includes(doc.type)
    );

    logger.info(`Processing ${filtered.length} documents for weekly digest`);

    // Process each document
    const processed: ProcessedDocument[] = [];
    for (const doc of filtered) {
      try {
        const processedDoc = await this.processDocument(doc);
        processed.push(processedDoc);
      } catch (error) {
        logger.error(`Error processing document ${doc.name}:`, error);
      }
    }

    return processed;
  }

  /**
   * Process a single document
   */
  async processDocument(doc: Document): Promise<ProcessedDocument> {
    // Fetch document content
    const content = await googleDocsMonitor.fetchDocument(doc.id);

    // Assemble context (related docs, previous digests, etc.)
    const context = await contextAssembler.assembleContext(doc);

    return {
      ...doc,
      content,
      context,
    };
  }

  /**
   * Process specific documents by name
   */
  async processDocumentsByName(docNames: string[]): Promise<ProcessedDocument[]> {
    // This is a placeholder - in production, you'd search Google Docs by name
    logger.info(`Processing documents by name: ${docNames.join(', ')}`);

    const processed: ProcessedDocument[] = [];
    // Implementation depends on how you want to resolve doc names to IDs
    // Could search by name, or maintain a mapping in config

    return processed;
  }
}

export default new DocumentProcessor();
```

### 2.2 Context Assembler

#### File: `integration/src/services/context-assembler.ts`

```typescript
import { Document, Context } from '../types/document';
import googleDocsMonitor from './google-docs-monitor';
import logger from './logger';

export class ContextAssembler {
  /**
   * Assemble context for a document
   */
  async assembleContext(doc: Document): Promise<Context> {
    const context: Context = {
      relatedDocs: [],
      previousDigests: [],
      roadmapDocs: [],
    };

    try {
      // Get related documents based on doc type
      switch (doc.type) {
        case 'sprint':
          context.relatedDocs = await this.findRelatedDocs(doc, ['prd', 'sdd']);
          break;
        case 'prd':
          context.relatedDocs = await this.findRelatedDocs(doc, ['sdd', 'roadmap']);
          break;
        case 'audit':
          context.relatedDocs = await this.findRelatedDocs(doc, ['deployment', 'sdd']);
          break;
      }

      // Get previous digests for continuity
      context.previousDigests = await this.findPreviousDigests(1);

      logger.info(`Assembled context for ${doc.name}: ${context.relatedDocs.length} related docs, ${context.previousDigests.length} previous digests`);
    } catch (error) {
      logger.error(`Error assembling context for ${doc.name}:`, error);
    }

    return context;
  }

  /**
   * Find related documents by type
   */
  private async findRelatedDocs(doc: Document, types: string[]): Promise<Document[]> {
    // This is a placeholder - in production, implement search logic
    // Could use document naming conventions, folder structure, or metadata
    return [];
  }

  /**
   * Find previous digests
   */
  private async findPreviousDigests(count: number): Promise<Document[]> {
    // Search "Executive Summaries" folder for recent digests
    return [];
  }
}

export default new ContextAssembler();
```

### 2.3 Department Detection

#### File: `integration/src/services/department-detector.ts`

```typescript
import configLoader from '../config/config-loader';
import discordBot from '../discord-bot';
import logger from './logger';

export class DepartmentDetector {
  /**
   * Detect department from Discord user ID
   */
  async detectDepartmentFromUser(userId: string): Promise<string> {
    const config = configLoader.getConfig();

    // Check explicit user mapping
    if (config.department_mapping.user_id_to_department[userId]) {
      return config.department_mapping.user_id_to_department[userId];
    }

    // Check Discord role mapping
    try {
      const client = discordBot.getClient();
      const guilds = client.guilds.cache;

      for (const guild of guilds.values()) {
        const member = await guild.members.fetch(userId);
        if (member) {
          for (const [roleName, department] of Object.entries(config.department_mapping.role_to_department)) {
            const role = guild.roles.cache.find(r => r.name === roleName.replace('@', ''));
            if (role && member.roles.cache.has(role.id)) {
              logger.info(`Detected department ${department} for user ${userId} via role ${roleName}`);
              return department;
            }
          }
        }
      }
    } catch (error) {
      logger.error(`Error detecting department from Discord roles:`, error);
    }

    // Fallback to default
    return config.department_mapping.default_format;
  }

  /**
   * Get format for department
   */
  getFormatForDepartment(department: string): string {
    const config = configLoader.getConfig();

    // Check if format exists
    if (config.output_formats[department]) {
      return department;
    }

    // Fallback to default
    return config.department_mapping.default_format;
  }

  /**
   * Get format for user (with optional override)
   */
  async getFormatForUser(userId: string, override?: string): Promise<string> {
    const config = configLoader.getConfig();

    // If override provided and allowed, use it
    if (override && config.department_mapping.allow_format_override) {
      if (config.output_formats[override]) {
        return override;
      }
    }

    // Detect department and get format
    const department = await this.detectDepartmentFromUser(userId);
    return this.getFormatForDepartment(department);
  }
}

export default new DepartmentDetector();
```

### 2.4 Translation Invoker

#### File: `integration/src/services/translation-invoker.ts`

```typescript
import * as fs from 'fs';
import * as path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';
import configLoader from '../config/config-loader';
import documentProcessor from './document-processor';
import { Translation } from '../types/translation';
import logger from './logger';

const execAsync = promisify(exec);

export class TranslationInvoker {
  /**
   * Generate summary for given documents and format
   */
  async generateSummary(docNames: string[], format: string): Promise<Translation> {
    const config = configLoader.getConfig();

    // Get documents
    const documents = docNames.length > 0
      ? await documentProcessor.processDocumentsByName(docNames)
      : await documentProcessor.gatherWeeklyDocs();

    if (documents.length === 0) {
      throw new Error('No documents found to summarize');
    }

    // Load prompt template
    const prompt = await this.loadPromptTemplate(format);

    // Prepare input for devrel-translator
    const input = this.prepareInput(documents, prompt, format);

    // Invoke devrel-translator agent
    const output = await this.invokeDevRelTranslator(input);

    return {
      format,
      content: output,
      sourceDocs: documents.map(d => d.name),
      generatedAt: new Date(),
    };
  }

  /**
   * Load prompt template for format
   */
  private async loadPromptTemplate(format: string): Promise<string> {
    const promptPath = path.join(__dirname, `../../config/prompts/${format}.md`);

    try {
      const prompt = fs.readFileSync(promptPath, 'utf8');
      return prompt;
    } catch (error) {
      logger.error(`Failed to load prompt template for format ${format}:`, error);
      throw new Error(`Prompt template not found: ${format}.md`);
    }
  }

  /**
   * Prepare input for devrel-translator
   */
  private prepareInput(documents: any[], prompt: string, format: string): string {
    const config = configLoader.getConfig();
    const formatConfig = config.output_formats[format];

    // Combine document contents
    const docsContent = documents.map(doc => `
## Document: ${doc.name}
${doc.content}

### Related Context:
${doc.context.relatedDocs.map((rd: any) => `- ${rd.name}`).join('\n')}
    `).join('\n\n---\n\n');

    // Inject into prompt template
    const input = prompt
      .replace('{{documents}}', docsContent)
      .replace('{{context}}', this.assembleContextText(documents))
      .replace('{{format}}', format)
      .replace('{{length}}', formatConfig.length)
      .replace('{{technical_level}}', formatConfig.technical_level);

    return input;
  }

  /**
   * Assemble context text from documents
   */
  private assembleContextText(documents: any[]): string {
    const contextParts: string[] = [];

    // Add previous digests
    const previousDigests = documents.flatMap(d => d.context.previousDigests || []);
    if (previousDigests.length > 0) {
      contextParts.push(`### Previous Digest:\n${previousDigests[0].name}`);
    }

    // Add roadmap context
    const roadmapDocs = documents.flatMap(d => d.context.roadmapDocs || []);
    if (roadmapDocs.length > 0) {
      contextParts.push(`### Roadmap Context:\n${roadmapDocs.map((rd: any) => `- ${rd.name}`).join('\n')}`);
    }

    return contextParts.join('\n\n');
  }

  /**
   * Invoke devrel-translator agent
   */
  private async invokeDevRelTranslator(input: string): Promise<string> {
    // Write input to temporary file
    const tempInputPath = path.join(__dirname, '../../tmp/translation-input.md');
    fs.mkdirSync(path.dirname(tempInputPath), { recursive: true });
    fs.writeFileSync(tempInputPath, input);

    try {
      // Invoke devrel-translator via Claude Code slash command
      // Note: This is a placeholder - actual implementation depends on how you want to invoke the agent
      // Options:
      // 1. Use Anthropic SDK directly
      // 2. Invoke Claude Code CLI: `claude-code /translate @${tempInputPath} for ${audience}`
      // 3. Use MCP protocol to invoke agent

      logger.info('Invoking devrel-translator agent...');

      // Placeholder: Use Anthropic SDK
      const Anthropic = require('@anthropic-ai/sdk');
      const anthropic = new Anthropic({
        apiKey: process.env.ANTHROPIC_API_KEY,
      });

      const message = await anthropic.messages.create({
        model: 'claude-sonnet-4-5-20250929',
        max_tokens: 4096,
        messages: [{
          role: 'user',
          content: input,
        }],
      });

      const output = message.content[0].text;

      logger.info('Translation generated successfully');
      return output;
    } catch (error) {
      logger.error('Error invoking devrel-translator:', error);
      throw error;
    }
  }
}

export default new TranslationInvoker();
```

---

## Phase 3-5: Complete Implementation

Due to length constraints, the remaining phases (Output Distribution, Scheduling, Testing) follow the same pattern. Key files to implement:

### Phase 3: Output Distribution
- `google-docs-publisher.ts` - Create and share Google Docs
- `discord-publisher.ts` - Post to Discord with threads
- `blog-publisher.ts` - Publish to Mirror/Paragraph
- `handlers/approval-reaction.ts` - Handle approval workflow

### Phase 4: Scheduling & Automation
- `schedulers/weekly-digest.ts` - Main scheduler entry point
- `.github/workflows/weekly-digest.yml` - GitHub Actions
- `scripts/run-weekly-digest.sh` - Cron script

### Phase 5: Testing & Monitoring
- Integration tests for all services
- End-to-end tests
- Monitoring and alerting setup

---

## Implementation Checklist

Use this checklist to track progress:

**Phase 1: Core Infrastructure** ✅
- [ ] Configuration system with YAML loader
- [ ] JSON schema validation
- [ ] Google Docs MCP integration
- [ ] Document scanner and classifier
- [ ] Discord bot foundation
- [ ] Slash command registration

**Phase 2: Translation Pipeline** ✅
- [ ] Document processor
- [ ] Context assembler
- [ ] Department detector
- [ ] Translation invoker
- [ ] Prompt template system

**Phase 3: Output Distribution**
- [ ] Google Docs publisher
- [ ] Discord publisher with threads
- [ ] Blog publisher (Mirror/Paragraph)
- [ ] Approval workflow handler

**Phase 4: Scheduling & Automation**
- [ ] Weekly digest scheduler
- [ ] GitHub Actions workflow
- [ ] Cron script
- [ ] Manual trigger CLI

**Phase 5: Testing & Monitoring**
- [ ] Unit tests for all services
- [ ] Integration tests
- [ ] End-to-end test
- [ ] Monitoring setup
- [ ] Alert configuration

---

## Environment Variables

Create `.env.example`:

```bash
# Google Docs API
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json

# Discord Bot
DISCORD_BOT_TOKEN=your_discord_bot_token
DISCORD_CLIENT_ID=your_discord_client_id
DISCORD_EXEC_SUMMARY_CHANNEL_ID=your_channel_id

# Anthropic API (for devrel-translator)
ANTHROPIC_API_KEY=your_anthropic_api_key

# Blog Publishing (Optional)
MIRROR_API_KEY=your_mirror_api_key

# Monitoring (Optional)
DISCORD_WEBHOOK_URL=your_webhook_url_for_alerts
```

---

## Dependencies

`package.json`:

```json
{
  "name": "devrel-integration",
  "version": "1.0.0",
  "description": "DevRel integration system for agentic-base",
  "main": "dist/index.js",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "ts-node src/index.ts",
    "weekly-digest": "ts-node src/schedulers/weekly-digest.ts",
    "generate-summary": "ts-node src/cli/generate-summary.ts",
    "test": "jest",
    "test:watch": "jest --watch",
    "validate-config": "ts-node scripts/validate-config.ts",
    "discord-bot": "ts-node src/discord-bot/index.ts"
  },
  "dependencies": {
    "@anthropic-ai/sdk": "^0.20.0",
    "discord.js": "^14.14.1",
    "googleapis": "^130.0.0",
    "js-yaml": "^4.1.0",
    "node-cron": "^3.0.3",
    "winston": "^3.11.0"
  },
  "devDependencies": {
    "@types/js-yaml": "^4.0.9",
    "@types/node": "^20.10.6",
    "@types/node-cron": "^3.0.11",
    "jest": "^29.7.0",
    "ts-jest": "^29.1.1",
    "ts-node": "^10.9.2",
    "typescript": "^5.3.3"
  }
}
```

---

## Next Steps for Implementation

1. **Review this spec** with the team
2. **Run `/implement-org-integration`** to invoke devops-crypto-architect
3. **Agent will**:
   - Create directory structure
   - Implement all services per spec
   - Write tests
   - Setup GitHub Actions
   - Create configuration examples
4. **Test the implementation**:
   - Dry-run mode first
   - Manual generation
   - Weekly automated digest
5. **Pilot with Product Manager** and iterate

---

**End of Implementation Specifications**
