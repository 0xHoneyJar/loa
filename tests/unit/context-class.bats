#!/usr/bin/env bats
# =============================================================================
# tests/unit/context-class.bats — cycle-126 Sprint 3 (PRD FR-3.1, SDD D-3.1)
# The context class: `long` by default; `standard` under LOA_CONTEXT_CLASS=standard
# or when the session model resolves to a catalog entry with context_window
# ≤ 200000 (alias-aware); written to .run/context-class atomically; never a
# non-zero exit; `--line` is the /loa line.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$PROJECT_ROOT/.claude/hooks/session-start/loa-context-class.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/cc.XXXXXX")"
  unset LOA_CONTEXT_CLASS
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }
_class() { head -1 "$T/.run/context-class"; }
_basis() { sed -n 2p "$T/.run/context-class" | grep -o 'basis=[a-z]*' | cut -d= -f2; }

@test "CC-1 default: long, basis default, file written (creating .run), exit 0, silent as a hook" {
  run bash "$HOOK" --root "$T" < /dev/null
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(_class)" = "long" ]; [ "$(_basis)" = "default" ]
  [ ! -e "$T/.run/.context-class."* ] || false
}

@test "CC-2 LOA_CONTEXT_CLASS=standard selects standard (basis env); =long pins long" {
  LOA_CONTEXT_CLASS=standard run bash "$HOOK" --root "$T" < /dev/null
  [ "$status" -eq 0 ]; [ "$(_class)" = "standard" ]; [ "$(_basis)" = "env" ]
  LOA_CONTEXT_CLASS=long run bash "$HOOK" --root "$T" --model claude-haiku-4-5-20251001 < /dev/null
  [ "$(_class)" = "long" ]; [ "$(_basis)" = "env" ]
}

@test "CC-3 a 200K session model selects standard, a 1M model long, an alias resolves (tiny → Haiku)" {
  run bash "$HOOK" --root "$T" --model claude-haiku-4-5-20251001 < /dev/null
  [ "$(_class)" = "standard" ]; [ "$(_basis)" = "model" ]
  run bash "$HOOK" --root "$T" --model claude-opus-5 < /dev/null
  [ "$(_class)" = "long" ]; [ "$(_basis)" = "model" ]
  run bash "$HOOK" --root "$T" --model tiny < /dev/null
  [ "$(_class)" = "standard" ]
  run bash "$HOOK" --root "$T" --model anthropic:claude-sonnet-4-5-20250929 < /dev/null
  [ "$(_class)" = "standard" ]
}

@test "CC-4 the hook payload's .model on stdin is honoured when no --model is given" {
  run bash -c "printf '%s' '{\"session_id\":\"s\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\",\"model\":\"claude-haiku-4-5-20251001\"}' | bash '$HOOK' --root '$T'"
  [ "$status" -eq 0 ]; [ "$(_class)" = "standard" ]; [ "$(_basis)" = "model" ]
  run bash -c "printf '%s' '{\"session_id\":\"s\",\"source\":\"startup\"}' | bash '$HOOK' --root '$T'"
  [ "$(_class)" = "long" ]; [ "$(_basis)" = "default" ]
}

@test "CC-5 an unknown model, malformed stdin or a missing catalog all fall back to long, exit 0" {
  run bash "$HOOK" --root "$T" --model not-a-model < /dev/null
  [ "$status" -eq 0 ]; [ "$(_class)" = "long" ]; [ "$(_basis)" = "default" ]
  run bash -c "printf 'not json' | bash '$HOOK' --root '$T'"
  [ "$status" -eq 0 ]; [ "$(_class)" = "long" ]
  run bash "$HOOK" --root "$T" --model claude-haiku-4-5-20251001 --catalog "$T/absent.yaml" < /dev/null
  [ "$status" -eq 0 ]; [ "$(_class)" = "long" ]
}

@test "CC-6 --line prints the /loa line and --json the record; the model id in the payload is sanitised" {
  run bash "$HOOK" --root "$T" --line < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == "Context: long (default; thresholds 20K/50K/30K/150K"* ]]
  LOA_CONTEXT_CLASS=standard run bash "$HOOK" --root "$T" --line < /dev/null
  [[ "$output" == "Context: standard (env; thresholds 2K/5K/3K/15K)" ]]
  run bash "$HOOK" --root "$T" --json --model claude-opus-5 < /dev/null
  echo "$output" | jq -e '.class == "long" and .basis == "model" and .model == "claude-opus-5" and .context_window == 1000000' >/dev/null
  # shell metacharacters never reach yq or the record: the id is stripped to its safe characters (and then resolves to nothing)
  run bash "$HOOK" --root "$T" --json --model 'claude-opus-5;rm -rf x' < /dev/null
  echo "$output" | jq -e '.class == "long" and .basis == "default" and .model == "claude-opus-5rm-rfx" and .context_window == null' >/dev/null
  ! grep -q ';' "$T/.run/context-class"
}

