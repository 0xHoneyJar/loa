"""adjudicate.py — cycle-131 Task 1.10 read (python3 -I, stdlib): Cohen's kappa over the two labelers' three-way labels,
the group-(a) adoption share with a Wilson 95 % interval, the group-(b) share (reported, decides nothing), and the list of
disagreements for the third labeler when kappa < 0.6. Rule (pre-registered 2026-10-19T06:08:48Z): adopt the same-scope rule iff
>= 80 % of the (a) packets (denominator: all (a) packets sampled) are `labelled` by the final labels."""
import json, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
KEY = os.path.expanduser("~/.cache/loa/cycle-131/adjudication-key.json")
LABELS = ("labelled", "different", "unclear")

def read_tsv(p):
    out = {}
    for ln in open(p, encoding="utf-8"):
        ln = ln.rstrip("\n")
        if not ln.strip() or ln.startswith("#"): continue
        parts = ln.split("\t")
        if len(parts) < 2: raise SystemExit(f"bad row in {p}: {ln!r}")
        pid, lab = parts[0].strip(), parts[1].strip().lower()
        if lab not in LABELS: raise SystemExit(f"bad label in {p}: {ln!r}")
        out[pid] = (lab, parts[2].strip() if len(parts) > 2 else "")
    return out

def kappa(a, b, ids):
    n = len(ids)
    po = sum(1 for i in ids if a[i][0] == b[i][0]) / n
    pe = sum((sum(1 for i in ids if a[i][0] == l) / n) * (sum(1 for i in ids if b[i][0] == l) / n) for l in LABELS)
    return 1.0 if pe == 1 else (po - pe) / (1 - pe), po

def wilson(k, n, z=1.959964):
    if n == 0: return (float("nan"), float("nan"))
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d; h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))

def main(labeler_files, final=None):
    key = json.load(open(KEY)); grp = {k["packet_id"]: k["group"] for k in key["key"]}
    ids = sorted(grp)
    labs = [read_tsv(os.path.join(HERE, f)) for f in labeler_files]
    for L, f in zip(labs, labeler_files):
        missing = [i for i in ids if i not in L]
        if missing: raise SystemExit(f"{f} lacks {missing}")
    k, po = kappa(labs[0], labs[1], ids)
    print(f"packets {len(ids)} (a={sum(1 for i in ids if grp[i]=='a')}, b={sum(1 for i in ids if grp[i]=='b')}); labelers {labeler_files[0]} vs {labeler_files[1]}: agreement {po:.3f}, Cohen's kappa {k:.3f}")
    dis = [i for i in ids if labs[0][i][0] != labs[1][i][0]]
    print("disagreements:", ", ".join(f"{i}({grp[i]}): {labs[0][i][0]} / {labs[1][i][0]}" for i in dis) or "none")
    if final:
        F = read_tsv(os.path.join(HERE, final)); fl = {i: F[i][0] for i in ids}
        src = f"final labels from {final}"
    elif len(labs) >= 3:
        fl = {}
        for i in ids:
            votes = [L[i][0] for L in labs]
            fl[i] = max(LABELS, key=lambda l: (votes.count(l), -LABELS.index(l))) if max(votes.count(l) for l in LABELS) >= 2 else "unclear"
        src = "final labels by majority of three"
    else:
        fl = {i: (labs[0][i][0] if labs[0][i][0] == labs[1][i][0] else None) for i in ids}
        src = "final labels = agreements (disagreements pending)"
    print(src)
    for g in ("a", "b"):
        gi = [i for i in ids if grp[i] == g]; n = len(gi)
        kk = sum(1 for i in gi if fl[i] == "labelled"); pend = sum(1 for i in gi if fl[i] is None)
        lo, hi = wilson(kk, n)
        print(f"group ({g}): n={n}, labelled={kk}, different={sum(1 for i in gi if fl[i]=='different')}, unclear={sum(1 for i in gi if fl[i]=='unclear')}, pending={pend}; share {kk/n if n else float('nan'):.3f} Wilson95 [{lo:.3f}, {hi:.3f}]")
        if g == "a":
            dec = "ADOPT the same-scope rule (recall stays the decision statistic)" if (pend == 0 and n and kk / n >= 0.8) else ("NOT adopted (recall_pm3 becomes the decision statistic)" if pend == 0 else "pending")
            print(f"adoption rule (>= 80 % of (a) labelled): {dec}; kappa floor 0.6 {'met' if k >= 0.6 else 'NOT met -> third labeler'}")
    print("\nper packet: id group L1 L2 final")
    for i in ids: print(i, grp[i], labs[0][i][0], labs[1][i][0], fl[i])

if __name__ == "__main__":
    args = sys.argv[1:]
    main(args[:3] if len(args) >= 2 else ["labels-L1.tsv", "labels-L2.tsv"], final=(args[3] if len(args) > 3 else None))
