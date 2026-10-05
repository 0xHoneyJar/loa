#!/usr/bin/env bats
# =============================================================================
# tests/unit/model-residue.bats — cycle-126 sprint-250 Tasks 4.2/4.3 (SDD D-4.1,
# D-4.3; bead bd-2fti). No routing alias, bash map, default or example pin names
# the previous generation as current: the bash maps agree with the catalog's
# `opus`, the script defaults are catalog aliases, `cheap` is Sonnet 5, the
# Gemini agents name served ids, and the acceptance grep returns nothing.
# =============================================================================

setup() {
    R="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CAT="${RES_CAT:-$R/.claude/defaults/model-config.yaml}"   # RES_CAT: red-first replay against a base catalog
}

yq_cat() { python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1]))
for k in sys.argv[2].split("."): d=d[k]
print(d)' "$CAT" "$1"; }

# map_value <script> <array> <key>
map_value() {
    local src
    src=$(awk -v a="$2" '$0 ~ "^declare -A "a"=\\(" {f=1} f{print} f && /^\)/{exit}' "$1")
    bash -c "$src"$'\n''printf "%s" "${'"$2"'[$1]:-}"' _ "$3"
}

@test "RES-1 the catalog: opus → claude-opus-5-5 (priced from the vendor page), cheap → claude-sonnet-5, opus-5 still pinnable" {
    [ "$(yq_cat aliases.opus)" = "anthropic:claude-opus-5-5" ]
    [ "$(yq_cat aliases.cheap)" = "anthropic:claude-sonnet-5" ]
    [ "$(yq_cat providers.anthropic.models.claude-opus-5-5.pricing.input_per_mtok)" = "4000000" ]
    [ "$(yq_cat providers.anthropic.models.claude-opus-5-5.pricing.output_per_mtok)" = "20000000" ]
    [ "$(yq_cat providers.anthropic.models.claude-opus-5-5.pricing.cache_read_per_mtok)" = "200000" ]
    [ "$(yq_cat backward_compat_aliases.claude-opus-5)" = "anthropic:claude-opus-5" ]
    [ "$(yq_cat backward_compat_aliases.claude-opus-5-5)" = "anthropic:claude-opus-5-5" ]
    grep -qE '^      anthropic: cheap +# → claude-sonnet-5$' "$CAT"
}

@test "RES-2 every bash opus map agrees with the catalog's aliases.opus" {
    local want s
    want=$(yq_cat aliases.opus)
    [ "$(map_value "$R/.claude/scripts/model-adapter.sh" MODEL_TO_ALIAS opus)" = "$want" ]
    for s in flatline-orchestrator.sh red-team-model-adapter.sh; do
        [ "$(map_value "$R/.claude/scripts/$s" MODEL_TO_PROVIDER_ID opus)" = "$want" ] || { echo "$s" >&2; return 1; }
        [ "$(map_value "$R/.claude/scripts/$s" MODEL_TO_PROVIDER_ID claude-sonnet-5)" = "anthropic:claude-sonnet-5" ] || { echo "$s sonnet-5" >&2; return 1; }
        [ "$(map_value "$R/.claude/scripts/$s" MODEL_TO_PROVIDER_ID claude-fable-5-1)" = "anthropic:claude-fable-5-1" ] || { echo "$s fable" >&2; return 1; }
    done
}

@test "RES-3 script defaults are catalog aliases: flatline-proposal-review / validate-learning / learning-extractor / red-team-pipeline" {
    local s
    for s in flatline-proposal-review.sh flatline-validate-learning.sh; do
        grep -qF 'GPT_MODEL="${LOA_GPT_MODEL:-reviewer}"' "$R/.claude/scripts/$s" || { echo "$s GPT" >&2; return 1; }
        grep -qF 'OPUS_MODEL="${LOA_OPUS_MODEL:-opus}"' "$R/.claude/scripts/$s" || { echo "$s OPUS" >&2; return 1; }
    done
    grep -qF 'call_flatline_chat "cheap"' "$R/.claude/scripts/flatline-learning-extractor.sh"
    grep -qF '.red_team.models.evaluator_primary // "opus"' "$R/.claude/scripts/red-team-pipeline.sh"
    [ "$(yq_cat aliases.reviewer)" != "" ]
}

@test "RES-4 example pins: hitl-jury-panel uses opus, alternative-model names the Bedrock Opus 4.8 id the catalog serves" {
    ! grep -q 'claude-opus-4-7' "$R/.claude/skills/hitl-jury-panel/SKILL.md"
    [ "$(grep -c '      model: opus$' "$R/.claude/skills/hitl-jury-panel/SKILL.md")" -ge 2 ]
    grep -qF 'bedrock:us.anthropic.claude-opus-4-8' "$R/.claude/data/personas/alternative-model.md"
    ! grep -q 'claude-3-5-sonnet' "$R/.claude/data/personas/alternative-model.md"
    python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); assert "us.anthropic.claude-opus-4-8" in d["providers"]["bedrock"]["models"]' "$CAT"
}

@test "RES-5 Gemini agents name served ids: deep-thinker → gemini-3.1-pro (thinking_traces), fast-thinker stays gemini-3-flash (no 3.1 flash served)" {
    [ "$(yq_cat agents.deep-thinker.model)" = "gemini-3.1-pro" ]
    python3 - "$CAT" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
target = d["aliases"]["gemini-3.1-pro"].split(":", 1)[1]
assert "thinking_traces" in d["providers"]["google"]["models"][target]["capabilities"], target
assert d["agents"]["fast-thinker"]["model"] == "gemini-3-flash"
assert not any(k.startswith("gemini-3.1-flash") for k in d["providers"]["google"]["models"])
PY
}

@test "RES-6 the acceptance grep: no previous-generation model is a default or described as current in live scripts, skills and data" {
    run grep -rnE -- ':-gpt-4o|:-claude-3|"gpt-4o-mini"|// "claude-opus-4-|\["opus"\]="anthropic:claude-opus-4-|Claude Opus 4\.7 \(current|model: claude-opus-4-7$|claude-3-5-sonnet' \
        "$R/.claude/scripts" "$R/.claude/data" "$R/.claude/hooks" \
        "$R/.claude/skills/hitl-jury-panel" "$R/.claude/skills/flatline-knowledge" "$R/.claude/skills/red-teaming"
    [ "$status" -eq 1 ] || { echo "$output" >&2; return 1; }
    run grep -nE 'Claude Opus 4\.7 \(alias resolves|opus: "anthropic:claude-opus-5" ' "$R/.loa.config.yaml.example"
    [ "$status" -eq 1 ] || { echo "$output" >&2; return 1; }
}
