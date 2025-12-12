---
description: Launch the DevOps architect to implement the organizational integration designed by the context engineering expert
args: [background]
---

I'm launching the devops-crypto-architect agent in **integration implementation mode** to implement the Discord bot, webhooks, sync scripts, and integration infrastructure designed during Phase 0.

**Execution Mode**: {{ "background - use /tasks to monitor" if "background" in $ARGUMENTS else "foreground (default)" }}

**Prerequisites** (verify before implementing):
- ✅ `docs/integration-architecture.md` exists (integration design complete)
- ✅ `docs/tool-setup.md` exists (tool configuration documented)
- ✅ `docs/team-playbook.md` exists (team workflows documented)
- ✅ `docs/a2a/integration-context.md` exists (agent integration context)

The DevOps architect will:
1. **Review integration architecture**: Understand the designed integration patterns
2. **Implement Discord bot**: Create the bot implementation based on architecture
3. **Implement webhooks**: Set up Linear, GitHub, Vercel webhook handlers
4. **Implement sync scripts**: Create automation scripts for tool synchronization
5. **Configure services**: Set up external service integrations (Linear, Discord, etc.)
6. **Set up secrets management**: Proper handling of API tokens and credentials
7. **Create deployment configs**: Docker, docker-compose, systemd services
8. **Implement monitoring**: Logging, health checks, alerting for integration layer
9. **Deploy to dev/staging**: Test the integration in non-production environment
10. **Create operational runbooks**: Documentation for running and maintaining integrations

The integration architect will create:
- Discord bot implementation (`integration/src/bot.ts` and handlers)
- Webhook handlers for Linear, GitHub, Vercel
- Sync scripts for cross-platform automation
- Configuration files and environment templates
- Deployment infrastructure (Docker, docker-compose, systemd)
- Monitoring and logging setup
- Operational runbooks for integration layer
- Testing scripts and validation procedures

All implementation code will be created in the `integration/` directory, matching the structure outlined in `docs/integration-architecture.md`.

{{ if "background" in $ARGUMENTS }}
Running in background mode. Use `/tasks` to monitor progress.

<Task
  subagent_type="devops-crypto-architect"
  prompt="You are implementing the organizational integration layer designed by the context-engineering-expert. This is **Phase 0.5: Integration Implementation**.

## Phase 1: Review Integration Design

Read ALL integration documentation:
1. `docs/integration-architecture.md` - Integration patterns, data flows, trigger points
2. `docs/tool-setup.md` - API keys, webhooks, MCP servers, environment variables
3. `docs/team-playbook.md` - Command structures, workflows, escalation paths
4. `docs/a2a/integration-context.md` - Cross-agent patterns, context preservation
5. Existing `integration/` directory (if any)

## Phase 2: Implementation Planning

Identify implementation scope:
- Discord bot implementation
- Linear/GitHub/Vercel webhook handlers
- Cron jobs / scheduled tasks
- Sync scripts
- Command handlers
- Monitoring and health checks

Choose technology stack matching org's existing tools.

## Phase 3: Directory Structure

Create structure in `integration/`:
```
integration/
├── src/                # Source code
│   ├── bot.ts         # Discord bot entry
│   ├── handlers/      # Event handlers
│   ├── webhooks/      # Webhook handlers
│   ├── services/      # API wrappers
│   ├── cron/          # Scheduled jobs
│   └── utils/         # Utilities
├── config/            # Config files
├── secrets/           # Secrets (GITIGNORED)
├── tests/             # Tests
├── Dockerfile
├── docker-compose.yml
└── README.md
```

## Phase 4: Core Implementation

1. **Discord Bot** - Initialize client, event listeners, graceful shutdown
2. **Command Handlers** - Parse and route slash commands
3. **Feedback Capture** - Listen for emoji reactions, create Linear issues
4. **Linear Service** - API wrapper with rate limiting
5. **Webhook Handlers** - Signature verification, event routing
6. **Cron Jobs** - Daily digest, sync tasks
7. **Config Management** - YAML configs for digest, sync, commands
8. **Secrets Management** - `.env.local.example` template
9. **Logging & Monitoring** - Structured logging, health endpoints
10. **Testing** - Unit and integration tests

## Phase 5: Deployment Infrastructure

Create:
- `Dockerfile` - Build image
- `docker-compose.yml` - Local development
- `*.service` - Systemd service
- `ecosystem.config.js` - PM2 config

## Phase 6: Documentation

