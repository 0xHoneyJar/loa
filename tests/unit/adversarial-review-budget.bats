#!/usr/bin/env bats
# =============================================================================
# tests/unit/adversarial-review-budget.bats — cycle-129 Sprint 3 Task 3.3 (PRD FR-7 AC-7.5, SDD D-7.4, D-7.6).
#
# The dissent budget pre-check prices every planned voice — the primary, the companion's first hop, each advisory voice —
# at its catalog price (python3 -m loa_cheval.metering.pricing --alias), instead of the fixed 10 / 30 USD per Mtok.
# An alias with no catalog price falls back to 10 / 30 for that voice and is said by name; a zero-priced entry estimates
# zero and is said too. Prices come from fixture entries in the test's project config (hounfour.providers overlays the
# catalog, as cheval merges it). Each voice: input tokens × input rate + 2000 × output rate, micro-USD/Mtok → cents.
# =============================================================================

load adversarial-review-s3-helpers

setup() { export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"; s3_setup sprint-s3bud; }   # (the CLI lock is this test's own — CMP-121)
teardown() { s3_teardown; }

_cfg() {  # <model> <budget> <companion_voice> [extra code_review lines]
    s3_config "hounfour:
  providers:
    openai:
      models:
        fixture-priced:
          pricing: {input_per_mtok: 2000000, output_per_mtok: 8000000}
    fixturelocal:
      models:
        fixture-zero:
          pricing: {input_per_mtok: 0, output_per_mtok: 0}
        fixture-zero-ow:
          open_weight: true
          pricing: {input_per_mtok: 0, output_per_mtok: 0}
        fixture-stale:
          price_date: \"2000-01-01\"
          pricing: {input_per_mtok: 1000000, output_per_mtok: 1000000}
flatline_protocol:
  code_review:
    enabled: true
    model: $1
    budget_cents: $2
    timeout_seconds: 30
    companion_voice: $3
    fallback_chain: []
${4:-}"
}

_big_diff() {  # a diff whose estimate is 1,000,500 input tokens (3,000,000 bytes / 3 + 500)
    { printf 'diff --git a/x.sh b/x.sh\n'; head -c $(( 3000000 - 25 )) /dev/zero | tr '\0' 'a'; } > "$T/diff.patch"
    [ "$(wc -c < "$T/diff.patch")" -eq 3000000 ]
}

@test "BUD-1 the primary is priced at its catalog rate (no fixed-rate fallback): 1,000,500 tokens × 2 + 2000 × 8 USD/Mtok = 201c" {
    _big_diff
    _cfg fixture-priced 150 false
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "4" ] || { cat "$T/stderr.log"; return 1; }
    [ "$(jq -r '.metadata.status' <<<"$result")" = "budget_exceeded" ]
    [ "$(jq '.metadata.estimated_cents' <<<"$result")" = "201" ]
    [ "$(jq -c '[.metadata.estimate_voices[] | {role, alias, estimated_cents, pricing_source}]' <<<"$result")" = '[{"role":"primary","alias":"fixture-priced","estimated_cents":201,"pricing_source":"config"}]' ]
    grep -qF "budget: estimate 201c over 1 planned voice(s) (primary fixture-priced 201c)" "$T/stderr.log"
    ! grep -q "no catalog price" "$T/stderr.log" || { echo "a catalog-priced primary fell back"; return 1; }
    [ ! -s "$CALLS" ]
}

@test "BUD-2 an alias with no catalog price falls back to 10 / 30 USD per Mtok for that voice, said by name (1000c + 6c)" {
    _big_diff
    _cfg mystery-model-x 150 false
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "4" ]
    [ "$(jq '.metadata.estimated_cents' <<<"$result")" = "1006" ]
    [ "$(jq -r '.metadata.estimate_voices[0].pricing_source' <<<"$result")" = "fallback" ]
    grep -qF "budget: no catalog price for mystery-model-x (primary) — the fixed 10 / 30 USD per Mtok applies to this voice" "$T/stderr.log"
    [ "$(grep -c "no catalog price" "$T/stderr.log")" = "1" ]
}

