#!/usr/bin/env python3
"""adjudicate.py <fixture> — build a2a/sprint-269/annotation/<fx>/adjudication.json from the lead's
decisions file <fx>/decisions.json: {"<id>": {"base": "A"|"B", "anchors": "union"|[...], "group": "D<k>",
"verdict": ..., "class": ..., "severity": ..., "category": ..., "reason": "..."}}. The description is the
base annotator's own text (the lead never rewrites a label); every other field defaults to the base record."""
import json, sys, os
fx = sys.argv[1]
root = f"grimoires/loa/a2a/sprint-269/annotation/{fx}"
A = json.load(open(f"{root}/A/labels.json")); B = json.load(open(f"{root}/B/labels.json"))
dec = json.load(open(f"{root}/decisions.json"))
def rec(side, i):
    return (side["hunks"] if i.startswith("H") else side["incidents"])[i]
out = {}
for i, d in dec.items():
    a, b = rec(A, i), rec(B, i)
    base = a if d.get("base", "A") == "A" else b
    r = {"verdict": d.get("verdict", base["verdict"]), "group": d.get("group", base.get("group")),
         "file": base.get("file"), "description": base.get("description"),
         "severity": d.get("severity", base.get("severity")), "category": d.get("category", base.get("category")),
         "reason": d["reason"]}
    anc = d.get("anchors", "union")
    r["anchor_lines"] = sorted(set(a.get("anchor_lines") or []) | set(b.get("anchor_lines") or [])) if anc == "union" else anc
    if r["verdict"] in ("not-defect", "not-at-head"):
        cls = d.get("class", base.get("not_defect_class"))
        r["severity"] = r["category"] = None
        r["anchor_lines"] = []
        if cls != "follow-on":   # a not-defect record with a group is a follow-on (annotation_merge.py); the class itself is not a record field
            r["group"] = None
    out[i] = r
json.dump(out, open(f"{root}/adjudication.json", "w"), indent=1, ensure_ascii=False)
print(f"{fx}: {len(out)} adjudication record(s)")