Create:
- `integration/README.md` - Overview, quick start, troubleshooting
- `integration/DEPLOYMENT.md` - Installation, config, deployment options
- `docs/deployment/runbooks/integration-operations.md` - Operations runbook
- `docs/deployment/integration-layer-handover.md` - Handover document

## Phase 7: Testing and Validation

Test each integration point:
- Discord bot connects
- Commands respond
- Emoji reactions create issues
- Webhooks trigger correctly
- Cron jobs execute
- Logs work properly
- Health checks respond

## Quality Standards

- ✅ Security (webhook signature verification, secrets handling)
- ✅ Reliability (error handling, retry logic)
- ✅ Observability (logging, health checks)
- ✅ Maintainability (clean code, documentation)
- ✅ Testability (unit and integration tests)
- ✅ Configuration (environment-based, no hardcoded values)

## Critical Reminders

1. NEVER commit secrets
2. Verify webhook signatures
3. Rate limit external APIs
4. Handle errors gracefully
5. Log security events
6. Test in staging first
7. Document everything

Your mission is to implement reliable, maintainable integration infrastructure."
/>
{{ else }}
Let me begin implementing the organizational integration layer.

You are implementing the organizational integration layer designed by the context-engineering-expert. This is **Phase 0.5: Integration Implementation**.

## Phase 1: Review Integration Design

Read ALL integration documentation:
1. `docs/integration-architecture.md` - Integration patterns, data flows, trigger points
2. `docs/tool-setup.md` - API keys, webhooks, MCP servers, environment variables
3. `docs/team-playbook.md` - Command structures, workflows, escalation paths
4. `docs/a2a/integration-context.md` - Cross-agent patterns, context preservation
5. Existing `integration/` directory (if any)

## Phase 2: Implementation Planning

Identify implementation scope:
- Discord bot implementation
- Linear/GitHub/Vercel webhook handlers
- Cron jobs / scheduled tasks
- Sync scripts
- Command handlers
- Monitoring and health checks

Choose technology stack matching org's existing tools.

## Phase 3: Directory Structure

Create structure in `integration/`:
```
integration/
├── src/                # Source code
│   ├── bot.ts         # Discord bot entry
│   ├── handlers/      # Event handlers
│   ├── webhooks/      # Webhook handlers
│   ├── services/      # API wrappers
│   ├── cron/          # Scheduled jobs
│   └── utils/         # Utilities
├── config/            # Config files
├── secrets/           # Secrets (GITIGNORED)
├── tests/             # Tests
├── Dockerfile
├── docker-compose.yml
└── README.md
```

## Phase 4: Core Implementation

1. **Discord Bot** - Initialize client, event listeners, graceful shutdown
2. **Command Handlers** - Parse and route slash commands
3. **Feedback Capture** - Listen for emoji reactions, create Linear issues
4. **Linear Service** - API wrapper with rate limiting
5. **Webhook Handlers** - Signature verification, event routing
6. **Cron Jobs** - Daily digest, sync tasks
7. **Config Management** - YAML configs for digest, sync, commands
8. **Secrets Management** - `.env.local.example` template
9. **Logging & Monitoring** - Structured logging, health endpoints
10. **Testing** - Unit and integration tests

## Phase 5: Deployment Infrastructure

Create:
- `Dockerfile` - Build image
- `docker-compose.yml` - Local development
- `*.service` - Systemd service
- `ecosystem.config.js` - PM2 config

## Phase 6: Documentation

Create:
- `integration/README.md` - Overview, quick start, troubleshooting
- `integration/DEPLOYMENT.md` - Installation, config, deployment options
- `docs/deployment/runbooks/integration-operations.md` - Operations runbook
- `docs/deployment/integration-layer-handover.md` - Handover document

## Phase 7: Testing and Validation

Test each integration point:
- Discord bot connects
- Commands respond
- Emoji reactions create issues
- Webhooks trigger correctly
- Cron jobs execute
- Logs work properly
- Health checks respond

## Quality Standards

- ✅ Security (webhook signature verification, secrets handling)
- ✅ Reliability (error handling, retry logic)
- ✅ Observability (logging, health checks)
- ✅ Maintainability (clean code, documentation)
- ✅ Testability (unit and integration tests)
- ✅ Configuration (environment-based, no hardcoded values)

## Critical Reminders

1. NEVER commit secrets
2. Verify webhook signatures
3. Rate limit external APIs
4. Handle errors gracefully
5. Log security events
6. Test in staging first
7. Document everything

Your mission is to implement reliable, maintainable integration infrastructure.
{{ endif }}
