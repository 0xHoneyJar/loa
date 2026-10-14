#!/usr/bin/env bats
# =============================================================================
# tests/unit/adversarial-review-advisory.bats — cycle-129 Sprint 3 Task 3.3 (PRD FR-7 AC-7.3, SDD D-7.4, DEC-0165, DEC-0155).
#
# Advisory voices run after the counted voices on the same prompts, concurrently, under one wall clock; their findings
# live ONLY under advisory_voices[].findings (voice: advisory, counted_as: advisory_voice, duplicate_of links); the rest of
# the envelope and the verdict-derive output are byte-identical (normalised: timestamps removed) with and without them;
# a failed or timed-out advisory voice is a status, never a verdict input; an attempt to count one is refused by name.
# Mock mode: invoke_dissenter is the harness stub (tests/unit/adversarial-review-s3-helpers.bash) — no model is called.
# =============================================================================

load adversarial-review-s3-helpers

setup() { export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"; s3_setup sprint-s3adv; }   # (the CLI lock is this test's own — CMP-121)
teardown() { s3_teardown; }

_base_cfg() {  # [extra lines for the code_review block]
    s3_config "flatline_protocol:
  code_review:
    enabled: true
    model: gpt-5.5-pro
    budget_cents: 500
    timeout_seconds: 30
    fallback_chain: []
${1:-}"
}

_feedback() {  # an approved review next to the envelope, for verdict-derive
    mkdir -p "$OUT_DIR"
    printf '%s\n' 'All good' '' 'No issues found.' \
      '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-x","ts":"2026-10-14T00:00:00Z"} -->' \
      > "$OUT_DIR/engineer-feedback.md"
}

_vd() {  # → verdict-derive's --json output on the standing envelope (status recorded, output kept whatever it is)
    "$PROJECT_ROOT/.claude/scripts/verdict-derive.sh" --file "$OUT_DIR/engineer-feedback.md" --gate review --json 2>"$T/vd.err" || true
}

@test "ADV-1 an advisory voice's findings are present only under advisory_voices[].findings, tagged and linked by duplicate_of" {
    _base_cfg "    advisory_voices: [adv-two]"
    BEHAVIOUR[adv-two]=two
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    env="$OUT_DIR/adversarial-review.json"
    # the counted voices are untouched: primary + companion, nothing advisory at the top level
    [ "$(jq '.findings | length' "$env")" = "2" ]
    [ "$(jq '[.findings[] | select(.voice == "advisory")] | length' "$env")" = "0" ]
    [ "$(jq '.verdict_quality.voices_planned' "$env")" = "2" ]
    # the block
    [ "$(jq '.advisory_voices | length' "$env")" = "1" ]
    [ "$(jq -r '.advisory_voices[0].alias' "$env")" = "adv-two" ]
    [ "$(jq -r '.advisory_voices[0].status' "$env")" = "succeeded" ]
    [ "$(jq -r '.advisory_voices[0].counted_as' "$env")" = "advisory_voice" ]
    [ "$(jq '.advisory_voices[0].findings | length' "$env")" = "3" ]
    [ "$(jq -r '[.advisory_voices[0].findings[].voice] | unique | join(",")' "$env")" = "advisory" ]
    [ "$(jq -r '[.advisory_voices[0].findings[].id] | join(",")' "$env")" = "DISS-A1-001,DISS-A1-002,DISS-A1-003" ]
    # same file, overlapping lines (9-12 over 10), same category → the counted primary finding; else null
    [ "$(jq -r '.advisory_voices[0].findings[0].duplicate_of' "$env")" = "DISS-001" ]
    [ "$(jq -r '.advisory_voices[0].findings[1].duplicate_of' "$env")" = "null" ]   # (line 40: no overlap)
    [ "$(jq -r '.advisory_voices[0].findings[2].duplicate_of' "$env")" = "null" ]   # (same line, another category)
    [ "$(jq -r '.advisory_voices[0].findings[0].answered_by' "$env")" = "adv-two" ]
    grep -qx "adv-two" "$CALLS"
    # stdout carries the same envelope
    [ "$(jq '.advisory_voices | length' <<<"$result")" = "1" ]
}

@test "ADV-2 the envelope without advisory_voices and the verdict-derive --json output are byte-identical with and without advisory voices" {
    _feedback
    BEHAVIOUR[adv-two]=two; BEHAVIOUR[adv-reject]=reject; BEHAVIOUR[adv-fail]=fail
    _base_cfg
    s3_run review >/dev/null
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    cp "$OUT_DIR/adversarial-review.json" "$T/without.json"
    _vd > "$T/vd-without.json"
    ls "$OUT_DIR" | LC_ALL=C sort > "$T/ls-without"
    _base_cfg "    advisory_voices: [adv-two, adv-reject, adv-fail]"
    s3_run review >/dev/null
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    cp "$OUT_DIR/adversarial-review.json" "$T/with.json"
    _vd > "$T/vd-with.json"
    ls "$OUT_DIR" | LC_ALL=C sort > "$T/ls-with"
    [ "$(jq '.advisory_voices | length' "$T/with.json")" = "3" ]
    jq -e 'has("advisory_voices") | not' "$T/without.json" >/dev/null
    # the normalised envelopes (advisory_voices deleted, timestamps removed, keys sorted) are byte-identical
    diff <(s3_norm "$T/without.json") <(s3_norm "$T/with.json")
    # …and each named input on its own, so a failure names it
    local k
    for k in '.findings' '.verdict_quality' '.verdict_quality.voices_planned' '.verdict_quality.voices_succeeded' \
             '.metadata.companion_voice' '.metadata.rejected_summary' '.metadata.rejected_sidecars' '.metadata.cost_usd'; do
        [ "$(jq -cS "$k" "$T/without.json")" = "$(jq -cS "$k" "$T/with.json")" ] || { echo "differs: $k"; return 1; }
    done
    # verdict-derive reads the same envelope and sidecars: its --json output is byte-identical
    [ -s "$T/vd-without.json" ]
    diff "$T/vd-without.json" "$T/vd-with.json"
    # the advisory voice's rejected payload never landed beside the envelope (verdict-derive would count it)
    diff "$T/ls-without" "$T/ls-with"
    [ "$(jq -r '.advisory_voices[] | select(.alias == "adv-reject") | .rejected_count' "$T/with.json")" = "1" ]
}

@test "ADV-3 a failed or malformed advisory voice is recorded under advisory_voices[].status and ignored by verdict quality" {
    BEHAVIOUR[adv-fail]=fail; BEHAVIOUR[adv-bad]=malformed
    _base_cfg "    advisory_voices: [adv-fail, adv-bad]"
    s3_run review >/dev/null
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    env="$OUT_DIR/adversarial-review.json"
    [ "$(jq -r '[.advisory_voices[].status] | join(",")' "$env")" = "failed,failed" ]
    [ "$(jq '[.advisory_voices[].findings | length] | add' "$env")" = "0" ]
    [ "$(jq -r '.verdict_quality.status' "$env")" = "APPROVED" ]
    [ "$(jq '.verdict_quality.voices_planned' "$env")" = "2" ]
    [ "$(jq '.verdict_quality.voices_succeeded' "$env")" = "2" ]
    [ "$(jq '[.verdict_quality.voices_dropped[]?.voice] | map(select(test("adv-"))) | length' "$env")" = "0" ]
}

@test "ADV-4 the advisory wall clock is honoured: a voice still running is killed and timed_out while a fast one completes" {
    BEHAVIOUR[adv-slow]=slow; BEHAVIOUR[adv-two]=two
    _base_cfg "    advisory_voices: [adv-slow, adv-two]
    advisory_timeout_seconds: 2"
    local t0 t1; t0=$(date +%s)
    s3_run review >/dev/null
    t1=$(date +%s)
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    (( t1 - t0 < 60 ))
    env="$OUT_DIR/adversarial-review.json"
    [ "$(jq -r '.advisory_voices[0].status' "$env")" = "timed_out" ]
    [ "$(jq -r '.advisory_voices[1].status' "$env")" = "succeeded" ]
    grep -q "Advisory voice adv-slow: still running at the 2s advisory wall clock — killed (timed_out)" "$T/stderr.log"
    # the hung hop did not outlive the run
    sleep 0.5
    ! pgrep -f "loa-s3adv-slow-$$" >/dev/null || { echo "the hung advisory hop outlived the run"; return 1; }
    [ "$(jq '.verdict_quality.voices_planned' "$env")" = "2" ]
}

@test "ADV-5 an advisory alias the block also counts in companion_chain is refused by name at plan time, before any call" {
    _base_cfg "    advisory_voices: [claude-headless]
    companion_chain:
      anthropic: [claude-headless]"
    printf 'hounfour:\n  advisory_promotion:\n    min_recall_ratio: 0.8\n' >> "$CONFIG_FILE"
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "1" ]
    grep -qF "advisory voice claude-headless cannot be counted: no arms report line for the alias (voice arms are a future iteration)" "$T/stderr.log"
    grep -qF "hounfour.advisory_promotion: min_recall_ratio=0.8, max_refuted_delta=unset" "$T/stderr.log"
    [ "$(jq -r '.metadata.status' <<<"$result")" = "advisory_promotion_refused" ]
    [ "$(jq -r '.metadata.alias' <<<"$result")" = "claude-headless" ]
    [ ! -s "$CALLS" ]
    [ ! -e "$OUT_DIR/adversarial-review.json" ]
}

