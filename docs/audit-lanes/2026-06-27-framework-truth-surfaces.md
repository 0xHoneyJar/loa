# Audit lane: Framework truth surfaces and release evidence

## Purpose

This draft PR distills Loa's public-claim, manifest, command-count, construct lifecycle, and release-evidence issues into one implementation lane. It is a routing artifact and does not claim the fixes are complete yet.

## Issue coverage

Refs #1117, #1118, #1119, #1120, #1121, #1123, #1124, #1126, #1130, #1131, #1132, #1133, #1134, #1135, #1136, #1140, #1143, #1145, #1149.

## Preserved state

Preserve Loa's existing framework behavior while making public claims, release claims, command counts, manifest coverage, and construct-pack lifecycle easier to verify.

## Target

Move fragile documentation and release assertions toward generated or checked evidence without changing unrelated installer or command semantics.

## Expected artifacts

Likely scope includes README claim checks, command inventory checks, manifest coverage checks, release checklist updates, construct lifecycle docs, and version-surface parity evidence.

## Allowed scope

Allowed: docs, scripts, manifests, fixtures, CI checks, and release-process updates for the cited issues. Not allowed: unrelated installer hardening, downstream repo changes, or broad framework redesign.

## Decision

Use one truth-surface PR because these issues share one root contract: Loa public and release claims should be generated, checked, or explicitly caveated.

## Rollback

Rollback is the closing PR revert; implementation commits should keep generated checks and docs changes separable.

## Non-claims

This lane does not claim all Loa docs are perfect and does not close issue references until evidence-producing implementation is present.