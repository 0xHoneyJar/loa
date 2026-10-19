"""extract.py — one record per valid run: per-source citations and per-defect detection under the
grader's rule, stray (false-positive) regions with context, costs by phase and voice, transcript
statistics, and the temporal attribution of every catch (first event that cited it, before or
after the dissent returned). Writes data/runs.json and prints a cross-check against grade.json."""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

SPRINT_A2A = "sandbox/grimoires/loa/a2a/sprint-1"
TEST_RE = re.compile(r"\bbats\b|\bpytest\b|bash -n\b|shellcheck")
EXEC_RE = re.compile(r'eval "\$\(sed|harness\.sh|source .*pr/head|\. .*pr/head|bash .*pr/head/|bash -c|\./pr/head/|cp .*pr/head/.* /tmp')
HEADFILE_RE = re.compile(r"pr/head/([A-Za-z0-9_./+-]+\.[A-Za-z0-9]{1,6})")
SED_RANGE = re.compile(r"sed -n\s+'?(\d+),(\d+)p'?\s+(?:--\s+)?\"?\$?\{?([A-Za-z_][A-Za-z0-9_]*)?\}?\"?\s*([^\s;|&]*)")
AWK_RANGE = re.compile(r"NR\s*>=\s*(\d+)\s*&&\s*NR\s*<=\s*(\d+)")
DISSENT_MARK = re.compile(r"voices_succeeded|\"DISS-0\d\d\"|DISS-00\d|adversarial-review\.json|adversarial-audit\.json")

def source_texts(run_dir, arm):
    sb = os.path.join(run_dir, "sandbox")
    a2a = os.path.join(run_dir, SPRINT_A2A)
    srcs = {}
    t = C.read_text(os.path.join(sb, "review.md"))
    if t is not None: srcs["review.md"] = t
    for name in ("engineer-feedback.md", "auditor-sprint-feedback.md"):
        t = C.read_text(os.path.join(a2a, name))
        if t is not None: srcs[name] = t
    envs = {}
    for gate in ("review", "audit"):
        env = C.read_json(os.path.join(run_dir, "eval", f"adversarial-{gate}.json"))
        if env is None:
            continue
        envs[gate] = env
        by_voice = {}
        for f in (env.get("findings") or []):
            if isinstance(f, dict):
                by_voice.setdefault(f.get("answered_by") or f.get("voice") or "unknown", []).append(f)
        for voice, fs in by_voice.items():
            srcs[f"envelope:{gate}:{voice}"] = "\n".join(C.envelope_texts({"findings": fs}))
    return srcs, envs

def envelope_info(env):
    if not env: return None
    md = env.get("metadata") or {}
    vq = env.get("verdict_quality") or {}
    return {"status": md.get("status"), "voices_succeeded": vq.get("voices_succeeded"),
            "voices_succeeded_ids": vq.get("voices_succeeded_ids"), "reason": (md.get("reason") or "")[:200],
            "n_findings": len(env.get("findings") or []),
            "findings": [{"id": f.get("id"), "voice": f.get("answered_by") or f.get("voice"), "severity": f.get("severity"),
                          "anchor": f.get("anchor"), "anchor_type": f.get("anchor_type"),
                          "description": (f.get("description") or "")[:400]} for f in (env.get("findings") or []) if isinstance(f, dict)]}

def symbol_hits(env_info, pr, defects, head_cache):
    """dissent findings that name the defect's region at symbol level (not the grader's rule):
    anchor `file:function` whose function encloses a defect site, or an anchor text found within
    ±3 lines of a site. Returns {defect_id: [{voice, finding_id, how}]}"""
    out = {}
    if not env_info: return out
    for d in defects:
        lines = head_cache.setdefault((pr, d["file"]), C.head_lines(pr, d["file"]))
        syms = {C.enclosing_symbol(lines, s) for s in C.defect_sites(d)} - {None}
        near = set()
        for s in C.defect_sites(d):
            for k in range(max(1, s - 3), min(len(lines or []), s + 3) + 1):
                if lines and lines[k - 1].strip():
                    near.add(lines[k - 1].strip())
        for f in env_info["findings"]:
            a = f.get("anchor") or ""
            how = None
            if f.get("anchor_type") in ("function", "symbol") and ":" in a:
                fpath, sym = a.rsplit(":", 1)
                if C.path_matches(fpath, d["file"]) and sym in syms:
                    how = "function"
            elif f.get("anchor_type") in ("hunk", "line") and a.strip():
                if any(a.strip() in n or n in a.strip() for n in near if len(n) > 12):
                    how = f["anchor_type"]
            if how:
                out.setdefault(d["id"], []).append({"voice": f["voice"], "finding_id": f["id"], "how": how})
    return out

