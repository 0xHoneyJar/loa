"""frontier.py — deliverable 4: catch rate vs USD per PR for bare ×1/×2/×3 (unions of trials), full,
full-without-audit (reconstructed), and the hypothetical 'full with the dissent's cost removed'."""
import itertools, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

def main():
    recs = json.load(open(os.path.join(C.DATA, "runs.json")))
    tasks = ["review-01", "review-02", "review-03", "review-04"]
    a0 = {t: sorted([r for r in recs if r["arm"] == "a0_bare" and r["task"] == t], key=lambda r: r["trial"]) for t in tasks}
    a1 = {t: sorted([r for r in recs if r["arm"] == "a1_full" and r["task"] == t], key=lambda r: r["trial"]) for t in tasks}
    def caught(r): return {k for k, d in r["per_defect"].items() if d["caught"]}
    def review_only(r): return {k for k, d in r["per_defect"].items() if any(s in ("review.md", "engineer-feedback.md") or s.startswith("envelope:review") for s in d["sources"])}
    def phase_cost(r, name, dissent=True):
        return sum(ph["primary_cost_usd"] + (ph["dissent_cost_usd"] if dissent else 0) for ph in r["phases"] if ph["name"] == name)
    configs = {}
    for t in tasks:
        n = len(a0[t][0]["per_defect"]); cfg = {}
        rs = a0[t]
        cfg["bare x1"] = (sum(len(caught(r)) for r in rs) / (3 * n), sum(r["cost_usd"] for r in rs) / 3, sum(r["wall_ms"] for r in rs) / 3)
        pairs = list(itertools.combinations(rs, 2))
        cfg["bare x2 (union)"] = (sum(len(caught(a) | caught(b)) for a, b in pairs) / (len(pairs) * n), 2 * sum(r["cost_usd"] for r in rs) / 3, 2 * sum(r["wall_ms"] for r in rs) / 3)
        cfg["bare x3 (union)"] = (len(set.union(*[caught(r) for r in rs])) / n, sum(r["cost_usd"] for r in rs), sum(r["wall_ms"] for r in rs))
        fs = a1[t]
        cfg["full"] = (sum(len(caught(r)) for r in fs) / (3 * n), sum(r["cost_usd"] for r in fs) / 3, sum(r["wall_ms"] for r in fs) / 3)
        cfg["full without AUDIT gate (reconstructed)"] = (sum(len(review_only(r)) for r in fs) / (3 * n), sum(phase_cost(r, "REVIEW") for r in fs) / 3, sum(ph["wall_ms"] or 0 for r in fs for ph in r["phases"] if ph["name"] == "REVIEW") / 3)
        cfg["full, dissent cost removed (hypothetical)"] = (cfg["full"][0], sum(phase_cost(r, "REVIEW", False) + phase_cost(r, "AUDIT", False) for r in fs) / 3, cfg["full"][2])
        cfg["review gate only, dissent cost removed (hypothetical)"] = (cfg["full without AUDIT gate (reconstructed)"][0], sum(phase_cost(r, "REVIEW", False) for r in fs) / 3, cfg["full without AUDIT gate (reconstructed)"][2])
        cfg["full x2 (union, from the 3 trials)"] = (sum(len(caught(a) | caught(b)) for a, b in itertools.combinations(fs, 2)) / (3 * n), 2 * sum(r["cost_usd"] for r in fs) / 3, 2 * sum(r["wall_ms"] for r in fs) / 3)
        configs[t] = cfg
    names = list(configs[tasks[0]].keys())
    overall = {nm: (sum(configs[t][nm][0] for t in tasks) / 4, sum(configs[t][nm][1] for t in tasks) / 4, sum(configs[t][nm][2] for t in tasks) / 4) for nm in names}
    json.dump({"per_task": configs, "task_mean": overall}, open(os.path.join(C.OUT, "frontier.json"), "w"), indent=1)
    L = ["# Deliverable 4 — cost-effectiveness frontier (suite v2, valid cells)\n",
         "Catch rate = task-mean of the per-PR rate (the report's statistic); USD = mean per PR (per run, or the summed runs for a union). Unions take the defects any of the trials caught. 'Reconstructed' re-applies the grader's rule to a subset of the sources; 'hypothetical' changes only the cost. Script: `scripts/frontier.py` on `data/runs.json`.\n",
         "## Task-mean frontier\n", "| configuration | catch rate | USD per PR | minutes per PR | USD per 0.01 catch over bare x1 |\n|---|---|---|---|---|"]
    b0 = overall["bare x1"]
    for nm in names:
        c, usd, ms = overall[nm]
        eff = "—" if c <= b0[0] + 1e-9 else f"{(usd - b0[1]) / ((c - b0[0]) * 100):.2f}"
        L.append(f"| {nm} | {c:.3f} | {usd:.2f} | {ms/60000:.1f} | {eff} |")
    L.append("\n## Per PR\n")
    for t in tasks:
        L.append(f"### {t} ({C.TASK_PR[t]}, {len(a0[t][0]['per_defect'])} defects)\n")
        L.append("| configuration | catch rate | USD | min |\n|---|---|---|---|")
        for nm in names:
            c, usd, ms = configs[t][nm]
            L.append(f"| {nm} | {c:.3f} | {usd:.2f} | {ms/60000:.1f} |")
        L.append("")
    # ASCII chart: task-mean, x = USD (0..14), y = catch (0.6..0.9)
    L.append("## ASCII chart (task-mean; x = USD per PR, y = catch rate)\n```text")
    pts = sorted(((overall[nm][1], overall[nm][0], nm) for nm in names))
    W, H = 72, 16
    xmax = max(p[0] for p in pts) * 1.05; ymin, ymax = 0.60, 0.92
    grid = [[" "] * W for _ in range(H)]
    labels = {}
    for i, (usd, c, nm) in enumerate(pts):
        x = min(W - 1, int(usd / xmax * (W - 1))); y = min(H - 1, max(0, int((ymax - c) / (ymax - ymin) * (H - 1))))
        grid[y][x] = str(i + 1) if grid[y][x] == " " else "*"
        labels[i + 1] = f"{nm}  ({c:.3f}, USD {usd:.2f})"
    for j, row in enumerate(grid):
        yv = ymax - j * (ymax - ymin) / (H - 1)
        L.append(f"{yv:5.2f} |" + "".join(row))
    L.append("      +" + "-" * W)
    L.append("       0" + " " * (W // 2 - 6) + f"USD per PR" + " " * (W // 2 - 10) + f"{xmax:.0f}")
    for k, v in labels.items(): L.append(f"  {k}: {v}")
    L.append("```\n")
    # cheapest configuration reaching each level
    L.append("## Cheapest configuration reaching each catch-rate level (task-mean)\n")
    L.append("| level | cheapest configuration | USD per PR | measured (not hypothetical) alternative |\n|---|---|---|---|")
    measured = {"bare x1", "bare x2 (union)", "bare x3 (union)", "full", "full without AUDIT gate (reconstructed)", "full x2 (union, from the 3 trials)"}
    for level in (0.65, 0.70, 0.75, 0.80, 0.85, 0.90):
        ok = sorted(((overall[nm][1], nm) for nm in names if overall[nm][0] >= level - 1e-9))
        okm = sorted(((overall[nm][1], nm) for nm in measured if overall[nm][0] >= level - 1e-9))
        L.append(f"| ≥ {level:.2f} | {ok[0][1] if ok else 'none'} | {ok[0][0]:.2f} | {okm[0][1] + f' (USD {okm[0][0]:.2f})' if okm else 'none'} |" if ok else f"| ≥ {level:.2f} | none | — | none |")
    L.append("\nReading: three bare passes (USD 2.11) reach 0.744; the full pipeline (USD 11.64) reaches 0.854 and nothing cheaper reaches 0.80 in this data. The reconstructed review gate alone keeps most of full's catch for about 55 % of its cost; the dissent's own cost is a quarter of a full run and buys no grader-credited citation (deliverable 2). On the two small PRs every configuration saturates, so the frontier is really drawn by pr-12 and pr-13.\n")
    open(os.path.join(C.OUT, "frontier.md"), "w").write("\n".join(L) + "\n")
    for nm in names: print(f"{nm:55s} catch {overall[nm][0]:.3f} USD {overall[nm][1]:6.2f} min {overall[nm][2]/60000:5.1f}")

if __name__ == "__main__":
    main()
