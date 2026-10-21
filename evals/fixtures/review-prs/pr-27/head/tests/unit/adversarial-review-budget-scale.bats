#!/usr/bin/env bats
# =============================================================================
# tests/unit/adversarial-review-budget-scale.bats — cycle-131 Sprint 1 Task 1.8 (PRD FR-4, SDD D-4.2).
#
# flatline_protocol.<code_review|security_audit>.budget_scale: fixed | diff (default fixed) and budget_cents_max
# (default 600). With diff the gate's budget is min(max(budget_cents, ceil(estimate × 1.2)), budget_cents_max); an
# estimate above that still refuses (exit 4, status budget_exceeded, reason budget). A malformed scale or maximum
# fails closed to fixed. The envelope names budget_scale / budget_cents_effective / budget_cents_max only when the
# key is written: a config without it writes the envelope it always wrote.
#
# Whole-run harness: adversarial-review-s3-helpers.bash (main() sourced, invoke_dissenter stubbed, no model called).
# Prices: one fixture alias at 100 USD per Mtok input and 0 output, so each voice costs tokens / 100 cents, with
# tokens = diff bytes / 3 + 500 (the gate's own estimate) — 108,300 bytes → 366c, 62,700 → 214c, 208,500 → 700c.
# =============================================================================

load adversarial-review-s3-helpers

setup() { export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"; s3_setup sprint-s3bsc; }
teardown() { s3_teardown; }

_cfg() {  # <gate key> <budget_cents> [extra gate lines] — the gate under test, companion off, one priced primary
    s3_config "hounfour:
  providers:
    openai:
      models:
        fixture-scale:
          pricing: {input_per_mtok: 100000000, output_per_mtok: 0}
flatline_protocol:
  $1:
    enabled: true
    model: fixture-scale
    budget_cents: $2
    timeout_seconds: 30
    companion_voice: false
    fallback_chain: []
${3:-}"
}

_diff_of() {  # <bytes> → $T/diff.patch of exactly that size (a header and one long line)
    { printf 'diff --git a/x.sh b/x.sh\n'; head -c $(( $1 - 25 )) /dev/zero | tr '\0' 'a'; } > "$T/diff.patch"
    [ "$(wc -c < "$T/diff.patch" | tr -d ' ')" -eq "$1" ]
}

@test "BSC-1 the key absent: the shipped gate, byte for byte — estimate 366c over budget 200c is refused and the envelope names no scaling" {
    _diff_of 108300
    _cfg code_review 200
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "4" ] || { cat "$T/stderr.log"; return 1; }
    [ "$(jq -r '.metadata.status' <<<"$result")" = "budget_exceeded" ]
    [ "$(jq '.metadata.estimated_cents' <<<"$result")" = "366" ]
    [ "$(jq '.metadata.budget_cents' <<<"$result")" = "200" ]
    # exactly the keys the gate wrote before cycle-131
    [ "$(jq -c '.metadata | keys' <<<"$result")" = '["budget_cents","estimate_voices","estimated_cents","status","type"]' ]
    grep -qF "Estimated cost (366c) exceeds budget (200c)" "$T/stderr.log"
    ! grep -q "budget_scale" "$T/stderr.log" || { echo "an absent key was said"; return 1; }
    [ ! -s "$CALLS" ]
}

@test "BSC-2 budget_scale: fixed written explicitly keeps the configured budget (366c over 200c refused) and names the scaling, reason budget" {
    _diff_of 108300
    _cfg code_review 200 "    budget_scale: fixed"
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "4" ] || { cat "$T/stderr.log"; return 1; }
    [ "$(jq -c '.metadata | {status, reason, budget_scale, budget_cents, budget_cents_effective, budget_cents_max, estimated_cents}' <<<"$result")" \
      = '{"status":"budget_exceeded","reason":"budget","budget_scale":"fixed","budget_cents":200,"budget_cents_effective":200,"budget_cents_max":600,"estimated_cents":366}' ]
    [ ! -s "$CALLS" ]
}