FILE_TOKEN = re.compile(r"[A-Za-z0-9_./+-]*?([A-Za-z0-9_+-]+\.(?:sh|bats|md|py|yaml|yml|json|txt|example))\b")
RANGE_RE = re.compile(r"sed -n\s+['\"]?([0-9,;p ]+)['\"]?|NR\s*>=\s*(\d+)\s*&&\s*NR\s*<=\s*(\d+)")
def _ranges(cmd):
    out = []
    for m in RANGE_RE.finditer(cmd):
        if m.group(2):
            out.append((int(m.group(2)), int(m.group(3)))); continue
        for part in m.group(1).split(";"):
            mm = re.match(r"\s*(\d+)(?:,(\d+))?p?\s*$", part)
            if mm:
                a = int(mm.group(1)); b = int(mm.group(2)) if mm.group(2) else a
                out.append((a, b))
    return out

def phase_stats(events, defects, pr, head_cache, dmap):
    st = {"n_events": len(events), "n_tool_calls": 0, "tools": {}, "n_test_runs": 0, "n_exec_probes": 0,
          "head_files_read": set(), "result_bytes": 0, "truncated_results": 0, "num_turns": None,
          "regions_read": {}, "diff_seen": {}, "must_match_seen": {}, "writes": []}
    for ev in events:
        if ev.get("type") == "result":
            st["num_turns"] = ev.get("num_turns")
        for kind, text in C.assistant_authored(ev):
            if kind.startswith("tool:"):
                st["n_tool_calls"] += 1
                st["tools"][kind[5:]] = st["tools"].get(kind[5:], 0) + 1
            if kind == "tool:Write" or (kind == "tool:Bash" and re.search(r"(cat|tee)\s*>>?\s*\S*(draft|feedback|review\.md|concerns)", text)):
                m = re.search(r"(?:^|\s|>)\s*(\S*(?:draft|feedback|review\.md|concerns)\S*)", text)
                st["writes"].append({"event": ev["_i"], "kind": kind, "target": (m.group(1) if m else None)})
            if kind == "tool:Bash":
                if TEST_RE.search(text): st["n_test_runs"] += 1
                if EXEC_RE.search(text): st["n_exec_probes"] += 1
                for m in HEADFILE_RE.finditer(text): st["head_files_read"].add(m.group(1))
                names = {m.group(1) for m in FILE_TOKEN.finditer(text)}
                rngs = _ranges(text)
                whole_diff = bool(re.search(r"\b(cat|less|more)\s+(\S*/)?head\.diff\b", text)) or ("git diff" in text and "--no-index" in text)
                for d in defects:
                    base = d["file"].rsplit("/", 1)[-1]
                    if base in names and d["id"] not in st["regions_read"]:
                        if any(a - 3 <= s <= b + 3 for a, b in rngs for s in C.defect_sites(d)):
                            st["regions_read"][d["id"]] = ev["_i"]
                    if d["id"] not in st["diff_seen"]:
                        dl = [dmap.get((d["file"], s)) for s in C.defect_sites(d)]
                        dl = [x for x in dl if x]
                        if whole_diff or (re.search(r"\bdiff\s+-u\b", text) and base in names):
                            st["diff_seen"][d["id"]] = ev["_i"]
                        elif "head.diff" in names and dl and any(a <= x <= b for a, b in rngs for x in dl):
                            st["diff_seen"][d["id"]] = ev["_i"]
        for res in C.tool_results(ev):
            st["result_bytes"] += len(res)
            if "<persisted-output>" in res: st["truncated_results"] += 1
            for d in defects:
                mm = d.get("must_match")
                if mm and d["id"] not in st["must_match_seen"] and mm.strip() and mm.strip()[:60] in res:
                    st["must_match_seen"][d["id"]] = ev["_i"]
    st["head_files_read"] = sorted(st["head_files_read"])
    return st

def first_citations(events, defects, dissent_idx):
    """per defect: the first event in which the assistant produced a grader-rule citation of it"""
    first = {}
    for ev in events:
        for kind, text in C.assistant_authored(ev):
            if ":" not in text: continue
            cites = C.citations(text)
            if not cites: continue
            for d in defects:
                if d["id"] in first: continue
                if any(C.cite_hits_defect(c, d) for c in cites):
                    first[d["id"]] = {"event": ev["_i"], "kind": kind,
                                      "when": ("pre_dissent" if dissent_idx is None or ev["_i"] < dissent_idx else "post_dissent")}
    return first