@test "CC-7 --show prints the recorded class without recomputing or rewriting; with no record it computes like --line" {
  run bash "$HOOK" --root "$T" --model claude-haiku-4-5-20251001 < /dev/null
  [ "$(_class)" = "standard" ]
  local before; before=$(stat -c %Y "$T/.run/context-class" 2>/dev/null || stat -f %m "$T/.run/context-class")
  sleep 1
  run bash "$HOOK" --root "$T" --show < /dev/null          # no --model, no env: a recompute would say long
  [ "$status" -eq 0 ]
  [[ "$output" == "Context: standard (model, claude-haiku-4-5-20251001; thresholds 2K/5K/3K/15K)" ]]
  [ "$(_class)" = "standard" ]
  local after; after=$(stat -c %Y "$T/.run/context-class" 2>/dev/null || stat -f %m "$T/.run/context-class")
  [ "$before" = "$after" ]
  rm -f "$T/.run/context-class"
  run bash "$HOOK" --root "$T" --show < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == "Context: long (default; thresholds 20K/50K/30K/150K"* ]]
  [ "$(_class)" = "long" ]
}

@test "CC-8 hook wiring: present in both settings files, behind hook-guard.sh (re-fires are handled by the hook, CC-17)" {
  for f in "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/hooks/settings.hooks.json"; do
    jq -e '[.hooks.SessionStart[].hooks[] | select(.command | test("hook-guard.sh.*loa-context-class.sh"))] | length == 1' "$f" >/dev/null
    jq -e '.hooks.SessionStart[].hooks[] | select(.command | test("loa-context-class.sh")) | .once == true' "$f" >/dev/null
  done
  [ -x "$HOOK" ]
}

@test "CC-9 the protocol shows both classes, the include cites the rule, /loa prints the recorded class" {
  local p="$PROJECT_ROOT/.claude/protocols/tool-result-clearing.md" inc="$PROJECT_ROOT/.claude/data/skill-includes/context_discipline.md"
  grep -q '| Context Type | `standard` (≤ 200K) | `long` (≥ 1M, default) | Action |' "$p"
  grep -q 'LOA_CONTEXT_CLASS=standard' "$p"
  grep -q '.run/context-class' "$inc"; grep -qF '`.claude/protocols/tool-result-clearing.md`' "$inc"   # the full path, so protocol-refs-resolve sees it
  grep -q 'long 20K/50K/30K/150K, standard 2K/5K/3K/15K' "$inc"
  local fn; fn="$(sed -n '/^display_context_line() {/,/^}/p' "$PROJECT_ROOT/.claude/scripts/loa-status.sh")"
  [ -n "$fn" ]
  grep -A1 '^      display_run_line$' "$PROJECT_ROOT/.claude/scripts/loa-status.sh" | grep -q 'display_context_line'
  mkdir -p "$T/.run"; printf 'standard\nbasis=env model=null context_window=null ts=x\n' > "$T/.run/context-class"
  run bash -c "cd '$T' && SCRIPT_DIR='$PROJECT_ROOT/.claude/scripts'; $fn
display_context_line"
  [ "$status" -eq 0 ]
  [ "$output" = "  Context: standard (env; thresholds 2K/5K/3K/15K)" ]
}

@test "CC-10 a value flag given last (--model, --catalog, --root) never blocks: exit 0, class long" {
  local f
  for f in --model --catalog; do
    rm -f "$T/.run/context-class"
    run timeout 5 bash "$HOOK" --root "$T" "$f" < /dev/null
    [ "$status" -eq 0 ]; [ "$(_class)" = "long" ]
  done
  rm -f "$T/.run/context-class"
  run bash -c "cd '$T' && timeout 5 bash '$HOOK' --root < /dev/null"   # outside a repo the root is the cwd
  [ "$status" -eq 0 ]; [ "$(_class)" = "long" ]
}

