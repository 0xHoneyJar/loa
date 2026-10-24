#!/usr/bin/env bash
# =============================================================================
# lib/session-exec.sh — the session mechanics every `claude -p` session of the eval harness shares
# (cycle-132 Task 1.4, SDD §1.4 "Blind session runner", D-7.1; cycle-133 Task 2.1, SDD §1.4 C-6, PRD FR-6)
#
# Sourced by a literal relative path (eval.yml trust boundary) by evals/harness/blind-session.sh and
# evals/harness/pipeline-run.sh: this file is the ONE copy of the python3 -I exec shim, the pass-through
# and secret keys, and the pricing the cap watchdog uses (D-4.10). evals/tests/blind-session.bats BS-8
# keeps the drift guard until the Sprint 3 smoke is green on the measurement pin (Task 3.6 deletes it).
#
# Contract (C-6; fail closed):
#   price_for <model>                → {"in":…,"out":…,"cr":…,"cc":…} (micro-USD per Mtok), status 0; or the
#                                      line ERR, status 1, one reason line on stderr, when the pricing JSON does
#                                      not parse or is not an object, the model id has no entry, or any of
#                                      in/out/cr/cc is missing, null, negative, non-numeric or non-finite.
#                                      Absent cache prices derive from the input price (read 0.1×, write 1.25×);
#                                      a cache price present as null is ERR. A zero price is a price.
#   price_events <events> <prices> <budget_micro>
#                                    → "<turns> <estimate_micro> <crossing_turn|0>", status 0; or ERR, status 1,
#                                      when the events file is unreadable, a line other than a partial last line
#                                      does not parse, the prices are not a valid {in,out,cr,cc} object (ERR and
#                                      null included), the budget is not an integer, a usage event carries an
#                                      invalid token count (not a non-negative integer; absent or null = 0; a
#                                      usage object with no token field), a stream delta has no open message, or
#                                      a COMPLETED assistant turn has no usage (metering incomplete). A turn is
#                                      completed once any later event (or the result) follows its last event;
#                                      the last turn of a live stream is in flight and prices on what it has.
#   unmetered_tail <events>          → true | false, status 0 (ERR as above): true when the attempt shows model
#                                      activity (system init, thinking tokens, an assistant or stream event) and
#                                      no usage event at all — spend unknown, never zero. Callers persist such an
#                                      attempt as an `unmetered_attempt` row when no authoritative result cost
#                                      exists.
#   Callers check BOTH the sentinel and the status: blind-session.sh does not launch (exit 2) and stops a live
#   session (metering_incomplete); pipeline-run.sh stops the phase (status infrastructure_error, reason
#   metering_incomplete).
#   Metering rules: every attempt is priced; usage snapshots of one message id (repeated assistant events,
#   stream_event message_start/message_delta) merge by the largest count per field — they are cumulative, so
#   they are never summed twice; cached-read and cache-write tokens price at their own rates; an interrupted
#   turn prices on the usage received; a refusal rerun inside a session (model_refusal_fallback) is a second
#   attempt whose turns carry their own message ids and are priced like any other (at the session model's
#   price: the fallback goes to a model no dearer, so the estimate stays conservative).
#
#   ENV_SHIM <keys-csv> <cmd…>       (python3 -I -c "$ENV_SHIM" …) keep exactly the named environment keys,
#                                      close every inherited descriptor above 2, exec <cmd>. Descriptors are
#                                      enumerated from /proc/self/fd (so one above 65535 or above a lowered soft
#                                      limit is closed); the listing handle and any descriptor named in
#                                      LOA_KEEP_FDS survive. LOA_KEEP_FDS: comma-separated decimal descriptor
#                                      numbers, default empty; anything else → exit 2. Without /proc the shim
#                                      falls back to os.closerange(3, hard RLIMIT_NOFILE), and to a fixed
#                                      1048576 when the hard limit is infinite or unusable.
#   assert_secret_keys               startup assertion: every PASS_KEYS entry whose upper-cased name matches
#                                      SECRET_KEY_PATTERN must be in SECRET_KEYS or NON_SECRET_ALLOWLIST; else
#                                      one stderr line per offender and status 1 (callers refuse to launch).
#
# Needs: REPO_ROOT (pricing.py lives under it); PRICE_CACHE is initialised here.
# Env: LOA_EVAL_PRICING_JSON (a {"<model>": {input_per_mtok, output_per_mtok, …}} override; malformed → ERR),
#      LOA_KEEP_FDS (read by ENV_SHIM only).
# Tested by evals/tests/session-exec.bats (and through the callers by blind-session.bats, pipeline-run.bats).
# =============================================================================