SEG_RE = re.compile(r"^\s*(?:cd\s+\S+\s*;\s*)?(?:\(\s*)?(?:export\s+\S+\s*;?\s*)?(?:timeout\s+(?:--\S+\s+)*\d+\s+)?(?:nohup\s+)?(?:bash\s+)?(?:timeout\s+\d+\s+)?\.?/?(?:\S*/)?adversarial-review\.sh\s+.*--type\s+(review|audit)\b.*--diff-file")
def is_launch(cmd):
    """a real dissent run: a command segment whose executable is adversarial-review.sh with --type and --diff-file,
    not a dry run, a record-fallback, or a heredoc body that merely mentions the script"""
    if "--dry-run" in cmd:
        return False
    in_heredoc = False
    for seg in re.split(r"\n|&&|\|\||;(?![^\n]*<<)", cmd):
        if "<<" in seg and "EOF" in seg: in_heredoc = True; continue
        if in_heredoc:
            if seg.strip() in ("EOF", "PY"): in_heredoc = False
            continue
        if SEG_RE.search(seg) and "--record-fallback" not in seg:
            return True
    return False

def dissent_arrival(events):
    """(arrival_event, launch_event): the assistant's tool_use that really ran adversarial-review.sh --type review|audit
    --diff-file is the launch; the arrival is the task_notification of that background task, or the tool_result of
    that tool_use when it ran in the foreground, else the first later tool result carrying envelope content."""
    launch = launch_id = None
    for ev in events:
        for blk in ((ev.get("message") or {}).get("content") or []) if ev.get("type") == "assistant" else []:
            if isinstance(blk, dict) and blk.get("type") == "tool_use":
                cmd = (blk.get("input") or {}).get("command") or ""
                if is_launch(cmd):
                    launch, launch_id = ev["_i"], blk.get("id"); break
        if launch: break
    if launch is None:
        return None, None
    task_id = None
    for ev in events:
        if ev["_i"] <= launch: continue
        if ev.get("type") == "system" and ev.get("subtype") == "task_started" and ev.get("tool_use_id") == launch_id:
            task_id = ev.get("task_id")
        if ev.get("type") == "system" and ev.get("subtype") == "task_notification" and task_id and ev.get("task_id") == task_id:
            return ev["_i"], launch
        if ev.get("type") == "user":
            for blk in (ev.get("message") or {}).get("content") or []:
                if isinstance(blk, dict) and blk.get("type") == "tool_result" and blk.get("tool_use_id") == launch_id and task_id is None:
                    return ev["_i"], launch
    for ev in events:
        if ev["_i"] <= launch: continue
        for res in C.tool_results(ev):
            if re.search(r"voices_succeeded|DISS-0\d\d|budget_exceeded|\"findings\"", res):
                return ev["_i"], launch
    return None, launch

