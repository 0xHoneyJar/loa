#!/usr/bin/env python3
"""arms-report.py — the cycle-129 FR-2 control-arm report (SDD D-2.3).

Invoked by `report.sh --arms`. Reads <results-root>/<suite>/STATUS.json (the
suite aggregate run-arms.sh writes), every batch's MANIFEST.json and
<arm>/results.jsonl, and the suite's pre-registered `ab.threshold` and
`ab.arms`, and writes one markdown report.

Per arm: recall (mean over defect fixtures of the per-fixture trial mean;
the min, max and spread of the per-trial means), refuted share (cited
findings matching neither a feedback label nor a fix region, over cited
findings, pooled over completed trials), tokens per call, the percentile
bootstrap interval of the recall drop (baseline - arm) resampling fixtures,
the verdict and the missed labels.

Verdict (pre-registered; never computed for baseline):
  inconclusive  --partial; the run is not complete; a planned fixture lacks
                trials_required completed trials in the arm or the baseline;
                model or source skew; no defect fixture; or only a recall
                rule is violated while the mean drop does not exceed the
                baseline's own trial-to-trial spread (a change too small to name)
  recall loss   the refuted-share rule is violated, or a recall rule is
                violated and the mean drop exceeds the baseline spread
  no recall loss  every rule holds:
                  upper bound of the drop interval <= mean_recall_max_drop
                  arm min trial mean >= baseline min trial mean - min_trial_recall_max_drop
                  arm refuted share <= baseline refuted share + refuted_share_max_rise
An `informational: true` arm's verdict reports a yield only.

Exit: 0 written, 1 refused (a suite is not complete and --partial was not
given), 2 error. Stdlib only.
"""
import argparse
import datetime
import json
import os
import random
import sys
from collections import Counter, defaultdict