# ENV_SHIM <keys-csv> <cmd…>: close every descriptor above 2 (DEC-0412; C-6), keep exactly the
# named environment variables, exec <cmd>. No eval (eval.yml trust boundary), and secret
# values never appear in any argv: they travel in the environment only.
ENV_SHIM='import os, resource, sys
keys = [k for k in sys.argv[1].split(",") if k]
env = {k: os.environ[k] for k in keys if k in os.environ}
keep = set()
for tok in os.environ.get("LOA_KEEP_FDS", "").split(","):
    tok = tok.strip()
    if not tok:
        continue
    if not tok.isdigit() or not tok.isascii():
        sys.stderr.write("ENV_SHIM: LOA_KEEP_FDS must be comma-separated descriptor numbers, got %r\n" % tok)
        sys.exit(2)
    keep.add(int(tok))
try:
    listing = os.open("/proc/self/fd", os.O_RDONLY | os.O_DIRECTORY)
except OSError:
    listing = None
if listing is not None:
    for name in os.listdir(listing):
        fd = int(name)
        if fd > 2 and fd != listing and fd not in keep:
            try:
                os.close(fd)
            except OSError:
                pass
    os.close(listing)
else:
    try:
        hard = resource.getrlimit(resource.RLIMIT_NOFILE)[1]
    except (OSError, ValueError):
        hard = -1
    if hard == resource.RLIM_INFINITY or hard <= 3:
        hard = 1048576
    lo = 3
    for k in sorted(keep):
        if lo <= k < hard:
            os.closerange(lo, k)
            lo = k + 1
    os.closerange(lo, hard)
os.execvpe(sys.argv[2], sys.argv[2:], env)'
# pass-through keys, taken from the driver's environment when set; SECRET_KEYS are never
# written to an argv or a capture (recorded as <set>)
PASS_KEYS="AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE AWS_BEARER_TOKEN_BEDROCK ANTHROPIC_BEDROCK_REGION_PREFIX ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL"
SECRET_KEYS=" AWS_BEARER_TOKEN_BEDROCK "
# a pass-through key whose upper-cased name matches this is secret-shaped: it must be listed in SECRET_KEYS (travels by
# name, recorded <set>) or, after review, in NON_SECRET_ALLOWLIST (space-padded, default empty)
SECRET_KEY_PATTERN='(KEY|TOKEN|SECRET|PASSWORD|PASS|CREDENTIAL|AUTH)'
NON_SECRET_ALLOWLIST=" "

assert_secret_keys() {  # assert_secret_keys → status 0, or one stderr line per offender and status 1
  local k up bad=0
  for k in $PASS_KEYS; do
    up="$(printf '%s' "$k" | tr 'a-z' 'A-Z')"
    [[ "$up" =~ $SECRET_KEY_PATTERN ]] || continue
    [[ "$SECRET_KEYS" == *" $k "* || "$NON_SECRET_ALLOWLIST" == *" $k "* ]] && continue
    echo "session-exec.sh: assert_secret_keys: pass-through key $k is secret-shaped but not in SECRET_KEYS; add it there (or, reviewed, to NON_SECRET_ALLOWLIST)" >&2
    bad=1
  done
  return "$bad"
}

# --- pricing and metering (one lookup per model; D-4.10; C-6) ----------------------------------
# SESSION_METER_PY <mode> … — the one implementation behind price_for / price_events / unmetered_tail:
#   price <model> table|entry   (stdin: the override table, or pricing.py's one-entry line)
#   events <file> <prices> <budget_micro> | unmetered <file>
# prints the result or ERR (status 1, the reason on stderr)
SESSION_METER_PY='import json, math, sys
def fail(why):
    sys.stderr.write("session-exec.sh: " + why + "\n")
    print("ERR")
    sys.exit(1)
