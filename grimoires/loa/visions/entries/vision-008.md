# Vision: Route Table as General-Purpose Skill Router

**ID**: vision-008
**Source**: Bridge iteration 2 of bridge-20260223-b6180e
**PR**: #404
**Date**: 2026-02-23T00:00:00Z
**Status**: Captured
**Tags**: [architecture, routing, framework-primitive]

## Insight

The declarative route table pattern in `lib-route-table.sh` (YAML config to parallel arrays to condition registry to backend registry to fallthrough cascade) is generic enough to route any Loa skill invocation, not just GPT reviews. Skills like `/flatline-review`, `/deploy-production`, and `/audit` could benefit from configurable backend selection with condition-based routing and per-route timeouts. The current implementation is tightly coupled to GPT review (backend functions take review-specific arguments), but the routing engine itself is skill-agnostic.

## Potential

Factor out a generic route engine that takes a "backend adapter" interface, allowing skills to register their own backends while sharing the route table parsing, validation, condition evaluation, and fallthrough logic. This would transform the route table from a single-skill utility into a framework primitive.

## Connection Points

- Bridgebuilder finding: vision-1 from bridge-20260223-b6180e
- Bridge: bridge-20260223-b6180e, iteration 2
- FAANG parallel: Envoy proxy evolved from HTTP router to general L7 protocol router via the same pattern generalization