@test "CC-11 without a timeout binary on PATH the payload's .model is still read (Haiku 4.5 → standard)" {
  local stub="$T/stub-bin" b bashbin
  mkdir -p "$stub"
  for b in bash cat jq yq git sed tr grep cut mkdir mktemp mv rm date dirname head; do
    command -v "$b" >/dev/null 2>&1 && ln -s "$(command -v "$b")" "$stub/$b"
  done
  [ ! -e "$stub/timeout" ] && [ ! -e "$stub/gtimeout" ]
  bashbin="$(command -v bash)"
  run env PATH="$stub" "$bashbin" -c "printf '%s' '{\"model\":\"claude-haiku-4-5-20251001\"}' | '$bashbin' '$HOOK' --root '$T' --line"
  [ "$status" -eq 0 ]
  [ "$output" = "Context: standard (model, claude-haiku-4-5-20251001; thresholds 2K/5K/3K/15K)" ]
  [ "$(_class)" = "standard" ]; [ "$(_basis)" = "model" ]
}

@test "CC-13 without a timeout binary an open stdin that never closes does not block the hook" {
  local stub="$T/stub-bin" b bashbin
  mkdir -p "$stub"
  for b in bash cat jq yq git sed tr grep cut mkdir mktemp mv rm date dirname head sleep; do
    command -v "$b" >/dev/null 2>&1 && ln -s "$(command -v "$b")" "$stub/$b"
  done
  bashbin="$(command -v bash)"
  run timeout 15 env PATH="$stub" "$bashbin" -c "'$bashbin' '$HOOK' --root '$T' --line < <(sleep 30)"
  [ "$status" -eq 0 ]
  [[ "$output" == "Context: long (default"* ]]
}

@test "CC-12 no unqualified single-search threshold (a bare 2000) survives in the protocols or the retrieval guides" {
  run grep -rnE 'tokens_estimated > 2000|>2000 tokens|> 2000 tokens' \
    "$PROJECT_ROOT/.claude/protocols" "$PROJECT_ROOT/.claude/skills"/*/context-retrieval.md "$PROJECT_ROOT/.claude/skills"/*/impact-analysis.md
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "CC-14 an alias target read back from the catalog is sanitised before the second lookup (no yq breakout)" {
  cat > "$T/cat.yaml" <<'YAML'
aliases:
  evil: 'anthropic:zz"] | {"q": {"context_window": 150000}} | [."q'
providers:
  anthropic:
    models:
      big: {context_window: 1000000}
YAML
  run bash "$HOOK" --root "$T" --catalog "$T/cat.yaml" --model evil --line < /dev/null
  [ "$status" -eq 0 ]
  [ "$(_class)" = "long" ]; [ "$(_basis)" = "default" ]
}

@test "CC-15 LOA_CONTEXT_CLASS is read case-insensitively (Standard, LONG)" {
  LOA_CONTEXT_CLASS=Standard run bash "$HOOK" --root "$T" < /dev/null
  [ "$status" -eq 0 ]; [ "$(_class)" = "standard" ]; [ "$(_basis)" = "env" ]
  LOA_CONTEXT_CLASS=LONG run bash "$HOOK" --root "$T" --model claude-haiku-4-5-20251001 < /dev/null
  [ "$(_class)" = "long" ]; [ "$(_basis)" = "env" ]
}

@test "CC-16 Bedrock-shaped ids resolve: region prefix, anthropic. vendor prefix and the -vN:M suffix are stripped" {
  run bash "$HOOK" --root "$T" --model global.anthropic.claude-haiku-4-5-20251001-v1:0 < /dev/null
  [ "$status" -eq 0 ]; [ "$(_class)" = "standard" ]; [ "$(_basis)" = "model" ]
  run bash "$HOOK" --root "$T" --model anthropic.claude-haiku-4-5-20251001-v1:0 < /dev/null
  [ "$(_class)" = "standard" ]; [ "$(_basis)" = "model" ]
  run bash "$HOOK" --root "$T" --model eu.anthropic.claude-opus-5 < /dev/null
  [ "$(_class)" = "long" ]; [ "$(_basis)" = "model" ]
}

@test "CC-17 a clear/compact/resume re-fire with no model keeps a recorded model or env class; startup does not" {
  local src
  for src in clear compact resume; do
    run bash "$HOOK" --root "$T" --model claude-haiku-4-5-20251001 < /dev/null
    [ "$(_class)" = "standard" ]
    run bash -c "printf '%s' '{\"session_id\":\"s\",\"source\":\"$src\"}' | bash '$HOOK' --root '$T'"
    [ "$status" -eq 0 ]; [ "$(_class)" = "standard" ] || { echo "source=$src overwrote the record"; false; }
    [ "$(_basis)" = "model" ]
  done
  run bash -c "printf '%s' '{\"session_id\":\"s\",\"source\":\"startup\"}' | bash '$HOOK' --root '$T'"
  [ "$(_class)" = "long" ]; [ "$(_basis)" = "default" ]
}
