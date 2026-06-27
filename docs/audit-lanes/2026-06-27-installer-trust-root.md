# Audit lane: Installer trust root and filesystem safety

## Purpose

This draft PR distills the installer, bootstrap, filesystem mutation, and install-mode safety issues into one implementation lane. It is a routing artifact and does not claim the fixes are complete yet.

## Issue coverage

Refs #1112, #1113, #1114, #1115, #1116, #1122, #1125, #1127, #1128, #1129, #1137, #1138, #1139, #1141, #1142, #1144, #1146, #1147, #1148, #1150, #1151.

## Preserved state

Preserve Loa's System / State / App separation and existing install modes outside the named installer and filesystem safety gaps.

## Target

Establish a small, testable trust-root contract for bootstrap downloads, installer option handling, helper sourcing, symlink containment, filesystem relocation, copied-artifact drift, and install recovery.

## Expected artifacts

Likely scope includes `.claude/scripts/mount-loa.sh`, `.claude/scripts/mount-submodule.sh`, installer helpers, installer fixtures, doctor/recovery docs, and release smoke evidence.

## Allowed scope

Allowed: focused installer code, test fixtures, release checks, and docs needed to prove the lane. Not allowed: unrelated command behavior, downstream app/state semantics, or adjacent repos.

## Decision

Use one coherent hardening PR instead of many tiny PRs because these issues share one root contract: installer actions must be deterministic, bounded, and recoverable.

## Rollback

Rollback is the closing PR revert; follow-up implementation commits should remain narrow enough that revert restores prior installer behavior.

## Non-claims

This lane does not certify every Loa framework surface and does not close issue references until implementation evidence is present.