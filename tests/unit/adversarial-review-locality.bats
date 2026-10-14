#!/usr/bin/env bats
# =============================================================================
# tests/unit/adversarial-review-locality.bats — cycle-129 Sprint 3 Task 3.5 (PRD FR-8 AC-8.1 … AC-8.3, SDD D-8.0 … D-8.2,
# DEC-0146).
#
# Under hounfour.locality: local_voices, adversarial-review.sh plans only hops whose provider has dispatch_group: local in
# the merged config (catalog + the project's hounfour.providers) and refuses every hosted hop of its inventory at plan time
# by name — primary chain, companion chain, advisory voices, the KF-004 repair chain (tiny, claude-headless, any pin; the
# chain is the answering voice). With one local family the audit is DEGRADED_SECURITY_REVIEW, the gate and verdict-derive
# treat the envelope as today, and the output says so. The default (hosted) is unchanged. Mock mode: the harness stub.
# =============================================================================

load adversarial-review-s3-helpers

setup() { export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"; s3_setup sprint-s3loc; }   # (the CLI lock is this test's own — CMP-121)
teardown() { s3_teardown; }

# one hosted provider (openai, the catalog's) and one local provider (localbox, declared here — a provider the cheval
# loader itself admits: keyless, opted in to its loopback host, every model with endpoint_family/auth_type/context_window;
# LOC-10 loads it through loa_cheval.config.loader)
_cfg() {  # <locality value | absent> [extra code_review / security_audit lines]
    local loc=""; [[ "$1" == absent ]] || loc="  locality: $1"
    s3_config "hounfour:
$loc
  providers:
    localbox:
      type: openai_compat
      endpoint: \"http://127.0.0.1:8000/v1\"
      allow_insecure_endpoint: \"127.0.0.1\"
      keyless: true
      models:
        qwen-local:
          endpoint_family: chat
          auth_type: http_api
          context_window: 32768
          dispatch_group: local
          pricing: {input_per_mtok: 0, output_per_mtok: 0}
        qwen-local-b:
          endpoint_family: chat
          auth_type: http_api
          context_window: 32768
          dispatch_group: local
          pricing: {input_per_mtok: 0, output_per_mtok: 0}
        qwen-local-c:
          endpoint_family: chat
          auth_type: http_api
          context_window: 32768
          dispatch_group: local
        qwen-leaky:
          endpoint_family: chat
          auth_type: http_api
          context_window: 32768
          dispatch_group: local
          fallback_chain: [\"openai:gpt-5.5\"]
  aliases:
    lq: \"localbox:qwen-local\"
    lqb: \"localbox:qwen-local-b\"
    lqc: \"localbox:qwen-local-c\"
flatline_protocol:
  code_review:
    enabled: true
    model: gpt-5.5
    budget_cents: 500
    timeout_seconds: 30
    fallback_chain: [lq]
${2:-}
  security_audit:
    enabled: true
    model: gpt-5.5
    budget_cents: 500
    timeout_seconds: 30
    fallback_chain: [lq]
${3:-}"
}

_hosted_in() {  # <file of hop names, one per line> → the hosted ones, as hop-locality.py classifies them against this config
    local hops; hops=$(sed 's/^repair://' "$1" | sort -u | grep -v '^$' || true)
    [[ -n "$hops" ]] || return 0
    # shellcheck disable=SC2086
    python3 -I "$PROJECT_ROOT/.claude/scripts/lib/hop-locality.py" --catalog "$PROJECT_ROOT/.claude/defaults/model-config.yaml" \
        --config "$CONFIG_FILE" -- $hops | awk -F'\t' '$3 != "local" { print $1 }'
}

@test "LOC-1 one hosted and one local provider: only the local hop is planned and every hosted hop is refused by name" {
    _cfg local_voices
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    env="$OUT_DIR/adversarial-review.json"
    # the dispatched hops: the local one only
    [ "$(sort -u "$CALLS" | tr '\n' ' ')" = "lq " ]
    [ "$(jq -r '.metadata.final_model' "$env")" = "lq" ]
    [ "$(jq -r '.metadata.model_attempts | join(",")' "$env")" = "lq:reviewed" ]
    # each refusal named: the hosted primary, the companion's default hop, the repair chain's two hosted hops
    grep -qxF "[adversarial-review] locality: local_voices refuses hosted hop gpt-5.5 (openai)" "$T/stderr.log"
    grep -qxF "[adversarial-review] locality: local_voices refuses hosted hop claude-headless (anthropic)" "$T/stderr.log"
    grep -qxF "[adversarial-review] locality: local_voices refuses hosted hop tiny (anthropic)" "$T/stderr.log"
    # the companion was not planned: its chain had no local hop — never rerouted
    [ "$(jq -r '.metadata.companion_voice.planned' "$env")" = "false" ]
    [ "$(jq -r '.metadata.companion_voice.reason' "$env")" = "locality_refused" ]
    # the envelope names the posture and each refusal with its role
    [ "$(jq -r '.metadata.locality.mode' "$env")" = "local_voices" ]
    # audit a257-1 LOW-A2: a review envelope is not a degraded security review, and carries no audit sentence
    [ "$(jq -r '.metadata.locality.degraded_security_review' "$env")" = "false" ]
    jq -e '.metadata.locality | has("note") | not' "$env" >/dev/null
    [ "$(jq -r '[.metadata.locality.refused[] | "\(.role):\(.alias):\(.provider)"] | sort | join(" ")' "$env")" = \
      "companion:claude-headless:anthropic primary:gpt-5.5:openai repair:claude-headless:anthropic repair:tiny:anthropic" ]
    [ "$(jq '.verdict_quality.voices_planned' "$env")" = "1" ]
}

@test "LOC-2 the repair chain is pinned to the answering local voice: no tiny, no claude-headless, no pin — even with an Anthropic key" {
    _cfg local_voices
    export ANTHROPIC_API_KEY="fixture-not-a-key"   # (tiny would lead the hosted chain with a key present)
    export LOA_ADVERSARIAL_REPAIR_MODEL="tiny claude-headless"
    load_adversarial_config review
    [ "$CONF_LOCALITY" = "local_voices" ]
    [ "$(_repair_model_chain lq)" = "lq" ]
    [ "$(_repair_chain_base lq)" = "lq" ]
    [ "$(_repair_model_chain gpt-5.5)" = "" ]   # (a hosted answering voice gets no repair hop at all)
    # and under hosted the same host walks tiny first (the switch is what pins it)
    _cfg hosted
    load_adversarial_config review
    [ "$(_repair_model_chain lq)" = "tiny claude-headless" ]   # (the operator pin is the whole chain under hosted)
    unset LOA_ADVERSARIAL_REPAIR_MODEL
    [ "$(_repair_model_chain lq)" = "tiny claude-headless lq" ]
}

@test "LOC-3 redaction-style: in a whole run with a rejected payload, an Anthropic key and the CLIs present, no hosted alias is ever dispatched" {
    _cfg local_voices "    advisory_voices: [lqc, gpt-5.5-pro]
    companion_chain:
      anthropic: [opus, lqb]"
    export ANTHROPIC_API_KEY="fixture-not-a-key" OPENAI_API_KEY="fixture-not-a-key"
    _repair_finding_via_model() { echo "repair:$4" >> "$CALLS"; return 1; }
    BEHAVIOUR[lq]=reject
    s3_run review >/dev/null
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    env="$OUT_DIR/adversarial-review.json"
    [ -s "$CALLS" ]
    grep -qx "repair:lq" "$CALLS"   # (the repair loop ran — pinned to the answering voice)
    [ "$(_hosted_in "$CALLS")" = "" ] || { echo "hosted hops dispatched:"; _hosted_in "$CALLS"; return 1; }
    # no hosted name in any planned hop the envelope records
    local planned
    planned=$(jq -r '[.metadata.model_attempts[], (.metadata.companion_voice.chain // [])[], (.advisory_voices // [] | map(select(.status != "refused")) | .[].alias)] | .[] | sub(":[a-z_]+$"; "")' "$env")
    printf '%s\n' "$planned" > "$T/planned"
    [ "$(_hosted_in "$T/planned")" = "" ] || { echo "hosted hops planned:"; _hosted_in "$T/planned"; return 1; }
    [ "$(jq -r '.metadata.companion_voice.chain | join(",")' "$env")" = "lqb" ]
    grep -qxF "[adversarial-review] locality: local_voices refuses hosted hop opus (anthropic)" "$T/stderr.log"
    grep -qxF "[adversarial-review] locality: local_voices refuses hosted hop gpt-5.5-pro (openai)" "$T/stderr.log"
    # the refused advisory voice is named in the block, never run
    [ "$(jq -r '.advisory_voices[] | select(.alias == "gpt-5.5-pro") | .status' "$env")" = "refused" ]
    [ "$(jq -r '.advisory_voices[] | select(.alias == "lqc") | .status' "$env")" = "succeeded" ]
    ! grep -qx "gpt-5.5-pro" "$CALLS" || { echo "a refused advisory voice was dispatched"; return 1; }
}

@test "LOC-4 one local family on the audit gate: the companion is duplicate_voice, the DEGRADED sentence is in the output, and the gate and verdict-derive treat the envelope as today" {
    _cfg local_voices "" "    companion_chain:
      anthropic: [lqb]"
    s3_run audit >/dev/null
    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    env="$OUT_DIR/adversarial-audit.json"
    [ "$(jq -r '.metadata.companion_voice.counted_as' "$env")" = "duplicate_voice" ]
    local s="locality: local_voices — with one local family the companion is not an independent second voice (duplicate_voice, or not planned), so every security audit is DEGRADED_SECURITY_REVIEW; adversarial-review-gate.sh and verdict-derive.sh treat this envelope exactly as they treat any other."
    grep -qxF "[adversarial-review] $s" "$T/stderr.log"
    [ "$(jq -r '.metadata.locality.note' "$env")" = "$s" ]
    # audit a257-1 LOW-A2: the one-family case is machine-readable on the audit envelope
    [ "$(jq -r '.metadata.locality.degraded_security_review' "$env")" = "true" ]
    # the config comment carries the same sentence
    grep -qF "$s" "$PROJECT_ROOT/.loa.config.yaml.example"
    # the COMPLETED gate opens on it (presence + metadata.type/model — today's check)
    local hook="$PROJECT_ROOT/.claude/hooks/safety/adversarial-review-gate.sh" cfg="$T/gate.yaml" rc=0
    printf 'flatline_protocol:\n  security_audit:\n    enabled: true\n' > "$cfg"
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s/COMPLETED"}}' "$OUT_DIR" \
        | env -u LOA_ADVERSARIAL_REVIEW_ENFORCE LOA_CONFIG_PATH_OVERRIDE="$cfg" bash "$hook" >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    # verdict-derive reads it like any envelope: an approved audit with the DEGRADED marker is consistent
    printf '%s\n' "APPROVED - LET'S FUCKING GO" '' 'DEGRADED_SECURITY_REVIEW: one local family (locality: local_voices).' \
        '<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-x","ts":"2026-10-14T00:00:00Z"} -->' \
        > "$OUT_DIR/auditor-sprint-feedback.md"
    run bash "$PROJECT_ROOT/.claude/scripts/verdict-derive.sh" --file "$OUT_DIR/auditor-sprint-feedback.md" --gate audit --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.consistent' <<<"$output")" = "true" ]
    [ "$(jq -r '.verdict' <<<"$output")" = "APPROVED" ]
}

@test "LOC-5 the default (no key) and hounfour.locality: hosted are unchanged: the hosted primary is dispatched, nothing is refused, no locality key" {
    local v
    for v in absent hosted; do
        : > "$CALLS"
        _cfg "$v"
        s3_run review >/dev/null
        [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
        grep -qx "gpt-5.5" "$CALLS"
        grep -qx "claude-headless" "$CALLS"   # (the default companion chain on a keyless host with the CLI)
        ! grep -q "locality:" "$T/stderr.log" || { echo "a locality line under $v"; return 1; }
        jq -e '.metadata | has("locality") | not' "$OUT_DIR/adversarial-review.json" >/dev/null
        [ "$(jq '.verdict_quality.voices_planned' "$OUT_DIR/adversarial-review.json")" = "2" ]
    done
}

@test "LOC-6 a primary chain with no local hop is refused before any call; an unknown locality value is refused by name" {
    _cfg local_voices
    yq -i '.flatline_protocol.code_review.fallback_chain = ["gpt-5.3-codex"]' "$CONFIG_FILE"
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "1" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "locality_refused" ]
    grep -qF "locality: local_voices leaves no local hop on the primary chain" "$T/stderr.log"
    [ ! -s "$CALLS" ]
    _cfg local
    result=$(s3_run review)
    [ "$(cat "$T/rc")" = "1" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "locality_invalid" ]
    grep -qF "hounfour.locality='local' is neither hosted nor local_voices" "$T/stderr.log"
    [ ! -s "$CALLS" ]
}

@test "LOC-7 a local entry whose fallback_chain reaches a hosted model is hosted (cheval would walk it inside the call)" {
    _cfg local_voices
    run python3 -I "$PROJECT_ROOT/.claude/scripts/lib/hop-locality.py" --catalog "$PROJECT_ROOT/.claude/defaults/model-config.yaml" \
        --config "$CONFIG_FILE" -- lq localbox:qwen-leaky opus native unknown-x
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p <<<"$output" | cut -f2-3)" = "localbox	local" ]
    [ "$(sed -n 2p <<<"$output" | cut -f3-4)" = "hosted	fallback_chain_reaches_hosted:openai:gpt-5.5(openai)" ]
    [ "$(sed -n 3p <<<"$output" | cut -f2-3)" = "anthropic	hosted" ]
    [ "$(sed -n 4p <<<"$output" | cut -f3)" = "hosted" ]
    [ "$(sed -n 5p <<<"$output" | cut -f2-4)" = "unknown	hosted	unresolved" ]
    # an unreadable config is fail-closed: every hop hosted
    printf ':\n  - [\n' > "$T/broken.yaml"
    run python3 -I "$PROJECT_ROOT/.claude/scripts/lib/hop-locality.py" --catalog "$PROJECT_ROOT/.claude/defaults/model-config.yaml" --config "$T/broken.yaml" -- lq
    [ "$(cut -f3-4 <<<"${lines[-1]}")" = "hosted	config_unreadable" ]
}

@test "LOC-8 the multi-model reference says the Claude Code session model is exempt and remains the platform" {
    grep -q "hounfour.locality: local_voices" "$PROJECT_ROOT/.claude/loa/reference/multi-model-reference.md"
    grep -qi "Claude Code session model is exempt" "$PROJECT_ROOT/.claude/loa/reference/multi-model-reference.md"
}

@test "LOC-9 a declared dispatch_group local on a hosted DNS endpoint (or a CLI provider) is hosted and refused by name (r257-1)" {
    _cfg local_voices
    yq -i '.hounfour.providers.hostedbox = {"type": "openai_compat", "endpoint": "https://api.acme.example/v1",
             "models": {"qwen-hosted": {"dispatch_group": "local", "endpoint_family": "chat", "auth_type": "http_api", "context_window": 32768}}}
           | .hounfour.providers.blockbox = {"type": "openai_compat", "endpoint": "https://203.0.113.5/v1", "dispatch_group": "local",
             "models": {"qwen-b": {"dispatch_group": "local", "endpoint_family": "chat", "auth_type": "http_api", "context_window": 32768}}}
           | .hounfour.providers.clibox = {"type": "claude-headless", "models": {"c1": {"kind": "cli", "dispatch_group": "local"}}}
           | .hounfour.providers.noend = {"type": "openai_compat", "models": {"n1": {"dispatch_group": "local"}}}
           | .hounfour.aliases.hb = "hostedbox:qwen-hosted"
           | .flatline_protocol.code_review.fallback_chain = ["hb", "lq"]' "$CONFIG_FILE"
    run python3 -I "$PROJECT_ROOT/.claude/scripts/lib/hop-locality.py" --catalog "$PROJECT_ROOT/.claude/defaults/model-config.yaml" \
        --config "$CONFIG_FILE" -- hb blockbox:qwen-b clibox:c1 noend:n1 lq "localbox:qwen-local"
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p <<<"$output" | cut -f2-4)" = "hostedbox	hosted	endpoint_not_local:api.acme.example" ] || { echo "$output"; return 1; }
    [ "$(sed -n 2p <<<"$output" | cut -f2-4)" = "blockbox	hosted	endpoint_not_local:203.0.113.5" ]
    [ "$(sed -n 3p <<<"$output" | cut -f2-4)" = "clibox	hosted	cli_provider" ]
    [ "$(sed -n 4p <<<"$output" | cut -f2-4)" = "noend	hosted	endpoint_missing" ]
    [ "$(sed -n 5p <<<"$output" | cut -f2-4)" = "localbox	local	dispatch_group=local" ]
    [ "$(sed -n 6p <<<"$output" | cut -f3)" = "local" ]
    # two layers, same config (r257-2 LOW-2): the planner refuses the mislabelled hop by name at plan time and never
    # dispatches it (shown under the harness stub, which stands in for cheval) …
    result=$(s3_run review)
    grep -qxF "[adversarial-review] locality: local_voices refuses hosted hop hb (hostedbox)" "$T/stderr.log" || { cat "$T/stderr.log"; return 1; }
    ! grep -qx "hb" "$CALLS" || { echo "the mislabelled hosted hop was dispatched"; return 1; }
    # … and in production cheval's loader refuses the WHOLE config by name at the first dispatch, so no hop of this
    # config — local ones included — answers until the label or the endpoint is fixed (the outcome an operator sees).
    mkdir -p "$T/proj9/.claude/defaults"
    cp "$PROJECT_ROOT/.claude/defaults/model-config.yaml" "$T/proj9/.claude/defaults/"
    cp "$CONFIG_FILE" "$T/proj9/.loa.config.yaml"
    # (clibox and noend are classifier-only shapes: the loader's older field checks would refuse them first; the two
    # complete HTTP providers reach the local-label rule itself)
    yq -i 'del(.hounfour.providers.clibox) | del(.hounfour.providers.noend)' "$T/proj9/.loa.config.yaml"
    run python3 -I -c 'import sys; sys.path.insert(0, sys.argv[2] + "/.claude/adapters")