def num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and v >= 0
def tidy(v):
    return int(v) if float(v).is_integer() else v
mode = sys.argv[1]
if mode == "price":
    model, src = sys.argv[2], sys.argv[3]
    try:
        doc = json.loads(sys.stdin.read())
    except ValueError:
        fail("price_for: the pricing JSON does not parse" + (" (LOA_EVAL_PRICING_JSON)" if src == "table" else ""))
    if src == "table":
        if not isinstance(doc, dict):
            fail("price_for: LOA_EVAL_PRICING_JSON is not an object of model entries")
        if model not in doc:
            fail("price_for: no price for model " + model + " in LOA_EVAL_PRICING_JSON")
        doc = doc[model]
    if not isinstance(doc, dict):
        fail("price_for: no price for model " + model + " (the entry is not an object)")
    def field(k):
        if k not in doc or not num(doc[k]):
            fail("price_for: model " + model + ": " + k + " is " + (repr(doc[k]) if k in doc else "missing")
                 + " (a non-negative finite number is required)")
        return doc[k]
    pin, pout = field("input_per_mtok"), field("output_per_mtok")
    cr = field("cache_read_per_mtok") if "cache_read_per_mtok" in doc else pin / 10
    ck = [k for k in ("cache_write_per_mtok", "cache_creation_per_mtok") if k in doc]
    cc = field(ck[0]) if ck else pin * 5 / 4
    print(json.dumps({"in": tidy(pin), "out": tidy(pout), "cr": tidy(cr), "cc": tidy(cc)}, separators=(",", ":")))
    sys.exit(0)
path = sys.argv[2]
if mode == "events":
    try:
        p = json.loads(sys.argv[3])
    except ValueError:
        fail("price_events: the prices are not JSON: " + sys.argv[3][:80])
    if not isinstance(p, dict) or not all(k in p and num(p[k]) for k in ("in", "out", "cr", "cc")):
        fail("price_events: the prices are not a valid {in,out,cr,cc} object: " + sys.argv[3][:80])
    try:
        budget = int(sys.argv[4])
    except ValueError:
        fail("price_events: the budget is not an integer: " + sys.argv[4][:40])
try:
    with open(path, "rb") as f:
        text = f.read().decode("utf-8", "replace")
except OSError as e:
    fail("price_events: the events file is unreadable: " + str(e))
lines = text.split("\n")
partial = lines[-1] != ""
if not partial:
    lines = lines[:-1]
TOK = ("input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")
order, turns = [], {}
pos, seen, open_id, last_usage, last_activity, has_result = -1, 0, None, -1, -1, False
def note(mid, u, n):
    global last_usage
    if mid not in turns:
        order.append(mid)
        turns[mid] = {"u": None, "last": pos}
    t = turns[mid]
    t["last"] = pos
    if u is None:
        return
    if not isinstance(u, dict) or not any(u.get(k) is not None for k in TOK):
        fail("price_events: line %d: a usage event without token counts" % n)
    cur = t["u"] or dict.fromkeys(TOK, 0)
    for k in TOK:
        v = u.get(k)
        if v is None:
            continue
        if not isinstance(v, int) or isinstance(v, bool) or v < 0:
            fail("price_events: line %d: invalid token count %s=%r" % (n, k, v))
        cur[k] = max(cur[k], v)
    t["u"] = cur
    last_usage = pos
