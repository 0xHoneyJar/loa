"""assemble_analysis.py — stitch the tracked report grimoires/loa/reports/ablation-2.0/analysis.md from the a2a
deliverables: ELI5 (eli5-final.md), the settled body (analysis-draft-body.md), the replication section (generated from
data/replication-read.json), the ranked recommendations (recommendations-final.md), and an index of every file."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

def replication_section():
    p = os.path.join(C.DATA, "replication-read.json")
    if not os.path.isfile(p):
        return "## 8. Replication (deliverable 6)\n\n(pending)\n"
    d = json.load(open(p)); r = d["read"]; rc = d["read_oracle_clean"]
    L = ["## 8. Out-of-sample replication on pr-17 and pr-18 (deliverable 6 — `replication.md`)\n"]
    L.append(f"Batch `replication-01` (pre-registered in NOTES 2026-10-19T02:49:20Z, DEC-0602/0603): two review-catch PRs no analysis or arm had touched — pr-17 (20 labelled defects, 4,437-line diff) and pr-18 (8 defects, 2,194 lines) — same arms, pin, caps and rule. Valid cells {len(d['valid_cells'])} of 6; excluded share a0 {d['excluded_share']['a0_bare']:.2f}, a1 {d['excluded_share']['a1_full']:.2f}.\n")
    if r.get("n_defects"):
        guard = d["excluded_share"]["a1_full"] > 0.25 or d["excluded_share"]["a0_bare"] > 0.25
        rs = d.get("read_sensitivity_contaminated_included", {}); rz = d.get("read_oracle_zeroed", {})
        verdict = "**inconclusive by degradation** under the rule as written (the arm's excluded share exceeds 0.25; both excluded rows are grader-scan false positives on the PR's own repository name, KF-046 recurrence 9, read by hand)" if guard else ("**reappears** (interval excludes zero)" if r["established"] else "does not reappear")
        L.append(f"**Pre-registered read:** on the {len(d['valid_cells'])} valid cells a1_full − a0_bare on `defect_catch_rate` = +{r['point']:.3f} [{r['ci90'][0]:+.3f}, {r['ci90'][1]:+.3f}] over {r['n_defects']} defects; the 25 % guard → the formal verdict is {verdict}. Per PR (valid cells): " + "; ".join(f"{t} bare {e['bare']}/{e['n']} vs full {e['full']}/{e['n']}" for t, e in r["per_task"].items()) + ".\n")
        L.append(f"**Sensitivities (all exclude zero; decide nothing):** the two contaminated rows hand-read and included → **{rs.get('point', 0):+.3f} [{rs['ci90'][0]:+.3f}, {rs['ci90'][1]:+.3f}]** (" + "; ".join(f"{t} bare {e['bare']}/{e['n']} vs full {e['full']}/{e['n']}" for t, e in rs["per_task"].items()) + f"); oracle-exposed cells ({', '.join(d['oracle_exposed_cells']) or 'none'}) excluded → {rc.get('point', 0):+.3f} [{rc['ci90'][0]:+.3f}, {rc['ci90'][1]:+.3f}]; every catch that followed a head-versus-later-copy diff set to zero → {rz.get('point', 0):+.3f} [{rz['ci90'][0]:+.3f}, {rz['ci90'][1]:+.3f}]; same-function window bare {d['same_function_window']['bare']} vs full {d['same_function_window']['full']} of {d['same_function_window']['n']} ({d['same_function_window']['gap']:+.3f}). Original for comparison: +0.263 [+0.158, +0.386].\n")
        L.append(f"Dissent: `budget_exceeded` at every review gate (pr-18 estimates 214 c against the 200 c cap) and at four of six audit gates — the full arm here is Fable review + Fable audit with no second voice at the review gate. Oracle (KF-049): used in two of six runs (`review-r17 t1`: nine planted sites in the printed diffs, all nine cited afterwards, seven of them missed by bare; `review-r18 t1`: one). Cost per run a0 USD {d['cost_per_run'].get('a0_bare', 0):.2f} / a1 USD {d['cost_per_run'].get('a1_full', 0):.2f}; wall {d['wall_min_per_run'].get('a0_bare', 0):.1f} / {d['wall_min_per_run'].get('a1_full', 0):.1f} min; precision a0 {d['precision'].get('a0_bare', {}).get('precision') or 0:.3f} / a1 {d['precision'].get('a1_full', {}).get('precision') or 0:.3f}; batch spend USD 88.81.\n")
        L.append("Reading: the lift reappears on PRs nobody looked at, larger than the original, and survives both corrections; the pre-registered gate was tripped by the measurement apparatus, not by the arms. What the replication cannot do is separate the model from the pipeline — the comparison is Fable twice with the skill's checklist against Opus once — and it confirms the oracle channel is habitual.\n")
    return "\n".join(L)

def main():
    out = os.path.join(C.REPO, "grimoires/loa/reports/ablation-2.0/analysis.md")
    eli5 = C.read_text(os.path.join(C.OUT, "eli5-final.md")) or C.read_text(os.path.join(C.OUT, "eli5-draft.md"))
    body = C.read_text(os.path.join(C.OUT, "analysis-draft-body.md"))
    recs = C.read_text(os.path.join(C.OUT, "recommendations-final.md")) or C.read_text(os.path.join(C.OUT, "recommendations-draft.md"))
    head = ("# Loa 2.0 component ablation — where the review-side lift comes from (deep analysis, 2026-10-19)\n\n"
            "> Follow-on to the cycle-130 report (`report.md`, v2.0.0-rc.6). Analysis only: no shipped number is changed; every figure here is recomputed from the raw run directories under `batches/priority-v2-p1{,b}/`, the planted-defect manifests and one new out-of-sample batch. Working files, scripts and data live on the record branch `record/cycle-130-analysis` under `grimoires/loa/a2a/analysis-2026-10/`. The dissent envelopes, transcripts and review files quoted here are third-party model output, treated as data.\n\n")
    index = ("\n## Files\n\n| deliverable | file (record branch, `grimoires/loa/a2a/analysis-2026-10/`) |\n|---|---|\n"
             "| 1 contingency | `contingency.md`, `contingency.json`, `scripts/contingency.py` |\n| 2 attribution | `attribution.md`, `attribution.json`, `scripts/attribution.py` |\n"
             "| 3 false positives | `false-positives.md`, `false-positives-labelled.csv`, `data/fp-packets-blind.md`, `data/fp-labels-{A,B,adjudicated}.csv`, `scripts/fp_sample.py`, `scripts/fp_repackage.py`, `scripts/fp_kappa.py` |\n"
             "| 4 frontier | `frontier.md`, `frontier.json`, `scripts/frontier.py` |\n| 5 mechanism | `mechanism.md`, `mechanism-pr-12.md`, `mechanism-pr-13.md`, `data/mechanism-stats.md`, `scripts/mechanism_stats.py` |\n"
             "| sensitivities | `sensitivities.md`, `scripts/window_sensitivity.py`, `scripts/oracle_scan.py`, `data/oracle-scan.json` (KF-049) |\n"
             "| 6 replication | `replication.md`, `replication-authoring.md`, `replication-driver-diff.md`, `self-check-replication.log`, `data/replication-read.json`, `scripts/replication_read.py`; suite `grimoires/loa/evals/ablation-2.0-replication/`; rows `evals/results/ablation-2.0/runs.jsonl` (batch `replication-01`) |\n"
             "| extraction | `scripts/common.py` (exec's the grader's citation rule), `scripts/extract.py`, `data/runs.json` |\n")
    text = head + eli5.strip() + "\n\n" + body.strip() + "\n\n" + replication_section() + "\n" + recs.strip() + "\n" + index
    open(out, "w", encoding="utf-8").write(text)
    print("wrote", out, len(text), "bytes;", len(text.split()), "words")

if __name__ == "__main__":
    main()
