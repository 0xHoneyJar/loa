"""fp_kappa.py — deliverable 3: agreement between the two blind labelers (Cohen's kappa, 4-way and 3-way),
the lead's adjudication of disagreements (data/fp-labels-adjudicated.csv when present), and the corrected
precision per arm: planted catches + the estimated share of 'real' flagged regions, extrapolated per stratum
(arm × PR) from the sample to the full false-positive universe, with a within-stratum bootstrap interval."""
import csv, json, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

LABELS = ["real", "style", "wrong", "not-a-finding"]
SEED, B = 20261015, 10000

def read_labels(path):
    out = {}
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            pid = (row.get("packet_id") or "").strip()
            lab = (row.get("label") or "").strip().lower().replace("not_a_finding", "not-a-finding").replace("notafinding", "not-a-finding")
            if pid and lab in LABELS:
                out[pid] = {"label": lab, "confidence": (row.get("confidence") or "").strip(), "note": (row.get("note") or "").strip()}
    return out

def kappa(a, b, labels):
    ids = sorted(set(a) & set(b))
    n = len(ids)
    if n == 0: return None, 0, 0
    agree = sum(1 for i in ids if a[i] == b[i])
    po = agree / n
    pe = sum((sum(1 for i in ids if a[i] == l) / n) * (sum(1 for i in ids if b[i] == l) / n) for l in labels)
    k = (po - pe) / (1 - pe) if pe < 1 else 1.0
    return k, agree, n

