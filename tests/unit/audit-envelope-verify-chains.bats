#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# tests/unit/audit-envelope-verify-chains.bats — cycle-137 FR-7 (bd-09z1i, SDD § 5.7)
#
# `audit-envelope.sh verify-chains [--verify-for-merge] <path>…`: one Python
# process calls the unchanged `audit_verify_chain` per path (each in its own
# try/except) and prints one JSON record per input path in argument order,
# {"i", "path", "ok", "error"}; exit 0 all ok, 1 any not ok, 2 usage/import.
# The wrapper is fail-closed (exactly one valid record per index, otherwise a
# FAILED record). `loa-status.sh` `_an_audit_chain_summary()` makes ONE such
# call and reproduces the per-call `valid` count by index.
# cycle-138 FR-3 (bd-hyah6, SDD § 5.3, DEC-1171): `_an_audit_chain_classify()`
# puts every primitive in exactly one state (valid / absent / broken / n/a); an
# absent chain file no longer counts as valid. The displayed V/7 is
# valid + n/a (V + A + B == 7); the JSON `valid` excludes the two n/a.
#
# Expected texts are stated here independently of the implementation.
# Fixtures: a root-signed trust store (writer w1, cutoff 2020), a tampered
# copy (rogue key appended, not re-signed), and signed chains.
# =============================================================================

setup_file() {
  python3 -c "import cryptography, rfc8785, yaml" 2>/dev/null || return 0
  local repo; repo="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export VCF="$BATS_FILE_TMPDIR/fx"
  python3 - "$VCF" "$repo" <<'PY'
import base64, json, shutil, sys
from pathlib import Path
out, repo = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(repo / ".claude/adapters"))
import rfc8785, yaml
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from loa_cheval import audit_envelope as audit

def pem(k):
    return k.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode()

root, writer, rogue = (Ed25519PrivateKey.generate() for _ in range(3))
(out / "keys").mkdir(parents=True)
(out / "keys/root.pub").write_text(pem(root))
core = {"schema_version": "1.0", "keys": [{"writer_id": "w1", "pubkey_pem": pem(writer)}],
        "revocations": [], "trust_cutoff": {"default_strict_after": "2020-01-01T00:00:00Z"}}
good = {**core, "root_signature": {"algorithm": "ed25519", "signer_pubkey": pem(root),
        "signed_at": "2020-01-01T00:00:00Z",
        "signature": base64.b64encode(root.sign(rfc8785.dumps(core))).decode()}}
(out / "store.yaml").write_text(yaml.safe_dump(good))
bad = json.loads(json.dumps(good))
bad["keys"].append({"writer_id": "rogue", "pubkey_pem": pem(rogue)})
(out / "store-tampered.yaml").write_text(yaml.safe_dump(bad))

def chain(tag):
    prev, lines = "GENESIS", []
    for k in range(3):
        env = {"schema_version": "1.1.0", "primitive_id": "L1", "event_type": "test.event",
               "ts_utc": f"2024-01-01T00:00:0{k}.000000Z", "prev_hash": prev,
               "payload": {"n": k, "tag": tag}, "redaction_applied": None, "signing_key_id": "w1"}
        env["signature"] = base64.b64encode(writer.sign(audit._chain_input_bytes(env))).decode()
        lines.append(json.dumps(env, separators=(",", ":")))
        prev = audit._sha256_hex(audit._chain_input_bytes(env))
    return lines

c = out / "chains"; c.mkdir()
for i in range(1, 6):
    (c / f"valid-{i}.jsonl").write_text("\n".join(chain(f"v{i}")) + "\n")
t = chain("t"); t[1] = t[1].replace('"tag":"t"', '"tag":"u"', 1)          # one byte flipped in entry 2
(c / "tampered.jsonl").write_text("\n".join(t) + "\n")
b = chain("b"); e = json.loads(b[2]); e["prev_hash"] = "0" * 64           # entry 3 link edited
b[2] = json.dumps(e, separators=(",", ":"))
(c / "broken.jsonl").write_text("\n".join(b) + "\n")
(c / "empty.jsonl").write_text("")
slots = [".run/panel-decisions.jsonl", ".run/cost-budget-events.jsonl", ".run/cycles.jsonl",
         "grimoires/loa/trust-ledger.jsonl", "grimoires/loa/handoffs/INDEX.md"]
for name, nvalid in (("r0", 0), ("r3", 3), ("r5", 5)):
    for k, slot in enumerate(slots):
        dst = out / "roots" / name / slot; dst.parent.mkdir(parents=True, exist_ok=True)
        src = c / (f"valid-{k + 1}.jsonl" if k < nvalid else ("tampered.jsonl" if k % 2 else "broken.jsonl"))
        shutil.copyfile(src, dst)
