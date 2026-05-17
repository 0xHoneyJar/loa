#!/usr/bin/env bats
# cycle-112 Sprint 2 (#167) T2.5 — workload_tier_map drift-gate logic tests.
#
# The CI workflow .github/workflows/workload-tier-map-drift.yml composes
# three pieces of logic; this suite tests each in isolation against
# synthetic fixtures:
#
#   1. tools/audit-workload-tier-map.sh exhaustiveness + schema gate
#   2. yq subtree projection (R-3 false-positive mitigation)
#   3. PR-body trailer regex (Tier-Change-Evidence / Operator-Approval)
#
# Note: the actual `gh pr view` call is not exercised here (requires live
# GitHub auth); the trailer-detection grep is exercised against in-memory
# PR-body fixtures.

setup() {
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export TMP="$(mktemp -d -t loa-drift-gate-XXXXXX)"
    export AUDIT_TOOL="$PROJECT_ROOT/tools/audit-workload-tier-map.sh"
    export SCHEMA="$PROJECT_ROOT/.claude/data/schemas/workload-tier-map.schema.json"
}

teardown() {
    rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# T2.5.audit — audit-workload-tier-map.sh contract tests
# ---------------------------------------------------------------------------

@test "T2.5.audit: passes on current .loa.config.yaml" {
    run "$AUDIT_TOOL"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "exhaustive coverage"
}

@test "T2.5.audit: JSON mode emits expected keys" {
    run "$AUDIT_TOOL" --json
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert set(d.keys()) >= {'missing', 'unexpected', 'expected_count', 'entries_count', 'verdict'}, d
print('json contract OK')
"
}

@test "T2.5.audit: exits 1 on missing entry" {
    # Swap-test: backup, replace .loa.config.yaml with a synthetic config
    # missing /review-sprint + reviewing-code entries, run audit, restore.
    cp "$PROJECT_ROOT/.loa.config.yaml" "$TMP/original.yaml"
    python3 - <<PY
import yaml
c = yaml.safe_load(open('$TMP/original.yaml'))
del c['workload_tier_map']['entries']['/review-sprint']
del c['workload_tier_map']['entries']['reviewing-code']
yaml.safe_dump(c, open('$PROJECT_ROOT/.loa.config.yaml', 'w'), default_flow_style=False, sort_keys=False)
PY
    set +e
    "$AUDIT_TOOL" >"$TMP/out" 2>&1
    rc=$?
    set -e
    cp "$TMP/original.yaml" "$PROJECT_ROOT/.loa.config.yaml"

    [ "$rc" -eq 1 ]
    grep -q "MISSING" "$TMP/out"
}

@test "T2.5.audit: exits 4 on schema violation" {
    # Inject an invalid tier value.
    cp "$PROJECT_ROOT/.loa.config.yaml" "$TMP/.loa.config.yaml.original"
    python3 - <<PY
import yaml
c = yaml.safe_load(open('$PROJECT_ROOT/.loa.config.yaml'))
c['workload_tier_map']['defaults']['tier'] = 'nonsense-tier'
yaml.safe_dump(c, open('$PROJECT_ROOT/.loa.config.yaml', 'w'), default_flow_style=False, sort_keys=False)
PY
    set +e
    "$AUDIT_TOOL" >"$TMP/out" 2>&1
    rc=$?
    set -e
    cp "$TMP/.loa.config.yaml.original" "$PROJECT_ROOT/.loa.config.yaml"

    [ "$rc" -eq 4 ]
    grep -q "schema violation" "$TMP/out"
}

# ---------------------------------------------------------------------------
# T2.5.yq-projection — subtree diff isolation (R-3 false-positive mitigation)
# ---------------------------------------------------------------------------

@test "T2.5.yq-projection: harmless reformatting elsewhere doesn't trip" {
    base="$TMP/base.yaml"
    head="$TMP/head.yaml"
    cat > "$base" <<'YAML'
unrelated_top_key: value
workload_tier_map:
  schema_version: "1.0"
  defaults:
    tier: advisor
  entries:
    /review-sprint:
      tier: advisor
      rationale: same rationale
      evidence_ref: default
YAML
    # Same workload_tier_map, but reformat unrelated key with comment.
    cat > "$head" <<'YAML'
unrelated_top_key: value  # added a comment elsewhere
workload_tier_map:
  schema_version: "1.0"
  defaults:
    tier: advisor
  entries:
    /review-sprint:
      tier: advisor
      rationale: same rationale
      evidence_ref: default
YAML

    base_wtm="$TMP/base_wtm.yaml"
    head_wtm="$TMP/head_wtm.yaml"
    yq eval '.workload_tier_map' "$base" > "$base_wtm"
    yq eval '.workload_tier_map' "$head" > "$head_wtm"

    diff -q "$base_wtm" "$head_wtm"
    # Exit 0 from diff -q means files are equivalent; the workflow's
    # "no workload_tier_map subtree change" branch fires.
}

@test "T2.5.yq-projection: real subtree mutation IS detected" {
    base="$TMP/base.yaml"
    head="$TMP/head.yaml"
    cat > "$base" <<'YAML'
workload_tier_map:
  schema_version: "1.0"
  defaults:
    tier: advisor
  entries:
    /review-sprint:
      tier: advisor
      rationale: original
      evidence_ref: default
YAML
    cat > "$head" <<'YAML'
workload_tier_map:
  schema_version: "1.0"
  defaults:
    tier: advisor
  entries:
    /review-sprint:
      tier: executor
      rationale: tier-downgrade
      evidence_ref: default
YAML
    base_wtm="$TMP/base_wtm.yaml"
    head_wtm="$TMP/head_wtm.yaml"
    yq eval '.workload_tier_map' "$base" > "$base_wtm"
    yq eval '.workload_tier_map' "$head" > "$head_wtm"

    run diff -q "$base_wtm" "$head_wtm"
    # diff -q exits 1 when files differ.
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# T2.5.trailer-regex — PR-body trailer detection
# ---------------------------------------------------------------------------

@test "T2.5.trailer-regex: Tier-Change-Evidence trailer detected" {
    body=$(cat <<'BODY'
## Summary
Bumped /review-sprint from executor to advisor based on A/B benchmark.

Tier-Change-Evidence: PR-885 A/B (executor missed 1 HC, 60% fewer findings)
BODY
)
    set +e
    has_evidence=$(echo "$body" | grep -c "^Tier-Change-Evidence:")
    has_operator=$(echo "$body" | grep -c "^Operator-Approval:")
    set -e
    [ "$has_evidence" -eq 1 ]
    [ "$has_operator" -eq 0 ]
}

@test "T2.5.trailer-regex: Operator-Approval trailer detected" {
    body=$(cat <<'BODY'
## Summary
Operator forced executor tier for a low-stakes new skill.

Operator-Approval: @janitooor in NOTES.md decision log 2026-05-17
BODY
)
    set +e
    has_evidence=$(echo "$body" | grep -c "^Tier-Change-Evidence:")
    has_operator=$(echo "$body" | grep -c "^Operator-Approval:")
    set -e
    [ "$has_evidence" -eq 0 ]
    [ "$has_operator" -eq 1 ]
}

@test "T2.5.trailer-regex: no trailer → fail signal" {
    body=$(cat <<'BODY'
## Summary
Changed tier without any justification trailer.
BODY
)
    set +e
    has_evidence=$(echo "$body" | grep -c "^Tier-Change-Evidence:")
    has_operator=$(echo "$body" | grep -c "^Operator-Approval:")
    set -e
    [ "$has_evidence" -eq 0 ]
    [ "$has_operator" -eq 0 ]
}

@test "T2.5.trailer-regex: trailer only counts at line start" {
    # An attacker can't smuggle a fake trailer mid-line.
    body=$(cat <<'BODY'
## Summary
This PR description mentions Tier-Change-Evidence: but only in prose,
not as an actual trailer.
BODY
)
    set +e
    has_evidence=$(echo "$body" | grep -c "^Tier-Change-Evidence:")
    set -e
    [ "$has_evidence" -eq 0 ]
}

# ---------------------------------------------------------------------------
# T2.5.workflow-yaml — YAML validity of the workflow itself
# ---------------------------------------------------------------------------

@test "T2.5.workflow-yaml: workload-tier-map-drift.yml parses as valid YAML" {
    workflow="$PROJECT_ROOT/.github/workflows/workload-tier-map-drift.yml"
    [ -f "$workflow" ]
    python3 -c "
import yaml
y = yaml.safe_load(open('$workflow'))
assert y['name'] == 'Workload Tier Map Drift Gate'
# 'on' is a YAML 1.1 boolean (True) — read via either key
trigger = y.get('on') if 'on' in y else y.get(True)
assert trigger is not None
assert 'pull_request' in trigger and 'push' in trigger
assert 'drift-gate' in y['jobs']
print('workflow YAML structurally valid')
"
}
