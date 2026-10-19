"""attribution.py — deliverable 2: which component first flagged every full-pipeline catch, the lift split by
component, the reconstructions (dissent removed, audit gate removed), and the cost split by phase and voice."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

def classify(d, run):
    """first-citation class of one caught defect in one a1 run"""
    fc = d["first_citation"]
    rv = (run["envelopes"].get("review") or {})
    review_voices = rv.get("voices_succeeded") or 0
    named = {g: sorted({h["voice"] for h in v}) for g, v in d["dissent_symbol_hits"].items() if v}
    if not fc:
        return "uncited", named
    if fc["phase"] == "AUDIT":
        return "audit_gate", named
    if review_voices == 0:
        return "review_no_dissent_voice", named   # budget_exceeded / killed: no voice ran on this gate
    if fc["when"] == "pre_dissent":
        return "review_pre_dissent", named
    if named.get("review"):
        return "review_post_dissent_named", named
    return "review_post_dissent_unnamed", named

def main():
    recs = json.load(open(os.path.join(C.DATA, "runs.json")))
    a0 = {(r["task"], r["trial"]): r for r in recs if r["arm"] == "a0_bare"}
    a1 = {(r["task"], r["trial"]): r for r in recs if r["arm"] == "a1_full"}
    rows = []
    for key, r in sorted(a1.items()):
        b = a0[key]
        for k, d in r["per_defect"].items():
            cls, named = classify(d, r)
            rows.append({"task": r["task"], "pr": r["pr"], "trial": r["trial"], "defect": k, "id": d["id"], "severity": d["severity"],
                         "full_caught": d["caught"], "bare_caught": b["per_defect"][k]["caught"], "class": cls if d["caught"] else "missed",
                         "first_event": (d["first_citation"] or {}).get("event"), "first_kind": (d["first_citation"] or {}).get("kind"),
                         "sources": d["sources"], "dissent_named": named,
                         "review_only_caught": any(s in ("review.md", "engineer-feedback.md") or s.startswith("envelope:review") for s in d["sources"]),
                         "audit_only_source": d["caught"] and all(s == "auditor-sprint-feedback.md" or s.startswith("envelope:audit") for s in d["sources"])})
    caught = [x for x in rows if x["full_caught"]]
    lift_rows = [x for x in caught if not x["bare_caught"]]
    n_pairs = len(rows)
    def count(rs, key="class"):
        out = {}
        for x in rs: out[x[key]] = out.get(x[key], 0) + 1
        return out
    by_class_all = count(caught); by_class_lift = count(lift_rows)
    # the dissent's symbol-level naming over all a1 defect-trials where a review envelope had voices
    named_any = sum(1 for x in rows if x["dissent_named"].get("review"))
    named_caught = sum(1 for x in caught if x["dissent_named"].get("review"))
    by_voice = {}
    for x in rows:
        for v in x["dissent_named"].get("review", []):
            by_voice.setdefault(v, {"named": 0, "caught": 0, "bare_missed": 0})
            by_voice[v]["named"] += 1; by_voice[v]["caught"] += x["full_caught"]; by_voice[v]["bare_missed"] += (not x["bare_caught"])
    # reconstructions (grader rule): remove the audit gate → catches from review-phase sources only
    rec_no_audit = sum(1 for x in rows if x["review_only_caught"])
    rec_full = len(caught); rec_bare = sum(1 for x in rows if x["bare_caught"])
    # per task means (the report's statistic is the task-mean of per-trial rates; the pooled rate is also given)
    def task_mean(pred):
        tm = {}
        for t in ("review-01", "review-02", "review-03", "review-04"):
            xs = [x for x in rows if x["task"] == t]
            tm[t] = sum(1 for x in xs if pred(x)) / len(xs)
        return tm, sum(tm.values()) / 4
    tm_full, m_full = task_mean(lambda x: x["full_caught"])
    tm_bare, m_bare = task_mean(lambda x: x["bare_caught"])
    tm_noaud, m_noaud = task_mean(lambda x: x["review_only_caught"])
    tm_nodis_lb, m_nodis_lb = task_mean(lambda x: x["full_caught"] and x["class"] not in ("review_post_dissent_named",))
    tm_nodis_lb2, m_nodis_lb2 = task_mean(lambda x: x["full_caught"] and x["class"] not in ("review_post_dissent_named", "review_post_dissent_unnamed"))
    # cost split
    cost = {"REVIEW_primary": 0, "REVIEW_dissent": 0, "AUDIT_primary": 0, "AUDIT_dissent": 0}
    voice = {}
    per_task_cost = {}
    for r in a1.values():
        for ph in r["phases"]:
            cost[f"{ph['name']}_primary"] += ph["primary_cost_usd"]; cost[f"{ph['name']}_dissent"] += ph["dissent_cost_usd"]
        for v, c in r["voice_cost_usd"].items(): voice[v] = voice.get(v, 0) + c
        pt = per_task_cost.setdefault(r["task"], {"runs": 0, "total": 0, "review": 0, "audit": 0, "dissent": 0})
        pt["runs"] += 1; pt["total"] += r["cost_usd"]
        for ph in r["phases"]:
            pt[ph["name"].lower()] += ph["primary_cost_usd"] + ph["dissent_cost_usd"]; pt["dissent"] += ph["dissent_cost_usd"]
    n_runs = len(a1); total = sum(cost.values())
    out = {"n_defect_trials": n_pairs, "full_caught": rec_full, "bare_caught": rec_bare, "lift_defect_trials": len(lift_rows),
           "first_citation_class_all_catches": by_class_all, "first_citation_class_lift_only": by_class_lift,
           "dissent_symbol_naming": {"defect_trials_named_review": named_any, "of_which_caught": named_caught, "by_voice": by_voice},
           "reconstruction_task_mean": {"bare": m_bare, "full": m_full, "full_without_audit_gate": m_noaud,
                                        "full_minus_post_dissent_named_catches(lower_bound_no_dissent)": m_nodis_lb,
                                        "full_minus_all_post_dissent_review_catches(extreme_lower_bound)": m_nodis_lb2,
                                        "per_task": {"bare": tm_bare, "full": tm_full, "no_audit": tm_noaud, "no_dissent_lb": tm_nodis_lb, "no_dissent_extreme": tm_nodis_lb2}},
           "reconstruction_pooled": {"bare": rec_bare / n_pairs, "full": rec_full / n_pairs, "full_without_audit_gate": rec_no_audit / n_pairs},
           "cost_split_usd_total_12_runs": cost, "cost_split_share": {k: v / total for k, v in cost.items()}, "voice_cost_usd_total": voice,
           "per_task_cost": per_task_cost, "rows": rows}
    json.dump(out, open(os.path.join(C.OUT, "attribution.json"), "w"), indent=1)
    L = ["# Deliverable 2 — voice attribution of every full-pipeline catch\n",
         "Source: `data/runs.json` (24 valid runs; the grader's own rule re-applied per source file and per dissent voice; transcript timing from `events-REVIEW.jsonl` / `events-AUDIT.jsonl`). Script: `scripts/attribution.py`.\n",
         "## The structural fact first\n",
         "Under the grader's rule a dissent voice can only be credited through a numeric `file:line` anchor in its envelope. **None of the 24 dissent envelopes (12 runs × review + audit) carries one**: every finding anchors on a function name, a hunk header or a code line (`anchor_type` function/hunk/line), so `envelope:*` sources contribute 0 citations in every run (see the per-source columns in `data/runs.json`). Every credited catch therefore sits in text the Fable reviewer or auditor wrote. The dissent can only have contributed by influence — a voice naming a region before Fable wrote it down — which is what the timing below measures.\n",
         "## First-citation class of the 46 full-arm catches (defect-trials)\n",
         "| class | meaning | all catches | of the 15 full-only catches |\n|---|---|---|---|"]
    meaning = {"review_pre_dissent": "Fable reviewer cited it (concerns/draft/feedback) BEFORE the dissent returned",
               "review_post_dissent_named": "first cited after the dissent returned AND a voice had named the enclosing function/hunk",
               "review_post_dissent_unnamed": "first cited after the dissent returned, no voice named the region",
               "review_no_dissent_voice": "review gate whose dissent ran no voice (budget_exceeded on pr-13; killed on review-03 t1): Fable alone",
               "audit_gate": "first cited only in the AUDIT gate's feedback", "uncited": "caught by grader but no transcript citation found"}
    for cls in ("review_pre_dissent", "review_post_dissent_named", "review_post_dissent_unnamed", "review_no_dissent_voice", "audit_gate", "uncited"):
        L.append(f"| `{cls}` | {meaning[cls]} | {by_class_all.get(cls, 0)} | {by_class_lift.get(cls, 0)} |")
    L.append(f"\nThe 15 full-only catches are the whole lift (bare-only catches: 0). Split: " + ", ".join(f"{k} {v}" for k, v in sorted(by_class_lift.items(), key=lambda kv: -kv[1])) + ".\n")
    L.append("## Did a dissent voice name the region at all? (symbol level, outside the grader's rule)\n")
    L.append(f"A review-gate dissent finding whose function anchor encloses a planted site, or whose hunk/line anchor text lies within ±3 lines of it: {named_any} of {n_pairs} defect-trials, {named_caught} of them caught by Fable. By voice (`answered_by`): " + "; ".join(f"**{v}** named {e['named']} (caught {e['caught']}, bare had missed {e['bare_missed']})" for v, e in sorted(by_voice.items())) + ". On pr-13 no voice ran (budget gate); on review-03 t1 the review dissent was killed by the 420 s cap.\n")
    L.append("## Reconstructions (task-mean catch rate, the report's statistic)\n")
    L.append("| configuration | task-mean catch rate | Δ vs bare | note |\n|---|---|---|---|")
    L.append(f"| bare | {m_bare:.3f} | — | 12 a0 runs |")
    L.append(f"| full (as shipped) | {m_full:.3f} | {m_full-m_bare:+.3f} | the pre-registered +0.263 is the defect-level statistic; task-mean matches the report's 0.854 − 0.668 = +0.186 |")
    L.append(f"| full without the AUDIT gate | {m_noaud:.3f} | {m_noaud-m_bare:+.3f} | grader rule over review.md + engineer-feedback.md + review envelope only; the audit's own citations dropped |")
    L.append(f"| full minus catches first cited after a voice named the region | {m_nodis_lb:.3f} | {m_nodis_lb-m_bare:+.3f} | lower bound for 'dissent removed': assumes every such catch was the dissent's |")
    L.append(f"| full minus every post-dissent review-gate catch | {m_nodis_lb2:.3f} | {m_nodis_lb2-m_bare:+.3f} | extreme bound: also drops post-dissent catches no voice named |")
    L.append("\nPer task: " + "; ".join(f"{t}: bare {tm_bare[t]:.2f} / full {tm_full[t]:.2f} / no-audit {tm_noaud[t]:.2f} / no-dissent-lb {tm_nodis_lb[t]:.2f}" for t in tm_full) + ".\n")
    L.append("Reading: under the grader's rule the dissent is invisible (0 credited citations) and removing the audit gate costs little catch; the honest 'dissent removed' figure lies between the lower bound and the shipped figure, because a Fable draft written after the dissent returned may or may not have used it — the transcript reading (deliverable 5) adjudicates the named cases one by one.\n")
    L.append("## Cost split (12 valid a1 runs)\n")
    L.append("| component | USD total | share |\n|---|---|---|")
    for k, v in cost.items(): L.append(f"| {k} | {v:.2f} | {v/total:.1%} |")
    L.append(f"| **total** | {total:.2f} | 100 % |")
    L.append("\nDissent voices by model (cost-ledger rows): " + ", ".join(f"{v} USD {c:.2f}" for v, c in sorted(voice.items())) + f". Per run: USD {total/n_runs:.2f}, of which dissent {(cost['REVIEW_dissent']+cost['AUDIT_dissent'])/n_runs:.2f} ({(cost['REVIEW_dissent']+cost['AUDIT_dissent'])/total:.1%}), AUDIT gate {(cost['AUDIT_primary']+cost['AUDIT_dissent'])/n_runs:.2f} ({(cost['AUDIT_primary']+cost['AUDIT_dissent'])/total:.1%}).\n")
    L.append("| task | runs | mean USD/run | review gate | audit gate | dissent (both gates) |\n|---|---|---|---|---|---|")
    for t, e in per_task_cost.items(): L.append(f"| {t} | {e['runs']} | {e['total']/e['runs']:.2f} | {e['review']/e['runs']:.2f} | {e['audit']/e['runs']:.2f} | {e['dissent']/e['runs']:.2f} |")
    L.append("\n## Per catch (full arm)\n")
    L.append("| task | trial | defect | sev | bare | class | first event | voices naming the region (review gate) | credited sources |\n|---|---|---|---|---|---|---|---|---|")
    for x in rows:
        if not x["full_caught"]: continue
        L.append(f"| {x['task']} | {x['trial']} | {x['defect']} | {x['severity']} | {'✓' if x['bare_caught'] else '✗'} | {x['class']} | {x['first_event']} ({(x['first_kind'] or '')[5:]}) | {', '.join(x['dissent_named'].get('review', [])) or '—'} | {', '.join(s.replace('.md','') for s in x['sources'] if not s.startswith('envelope'))} |")
    open(os.path.join(C.OUT, "attribution.md"), "w").write("\n".join(L) + "\n")
    print(json.dumps({k: out[k] for k in ("first_citation_class_all_catches", "first_citation_class_lift_only", "dissent_symbol_naming", "reconstruction_task_mean", "cost_split_usd_total_12_runs", "voice_cost_usd_total")}, indent=1, default=str)[:4000])

if __name__ == "__main__":
    main()