@test "ADV-6 with no advisory_voices the envelope has no advisory_voices key (the default is unchanged)" {
    _base_cfg
    s3_run review >/dev/null
    [ "$(cat "$T/rc")" = "0" ]
    jq -e 'has("advisory_voices") | not' "$OUT_DIR/adversarial-review.json" >/dev/null
    _base_cfg "    advisory_voices: []"
    s3_run review >/dev/null
    jq -e 'has("advisory_voices") | not' "$OUT_DIR/adversarial-review.json" >/dev/null
    ! grep -q "Advisory voice" "$T/stderr.log" || { echo "an empty advisory_voices ran something"; return 1; }
}

@test "ADV-7 a malformed advisory_voices value is said and ignored; a bad element is dropped by index" {
    _base_cfg "    advisory_voices: adv-two"
    s3_run review >/dev/null
    grep -q "advisory_voices is a str, not a list of aliases — ignored" "$T/stderr.log"
    jq -e 'has("advisory_voices") | not' "$OUT_DIR/adversarial-review.json" >/dev/null
    BEHAVIOUR[adv-two]=two
    _base_cfg "    advisory_voices: [adv-two, {x: 1}, 'bad name']"
    s3_run review >/dev/null
    grep -q "advisory_voices\[1\] is not a hop name (!!map) — dropped" "$T/stderr.log"
    grep -q "advisory_voices\[2\] is not a hop name (!!str) — dropped" "$T/stderr.log"
    [ "$(jq -r '[.advisory_voices[].alias] | join(",")' "$OUT_DIR/adversarial-review.json")" = "adv-two" ]
}