shutil.copytree(out / "roots/r3", out / "roots/r3-partial")
(out / "roots/r3-partial/.run/cycles.jsonl").unlink()
(out / "roots/r3-partial/grimoires/loa/trust-ledger.jsonl").unlink()
(out / "roots/none").mkdir()
PY
}

setup() {
  python3 -c "import cryptography, rfc8785, yaml" 2>/dev/null || skip "python cryptography/rfc8785/yaml not installed"
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  AE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
  STATUS="$PROJECT_ROOT/.claude/scripts/loa-status.sh"
  C="$VCF/chains"
  W="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/vc.XXXXXX")"
  # Hermetic verifier environment: the fixture store and pin, no ambient overrides.
  unset LOA_AUDIT_STRICT_VERIFY LOA_AUDIT_VERIFY_SIGS LOA_AUDIT_SIGNING_KEY_ID LOA_AUDIT_KEY_DIR
  export LOA_TRUST_STORE_FILE="$VCF/store.yaml"
  export LOA_PINNED_ROOT_PUBKEY_PATH="$VCF/keys/root.pub"
}

teardown() {
  [[ -n "${W:-}" && -d "$W" ]] || return 0
  chmod -R u+w "$W" 2>/dev/null || true
  find "$W" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$W" 2>/dev/null || true
}

# The expected fixture texts (stated independently of the implementation).
TAMPERED_ERR='BROKEN line 2: signature verification failed for signing_key_id=w1'
BROKEN_PREFIX='BROKEN line 3: prev_hash mismatch (got 0000000000000000000000000000000000000000000000000000000000000000, expected '
STORE_INVALID='[TRUST-STORE-INVALID] trust-store root_signature does NOT verify against pinned root pubkey; refusing all writes/reads (issue #690)'

# _an <fn> <root> [script] — run ONLY the `_an_audit_chain_*` functions of
# loa-status.sh against <root> and call <fn> (AUDIT_ENVELOPE_SCRIPT defaults to
# the repository's own audit-envelope.sh). `human` renders the Audit chain lines
# from one classification.
_an() {
  local fn="$1" root="$2" script="${3:-$AE}"
  bash -c 'set -euo pipefail; source <(sed -n "/^_an_audit_chain_[a-z_]*() {\$/,/^}\$/p" "$1")
           PROJECT_ROOT="$2"; AUDIT_ENVELOPE_SCRIPT="$3"
           if [[ "$4" == human ]]; then _an_audit_chain_human "$(_an_audit_chain_classify)"; else "_an_audit_chain_$4"; fi' \
    _ "$STATUS" "$root" "$script" "$fn"
}
_summary() { _an summary "$@"; }
_classify() { _an classify "$@"; }
_human() { _an human "$@"; }

# _states <root> [script] — the state column of the classification, space-joined (L1 … L7).
_states() {
  local out id p st acc=""
  out="$(_classify "$@")" || return 1
  while read -r id p st; do acc="${acc:+$acc }$st"; done <<<"$out"
  echo "$acc"
}

# _invariants <classification> <summary> — exactly seven lines L1 … L7 (L5/L7
# path "-" and n/a; every other path its chain slot), every state in the set,
# and the displayed V = valid + n/a with V + A + B == 7 (DEC-1171).
_invariants() {
  local cls="$1" sum="$2" id p st n=0 v=0 a=0 b=0 na=0 want
  local ids=(L1 L2 L3 L4 L5 L6 L7)
  local slots=(.run/panel-decisions.jsonl .run/cost-budget-events.jsonl .run/cycles.jsonl
               grimoires/loa/trust-ledger.jsonl - grimoires/loa/handoffs/INDEX.md -)
  while read -r id p st; do
    [ "$id" = "${ids[$n]}" ] || { echo "line $n id $id" >&2; return 1; }
    [ "$p" = "${slots[$n]}" ] || { echo "line $n path $p" >&2; return 1; }
    case "$st" in
      valid) v=$((v + 1)) ;; absent) a=$((a + 1)) ;; broken) b=$((b + 1)) ;; n/a) na=$((na + 1)) ;;
      *) echo "line $n state $st" >&2; return 1 ;;
    esac
    if [[ "$p" == - ]]; then [ "$st" = n/a ] || return 1; else [ "$st" != n/a ] || return 1; fi
    n=$((n + 1))
  done <<<"$cls"
  # Every check returns explicitly: the function is called in `||` context, where errexit is
  # suspended and only the LAST command's status would otherwise count (Sprint 284 review, DISS-C-001).
  [ "$n" -eq 7 ] || { echo "lines $n (want 7)" >&2; return 1; }
  [ "$na" -eq 2 ] || { echo "n/a $na (want 2)" >&2; return 1; }
  [ $((v + a + b + na)) -eq 7 ] || { echo "valid+absent+broken+n/a = $((v + a + b + na)) (want 7)" >&2; return 1; }   # JSON counts: valid excludes n/a
  [ "$sum" = "$((v + na))/7" ] || { echo "summary $sum (want $((v + na))/7)" >&2; return 1; }                    # displayed V adds n/a back
  [ $((v + na + a + b)) -eq 7 ] || { echo "V+A+B = $((v + na + a + b)) (want 7)" >&2; return 1; }              # V + A + B == 7
  return 0
}