from loa_cheval.config.loader import load_config
try:
    load_config(project_root=sys.argv[1])
except Exception as exc:
    print(exc); sys.exit(3)
print("loaded"); sys.exit(0)' "$T/proj9" "$PROJECT_ROOT"
    [ "$status" -eq 3 ] || { echo "the loader admitted a mislabelled provider: $output"; return 1; }
    [[ "$output" == *"[CONFIG-INVALID] providers."*"dispatch_group local"* ]] || { echo "$output"; return 1; }
}

@test "LOC-10 the suite's localbox fixture is a provider the cheval loader admits (LOW-1, r257-1); under local_voices the loader refuses qwen-leaky's hosted fallback by name (audit a257-1 MEDIUM-A1 (b))" {
    _load10() {
        run python3 -I -c 'import sys; sys.path.insert(0, sys.argv[2] + "/.claude/adapters")
from loa_cheval.config.loader import load_config
try:
    merged, _ = load_config(project_root=sys.argv[1])
except Exception as exc:
    print(exc); sys.exit(3)
p = merged["providers"]["localbox"]
assert p["keyless"] is True and p["allow_insecure_endpoint"] == "127.0.0.1", p
print("loaded", " ".join(sorted(p["models"])))' "$T/proj" "$PROJECT_ROOT"
    }
    mkdir -p "$T/proj/.claude/defaults"
    cp "$PROJECT_ROOT/.claude/defaults/model-config.yaml" "$T/proj/.claude/defaults/"
    # under hosted a local model may still fall back to the cloud: the whole fixture loads
    _cfg hosted
    cp "$CONFIG_FILE" "$T/proj/.loa.config.yaml"
    _load10
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"loaded qwen-leaky qwen-local qwen-local-b qwen-local-c"* ]]
    # under local_voices the loader refuses the local model whose fallback_chain reaches a hosted hop, by name …
    _cfg local_voices
    cp "$CONFIG_FILE" "$T/proj/.loa.config.yaml"
    _load10
    [ "$status" -eq 3 ] || { echo "the loader admitted qwen-leaky under local_voices: $output"; return 1; }
    [[ "$output" == *"[CONFIG-INVALID] providers.localbox.models.qwen-leaky: under hounfour.locality local_voices the fallback_chain reaches a hosted hop openai:gpt-5.5"* ]] || { echo "$output"; return 1; }
    # … and the rest of the fixture loads
    yq -i 'del(.hounfour.providers.localbox.models.qwen-leaky)' "$T/proj/.loa.config.yaml"
    _load10
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"loaded qwen-local qwen-local-b qwen-local-c"* ]]
}