@test "ADV-9 the audit gate reads security_audit.advisory_voices: the block is on adversarial-audit.json, the tally inputs unchanged" {
    BEHAVIOUR[adv-two]=two; BEHAVIOUR[adv-reject]=reject
    s3_config "flatline_protocol:
  security_audit:
    enabled: true
    model: gpt-5.5-pro
    budget_cents: 500
    timeout_seconds: 30
    fallback_chain: []
    advisory_voices: [adv-two, adv-reject]
  code_review:
    advisory_voices: [not-this-gate]"
    s3_run audit >/dev/null
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    env="$OUT_DIR/adversarial-audit.json"
    [ "$(jq -r '[.advisory_voices[].alias] | join(",")' "$env")" = "adv-two,adv-reject" ]
    [ "$(jq -r '.advisory_voices[0].findings[0].severity' "$env")" = "MEDIUM" ]
    [ "$(jq -r '.advisory_voices[0].findings[0].duplicate_of' "$env")" = "DISS-001" ]
    [ "$(jq '.advisory_voices[1].rejected_summary | length' "$env")" = "1" ]
    [ "$(jq '.metadata.rejected_count' "$env")" = "0" ]
    ! grep -qx "not-this-gate" "$CALLS" || { echo "the review block's advisory voice ran on the audit gate"; return 1; }
}

@test "ADV-8 the review and audit skills tell the reader to read advisory_voices[].findings as advisory input" {
    grep -q 'advisory_voices\[\]\.findings' "$PROJECT_ROOT/.claude/skills/reviewing-code/SKILL.md"
    grep -q 'advisory_voices\[\]\.findings' "$PROJECT_ROOT/.claude/skills/auditing-security/SKILL.md"
}
