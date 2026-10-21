#!/usr/bin/env bats
# =============================================================================
# tests/unit/profile-floor.bats — cycle-129 sprint-256 Task 2.7 (AC-2.9; PRD
# AC-9.2; SDD D-9.2, DEC-0166)
#
# No profile can reach the floor. The floor source is .claude/data/floor.yaml
# (read here, never duplicated); its sha256 pin is READ from
# tests/unit/guard-origins.bats (FLOOR_SHA256) so the two suites cannot
# disagree. Under `lean` every floor surface reads byte-identically to
# `standard`: the floor config keys (the two gate skills' flatline_protocol.*
# config, destructive_command_guard.*, implement_gate.*, hounfour.locality),
# verdict-derive.sh on fixture feedback files, the adversarial gate's
# decision and environment, the deny-list file, the fence on the corpus and
# the FR-1.2b / FR-SZ probes, and user-invoked-commands.txt.
# =============================================================================

bats_require_minimum_version 1.5.0

setup() {
    R="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LIB="$R/.claude/scripts/lib/profile-lib.sh"
    PROFILES="$R/.claude/data/profiles.yaml"
    FLOOR="$R/.claude/data/floor.yaml"
    T="$BATS_TEST_TMPDIR"
    # Two configs that differ ONLY in loa.profile: this repository's own config
    # (which carries the floor keys it really uses) with the profile set.
    for p in lean standard; do
        cp "$R/.loa.config.yaml" "$T/$p.yaml"
        yq -i ".loa.profile = \"$p\"" "$T/$p.yaml"
    done
    unset LOA_PROFILE_CONFIG_FILE LOA_PROFILE_CACHE_FILE LOA_PROFILES_FILE
}

# The floor key patterns, as the lib and the guard register read them.
floor_keys() { yq -r '.floor_keys[]' "$FLOOR"; }

@test "PF-1 floor.yaml matches the sha256 pin guard-origins.bats carries (one constant, two suites)" {
    local pin actual
    pin=$(sed -n 's/^FLOOR_SHA256="\([0-9a-f]\{64\}\)"$/\1/p' "$R/tests/unit/guard-origins.bats")
    [ -n "$pin" ] || { echo "no FLOOR_SHA256 in guard-origins.bats"; return 1; }
    actual=$(bash -c 'source "$1/.claude/scripts/compat-lib.sh"; sha256_portable "$2"' _ "$R" "$FLOOR" | cut -d' ' -f1)
    [ "$actual" = "$pin" ] || { echo "floor.yaml sha256 $actual != pinned $pin"; return 1; }
}

@test "PF-2 no profiles.yaml key matches a floor key or is an ancestor of one" {
    run python3 -I - "$PROFILES" "$FLOOR" <<'PY'
import re, subprocess, sys, json
def load(p):
    return json.loads(subprocess.check_output(["yq", "-o=json", ".", p]))
prof, floor = load(sys.argv[1]), load(sys.argv[2])
keys = sorted({k for v in prof["profiles"].values() for k in v})
assert len(keys) == 9, keys
bad = []
for k in keys:
    for f in floor["floor_keys"]:
        rx = "^" + ".+".join(re.escape(s) for s in f.split("*")) + "$"
        if re.match(rx, k) or f.split("*")[0].startswith(k + "."):
            bad.append((k, f))
print("violations:", bad)
sys.exit(1 if bad else 0)
PY
    echo "$output"
    [ "$status" -eq 0 ]
    # floor_keys_forbidden is not duplicated into profiles.yaml.
    [ "$(yq -r 'has("floor_keys_forbidden")' "$PROFILES")" = "false" ]
}