# _oracle <root> — the FR-3 classification, independently: one singular
# `verify-chain` per existing chain file, missing files count ABSENT (not valid),
# +2 for L5/L7 (n/a, added back for the displayed count).
_oracle() {
  local root="$1" valid=2 p
  for p in .run/panel-decisions.jsonl .run/cost-budget-events.jsonl .run/cycles.jsonl \
           grimoires/loa/trust-ledger.jsonl grimoires/loa/handoffs/INDEX.md; do
    if [[ -f "$root/$p" ]]; then
      bash "$AE" verify-chain "$root/$p" >/dev/null 2>&1 && valid=$((valid + 1))
    fi
  done
  echo "${valid}/7"
}

# _py3_lines <trace-file> — `python3` command lines in a PS4='+' xtrace.
_py3_lines() { grep -cE '^\++ ?python3( |$)' "$1" || true; }

@test "VC-1 valid / tampered / broken-link / missing / empty → one record per path in order, exit 1" {
  run bash "$AE" verify-chains "$C/valid-1.jsonl" "$C/tampered.jsonl" "$C/broken.jsonl" "$W/missing.jsonl" "$C/empty.jsonl"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 5 ]
  printf '%s\n' "$output" | jq -se --arg c "$C" --arg w "$W" --arg t "$TAMPERED_ERR" --arg b "$BROKEN_PREFIX" '
    length == 5
    and ([.[].i] == [0, 1, 2, 3, 4])
    and ([.[].path] == [$c + "/valid-1.jsonl", $c + "/tampered.jsonl", $c + "/broken.jsonl", $w + "/missing.jsonl", $c + "/empty.jsonl"])
    and ([.[].ok] == [true, false, false, false, true])
    and .[0].error == null and .[4].error == null
    and .[1].error == $t
    and (.[2].error | startswith($b))
    and .[3].error == "missing"' >/dev/null
}

@test "VC-2 all valid → exit 0, every record ok with a null error" {
  run bash "$AE" verify-chains "$C/valid-1.jsonl" "$C/valid-2.jsonl" "$C/valid-3.jsonl"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -se 'length == 3 and all(.[]; .ok == true and .error == null) and ([.[].i] == [0, 1, 2])' >/dev/null
}

@test "VC-3 zero paths → exit 2 with a usage line on stderr and nothing on stdout" {
  run --separate-stderr bash "$AE" verify-chains
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"Usage: audit-envelope.sh verify-chains [--verify-for-merge] <log_path>..."* ]]
  run --separate-stderr bash "$AE" verify-chains --verify-for-merge
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"Usage: audit-envelope.sh verify-chains"* ]]
}

@test "VC-4 paths with spaces, colons, a newline and a leading dash round-trip exactly" {
  mkdir -p "$W/dir with space:colon"
  local p1="$W/dir with space:colon/a b:c.jsonl" p2="$W/dir with space:colon/line"$'\n'"break.jsonl" p3="$W/-dash.jsonl"
  cp "$C/valid-1.jsonl" "$p1"; cp "$C/tampered.jsonl" "$p2"; cp "$C/valid-2.jsonl" "$p3"
  run bash "$AE" verify-chains "$p1" "$p2" "$p3"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 3 ]
  printf '%s\n' "$output" | jq -se --arg p1 "$p1" --arg p2 "$p2" --arg p3 "$p3" --arg t "$TAMPERED_ERR" '
    [.[].path] == [$p1, $p2, $p3] and [.[].ok] == [true, false, true] and .[1].error == $t' >/dev/null
}

@test "VC-5 the same path twice → two records" {
  run bash "$AE" verify-chains "$C/valid-1.jsonl" "$C/valid-1.jsonl"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -se --arg p "$C/valid-1.jsonl" '
    length == 2 and [.[].i] == [0, 1] and all(.[]; .path == $p and .ok == true)' >/dev/null
}

