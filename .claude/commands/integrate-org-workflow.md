---
description: Launch the context engineering expert to integrate agentic-base with your organization's tools and workflows (Discord, Google Docs, Linear, etc.)
---

I'm launching the context-engineering-expert agent to help you integrate the agentic-base framework with your organization's existing development processes and tools.

The agent will guide you through a structured discovery process to:
1. **Map your current workflow** - Understand how your teams work across Discord, Google Docs, Linear, and other platforms
2. **Identify integration points** - Determine where and how agents should connect with your tools
3. **Design context architecture** - Create the information flow patterns between platforms and agents
4. **Adapt agentic-base** - Modify the framework to work with your organizational processes
5. **Plan rollout strategy** - Create an incremental adoption plan with pilot teams

The context engineering expert will ask targeted questions across these phases:
- Current Workflow Mapping (tools, roles, handoffs)
- Pain Points & Bottlenecks (where context gets lost)
- Integration Requirements (which tools, what automation level)
- Team Structure & Permissions (authority, access controls)
- Data & Context Requirements (what info agents need)
- Success Criteria & Constraints (goals, limitations)

The agent will then generate:
- **Integration Architecture Document** (`docs/integration-architecture.md`)
- **Tool Configuration Guide** (`docs/tool-setup.md`)
- **Team Playbook** (`docs/team-playbook.md`)
- **Implementation Code & Configs** (Discord bots, webhooks, sync scripts)
- **Adoption & Change Management Plan**

This is especially valuable if you have:
- Multi-team initiatives spanning different departments
- Discussions happening in Discord/Slack
- Collaborative documents in Google Docs/Notion
- Project tracking in Linear/Jira
- Multiple developers working concurrently

Let me launch the agent now to begin understanding your organizational workflow.

<Task
  subagent_type="context-engineering-expert"
  prompt="Help the user integrate the agentic-base framework with their organization's existing tools and workflows. Conduct thorough discovery to understand their current process (Discord discussions, Google Docs collaboration, Linear project management, etc.). Ask targeted questions about workflow, pain points, integration requirements, team structure, data needs, and success criteria. Design a comprehensive integration architecture that preserves their existing workflows while enabling seamless agent collaboration. Generate all required deliverables: integration architecture document, tool configuration guide, team playbook, implementation code/configs, and adoption plan. For multi-developer teams, propose specific strategies to adapt the single-threaded agentic-base framework for concurrent team collaboration. Focus on practical, maintainable solutions that respect organizational constraints and culture."
/>