@test "BSC-3 budget_scale: diff — estimate 214c over budget 200c scales the budget to ceil(214 × 1.2) = 257c and the review runs, the envelope says so" {
    _diff_of 62700
    _cfg code_review 200 "    budget_scale: diff"
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    grep -qx "fixture-scale" "$CALLS"
    grep -qF "budget: estimate 214c over 1 planned voice(s) (primary fixture-scale 214c)" "$T/stderr.log"
    grep -qF "budget: budget_scale=diff — configured 200c, estimate 214c, effective 257c (max 600c)" "$T/stderr.log"
    [ "$(jq -c '.metadata | {budget_scale, budget_cents_effective, budget_cents_max}' <<<"$result")" = '{"budget_scale":"diff","budget_cents_effective":257,"budget_cents_max":600}' ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
}

@test "BSC-4 budget_scale: diff — estimate 700c caps the budget at budget_cents_max 600c and is refused (exit 4, budget_exceeded, reason budget)" {
    _diff_of 208500
    _cfg code_review 200 "    budget_scale: diff"
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "4" ] || { cat "$T/stderr.log"; return 1; }
    [ "$(jq -c '.metadata | {status, reason, budget_scale, budget_cents, budget_cents_effective, budget_cents_max, estimated_cents}' <<<"$result")" \
      = '{"status":"budget_exceeded","reason":"budget","budget_scale":"diff","budget_cents":200,"budget_cents_effective":600,"budget_cents_max":600,"estimated_cents":700}' ]
    grep -qF "Estimated cost (700c) exceeds budget (600c)" "$T/stderr.log"
    [ ! -s "$CALLS" ]
    # a lower maximum is honoured: 214c with budget_cents_max 250 → ceil(256.8) = 257 is held to 250, and 214c fits under it
    _diff_of 62700
    _cfg code_review 200 "    budget_scale: diff
    budget_cents_max: 250"
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    [ "$(jq '.metadata.budget_cents_effective' <<<"$result")" = "250" ]
    # and a maximum below the estimate refuses: 214c with budget_cents_max 210
    _cfg code_review 200 "    budget_scale: diff
    budget_cents_max: 210"
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "4" ]
    [ "$(jq -c '.metadata | {reason, budget_cents_effective, budget_cents_max}' <<<"$result")" = '{"reason":"budget","budget_cents_effective":210,"budget_cents_max":210}' ]
}

@test "BSC-5 a malformed budget_scale fails closed to fixed and is said: 366c over 200c is refused whatever the spelling (Diff, yes, a list, a map)" {
    _diff_of 108300
    local v
    for v in "Diff" "yes" "[diff]" "{a: diff}" "1"; do
        _cfg code_review 200 "    budget_scale: $v"
        result=$(s3_run review)
        [ "$(cat "$T/rc")" = "4" ] || { echo "budget_scale: $v"; cat "$T/stderr.log"; return 1; }
        [ "$(jq -r '.metadata.budget_scale' <<<"$result")" = "fixed" ] || { echo "budget_scale: $v"; return 1; }
        [ "$(jq '.metadata.budget_cents_effective' <<<"$result")" = "200" ]
        grep -q "WARN: flatline_protocol.code_review.budget_scale=.* is not fixed or diff — fixed applies" "$T/stderr.log" || { echo "budget_scale: $v not said"; return 1; }
    done
    [ ! -s "$CALLS" ]
}

@test "BSC-6 a malformed budget_cents_max fails closed to fixed and is said (diff with a max of 6OO, -1, 600.5 or 060 keeps the configured budget)" {
    _diff_of 62700
    local v
    for v in "6OO" "-1" "600.5" "060"; do
        _cfg code_review 200 "    budget_scale: diff
    budget_cents_max: $v"
        result=$(s3_run review)
        [ "$(cat "$T/rc")" = "4" ] || { echo "budget_cents_max: $v"; cat "$T/stderr.log"; return 1; }
        [ "$(jq -r '.metadata.budget_scale' <<<"$result")" = "fixed" ]
        [ "$(jq '.metadata.budget_cents_effective' <<<"$result")" = "200" ]
        grep -qF "is not a whole number — budget_scale fixed applies" "$T/stderr.log" || { echo "budget_cents_max: $v not said"; return 1; }
    done
}

