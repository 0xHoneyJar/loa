# Application Directory

This directory is where your application code will be generated.

**Files are added automatically during the `/implement` phase** after completing:

1. `/plan-and-analyze` - Creates Product Requirements Document (PRD)
2. `/architect` - Creates Software Design Document (SDD)
3. `/sprint-plan` - Creates Sprint Plan with tasks

Once you run `/implement sprint-1`, the sprint-task-implementer agent will:
- Remove this README
- Generate production code based on your PRD, SDD, and sprint plan
- Create appropriate project structure (src/, tests/, config/, etc.)
- Write tests alongside implementation

**Do not manually add files here** - let the agents handle code generation to maintain consistency with your requirements and architecture documents.