@test "PF-3 under lean the resolved document names no floor key and every floor key reads as under standard" {
    local p k
    for p in lean standard; do
        LOA_PROFILE_CONFIG_FILE="$T/$p.yaml" bash "$LIB" json > "$T/$p.json"
        [ "$(jq -r '.profile' "$T/$p.json")" = "$p" ]
    done
    # Concrete floor keys: every leaf path of this config and the example that a
    # floor pattern matches (flatline_protocol.*.companion_voice expands here).
    yq -o=json '.' "$R/.loa.config.yaml" > "$T/cfg.json"
    yq -o=json '.' "$R/.loa.config.yaml.example" > "$T/ex.json"
    floor_keys > "$T/floor.txt"
    python3 -I - "$T/cfg.json" "$T/ex.json" "$T/floor.txt" > "$T/concrete.txt" <<'PY'
import json, re, sys
pats = [l.strip() for l in open(sys.argv[3]) if l.strip()]
rxs = ["^" + ".+".join(re.escape(s) for s in p.split("*")) + "$" for p in pats]
out = set(p for p in pats if "*" not in p)
def walk(x, path):
    if isinstance(x, dict):
        for k, v in x.items():
            walk(v, path + [str(k)])
    if path:
        key = ".".join(path)
        if any(re.match(r, key) for r in rxs):
            out.add(key)
for f in sys.argv[1:3]:
    walk(json.load(open(f)), [])
print("\n".join(sorted(k for k in out if re.fullmatch(r"[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*", k))))
PY
    grep -qx 'flatline_protocol.code_review.enabled' "$T/concrete.txt"
    grep -qx 'flatline_protocol.security_audit.enabled' "$T/concrete.txt"
    grep -q '^flatline_protocol\.[a-z_]*\.companion_voice$' "$T/concrete.txt"
    while IFS= read -r k; do
        [ "$(jq -r --arg k "$k" '.knobs | has($k)' "$T/lean.json")" = "false" ] || { echo "lean resolves floor key $k"; return 1; }
        a=$(LOA_PROFILE_CONFIG_FILE="$T/lean.yaml" bash "$LIB" knob "$k" __unset__ 2>/dev/null)
        b=$(LOA_PROFILE_CONFIG_FILE="$T/standard.yaml" bash "$LIB" knob "$k" __unset__ 2>/dev/null)
        [ "$a" = "$b" ] || { echo "$k: lean=$a standard=$b"; return 1; }
    done < "$T/concrete.txt"
    # The two gate skills' whole flatline_protocol config is byte-identical.
    for g in code_review security_audit; do
        cmp <(yq -o=json ".flatline_protocol.$g" "$T/lean.yaml") <(yq -o=json ".flatline_protocol.$g" "$T/standard.yaml")
    done
}

@test "PF-4 verdict-derive.sh output is byte-identical under lean and standard" {
    local f p
    printf 'All good\n\n## Observations\n\n- **LOW** `a.sh:1` — naming\n\n<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":1},"sprint_id":"sprint-9","ts":"2026-10-14T00:00:00Z"} -->\n' > "$T/ok.md"
    printf '## Changes Required\n\n- **HIGH** `a.sh:1` — unchecked input\n\nAll good\n\n<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":1,"medium":0,"low":0},"sprint_id":"sprint-9","ts":"2026-10-14T00:00:00Z"} -->\n' > "$T/bad.md"
    for f in ok bad; do
        for p in lean standard; do
            rc=0
            LOA_PROFILE_CONFIG_FILE="$T/$p.yaml" bash "$R/.claude/scripts/verdict-derive.sh" --file "$T/$f.md" --gate review --json \
                > "$T/vd-$f-$p.out" 2>&1 || rc=$?
            echo "$rc" >> "$T/vd-$f-$p.out"
        done
        cmp "$T/vd-$f-lean.out" "$T/vd-$f-standard.out"
    done
    # The fixtures exercise both outcomes, so identity is not vacuous.
    ! cmp -s "$T/vd-ok-lean.out" "$T/vd-bad-lean.out"
}

@test "PF-5 the adversarial-review gate decides identically under lean and standard" {
    local d="$T/grimoires/loa/a2a/sprint-999" p rc
    mkdir -p "$d"
    for p in lean standard; do
        yq -i '.flatline_protocol.code_review.enabled = true' "$T/$p.yaml"
        rc=0
        printf '{"tool_name":"Write","tool_input":{"file_path":"%s/COMPLETED"}}' "$d" \
            | env -u LOA_ADVERSARIAL_REVIEW_ENFORCE LOA_PROFILE_CONFIG_FILE="$T/$p.yaml" LOA_CONFIG_PATH_OVERRIDE="$T/$p.yaml" \
              bash "$R/.claude/hooks/safety/adversarial-review-gate.sh" > "$T/gate-$p.out" 2>&1 || rc=$?
        echo "$rc" >> "$T/gate-$p.out"
    done
    cmp "$T/gate-lean.out" "$T/gate-standard.out"
    # No dissent envelope for an enabled gate: the gate refuses (exit 2) under both.
    [ "$(tail -1 "$T/gate-lean.out")" = "2" ]
    # The gate's environment knob is not a profile key and the gate never sources the lib.
    ! grep -q 'profile-lib' "$R/.claude/hooks/safety/adversarial-review-gate.sh"
    ! yq -r '.profiles[] | keys | .[]' "$PROFILES" | grep -qi 'adversarial'
}