def extract(run, head_cache):
    man = C.load_manifest(run["pr"]); defects = man["defects"]; pos = C.defect_positions(man)
    grade = C.read_json(os.path.join(run["run_dir"], "grade.json"))
    pipe = C.read_json(os.path.join(run["run_dir"], "meta", "pipeline.json"))
    srcs, envs = source_texts(run["run_dir"], run["arm"])
    per_source = {}
    all_cites, seen = [], set()
    for name, text in srcs.items():
        cites = C.citations(text)
        per_source[name] = {"n_citations": len(cites), "detected": C.detected(cites, defects)}
        for c in cites:
            if c not in seen:
                seen.add(c); all_cites.append(c)
    det_union = C.detected(all_cites, defects)
    regions = C.stray_regions(all_cites, defects)
    hunks = C.diff_hunks(run["pr"])
    dmap = C.diff_line_map(run["pr"])
    # which source(s) cited each stray region + the citing text snippet
    for rg in regions:
        rg["sources"] = []
        for name, text in srcs.items():
            cs = C.citations(text)
            if any(C.strip_side(p) == rg["file"] and not (b < rg["lo_w"] or a > rg["hi_w"]) for p, a, b in cs):
                rg["sources"].append(name)
        rg["in_diff"] = C.in_diff(hunks, rg["file"], rg["lo"], rg["hi"])
        rg["hunk_distance"] = C.nearest_hunk_distance(hunks, rg["file"], rg["lo"])
        rg["file_in_pr"] = rg["file"] in hunks or C.head_lines(run["pr"], rg["file"]) is not None
    # costs
    phases = []
    for ph in (pipe or {}).get("phases") or []:
        phases.append({"name": ph.get("name"), "primary_cost_usd": ph.get("cost_usd") or 0.0,
                       "dissent_cost_usd": ph.get("ledger_cost_usd") or 0.0, "wall_ms": ph.get("wall_ms") or ph.get("duration_ms"),
                       "num_turns": ph.get("num_turns"), "tokens_out": ph.get("tokens_out"), "verdict": ph.get("verdict")})
    # dissent voice cost split from the cost ledger
    voice_cost = {}
    for line in (C.read_text(os.path.join(run["run_dir"], "eval", "cost-ledger.jsonl")) or "").splitlines():
        try: row = json.loads(line)
        except ValueError: continue
        voice_cost[row.get("model")] = voice_cost.get(row.get("model"), 0.0) + (row.get("cost_micro_usd") or 0) / 1e6
    # transcripts
    tr = {}
    temporal = {}
    for phase in ("BARE", "REVIEW", "AUDIT"):
        p = os.path.join(run["run_dir"], "transcripts", f"events-{phase}.jsonl")
        if not os.path.isfile(p): continue
        events = C.read_events(p)
        didx, launch = dissent_arrival(events)
        st = phase_stats(events, defects, run["pr"], head_cache, dmap)
        st["dissent_arrival_event"] = didx; st["dissent_launch_event"] = launch
        tr[phase] = st
        temporal[phase] = first_citations(events, defects, didx)
    # per-defect summary
    per_defect = {}
    for k, d in pos.items():
        srcs_hit = [n for n, v in per_source.items() if d["id"] in v["detected"]]
        first = None
        for phase in ("BARE", "REVIEW", "AUDIT"):
            if phase in temporal and d["id"] in temporal[phase]:
                first = dict(temporal[phase][d["id"]], phase=phase); break
        per_defect[k] = {"id": d["id"], "file": d["file"], "sites": C.defect_sites(d), "severity": d.get("severity"),
                         "category": d.get("category"), "label_source": d.get("label_source"),
                         "in_diff": any(C.in_diff(hunks, d["file"], s, s) for s in C.defect_sites(d)),
                         "hunk_distance": min([C.nearest_hunk_distance(hunks, d["file"], s) or 0 for s in C.defect_sites(d)] or [None]),
                         "caught": d["id"] in det_union, "sources": srcs_hit, "first_citation": first,
                         "dissent_symbol_hits": {g: symbol_hits(envelope_info(envs.get(g)), run["pr"], [d], head_cache).get(d["id"], []) for g in envs},
                         "region_read": {ph: tr[ph]["regions_read"].get(d["id"]) for ph in tr},
                         "diff_seen": {ph: tr[ph]["diff_seen"].get(d["id"]) for ph in tr},
                         "diff_line": [dmap.get((d["file"], s)) for s in C.defect_sites(d)],
                         "must_match_seen": {ph: tr[ph]["must_match_seen"].get(d["id"]) for ph in tr}}
    rec = dict(run)
    rec.update({"grade": {"caught": grade["recall"]["defects_caught"], "seeded": grade["recall"]["defects_seeded"],
                          "missed": grade["recall"]["missed"], "flags": grade["recall"]["flags"], "false_positives": grade["false_positives"],
                          "verdicts": grade.get("verdicts"), "verdict_accuracy": grade.get("verdict_accuracy")},
                "detected_union": det_union, "n_citations_union": len(all_cites), "per_source": per_source,
                "stray_regions": regions, "n_stray_regions": len(regions),
                "cost_usd": (pipe or {}).get("spent_usd"), "phases": phases, "voice_cost_usd": voice_cost,
                "wall_ms": sum((ph.get("wall_ms") or 0) for ph in phases),
                "envelopes": {g: envelope_info(e) for g, e in envs.items()}, "transcripts": tr, "per_defect": per_defect})
    # cross-check with grade.json
    missed_pos = sorted(k for k, d in pos.items() if d["id"] not in det_union)
    rec["crosscheck"] = {"caught_match": len(det_union) == grade["recall"]["defects_caught"],
                         "missed_match": missed_pos == sorted(grade["recall"]["missed"]),
                         "flags_match": len(all_cites) == grade["recall"]["flags"],
                         "fp_match": len(regions) == grade["false_positives"]}
    return rec

def main():
    head_cache = {}
    recs = [extract(r, head_cache) for r in C.valid_runs()]
    os.makedirs(C.DATA, exist_ok=True)
    with open(os.path.join(C.DATA, "runs.json"), "w", encoding="utf-8") as f:
        json.dump(recs, f, indent=1, sort_keys=True)
    bad = [(r["run_id"], r["crosscheck"]) for r in recs if not all(r["crosscheck"].values())]
    print(f"{len(recs)} runs extracted; cross-check failures: {len(bad)}")
    for b in bad: print("  ", b)
    for r in recs:
        print(f"{r['arm']:8s} {r['task']} t{r['trial']} caught {r['grade']['caught']}/{r['grade']['seeded']} flags {r['grade']['flags']:3d} fp {r['grade']['false_positives']:3d} cost {r['cost_usd']:.2f} "
              + " ".join(f"{k}={len(v['detected'])}/{v['n_citations']}" for k, v in r["per_source"].items()))

if __name__ == "__main__":
    main()
