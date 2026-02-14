# Vision: Pluggable credential provider registry

**ID**: vision-001
**Source**: Bridge iteration 1 of bridge-20260213-8d24fa
**PR**: #306
**Date**: 2026-02-13T03:52:38Z
**Status**: Captured
**Tags**: [architecture]

## Insight

The `get_credential_provider()` factory currently hardcodes the chain: env → encrypted → dotenv. A future enhancement could allow users to register custom providers via `.loa.config.yaml` (e.g., HashiCorp Vault, AWS Secrets Manager, 1Password CLI).

## Potential

Enables enterprise adoption where credentials live in centralized secret managers rather than local stores.

## Connection Points

- Bridgebuilder finding: vision-1
- Bridge: bridge-20260213-8d24fa, iteration 1