@test "PF-6 the fence decides every corpus row and the FR-1.2b / FR-SZ probes identically under lean and standard" {
    local p row cmd rc id
    jq -r '.id' "$R/tests/fixtures/fence-corpus/corpus.jsonl" > /dev/null
    # Floor probes (the corpus carries the floor rules named in floor.yaml floor_corpus when they exist).
    printf '%s\n' \
        '{"id":"FP-1","cmd":"git stash pop 2>/dev/null"}' \
        '{"id":"FP-2","cmd":"git stash push -m x | tail -1"}' \
        '{"id":"FP-3","cmd":"echo x > .claude/hooks/evil.sh"}' \
        '{"id":"FP-4","cmd":"cp /tmp/a .claude/settings.json"}' \
        '{"id":"FP-5","cmd":"sed -i s/a/b/ .claude/scripts/verdict-derive.sh"}' > "$T/probes.jsonl"
    cat "$R/tests/fixtures/fence-corpus/corpus.jsonl" "$T/probes.jsonl" > "$T/all.jsonl"
    for p in lean standard; do
        mkdir -p "$T/root-$p/repo"
        cp "$T/$p.yaml" "$T/root-$p/.loa.config.yaml"
        : > "$T/fence-$p.txt"
        while IFS= read -r row; do
            [ -n "$row" ] || continue
            id=$(jq -r '.id' <<<"$row"); cmd=$(jq -r '.cmd' <<<"$row")
            rc=0
            (cd "$T/root-$p/repo" && jq -cn --arg c "$cmd" '{tool_input: {command: $c}}' \
                | env -u TMPDIR LOA_AUDIT_REPLAY=1 LOA_REPO_ROOT="$T/root-$p" LOA_PROFILE_CONFIG_FILE="$T/$p.yaml" \
                  bash "$R/.claude/hooks/safety/block-destructive-bash.sh" >/dev/null 2>&1) || rc=$?
            echo "$id $rc" >> "$T/fence-$p.txt"
        done < "$T/all.jsonl"
    done
    cmp "$T/fence-lean.txt" "$T/fence-standard.txt"
    for id in FP-1 FP-2 FP-3 FP-4 FP-5; do
        grep -qx "$id 2" "$T/fence-lean.txt" || { echo "$id not blocked under lean: $(grep "^$id " "$T/fence-lean.txt")"; return 1; }
    done
    # Every floor_corpus row present in the corpus is in the compared set.
    while IFS= read -r rule; do
        jq -r --arg r "$rule" 'select(.rule == $r or (($r | endswith("*")) and (.rule | startswith($r | rtrimstr("*"))))) | .id' \
            "$R/tests/fixtures/fence-corpus/corpus.jsonl" | while IFS= read -r id; do
            grep -q "^$id " "$T/fence-lean.txt"
        done
    done < <(yq -r '.floor_corpus.rules[]' "$FLOOR")
}

@test "PF-7 the deny list, the System-Zone rules and user-invoked-commands.txt are untouched by resolving any profile" {
    local f before after p
    for f in .claude/hooks/settings.deny.json .claude/data/user-invoked-commands.txt .claude/rules/zone-system.md .claude/data/floor.yaml; do
        before=$(bash -c 'source "$1/.claude/scripts/compat-lib.sh"; sha256_portable "$1/$2"' _ "$R" "$f" | cut -d' ' -f1)
        for p in lean standard; do
            LOA_PROFILE_CONFIG_FILE="$T/$p.yaml" LOA_PROFILE_CACHE_FILE="$T/cache-$p.json" bash "$LIB" json >/dev/null
        done
        after=$(bash -c 'source "$1/.claude/scripts/compat-lib.sh"; sha256_portable "$1/$2"' _ "$R" "$f" | cut -d' ' -f1)
        [ "$before" = "$after" ]
    done
    # The lib reads exactly three inputs and writes only its cache.
    ! grep -Eq 'settings\.deny|user-invoked-commands|zone-system' "$LIB"
    # The resolved documents differ only in the profile name and the profile-sourced values.
    [ "$(jq -r '.profile' "$T/cache-lean.json")" = "lean" ]
    [ "$(jq -c '.profile_keys' "$T/cache-lean.json")" = "$(jq -c '.profile_keys' "$T/cache-standard.json")" ]
}
