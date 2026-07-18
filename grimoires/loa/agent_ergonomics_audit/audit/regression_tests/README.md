# Regression-test pointers (pass 1)

Per loa adaptation #3 (phase0_scope_decision.md), regression tests live where
CI runs them, not in this directory. Mapping:

| Rec | Test file (CI-run) |
|-----|--------------------|
| R-001, R-007 | tests/unit/agent-ergonomics-loa-status.bats |
| R-002 | tests/unit/block-destructive-bash.bats (Group R-002, 11 fixtures) |
| R-003 | tests/unit/agent-ergonomics-unknown-flag.bats (beads-health cases) + drift gate in agent-ergonomics-capabilities.bats |
| R-004 | tests/unit/agent-ergonomics-workflow-state.bats |
| R-005 | tests/unit/classify-merge-pr.bats (Group R-005, 4 fixtures) |
| R-006 | tests/unit/agent-ergonomics-capabilities.bats (incl. 2 drift gates) |
| R-008 | tests/unit/agent-ergonomics-unknown-flag.bats |
| R-009 | tests/unit/agent-ergonomics-unknown-flag.bats (value-guard cases) |
| R-010 | tests/unit/agent-ergonomics-unknown-flag.bats (vsc --skill case) |
| R-011 | tests/unit/agent-ergonomics-color-guard.bats |
| R-012 | tests/unit/agent-ergonomics-unknown-flag.bats (semver cases) |
| R-013 | tests/unit/agent-ergonomics-golden-path.bats |