def load_yaml_subset(path):
    """The suites are YAML (no stdlib parser); the harness already depends on yq v4."""
    import subprocess
    out = subprocess.run(["yq", "-o=json", ".", path], check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def read_jsonl(path):
    rows = []
    if not os.path.isfile(path):
        return rows
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    continue
    return rows


def mean(xs):
    xs = [x for x in xs if x is not None]
    return sum(xs) / len(xs) if xs else None


def fmt(x, nd=3):
    return "n/a" if x is None else f"{x:.{nd}f}"


def recall_details(row):
    for g in row.get("graders") or []:
        if g.get("name") == "recall-vs-defects.sh" and isinstance(g.get("details"), dict):
            return g["details"]
    return None


def tokens(row):
    u = (row.get("executor") or {}).get("usage") or {}
    if not u:
        return None
    return sum(int(u.get(k, 0) or 0) for k in
               ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"))


def percentile(sorted_xs, q):
    if not sorted_xs:
        return None
    k = max(0, min(len(sorted_xs) - 1, int(round(q * (len(sorted_xs) - 1)))))
    return sorted_xs[k]


def bootstrap(deltas, iterations, level, seed):
    """Percentile bootstrap of the mean of per-fixture deltas (resample fixtures)."""
    if not deltas:
        return None, None
    rng = random.Random(seed)
    n = len(deltas)
    means = sorted(sum(deltas[rng.randrange(n)] for _ in range(n)) / n for _ in range(iterations))
    a = (1.0 - level) / 2.0
    return percentile(means, a), percentile(means, 1.0 - a)


class Arm:
    def __init__(self, arm_id):
        self.id = arm_id
        self.cells = defaultdict(list)   # fixture -> [(trial, recall)], every completed trial kept
        self.planted = {}                # fixture -> planted count
        self.cited = 0
        self.refuted = 0
        self.tokens = []
        self.models = set()
        self.sources = set()
        self.done = 0
        self.errors = 0
        self.fallback_trials = 0         # trials the CLI moved to another model on a safeguard refusal
        self.fallback_kinds = Counter()
        self.missed = Counter()          # (fixture, label) -> trials missed
        self.seen = Counter()            # (fixture, label) -> trials graded

    def add(self, row):
        if row.get("status") != "completed":
            self.errors += 1
            return
        d = recall_details(row)
        if d is None:
            self.errors += 1
            return
        self.done += 1
        fx = row.get("fixture") or row.get("task_id", "").split("-", 1)[-1]
        self.planted[fx] = int(d.get("planted") or 0)
        if d.get("recall") is not None:
            self.cells[fx].append((int(row.get("trial") or 0), float(d["recall"])))
        if d.get("findings_cited") is not None:
            self.cited += int(d.get("findings_cited") or 0)
            self.refuted += int(d.get("findings_refuted") or 0)
        t = tokens(row)
        if t is not None:
            self.tokens.append(t)
        self.models.add(row.get("model_id") or (row.get("executor") or {}).get("model_id"))
        # every model that produced output in the call (an auxiliary model is skew too)
        for mid, out in ((row.get("executor") or {}).get("models_used") or {}).items():
            if out:
                self.models.add(mid)
        fb = (row.get("executor") or {}).get("refusal_fallbacks") or []
        if fb:
            self.fallback_trials += 1
            for x in fb:
                self.fallback_kinds[f"{x.get('from')}→{x.get('to')} ({x.get('category')})"] += 1
        self.sources.add(row.get("source_commit") or (row.get("executor") or {}).get("source_commit"))
        for lbl in d.get("missed") or []:
            self.missed[(fx, lbl)] += 1
            self.seen[(fx, lbl)] += 1
        for lbl in d.get("detected") or []:
            self.seen[(fx, lbl)] += 1

    def defect_fixtures(self):
        return sorted(f for f, p in self.planted.items() if p > 0 and self.cells.get(f))

    def fixture_means(self):
        return {f: mean([r for _t, r in self.cells[f]]) for f in self.defect_fixtures()}

    def trial_means(self):
        by_trial = defaultdict(list)
        for f in self.defect_fixtures():
            for t, r in self.cells[f]:
                by_trial[t].append(r)
        return {t: mean(v) for t, v in sorted(by_trial.items())}

    def refuted_share(self):
        return self.refuted / self.cited if self.cited else None


def suite_report(root, suites_dir, suite, partial, out_lines):
    sdir = os.path.join(root, suite)
    status = {}
    sp = os.path.join(sdir, "STATUS.json")
    if os.path.isfile(sp):
        status = json.load(open(sp, encoding="utf-8"))
    spec = load_yaml_subset(os.path.join(suites_dir, f"{suite}.yaml"))
    ab = spec.get("ab") or {}
    th = ab.get("threshold") or {}
    arm_meta = {a["id"]: a for a in ab.get("arms") or []}
    trials_required = int(th.get("trials_required", 3))
    max_drop = float(th.get("mean_recall_max_drop", 0.10))
    min_trial_drop = float(th.get("min_trial_recall_max_drop", 0.15))
    refuted_rise = float(th.get("refuted_share_max_rise", 0.10))
    bs = th.get("bootstrap") or {}
    iterations = int(bs.get("iterations", 2000))
    level = float(bs.get("level", 0.90))

    planned_fx, planned_arms, manifests = set(), [], []
    arms = {}
    for batch in sorted(os.listdir(sdir)) if os.path.isdir(sdir) else []:
        bdir = os.path.join(sdir, batch)
        mp = os.path.join(bdir, "MANIFEST.json")
        if not os.path.isfile(mp):
            continue
        m = json.load(open(mp, encoding="utf-8"))
        if m.get("dry_run"):
            continue
        manifests.append(m)
        planned_fx.update(m.get("fixtures") or [])
        for a in m.get("arms") or []:
            if a not in planned_arms:
                planned_arms.append(a)
            arm = arms.setdefault(a, Arm(a))
            for row in read_jsonl(os.path.join(bdir, a, "results.jsonl")):
                arm.add(row)
    order = [a for a in arm_meta if a in arms] + [a for a in planned_arms if a not in arm_meta]
    state = status.get("state", "unknown")
    complete = state == "complete"

    out_lines.append(f"## {suite}")
    out_lines.append("")
    out_lines.append(f"- STATUS: `{state}`; batches: {', '.join(b.get('batch', '?') for b in status.get('batches', [])) or 'none'}")
    srcs = sorted({m.get('source_commit') for m in manifests})
    models = sorted({m.get('model_id') for m in manifests})
    out_lines.append(f"- source commit(s): {', '.join(f'`{s[:12]}`' for s in srcs if s) or 'n/a'}; executor model requested: {', '.join(f'`{x}`' for x in models if x) or 'n/a'}")
    out_lines.append(f"- planned fixtures ({len(planned_fx)}): {', '.join(sorted(planned_fx)) or 'none'}")
    out_lines.append(f"- threshold: trials_required {trials_required}, mean_recall_max_drop {max_drop}, "
                     f"min_trial_recall_max_drop {min_trial_drop}, refuted_share_max_rise {refuted_rise}, "
                     f"bootstrap {bs.get('method', 'percentile')} {level} over {bs.get('resample', 'fixtures')} x{iterations}")
    out_lines.append("")

    base = arms.get("baseline")
    base_fm = base.fixture_means() if base else {}
    base_tm = base.trial_means() if base else {}
    base_spread = (max(base_tm.values()) - min(base_tm.values())) if base_tm else None
    base_min = min(base_tm.values()) if base_tm else None
    base_ref = base.refuted_share() if base else None

    def coverage_gaps(arm):
        gaps = []
        for fx in sorted(planned_fx):
            planted = arm.planted.get(fx)
            n = len(arm.cells.get(fx, [])) if planted else 0
            if planted == 0:
                continue  # a clean fixture carries no recall; refuted share only
            if n < trials_required:
                gaps.append(f"{fx} {n}/{trials_required}")
        return gaps

    header = ("| arm | trials done | errors | mean recall | min | max | spread | drop vs baseline | "
              f"{int(level * 100)}% CI of drop | refuted share | tokens/call | verdict |")
    out_lines.append(header)
    out_lines.append("|" + "---|" * 12)
    details = []
    verdicts = {}
    for a in order:
        arm = arms[a]
        fm = arm.fixture_means()
        tm = arm.trial_means()
        m = mean(list(fm.values()))
        mn = min(tm.values()) if tm else None
        mx = max(tm.values()) if tm else None
        spread = (mx - mn) if tm else None
        rs = arm.refuted_share()
        tok = mean(arm.tokens)
        drop = lo = hi = None
        reasons = []
        if a == "baseline":
            verdict = "(reference)"
        else:
            common = sorted(set(fm) & set(base_fm))
            deltas = [base_fm[f] - fm[f] for f in common]
            drop = mean(deltas)
            lo, hi = bootstrap(deltas, iterations, level, f"{suite}:{a}")
            if partial:
                reasons.append("--partial report")
            if not complete:
                reasons.append(f"run state is {state}")
            if base is None:
                reasons.append("no baseline arm")
            gaps = coverage_gaps(arm) + ([f"baseline {g}" for g in coverage_gaps(base)] if base else [])
            if gaps:
                reasons.append("coverage: " + ", ".join(gaps[:8]) + (" …" if len(gaps) > 8 else ""))
            mods = {x for x in arm.models | (base.models if base else set()) if x}
            if len(mods) > 1:
                reasons.append("model skew: " + ", ".join(sorted(mods)))
            srcs_a = {x for x in arm.sources | (base.sources if base else set()) if x}
            if len(srcs_a) > 1:
                reasons.append("source skew: " + ", ".join(sorted(s[:12] for s in srcs_a)))
            if not deltas:
                reasons.append("no defect fixture graded in both arms")
            if reasons:
                verdict = "inconclusive"
            else:
                violated, refuted_violated = [], False
                if hi is None or hi > max_drop:
                    violated.append(f"drop CI upper {fmt(hi)} > {max_drop}")
                if mn is None or base_min is None or mn < base_min - min_trial_drop:
                    violated.append(f"min trial {fmt(mn)} < baseline min {fmt(base_min)} - {min_trial_drop}")
                if rs is not None and base_ref is not None and rs > base_ref + refuted_rise:
                    violated.append(f"refuted share {fmt(rs)} > baseline {fmt(base_ref)} + {refuted_rise}")
                    refuted_violated = True
                if not violated:
                    verdict = "no recall loss"
                elif (not refuted_violated and drop is not None and base_spread is not None
                      and abs(drop) <= base_spread):
                    # only recall rules failed and the mean moved less than the
                    # baseline moves against itself: too small a change to name
                    verdict = "inconclusive"
                    reasons.append("rule violated (" + "; ".join(violated) + f") but |drop| {fmt(abs(drop))} "
                                   f"<= baseline spread {fmt(base_spread)}: no change can be named")
                else:
                    verdict = "recall loss"
                    reasons.extend(violated)
            if (arm_meta.get(a) or {}).get("informational"):
                verdict += " (informational: yield only)"
        verdicts[a] = verdict
        out_lines.append(
            f"| `{a}` | {arm.done} | {arm.errors} | {fmt(m)} | {fmt(mn)} | {fmt(mx)} | {fmt(spread)} | "
            f"{fmt(drop)} | {('[' + fmt(lo) + ', ' + fmt(hi) + ']') if lo is not None else 'n/a'} | "
            f"{fmt(rs)} | {('%.0f' % tok) if tok is not None else 'n/a'} | **{verdict}** |")
        if arm.fallback_trials:
            reasons.append(f"{arm.fallback_trials}/{arm.done} trial(s) fell back to another model on a safeguard refusal: "
                           + ", ".join(f"{k} x{n}" for k, n in arm.fallback_kinds.most_common()))
        if reasons:
            details.append(f"- `{a}`: " + "; ".join(reasons))
        if a != "baseline" and drop is not None and base_spread is not None:
            named = "named" if abs(drop) > base_spread else "not named (within the baseline's own spread)"
            details.append(f"- `{a}`: mean drop {fmt(drop)} vs baseline spread {fmt(base_spread)}: change {named}")
    out_lines.append("")
    if details:
        out_lines.append("Verdict notes:")
        out_lines.extend(details)
        out_lines.append("")
    out_lines.append("### Missed labels")
    out_lines.append("")
    for a in order:
        arm = arms[a]
        items = sorted(arm.missed.items(), key=lambda kv: (-kv[1], kv[0]))
        if not items:
            out_lines.append(f"- `{a}`: none")
            continue
        shown = ", ".join(f"{fx}:{lbl} ({n}/{arm.seen[(fx, lbl)]})" for (fx, lbl), n in items[:40])
        more = f" … and {len(items) - 40} more" if len(items) > 40 else ""
        out_lines.append(f"- `{a}`: {shown}{more}")
    out_lines.append("")
    return state, verdicts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results-root", required=True)
    ap.add_argument("--suites-dir", required=True)
    ap.add_argument("--suites", default="")
    ap.add_argument("--out", required=True)
    ap.add_argument("--partial", action="store_true")
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    args = ap.parse_args()

    suites = [s for s in args.suites.split(",") if s] or sorted(
        s for s in ("review-recall", "audit-recall") if os.path.isdir(os.path.join(args.results_root, s)))
    if not suites:
        print(f"arms-report: no suite results under {args.results_root}", file=sys.stderr)
        return 2
    for s in suites:
        if not os.path.isdir(os.path.join(args.results_root, s)):
            print(f"arms-report: no results for suite {s} under {args.results_root}", file=sys.stderr)
            return 2
        st = {}
        sp = os.path.join(args.results_root, s, "STATUS.json")
        if os.path.isfile(sp):
            st = json.load(open(sp, encoding="utf-8"))
        if st.get("state") != "complete" and not args.partial:
            print(f"arms-report: {s} STATUS.json state is {st.get('state', 'missing')!r}, not 'complete'; "
                  "refusing to write a verdict report (pass --partial for an inconclusive interim report)",
                  file=sys.stderr)
            return 1

    lines = [f"# Control-arm report — {args.date}", ""]
    if args.partial:
        lines += ["> **PARTIAL REPORT.** Written with `--partial` before every run completed: every verdict "
                  "below reads `inconclusive` and none licenses a deletion (SDD D-2.3).", ""]
    lines += ["Generated by `evals/harness/report.sh --arms` from `" + args.results_root + "`. "
              "Recall is graded by `recall-vs-defects.sh` (planted defects and approved record labels); "
              "refuted share counts cited findings that match neither a label nor a fix region. "
              "A deletion that relies on an arm requires the lead to read that arm's missed labels and record the reading.", ""]
    for s in suites:
        suite_report(args.results_root, args.suites_dir, s, args.partial, lines)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines).rstrip() + "\n")
    print(args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