def main():
    sample = json.load(open(os.path.join(C.DATA, "fp-sample.json")))
    recs = json.load(open(os.path.join(C.DATA, "runs.json")))
    A = read_labels(os.path.join(C.DATA, "fp-labels-A.csv")); Bl = read_labels(os.path.join(C.DATA, "fp-labels-B.csv"))
    adj_path = os.path.join(C.DATA, "fp-labels-adjudicated.csv")
    ADJ = read_labels(adj_path) if os.path.isfile(adj_path) else {}
    la = {k: v["label"] for k, v in A.items()}; lb = {k: v["label"] for k, v in Bl.items()}
    k4, agree4, n4 = kappa(la, lb, LABELS)
    # 3-way: collapse not-a-finding into style (neither is a defect claim at this location)
    col = lambda l: "style" if l == "not-a-finding" else l
    k3, agree3, n3 = kappa({k: col(v) for k, v in la.items()}, {k: col(v) for k, v in lb.items()}, ["real", "style", "wrong"])
    # binary real vs not
    kb, agreeb, nb = kappa({k: (v == "real") for k, v in la.items()}, {k: (v == "real") for k, v in lb.items()}, [True, False])
    # final labels: adjudicated where present, else agreed label, else None
    final = {}
    for p in sample:
        pid = p["packet_id"]
        if pid in ADJ: final[pid] = ADJ[pid]["label"]
        elif pid in la and pid in lb and la[pid] == lb[pid]: final[pid] = la[pid]
        else: final[pid] = None
    disagreements = [p for p in sample if p["packet_id"] in la and p["packet_id"] in lb and la[p["packet_id"]] != lb[p["packet_id"]]]
    # universe of FP regions per stratum and the planted catches per arm
    strata_n = {}
    planted = {"a0_bare": 0, "a1_full": 0}; flagged = {"a0_bare": 0, "a1_full": 0}
    for r in recs:
        strata_n[(r["arm"], r["pr"])] = strata_n.get((r["arm"], r["pr"]), 0) + r["n_stray_regions"]
        planted[r["arm"]] += r["grade"]["caught"]; flagged[r["arm"]] += r["grade"]["flags"]
    def precision(labelset, rnd=None):
        """corrected precision per arm from a per-packet label map; rnd → one bootstrap resample within strata"""
        out = {}
        for arm in ("a0_bare", "a1_full"):
            real_est = 0.0; nf_est = 0.0
            for pr in ("pr-05", "pr-08", "pr-12", "pr-13"):
                pk = [p for p in sample if p["arm"] == arm and p["pr"] == pr and labelset.get(p["packet_id"]) is not None]
                if not pk: continue
                if rnd is not None: pk = [pk[rnd.randrange(len(pk))] for _ in pk]
                share_real = sum(1 for p in pk if labelset[p["packet_id"]] == "real") / len(pk)
                share_nf = sum(1 for p in pk if labelset[p["packet_id"]] == "not-a-finding") / len(pk)
                real_est += share_real * strata_n[(arm, pr)]; nf_est += share_nf * strata_n[(arm, pr)]
            fp_total = sum(v for (a, _), v in strata_n.items() if a == arm)
            out[arm] = {"planted_caught": planted[arm], "flagged": flagged[arm], "fp_regions": fp_total, "grader_precision": planted[arm] / flagged[arm],
                        "est_real_unplanted": real_est, "est_not_a_finding": nf_est,
                        "corrected_precision": (planted[arm] + real_est) / flagged[arm],
                        "corrected_precision_excluding_cross_refs": (planted[arm] + real_est) / max(1, flagged[arm] - nf_est)}
        return out
    results = {}
    for name, ls in (("labeler_A", la), ("labeler_B", lb), ("final", final)):
        pt = precision(ls)
        rnd = random.Random(SEED); boots = {a: [] for a in pt}
        for _ in range(B):
            pb = precision(ls, rnd)
            for a in pt: boots[a].append(pb[a]["corrected_precision"])
        for a in pt:
            v = sorted(boots[a]); pt[a]["corrected_precision_ci90"] = [v[int(0.05 * B)], v[int(0.95 * B) - 1]]
        results[name] = pt
    # label distributions
    def dist(ls, pred=lambda p: True):
        d = {l: 0 for l in LABELS}
        for p in sample:
            if pred(p) and ls.get(p["packet_id"]) in d: d[ls[p["packet_id"]]] += 1
        return d
    by_arm = {arm: {"A": dist(la, lambda p, a=arm: p["arm"] == a), "B": dist(lb, lambda p, a=arm: p["arm"] == a), "final": dist(final, lambda p, a=arm: p["arm"] == a)} for arm in ("a0_bare", "a1_full")}
    by_pr = {pr: dist(final, lambda p, q=pr: p["pr"] == q) for pr in ("pr-05", "pr-08", "pr-12", "pr-13")}
    near = [p for p in sample if p["near_planted"] and final.get(p["packet_id"]) == "real"]
    out = {"n_packets": len(sample), "labelled_A": len(la), "labelled_B": len(lb), "adjudicated": len(ADJ),
           "kappa_4way": {"kappa": k4, "agree": agree4, "n": n4}, "kappa_3way_collapsed": {"kappa": k3, "agree": agree3, "n": n3}, "kappa_real_vs_not": {"kappa": kb, "agree": agreeb, "n": nb},
           "disagreements": [{"packet_id": p["packet_id"], "arm": p["arm"], "pr": p["pr"], "file": p["file"], "lines": p["lines"], "A": la.get(p["packet_id"]), "B": lb.get(p["packet_id"]), "final": final.get(p["packet_id"]), "note_A": A.get(p["packet_id"], {}).get("note"), "note_B": Bl.get(p["packet_id"], {}).get("note")} for p in disagreements],
           "label_distribution_by_arm": by_arm, "final_distribution_by_pr": by_pr, "fp_universe_by_stratum": {f"{a}|{p}": v for (a, p), v in sorted(strata_n.items())},
           "precision": results, "real_near_planted": [{"packet_id": p["packet_id"], "arm": p["arm"], "file": p["file"], "lines": p["lines"], "near": p["near_planted"]} for p in near],
           "unresolved": [p["packet_id"] for p in sample if final.get(p["packet_id"]) is None]}
    json.dump(out, open(os.path.join(C.OUT, "false-positives.json"), "w"), indent=1)
    # the labelled CSV (lead copy with provenance)
    with open(os.path.join(C.OUT, "false-positives-labelled.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f); w.writerow(["packet_id", "arm", "pr", "run_id", "file", "lines", "in_diff", "sources", "label_A", "conf_A", "note_A", "label_B", "conf_B", "note_B", "final", "near_planted"])
        for p in sample:
            pid = p["packet_id"]
            w.writerow([pid, p["arm"], p["pr"], p["run_id"], p["file"], f"{p['lines'][0]}-{p['lines'][1]}", p["region_in_diff"], ";".join(p["sources"]),
                        A.get(pid, {}).get("label"), A.get(pid, {}).get("confidence"), A.get(pid, {}).get("note"),
                        Bl.get(pid, {}).get("label"), Bl.get(pid, {}).get("confidence"), Bl.get(pid, {}).get("note"), final.get(pid),
                        ";".join(f"{x['defect']}@{x['site']}(d={x['distance']}{',same-fn' if x['same_symbol'] else ''})" for x in p["near_planted"])])
    print(json.dumps({k: out[k] for k in ("n_packets", "labelled_A", "labelled_B", "adjudicated", "kappa_4way", "kappa_3way_collapsed", "kappa_real_vs_not", "label_distribution_by_arm", "unresolved")}, indent=1))
    for name, pt in results.items():
        for a, e in pt.items():
            print(f"{name:10s} {a}: grader precision {e['grader_precision']:.3f} → corrected {e['corrected_precision']:.3f} [{e['corrected_precision_ci90'][0]:.3f}, {e['corrected_precision_ci90'][1]:.3f}] (real unplanted ≈ {e['est_real_unplanted']:.0f} of {e['fp_regions']} FP regions; cross-refs ≈ {e['est_not_a_finding']:.0f}); excluding cross-refs {e['corrected_precision_excluding_cross_refs']:.3f}")
    print(f"disagreements: {len(disagreements)}; real near a planted site: {len(near)}")

if __name__ == "__main__":
    main()