@test "BUD-3 a zero-priced entry estimates 0c and is said: a 0-cent budget admits it, where the fixed rate would refuse" {
    _cfg fixture-zero 0 false
    s3_run review >/dev/null
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    grep -qF "budget: fixture-zero (primary) is zero-priced in the catalog — estimated 0c" "$T/stderr.log"
    grep -qF "budget: estimate 0c over 1 planned voice(s) (primary fixture-zero 0c)" "$T/stderr.log"
    grep -qx "fixture-zero" "$CALLS"
    # audit a257-1 LOW-A3: the zero price is on an entry not marked open_weight — said by name (the estimate is unchanged)
    grep -qF "budget: zero price on fixture-zero (primary), not marked open_weight — check the pricing overlay" "$T/stderr.log"
    # the same run priced at the fixed rate is refused (the regression this replaces: 2000 output tokens × 30 = 6c > 0)
    _cfg mystery-model-x 0 false
    s3_run review >/dev/null
    [ "$(cat "$T/rc")" = "4" ]
}

@test "BUD-4 the gate sums every planned voice: primary + the companion's first hop + each advisory voice" {
    _big_diff
    _cfg fixture-priced 1 true "    advisory_voices: [fixture-zero, mystery-model-x]"
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "4" ] || { cat "$T/stderr.log"; return 1; }
    [ "$(jq -r '[.metadata.estimate_voices[] | "\(.role)=\(.alias)"] | join(" ")' <<<"$result")" = "primary=fixture-priced companion=claude-headless advisory=fixture-zero advisory=mystery-model-x" ]
    # the companion's price is the catalog's (whatever it is today): recompute it from the same CLI
    local row ci co comp
    row=$(PYTHONSAFEPATH=1 PYTHONPATH="$PROJECT_ROOT/.claude/adapters" python3 -W ignore::RuntimeWarning -m loa_cheval.metering.pricing --alias claude-headless --config "$CONFIG_FILE")
    ci=$(sed -n 's/.* input_per_mtok=\([0-9]*\) .*/\1/p' <<<"$row"); co=$(sed -n 's/.* output_per_mtok=\([0-9]*\) .*/\1/p' <<<"$row")
    [[ "$ci" =~ ^[0-9]+$ && "$co" =~ ^[0-9]+$ ]]
    comp=$(( 1000500 * ci / 10000000000 + 2000 * co / 10000000000 ))
    [ "$(jq '.metadata.estimate_voices[1].estimated_cents' <<<"$result")" = "$comp" ]
    [ "$(jq '.metadata.estimate_voices[2].estimated_cents' <<<"$result")" = "0" ]
    [ "$(jq '.metadata.estimate_voices[3].estimated_cents' <<<"$result")" = "1006" ]
    [ "$(jq '.metadata.estimated_cents' <<<"$result")" = "$(( 201 + comp + 0 + 1006 ))" ]
    [ "$(jq '[.metadata.estimate_voices[].estimated_cents] | add' <<<"$result")" = "$(jq '.metadata.estimated_cents' <<<"$result")" ]
    grep -qF "budget: fixture-zero (advisory) is zero-priced in the catalog — estimated 0c" "$T/stderr.log"
    grep -qF "budget: no catalog price for mystery-model-x (advisory)" "$T/stderr.log"
}

@test "BUD-5 a stale catalog price (price_date older than 90 days) is used as given and said" {
    _cfg fixture-stale 1000 false
    s3_run review >/dev/null
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    grep -qF "budget: fixture-stale (primary) has a stale catalog price (price_date older than 90 days) — used as given" "$T/stderr.log"
}

@test "BUD-6 with no price CLI answer at all every voice falls back and is said (the gate never prices from nothing)" {
    _cfg fixture-priced 1000 false
    # a PYTHONPATH that cannot import the package: the CLI fails, every planned voice is unknown
    local real patched
    real="$(declare -f _adv_budget_estimate)"
    patched="${real/PYTHONPATH=\"\$PROJECT_ROOT\/.claude\/adapters\"/PYTHONPATH=/nonexistent}"
    [ "$patched" != "$real" ]   # (the seam was found: the CLI really cannot be imported in this run)
    eval "$patched"
    s3_run review >/dev/null
    [ "$(cat "$T/rc")" = "0" ]
    grep -qF "budget: no catalog price for fixture-priced (primary)" "$T/stderr.log"
}

@test "BUD-7 a zero-priced entry marked open_weight estimates 0c with no overlay warning (audit a257-1 LOW-A3)" {
    _cfg fixture-zero-ow 0 false
    s3_run review >/dev/null
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    grep -qF "budget: fixture-zero-ow (primary) is zero-priced in the catalog — estimated 0c" "$T/stderr.log"
    ! grep -qF "budget: zero price on fixture-zero-ow" "$T/stderr.log" || { echo "an open_weight entry was warned"; return 1; }
    grep -qx "fixture-zero-ow" "$CALLS"
}
