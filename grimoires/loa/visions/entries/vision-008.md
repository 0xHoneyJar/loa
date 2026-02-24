# Vision 008: Manifest as Declarative Configuration

**Source**: Bridge bridge-20260224-b4e7f1, Iteration 1, PR #406
**Finding ID**: speculation-1
**Captured**: 2026-02-24
**Status**: Captured

## Insight

The symlink manifest currently lives in bash (function populating arrays). A natural evolution would be to externalize it to a declarative format (YAML/JSON) that multiple tools could consume — including a future Go/Rust CLI, a CI linter, or a VS Code extension. The bash function would become a reader, not a definer.

## FAANG Parallel

Kubernetes CRDs started as Go structs, then became YAML declarations. The declarative form enabled an entire ecosystem of tools that the imperative form could not.

## Teachable Moment

When a manifest serves multiple consumers, the manifest wants to become data, not code.

## Potential Impact

- Enables non-bash consumers (Go/Rust CLI, CI tools, VS Code extension)
- Separates topology definition from topology application
- Makes symlink structure queryable and testable without bash execution
- Aligns with Loa's existing use of YAML/JSON for configuration

## Prerequisites

- Multiple consumers that need the manifest data
- Clear need for the manifest to be the source of truth beyond bash scripts