@test "VC-6 a read-only chain tree is not mutated (sha256 and file list identical before and after)" {
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
  mkdir -p "$W/ro"; cp "$C"/*.jsonl "$W/ro/"
  chmod -R a-w "$W/ro"
  local before after f
  before="$(for f in "$W/ro"/*; do printf '%s %s\n' "$(sha256_portable "$f")" "$f"; done; ls -la "$W/ro" | wc -l)"
  run bash "$AE" verify-chains "$W/ro"/*.jsonl
  [ "$status" -eq 1 ]                          # tampered + broken are in the tree
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 8 ]
  after="$(for f in "$W/ro"/*; do printf '%s %s\n' "$(sha256_portable "$f")" "$f"; done; ls -la "$W/ro" | wc -l)"
  [ "$before" = "$after" ]
}

@test "VC-7 a tampered trust store → EVERY record ok:false with [TRUST-STORE-INVALID]" {
  export LOA_TRUST_STORE_FILE="$VCF/store-tampered.yaml"
  run bash "$AE" verify-chains "$C/valid-1.jsonl" "$C/valid-2.jsonl" "$C/empty.jsonl" "$C/broken.jsonl"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -se --arg s "$STORE_INVALID" 'length == 4 and all(.[]; .ok == false and .error == $s)' >/dev/null
}

@test "VC-8 --verify-for-merge reaches the verifier (missing store → every path [TRUST-STORE-BOOTSTRAP-PENDING])" {
  run bash "$AE" verify-chains --verify-for-merge "$C/valid-1.jsonl" "$C/valid-2.jsonl"
  [ "$status" -eq 0 ]
  export LOA_TRUST_STORE_FILE="$W/no-store.yaml"
  run bash "$AE" verify-chains --verify-for-merge "$C/valid-1.jsonl" "$C/empty.jsonl"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -se 'length == 2 and all(.[]; .ok == false and (.error | startswith("[TRUST-STORE-BOOTSTRAP-PENDING] trust-store is not signed")))' >/dev/null
  # Non-strict, the unsigned empty chain still passes under the missing store; signed history does not.
  run bash "$AE" verify-chains "$C/valid-1.jsonl" "$C/empty.jsonl"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -se '[.[].ok] == [false, true] and (.[0].error | contains("[TRUST-STORE-BOOTSTRAP-PENDING]"))' >/dev/null
}

@test "VC-9 per-path results equal the singular per-call results on every fixture chain (both modes, both stores)" {
  local store strict c rc msg rec
  for store in "$VCF/store.yaml" "$VCF/store-tampered.yaml"; do
    export LOA_TRUST_STORE_FILE="$store"
    for strict in "" "--verify-for-merge"; do
      run bash "$AE" verify-chains ${strict:+"$strict"} "$C"/*.jsonl
      local batch="$output" k=0
      for c in "$C"/*.jsonl; do
        rc=0; msg="$(bash "$AE" verify-chain ${strict:+"$strict"} "$c" 2>&1)" || rc=$?
        rec="$(printf '%s\n' "$batch" | jq -c --argjson k "$k" 'select(.i == $k)')"
        [ "$(jq -r '.path' <<<"$rec")" = "$c" ]
        if [ "$rc" -eq 0 ]; then
          [ "$(jq -r '.ok' <<<"$rec")" = "true" ]
        else
          [ "$(jq -r '.ok' <<<"$rec")" = "false" ]
          [ "$(jq -r '.error' <<<"$rec")" = "$msg" ]
        fi
        k=$((k + 1))
      done
    done
  done
}

@test "VC-10 singular verify-chain output is unchanged (stdout, stderr, exit) on the fixtures" {
  run --separate-stderr bash "$AE" verify-chain "$C/valid-1.jsonl"
  [ "$status" -eq 0 ]; [ "$output" = "OK 3 entries" ]; [ -z "$stderr" ]
  run --separate-stderr bash "$AE" verify-chain "$C/tampered.jsonl"
  [ "$status" -eq 1 ]; [ -z "$output" ]; [ "$stderr" = "$TAMPERED_ERR" ]
  run --separate-stderr bash "$AE" verify-chain "$C/empty.jsonl"
  [ "$status" -eq 0 ]; [ "$output" = "OK 0 entries" ]
  run --separate-stderr bash "$AE" verify-chain "$W/missing.jsonl"
  [ "$status" -eq 2 ]; [ -z "$output" ]; [ "$stderr" = "[audit-envelope] audit_verify_chain: file not found: $W/missing.jsonl" ]
  LOA_TRUST_STORE_FILE="$VCF/store-tampered.yaml" run --separate-stderr bash "$AE" verify-chain "$C/valid-1.jsonl"
  [ "$status" -eq 1 ]; [ "$stderr" = "$STORE_INVALID" ]
}

@test "VC-11 a per-path exception becomes that path's record and the next path still runs" {
  mkdir -p "$W/a-directory.jsonl"
  run bash "$AE" verify-chains "$W/a-directory.jsonl" "$C/valid-1.jsonl"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | jq -se --arg d "$W/a-directory.jsonl" '
    length == 2 and .[0].ok == false
    and .[0].error == ("IsADirectoryError: [Errno 21] Is a directory: \u0027" + $d + "\u0027")
    and .[1].ok == true and .[1].error == null' >/dev/null
}

@test "VC-12 an import failure → exit 2, the error on stderr, every path a FAILED record" {
  # Mirror without the Python adapter (REAL directories at the same depth).
  mkdir -p "$W/m/.claude/scripts" "$W/m/lib"
  cp "$AE" "$PROJECT_ROOT/.claude/scripts/compat-lib.sh" "$W/m/.claude/scripts/"
  cp "$PROJECT_ROOT/lib/jcs.sh" "$W/m/lib/"
  PYTHONPATH= run --separate-stderr bash "$W/m/.claude/scripts/audit-envelope.sh" verify-chains "$C/valid-1.jsonl" "$C/valid-2.jsonl"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"verify-chains: cannot import the verifier"* ]]
  printf '%s\n' "$output" | jq -se 'length == 2 and all(.[]; .ok == false and (.error | startswith("[VERIFY-CHAINS-NO-RECORD]")))' >/dev/null
}

@test "VC-13 verify-chains over five paths starts ONE python3 process" {
  local x="$W/trace" xfd
  exec {xfd}>"$x"
  env PS4='+' BASH_XTRACEFD="$xfd" SHELLOPTS=xtrace bash -x "$AE" verify-chains "$C"/valid-*.jsonl >/dev/null 2>&1 || true
  exec {xfd}>&-
  [ "$(_py3_lines "$x")" -eq 1 ]
}

@test "LS-1 _an_audit_chain_summary: N/7 equals the per-call oracle and the stated count on every fixture root (absent is not valid)" {
  local r want got
  for r in r0:2/7 r3:5/7 r5:7/7 r3-partial:4/7 none:2/7; do
    want="${r#*:}"; r="${r%%:*}"
    got="$(_summary "$VCF/roots/$r")"
    [ "$got" = "$want" ] || { echo "root $r: got $got want $want" >&2; return 1; }
    [ "$(_oracle "$VCF/roots/$r")" = "$want" ]
  done
  export LOA_TRUST_STORE_FILE="$VCF/store-tampered.yaml"
  [ "$(_summary "$VCF/roots/r5")" = "2/7" ]
  [ "$(_oracle "$VCF/roots/r5")" = "2/7" ]
}

@test "LS-2 loa-status.sh (whole script) shows the same Audit chain cell: 7/7 on r5, 2/7 (0 absent, 5 broken) with a tampered store" {
  cd "$VCF/roots/r5"
  export LOA_STATUS_CONFIG_FILE="$W/no-loa-config.yaml"
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  [[ "$output" == *"Audit chain: 7/7 primitives validate."* ]]
  LOA_TRUST_STORE_FILE="$VCF/store-tampered.yaml" run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  local block='  Audit chain: 2/7 validate (0 absent, 5 broken).
  L1 panel-decisions.jsonl: broken
  L2 cost-budget-events.jsonl: broken
  L3 cycles.jsonl: broken
  L4 trust-ledger.jsonl: broken
  L6 INDEX.md: broken
'
  [[ "$output" == *"$block"* ]]
  [[ "$output" != *"primitives validate."* ]]
}

@test "LS-3 _an_audit_chain_summary makes ONE verifier call (python3 lines in the trace: 1, was one per chain file)" {
  local x="$W/trace" xfd
  exec {xfd}>"$x"
  env PS4='+' BASH_XTRACEFD="$xfd" SHELLOPTS=xtrace bash -c 'source <(sed -n "/^_an_audit_chain_[a-z_]*() {\$/,/^}\$/p" "$1")
    PROJECT_ROOT="$2"; AUDIT_ENVELOPE_SCRIPT="$3"; _an_audit_chain_summary' _ "$STATUS" "$VCF/roots/r5" "$AE" >"$W/out" 2>/dev/null || true
  exec {xfd}>&-
  [ "$(cat "$W/out")" = "7/7" ]
  [ "$(_py3_lines "$x")" -eq 1 ]
}

# _stub <body> — an AUDIT_ENVELOPE_SCRIPT stand-in that answers only `verify-chains`.
_stub() {
  printf '#!/usr/bin/env bash\n[[ "$1" == verify-chains ]] || exit 9\nshift\n%s\n' "$1" > "$W/stub.sh"
  chmod +x "$W/stub.sh"
  echo "$W/stub.sh"
}

@test "LS-4 fail-closed: a truncated record set counts the unrecorded paths invalid (exit 0 and exit 1)" {
  # Five existing chains; the stub reports only indices 0 and 1 as ok.
  local body='i=0; for p in "$@"; do [[ $i -lt 2 ]] && jq -nc --argjson i $i --arg p "$p" "{i:\$i,path:\$p,ok:true,error:null}"; i=$((i+1)); done; exit '
  [ "$(_summary "$VCF/roots/r5" "$(_stub "${body}0")")" = "4/7" ]
  [ "$(_summary "$VCF/roots/r5" "$(_stub "${body}1")")" = "4/7" ]
}

@test "LS-5 fail-closed: abnormal exit, unparsable output, duplicate or path-mismatched records are not counted" {
  local all='i=0; for p in "$@"; do jq -nc --argjson i $i --arg p "$p" "{i:\$i,path:\$p,ok:true,error:null}"; i=$((i+1)); done'
  [ "$(_summary "$VCF/roots/r5" "$(_stub "$all; exit 0")")" = "7/7" ]     # control: the stub protocol itself counts
  [ "$(_summary "$VCF/roots/r5" "$(_stub "$all; exit 3")")" = "2/7" ]     # abnormal exit: nothing counts
  [ "$(_summary "$VCF/roots/r5" "$(_stub "$all; echo '{not json'; exit 0")")" = "2/7" ]   # unparsable output
  [ "$(_summary "$VCF/roots/r5" "$(_stub "$all; jq -nc --arg p \"\$1\" '{i:0,path:\$p,ok:true,error:null}'; exit 0")")" = "6/7" ]  # index 0 duplicated
  local mis='i=0; for p in "$@"; do jq -nc --argjson i $i "{i:\$i,path:\"elsewhere\",ok:true,error:null}"; i=$((i+1)); done'
  [ "$(_summary "$VCF/roots/r5" "$(_stub "$mis; exit 0")")" = "2/7" ]   # every record names another path
}

# ---------------------------------------------------------------------------
# cycle-138 FR-3: per-primitive classification (valid / absent / broken / n/a)
# Expected states per root, stated from the fixture build above (slots L1 L2 L3
# L4 L6 = valid-1..5 for k < nvalid, else tampered (odd k) / broken (even k)):
#   r0          broken broken broken broken n/a broken n/a     V 2  A 0  B 5
#   r3          valid  valid  valid  broken n/a broken n/a     V 5  A 0  B 2
#   r5          valid  valid  valid  valid  n/a valid  n/a     V 7  A 0  B 0
#   r3-partial  valid  valid  absent absent n/a broken n/a     V 4  A 2  B 1
#   none        absent absent absent absent n/a absent n/a     V 2  A 5  B 0
#   r5 + tampered store: every chain broken                    V 2  A 0  B 5
# ---------------------------------------------------------------------------

@test "LS-6 _an_audit_chain_classify: one state per primitive on every fixture root, both invariants hold" {
  local r want got cls
  for r in "r0:broken broken broken broken n/a broken n/a" \
           "r3:valid valid valid broken n/a broken n/a" \
           "r5:valid valid valid valid n/a valid n/a" \
           "r3-partial:valid valid absent absent n/a broken n/a" \
           "none:absent absent absent absent n/a absent n/a"; do
    want="${r#*:}"; r="${r%%:*}"
    got="$(_states "$VCF/roots/$r")"
    [ "$got" = "$want" ] || { echo "root $r: got '$got' want '$want'" >&2; return 1; }
    cls="$(_classify "$VCF/roots/$r")"
    _invariants "$cls" "$(_summary "$VCF/roots/$r")" || { echo "root $r: invariant" >&2; return 1; }
  done
  export LOA_TRUST_STORE_FILE="$VCF/store-tampered.yaml"
  [ "$(_states "$VCF/roots/r5")" = "broken broken broken broken n/a broken n/a" ]
  _invariants "$(_classify "$VCF/roots/r5")" "2/7"
}

@test "LS-7 human lines: healthy r5 is today's exact line; none, r3-partial and a tampered store name each non-valid primitive" {
  [ "$(_human "$VCF/roots/r5")" = "  Audit chain: 7/7 primitives validate." ]
  [ "$(_human "$VCF/roots/none")" = "  Audit chain: 2/7 validate (5 absent, 0 broken).
  L1 panel-decisions.jsonl: absent
  L2 cost-budget-events.jsonl: absent
  L3 cycles.jsonl: absent
  L4 trust-ledger.jsonl: absent
  L6 INDEX.md: absent" ]
  [ "$(_human "$VCF/roots/r3-partial")" = "  Audit chain: 4/7 validate (2 absent, 1 broken).
  L3 cycles.jsonl: absent
  L4 trust-ledger.jsonl: absent
  L6 INDEX.md: broken" ]
  [ "$(_human "$VCF/roots/r0")" = "  Audit chain: 2/7 validate (0 absent, 5 broken).
  L1 panel-decisions.jsonl: broken
  L2 cost-budget-events.jsonl: broken
  L3 cycles.jsonl: broken
  L4 trust-ledger.jsonl: broken
  L6 INDEX.md: broken" ]
  LOA_TRUST_STORE_FILE="$VCF/store-tampered.yaml" run _human "$VCF/roots/r5"
  [ "$status" -eq 0 ]
  [ "$output" = "  Audit chain: 2/7 validate (0 absent, 5 broken).
  L1 panel-decisions.jsonl: broken
  L2 cost-budget-events.jsonl: broken
  L3 cycles.jsonl: broken
  L4 trust-ledger.jsonl: broken
  L6 INDEX.md: broken" ]
}

@test "LS-8 one deleted chain file → absent 1, named, never 7/7; an empty existing list makes no verifier call" {
  local r="$W/root"
  cp -R "$VCF/roots/r5" "$r"
  rm "$r/grimoires/loa/trust-ledger.jsonl"
  [ "$(_states "$r")" = "valid valid valid absent n/a valid n/a" ]
  [ "$(_summary "$r")" = "6/7" ]
  [ "$(_human "$r")" = "  Audit chain: 6/7 validate (1 absent, 0 broken).
  L4 trust-ledger.jsonl: absent" ]
  _invariants "$(_classify "$r")" "6/7"
  # none: the stub leaves a marker if it is ever called.
  local s; s="$(_stub "touch '$W/called'; exit 0")"
  [ "$(_states "$VCF/roots/none" "$s")" = "absent absent absent absent n/a absent n/a" ]
  [ "$(_summary "$VCF/roots/none" "$s")" = "2/7" ]
  [ ! -e "$W/called" ]
}

@test "LS-9 an unreadable chain file (mode 000) → that primitive broken" {
  [ "$(id -u)" -ne 0 ] || skip "running as root: mode 000 stays readable"
  local r="$W/root"
  cp -R "$VCF/roots/r5" "$r"
  chmod 000 "$r/.run/cost-budget-events.jsonl"
  [ "$(_states "$r")" = "valid broken valid valid n/a valid n/a" ]
  [ "$(_human "$r")" = "  Audit chain: 6/7 validate (0 absent, 1 broken).
  L2 cost-budget-events.jsonl: broken" ]
  _invariants "$(_classify "$r")" "6/7"
  chmod 600 "$r/.run/cost-budget-events.jsonl"
}

@test "LS-10 verifier exit 0 / 1 parse the records; exit 2 or garbage → every existing chain broken, absent stays absent" {
  local all='i=0; for p in "$@"; do jq -nc --argjson i $i --arg p "$p" "{i:\$i,path:\$p,ok:true,error:null}"; i=$((i+1)); done'
  local rp="$VCF/roots/r3-partial" s
  for s in "$all; exit 0" "$all; exit 1"; do
    [ "$(_states "$rp" "$(_stub "$s")")" = "valid valid absent absent n/a valid n/a" ]
    _invariants "$(_classify "$rp" "$(_stub "$s")")" "5/7"
  done
  for s in "$all; exit 2" "echo 'garbage, not a record'; exit 0" "$all; echo '{not json'; exit 1"; do
    [ "$(_states "$rp" "$(_stub "$s")")" = "broken broken absent absent n/a broken n/a" ] \
      || { echo "stub [$s]" >&2; return 1; }
    _invariants "$(_classify "$rp" "$(_stub "$s")")" "2/7"
  done
  [ "$(_human "$rp" "$(_stub "$all; exit 2")")" = "  Audit chain: 2/7 validate (2 absent, 3 broken).
  L1 panel-decisions.jsonl: broken
  L2 cost-budget-events.jsonl: broken
  L3 cycles.jsonl: absent
  L4 trust-ledger.jsonl: absent
  L6 INDEX.md: broken" ]
}

@test "LS-11 a duplicate record for index 0 and none for index 1 → both broken; shifted (unexpected) indices → every chain broken" {
  local dup='i=0; for p in "$@"; do
      if [[ $i -eq 0 ]]; then jq -nc --arg p "$p" "{i:0,path:\$p,ok:true,error:null}"; jq -nc --arg p "$p" "{i:0,path:\$p,ok:true,error:null}"
      elif [[ $i -ne 1 ]]; then jq -nc --argjson i $i --arg p "$p" "{i:\$i,path:\$p,ok:true,error:null}"; fi
      i=$((i+1)); done; exit 0'
  [ "$(_states "$VCF/roots/r5" "$(_stub "$dup")")" = "broken broken valid valid n/a valid n/a" ]
  _invariants "$(_classify "$VCF/roots/r5" "$(_stub "$dup")")" "5/7"
  local shift1='i=1; for p in "$@"; do jq -nc --argjson i $i --arg p "$p" "{i:\$i,path:\$p,ok:true,error:null}"; i=$((i+1)); done; exit 0'
  [ "$(_states "$VCF/roots/r5" "$(_stub "$shift1")")" = "broken broken broken broken n/a broken n/a" ]
  _invariants "$(_classify "$VCF/roots/r5" "$(_stub "$shift1")")" "2/7"
}

@test "LS-12 no executable verifier → every existing chain broken, absent stays absent (V + A + B == 7)" {
  [ "$(_states "$VCF/roots/r3-partial" "$W/no-such-verifier")" = "broken broken absent absent n/a broken n/a" ]
  _invariants "$(_classify "$VCF/roots/r3-partial" "$W/no-such-verifier")" "2/7"
  [ "$(_summary "$VCF/roots/none" "$W/no-such-verifier")" = "2/7" ]
}

@test "LS-13 loa-status.sh --json: audit_chain {valid (n/a excluded), absent, broken, not_applicable 2, total 7, primitives[7]} beside audit_chain_summary" {
  export LOA_STATUS_CONFIG_FILE="$W/no-loa-config.yaml"
  local r want
  for r in "r5:7/7:5:0:0:valid valid valid valid n/a valid n/a" \
           "none:2/7:0:5:0:absent absent absent absent n/a absent n/a" \
           "r3-partial:4/7:2:2:1:valid valid absent absent n/a broken n/a"; do
    local root="${r%%:*}" rest="${r#*:}"
    local sum="${rest%%:*}"; rest="${rest#*:}"
    local v="${rest%%:*}"; rest="${rest#*:}"
    local a="${rest%%:*}"; rest="${rest#*:}"
    local b="${rest%%:*}" states="${rest#*:}"
    ( cd "$VCF/roots/$root" && timeout 120 bash "$STATUS" --no-stale-check --json ) > "$W/out.json"
    jq -e --arg sum "$sum" --argjson v "$v" --argjson a "$a" --argjson b "$b" --arg states "$states" '
      .agent_network as $n | $n.audit_chain as $c
      | $n.audit_chain_summary == $sum
      and ($c | keys_unsorted) == ["valid", "absent", "broken", "not_applicable", "total", "primitives"]
      and $c.valid == $v and $c.absent == $a and $c.broken == $b
      and $c.not_applicable == 2 and $c.total == 7
      and ($c.valid + $c.absent + $c.broken + $c.not_applicable) == $c.total
      and ($c.valid + $c.not_applicable | tostring) + "/7" == $sum
      and ($c.primitives | map(.id)) == ["L1", "L2", "L3", "L4", "L5", "L6", "L7"]
      and ($c.primitives | map(.state) | join(" ")) == $states
      and ($c.primitives | map(.path)) == [".run/panel-decisions.jsonl", ".run/cost-budget-events.jsonl",
           ".run/cycles.jsonl", "grimoires/loa/trust-ledger.jsonl", null, "grimoires/loa/handoffs/INDEX.md", null]
      and ($c.primitives | all(keys_unsorted == ["id", "path", "state"]))' "$W/out.json" >/dev/null \
      || { echo "root $root: $(jq -c .agent_network.audit_chain "$W/out.json")" >&2; return 1; }
  done
}

@test "LS-14 loa-status.sh (whole script) on the none root: the 2/7 line plus five absent lines, never 7/7" {
  cd "$VCF/roots/none"
  export LOA_STATUS_CONFIG_FILE="$W/no-loa-config.yaml"
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  local block='  Audit chain: 2/7 validate (5 absent, 0 broken).
  L1 panel-decisions.jsonl: absent
  L2 cost-budget-events.jsonl: absent
  L3 cycles.jsonl: absent
  L4 trust-ledger.jsonl: absent
  L6 INDEX.md: absent
'
  [[ "$output" == *"$block"* ]]
  [[ "$output" != *"Audit chain: 7/7"* ]]
}
