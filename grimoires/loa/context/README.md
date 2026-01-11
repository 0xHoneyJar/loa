# Context Directory

This directory is for user-provided context that feeds into the PRD discovery process (`/plan-and-analyze`).

## What to Put Here

- Product briefs, specs, or requirements documents
- Market research or competitive analysis
- Technical constraints or architecture notes
- Stakeholder feedback or user research
- Any documents that inform what you want to build

## Important: Files Are Not Tracked

**All files in this directory (except this README) are gitignored.**

This is intentional because:
1. Context files are user-specific and project-specific
2. They may contain sensitive business information
3. Loa is a template - your context shouldn't pollute the framework

## How It Works

When you run `/plan-and-analyze`, the discovering-requirements agent will:
1. Read all files in this directory
2. Use them as input for generating your PRD
3. Ask clarifying questions based on what it finds

## Supported Formats

- Markdown (`.md`)
- Text files (`.txt`)
- PDFs (`.pdf`)
- Images (`.png`, `.jpg`) - for mockups or diagrams

Place your context files here, then run `/plan-and-analyze` to begin discovery.