@test "BSC-7 the formula's other branches: a configured budget above ceil(estimate × 1.2) is kept, and one above the maximum is held to the maximum (min(max(…), max))" {
    _diff_of 62700
    _cfg code_review 300 "    budget_scale: diff"
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    [ "$(jq '.metadata.budget_cents_effective' <<<"$result")" = "300" ]
    _cfg code_review 1000 "    budget_scale: diff"
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "0" ]
    [ "$(jq '.metadata.budget_cents_effective' <<<"$result")" = "600" ]
    # the helper itself: ceil in integer arithmetic, and fixed is the configured budget whatever the estimate
    CONF_BUDGET_SCALE=diff CONF_BUDGET_CENTS_MAX=600
    [ "$(_adv_budget_effective 0 5)" = "6" ]       # ceil(6.0)
    [ "$(_adv_budget_effective 0 10)" = "12" ]     # ceil(12.0)
    [ "$(_adv_budget_effective 0 11)" = "14" ]     # ceil(13.2)
    [ "$(_adv_budget_effective 0 214)" = "257" ]   # ceil(256.8)
    [ "$(_adv_budget_effective 150 0)" = "150" ]
    [ "$(_adv_budget_effective 0 700)" = "600" ]
    CONF_BUDGET_SCALE=fixed
    [ "$(_adv_budget_effective 200 700)" = "200" ]
}

@test "BSC-8 each gate reads its own block: security_audit.budget_scale: diff scales the audit gate; the review gate without the key stays fixed" {
    _diff_of 62700
    s3_config "hounfour:
  providers:
    openai:
      models:
        fixture-scale:
          pricing: {input_per_mtok: 100000000, output_per_mtok: 0}
flatline_protocol:
  code_review:
    enabled: true
    model: fixture-scale
    budget_cents: 200
    timeout_seconds: 30
    companion_voice: false
    fallback_chain: []
  security_audit:
    enabled: true
    model: fixture-scale
    budget_cents: 200
    timeout_seconds: 30
    companion_voice: false
    fallback_chain: []
    budget_scale: diff"
    result=$(s3_run audit)
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    [ "$(jq -c '.metadata | {type, budget_scale, budget_cents_effective}' <<<"$result")" = '{"type":"audit","budget_scale":"diff","budget_cents_effective":257}' ]
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "4" ]
    [ "$(jq -c '.metadata | keys' <<<"$result")" = '["budget_cents","estimate_voices","estimated_cents","status","type"]' ]
}

@test "BSC-9 the shipped example config documents both keys under both gates with the default fixed and the formula, and the live config sets neither" {
    local ex="$PROJECT_ROOT/.loa.config.yaml.example"
    local gate
    for gate in code_review security_audit; do
        [ "$(yq eval ".flatline_protocol.${gate}.budget_scale" "$ex")" = "fixed" ] || { echo "$gate: budget_scale is not fixed in the example"; return 1; }
        [ "$(yq eval ".flatline_protocol.${gate}.budget_cents_max" "$ex")" = "600" ] || { echo "$gate: budget_cents_max is not 600"; return 1; }
    done
    grep -qF "min(max(budget_cents, ceil(estimate × 1.2)), budget_cents_max)" "$ex"
    if [[ -f "$PROJECT_ROOT/.loa.config.yaml" ]]; then
        [ "$(yq eval '.flatline_protocol.code_review.budget_scale // "absent"' "$PROJECT_ROOT/.loa.config.yaml")" = "absent" ]
        [ "$(yq eval '.flatline_protocol.security_audit.budget_scale // "absent"' "$PROJECT_ROOT/.loa.config.yaml")" = "absent" ]
    fi
}

@test "BSC-10 with the companion voice planned the scaling covers both voices' estimate and survives the fold: the folded two-voice envelope still names it" {
    s3_config "hounfour:
  providers:
    openai:
      models:
        fixture-scale:
          pricing: {input_per_mtok: 100000000, output_per_mtok: 0}
flatline_protocol:
  code_review:
    enabled: true
    model: fixture-scale
    budget_cents: 0
    timeout_seconds: 30
    companion_voice: true
    fallback_chain: []
    budget_scale: diff"
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    grep -q "budget: estimate [0-9]*c over 2 planned voice(s) (primary fixture-scale [0-9]*c, companion claude-headless [0-9]*c)" "$T/stderr.log"
    grep -qx "fixture-scale" "$CALLS"
    grep -qx "claude-headless" "$CALLS"
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
    [ "$(jq -c '.metadata | {budget_scale, budget_cents_max}' <<<"$result")" = '{"budget_scale":"diff","budget_cents_max":600}' ]
    # budget_cents 0 is the configured cap; diff lifted it to ceil(estimate × 1.2) — at least the estimate, never above 600
    local est eff
    est=$(sed -n 's/.*budget: estimate \([0-9]*\)c over 2 planned.*/\1/p' "$T/stderr.log" | head -1)
    eff=$(jq '.metadata.budget_cents_effective' <<<"$result")
    [ "$eff" = "$(( (est * 12 + 9) / 10 ))" ] || { echo "est=$est eff=$eff"; return 1; }
}
