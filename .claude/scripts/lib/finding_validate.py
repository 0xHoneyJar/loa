#!/usr/bin/env python3
# =============================================================================
# finding_validate.py — the python validator of the canonical finding (cycle-133 C-11; FR-11; D-3.2 DEC-0849,
# D-3.5 DEC-0857). One of the four validators of .claude/schemas/finding.schema.json v1 (with the zod schema in
# the Bridgebuilder skill, lib/finding-validate.sh and verdict-derive.sh's bullet grammar); all four must agree on
# every vector under .claude/schemas/finding.vectors/{valid,invalid}/.
#
# Usage:
#   finding_validate.py [FILE|-]          validate one finding (a JSON object) from FILE or stdin
#   finding_validate.py --vectors DIR     run every DIR/{valid,invalid}/*.json vector; one line per vector
#
# Output (single finding): one JSON line, sorted keys —
#   {"errors": [codes, sorted], "finding": <normalised finding> | null, "valid": bool, "warnings": [text]}
# The normalised finding keeps only the schema's named fields: id (given, else derived F-<6 hex>), severity,
# blocking (default false), and file, anchor_line, anchor_line_end, failure_scenario (resolved by alias
# precedence), confidence (as the enum), title, suggestion when present. Warnings name an alias used for
# failure_scenario: "`failure_mode` is an alias of `failure_scenario`; removed in 2.1.0" (and `description`).
#
# Error codes (x-loa-rules.error_codes): not_object, id, file, anchor_line, anchor_line_end, severity, blocking,
# confidence, failure_scenario, alias_conflict, title, suggestion.
#
# Exit: 0 valid (every vector agreed); 1 invalid (a vector disagreed); 2 usage or unreadable input.
# Python 3 standard library only; run with python3 -I.
# =============================================================================
import hashlib
import json
import math
import os
import re
import sys

SEVERITIES = ("CRITICAL", "HIGH", "MEDIUM", "LOW", "PRAISE", "SPECULATION", "REFRAME", "INFO")
DEFECT = ("CRITICAL", "HIGH", "MEDIUM", "LOW")
WS = re.compile(r"[ \t\n\r\f\v]+")
EDGE = re.compile(r"^[^A-Za-z0-9]+|[^A-Za-z0-9]+$")
DENYLIST = ("todo", "n/a", "see above", "as described", "placeholder")
DENY_RE = [re.compile(r"(?<![A-Za-z0-9])" + r"[ \t\n\r\f\v]+".join(re.escape(w) for w in p.split(" ")) + r"(?![A-Za-z0-9])")
           for p in DENYLIST]
MIN_TOKENS = 12
LINE_MAX = 10000000
ALIAS_WARNING = "`%s` is an alias of `failure_scenario`; removed in 2.1.0"
_LOWER = {c: c + 32 for c in range(65, 91)}


def ascii_lower(s):
    return s.translate(_LOWER)


def _int_line(v):
    """an integral JSON number in 1 … 10,000,000 (12 and 12.0 alike), else None"""
    if isinstance(v, bool):
        return None
    if isinstance(v, int):
        n = v
    elif isinstance(v, float) and math.isfinite(v) and v.is_integer():
        n = int(v)
    else:
        return None
    return n if 1 <= n <= LINE_MAX else None


def path_ok(p):
    if not isinstance(p, str) or p == "" or p.startswith("/") or "\\" in p:
        return False
    if any(ord(c) < 0x20 or ord(c) == 0x7F for c in p):
        return False
    return all(seg not in ("", ".", "..") for seg in p.split("/"))


def tokens(s):
    return [t for t in WS.split(s) if t]


def denied(s):
    low = ascii_lower(s)
    return any(r.search(low) for r in DENY_RE)


def when_then(toks):
    st = [ascii_lower(EDGE.sub("", t)) for t in toks]
    for i, t in enumerate(st):
        if t == "when":
            for j in range(i + 2, len(st) - 1):
                if st[j] == "then":
                    return True
    return False


def content_ok(s):
    """the C-11 content rule for a defect severity's failure_scenario"""
    if denied(s):
        return False
    toks = tokens(s)
    return len(toks) >= MIN_TOKENS or when_then(toks)


def confidence_of(v):
    if isinstance(v, str):
        return v if v in ("high", "medium", "low") else None
    if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or not 0 <= v <= 1:
        return None
    return "high" if v >= 0.75 else "medium" if v >= 0.45 else "low"


def derive_id(file, line, title):
    text = "%s:%s:%s" % (file if file is not None else "", line if line is not None else "", title if title is not None else "")
    return "F-" + hashlib.sha256(text.encode("utf-8")).hexdigest()[:6]