for n, line in enumerate(lines, 1):
    if not line.strip():
        continue
    try:
        e = json.loads(line)
    except ValueError:
        if partial and n == len(lines):
            continue
        fail("price_events: line %d does not parse" % n)
    if not isinstance(e, dict):
        continue
    pos += 1
    t = e.get("type")
    if t == "assistant":
        m = e.get("message")
        if not isinstance(m, dict):
            fail("price_events: line %d: an assistant event without a message" % n)
        seen += 1
        mid = m.get("id") if isinstance(m.get("id"), str) and m.get("id") else "event-%d" % seen
        note(mid, m.get("usage"), n)
        last_activity = pos
    elif t == "stream_event":
        ev = e.get("event") if isinstance(e.get("event"), dict) else {}
        if ev.get("type") == "message_start" and isinstance(ev.get("message"), dict):
            seen += 1
            mid = ev["message"].get("id")
            open_id = mid if isinstance(mid, str) and mid else "event-%d" % seen
            note(open_id, ev["message"].get("usage"), n)
        elif ev.get("type") == "message_delta":
            if open_id is None:
                fail("price_events: line %d: a message_delta with no open message" % n)
            note(open_id, ev.get("usage"), n)
        elif open_id is not None:
            note(open_id, None, n)
        last_activity = pos
    elif t == "system" and e.get("subtype") in ("init", "thinking_tokens"):
        last_activity = pos
    elif t == "result":
        has_result = True
for mid in order:
    t = turns[mid]
    if t["u"] is None and (has_result or t["last"] < pos):
        fail("price_events: metering incomplete: the completed assistant turn %s has no usage event" % mid)
metered = [turns[m]["u"] for m in order if turns[m]["u"] is not None]
if mode == "unmetered":
    print("true" if not metered and last_activity >= 0 else "false")
    sys.exit(0)
costs = [(u["input_tokens"] * p["in"] + u["output_tokens"] * p["out"] + u["cache_read_input_tokens"] * p["cr"]
          + u["cache_creation_input_tokens"] * p["cc"]) / 1000000 for u in metered]
s, cross = 0, 0
for i, c in enumerate(costs):
    s += c
    if not cross and s >= budget:
        cross = i + 1
print("%d %d %d" % (len(costs), math.floor(sum(costs) + 0.5), cross))'

PRICE_CACHE=""
price_for() {  # price_for <model id> → {"in":…,"out":…,"cr":…,"cc":…} micro-USD per Mtok; or ERR, status 1
  local m="$1" hit alias j rc=0
  hit="$(printf '%s\n' "$PRICE_CACHE" | awk -F'\t' -v m="$m" '$1 == m {print $2; exit}')"
  if [[ -n "$hit" ]]; then printf '%s\n' "$hit"; [[ "$hit" != ERR ]]; return; fi
  if [[ -n "${LOA_EVAL_PRICING_JSON:-}" ]]; then
    j="$(printf '%s' "$LOA_EVAL_PRICING_JSON" | python3 -I -c "$SESSION_METER_PY" price "$m" table)" || rc=$?
  else
    alias="$(printf '%s' "$m" | sed -E 's/^([a-z]+\.)?anthropic\.//; s/-v[0-9]+(:[0-9]+)?$//')"
    j="$(cd "$REPO_ROOT/.claude/adapters" && python3 -I "$REPO_ROOT/.claude/adapters/loa_cheval/metering/pricing.py" \
          --alias "$alias" --json)" || rc=$?
    if [[ $rc -ne 0 || -z "$j" ]]; then
      echo "session-exec.sh: price_for: pricing.py failed for model $m (exit $rc)" >&2; j=ERR rc=1
    else
      j="$(printf '%s' "$j" | sed -n '1p' | python3 -I -c "$SESSION_METER_PY" price "$m" entry)" || rc=$?
    fi
  fi
  [[ $rc -eq 0 && -n "$j" && "$j" != ERR ]] || { j=ERR rc=1; }
  PRICE_CACHE="$PRICE_CACHE$m"$'\t'"$j"$'\n'
  printf '%s\n' "$j"
  return "$rc"
}
# price_events <events> <prices> <budget_micro> → "<turns> <estimate_micro> <crossing_turn|0>"; or ERR, status 1
price_events() {
  python3 -I -c "$SESSION_METER_PY" events "$1" "$2" "$3"
}
# unmetered_tail <events> → true | false; or ERR, status 1
unmetered_tail() {
  python3 -I -c "$SESSION_METER_PY" unmetered "$1"
}
