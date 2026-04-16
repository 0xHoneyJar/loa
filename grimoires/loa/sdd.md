# SDD: Fix (( var++ )) under set -e (cycle-081)

## Approach

Mechanical replacement using sed: `(( var++ ))` → `var=$((var + 1))`, `(( var-- ))` → `var=$((var - 1))`.

Only replace unguarded sites (no `|| true` suffix). Leave guarded sites as-is (they work correctly).

Add lint script for future prevention.