def validate(f):
    """→ (normalised finding | None, sorted error codes, warnings)"""
    if not isinstance(f, dict):
        return None, ["not_object"], []
    errs, warns = set(), []
    sev = f.get("severity")
    defect = None
    if isinstance(sev, str) and sev in SEVERITIES:
        defect = sev in DEFECT
    else:
        errs.add("severity")
    out = {}
    if f.get("id") is not None:
        if isinstance(f["id"], str) and WS.sub("", f["id"]) != "":
            out["id"] = f["id"]
        else:
            errs.add("id")
    if f.get("file") is not None:
        if path_ok(f["file"]):
            out["file"] = f["file"]
        else:
            errs.add("file")
    elif defect:
        errs.add("file")
    line = None
    if f.get("anchor_line") is not None:
        line = _int_line(f["anchor_line"])
        if line is None:
            errs.add("anchor_line")
        else:
            out["anchor_line"] = line
    elif defect:
        errs.add("anchor_line")
    if f.get("anchor_line_end") is not None:
        end = _int_line(f["anchor_line_end"])
        if end is None or line is None or end < line:
            errs.add("anchor_line_end")
        else:
            out["anchor_line_end"] = end
    blocking = f.get("blocking")
    if blocking is not None and not isinstance(blocking, bool):
        errs.add("blocking")
    if f.get("confidence") is not None:
        c = confidence_of(f["confidence"])
        if c is None:
            errs.add("confidence")
        else:
            out["confidence"] = c
    for k in ("title", "suggestion"):
        if f.get(k) is not None:
            if isinstance(f[k], str):
                out[k] = f[k]
            else:
                errs.add(k)
    fs, fm, de = f.get("failure_scenario"), f.get("failure_mode"), f.get("description")
    if fs is not None and fm is not None and not (isinstance(fs, str) and isinstance(fm, str) and fs == fm):
        errs.add("alias_conflict")
    picked = None
    for key, val in (("failure_scenario", fs), ("failure_mode", fm), ("description", de)):
        if val is not None:
            picked = val
            if key != "failure_scenario":
                warns.append(ALIAS_WARNING % key)
            break
    if picked is None:
        if defect:
            errs.add("failure_scenario")
    elif not isinstance(picked, str):
        errs.add("failure_scenario")
    elif defect and not content_ok(picked):
        errs.add("failure_scenario")
    else:
        out["failure_scenario"] = picked
    if errs:
        return None, sorted(errs), warns
    out["severity"] = sev
    out["blocking"] = blocking is True
    if "id" not in out:
        out["id"] = derive_id(out.get("file"), out.get("anchor_line"), out.get("title"))
    return out, [], warns


def result(f):
    n, e, w = validate(f)
    return {"errors": e, "finding": n, "valid": not e, "warnings": w}


def dumps(o):
    return json.dumps(o, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def run_vectors(root):
    bad, n = 0, 0
    for kind in ("valid", "invalid"):
        d = os.path.join(root, kind)
        for name in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            if not name.endswith(".json"):
                continue
            n += 1
            with open(os.path.join(d, name), encoding="utf-8") as fh:
                vec = json.load(fh)
            got = result(vec.get("finding"))
            exp = vec.get("expect")
            ok = got == exp and got["valid"] == (kind == "valid")
            bad += 0 if ok else 1
            print("%s %s/%s%s" % ("ok" if ok else "DISAGREE", kind, name, "" if ok else " got " + dumps(got)))
    if n == 0:
        print("finding_validate.py: no vectors under %s" % root, file=sys.stderr)
        return 2
    print("vectors %d, disagreements %d" % (n, bad))
    return 1 if bad else 0


def main(argv):
    if argv[:1] == ["--vectors"]:
        if len(argv) != 2:
            print("usage: finding_validate.py --vectors DIR", file=sys.stderr)
            return 2
        return run_vectors(argv[1])
    if len(argv) > 1 or (argv and argv[0].startswith("-") and argv[0] != "-"):
        print("usage: finding_validate.py [FILE|-] | --vectors DIR", file=sys.stderr)
        return 2
    try:
        text = sys.stdin.read() if not argv or argv[0] == "-" else open(argv[0], encoding="utf-8").read()
        f = json.loads(text)
    except (OSError, ValueError) as e:
        print("finding_validate.py: unreadable input: %s" % e, file=sys.stderr)
        return 2
    r = result(f)
    print(dumps(r))
    return 0 if r["valid"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
