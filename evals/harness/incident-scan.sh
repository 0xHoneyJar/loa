#!/usr/bin/env bash
# =============================================================================
# incident-scan.sh — compile the post-merge incidents attributable to a
# review-catch record fixture (cycle-132 FR-2, SDD §1.4 "Incident scanner",
# §5.2, D-2.1, D-7.8)
#
# Usage:
#   incident-scan.sh <fixture> [--out DIR] [--main-ref origin/main] [--window-days N]
#                    [--no-gh] [--record-refs ref,ref…] [--scan-date ISO]
#                    [--repo <git dir>] [--corpus <evals/fixtures/review-prs>]
#
#   <fixture>        pr-NN (under --corpus) or a fixture directory holding
#                    fixture.yaml (head_commit, fix_commit, sprint) and head.diff
#   --out DIR        output directory (default <corpus>/incidents)
#   --main-ref REF   the integration branch (default origin/main)
#   --window-days N  optional upper bound: the window ends at min(scan date,
#                    merge date + N days); default: the scan date (D-7.8)
#   --no-gh          skip the GitHub search source; meta records gh_queries: []
#   --record-refs    the record branches searched for Bridgebuilder rounds
#                    (default: every refs/remotes/origin/record/* ref)
#   --scan-date ISO  the scan instant (default: now, UTC); tests pin it
#
# The window (D-7.8): ONE rule for every source, from the merge date to the scan
# date. The merge commit is the oldest commit on <main-ref>'s first-parent chain
# that contains fix_commit (the fix commit itself when it landed on main
# directly); the merge date is its committer date. The PR number comes from the
# merge subject ("Merge pull request #N" or a trailing "(#N)").
#
# Sources (each kept only inside the window):
#   (a) fix-commit     commits in <merge>..<main-ref> (no merges) touching a
#                      head-changed file whose subject starts with "fix"; the
#                      evidence is the commit restricted to those files (.diff)
#   (b) issue          gh api --paginate search/issues, repo:0xHoneyJar/loa, the
#                      changed files' basenames (OR-batched, created:>= the merge
#                      day); an item is kept when it was created in the window
#                      and its title or body cites a changed path (full relative
#                      path); every query's page count, total_count and
#                      incomplete_results are recorded; truncated = any query
#                      incomplete, capped (search returns ≤ 1000) or short
#   (c) bridgebuilder  bridgebuilder*.md / bb-triage*.md files on the record refs
#                      that name the sprint's PR (#N in the file name or the first
#                      `#` heading; a body mention is not enough) and whose round is dated in
#                      the window (the bridgebuilder-YYYYMMDDTHHMMSS run id, else
#                      a **Date:** line, else the file's first commit on the ref)
#   (d) kf             grimoires/loa/known-failures.md on <main-ref>: a `## KF-NNN`
#                      entry citing a changed path with an ISO date in the window
#                      (the earliest such date is the incident date)
#
# Writes (replacing an earlier scan of the fixture):
#   <out>/pr-NN.tsv              header `id kind ref date files excerpt`; ids I01 …
#                                sorted by (date, kind, ref); excerpt ≤ 400 chars,
#                                control characters stripped; files comma-joined
#   <out>/pr-NN/evidence/<id>.md|.diff   the full issue body / file text / commit
#   <out>/pr-NN.meta.json        {fixture, main_ref, main_sha, merge_commit,
#                                merge_date, pr, scanned_at, window: {from, to},
#                                counts: {fix-commit, issue, bridgebuilder, kf},
#                                gh_queries: [...], truncated, maturity_days,
#                                changed_files, record_refs}
# Environment: INCIDENT_SCAN_GH_PAUSE (seconds between search calls, default 2.2).
# Secret-shaped strings in third-party text are replaced by REDACTED-SECRET and
# every written file must pass evals/graders/no-secrets.sh, else nothing is kept.
# The gh results are a snapshot: recorded, never re-queried by a reproduction.
#
# Exit: 0 written, 1 refused (fixture, ref or fix commit missing, fix not on the
# main ref, gh failure, secret scan failed), 2 usage
# Tested by evals/tests/incident-scan.bats.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

exec python3 -I - "$REPO_ROOT" "$@" <<'PY'
import argparse, datetime as dt, json, os, re, shutil, subprocess, sys, tempfile, time

HARNESS_ROOT = sys.argv[1]
ap = argparse.ArgumentParser(prog="incident-scan.sh")
ap.add_argument("fixture")
ap.add_argument("--out"); ap.add_argument("--main-ref", default="origin/main")
ap.add_argument("--window-days", type=int); ap.add_argument("--no-gh", action="store_true")
ap.add_argument("--record-refs"); ap.add_argument("--scan-date")
ap.add_argument("--repo", default=HARNESS_ROOT)
ap.add_argument("--corpus", default=os.path.join(HARNESS_ROOT, "evals", "fixtures", "review-prs"))
try:
    args = ap.parse_args(sys.argv[2:])
except SystemExit as e:
    sys.exit(2 if e.code else 0)

GH_REPO = "0xHoneyJar/loa"
try:   # seconds between search calls (30/min limit); bats sets 0
    GH_PAUSE = max(0.0, float(os.environ.get("INCIDENT_SCAN_GH_PAUSE", "2.2")))
except ValueError:
    GH_PAUSE = 2.2
NO_SECRETS = os.path.join(HARNESS_ROOT, "evals", "graders", "no-secrets.sh")
REPO, CORPUS = os.path.abspath(args.repo), os.path.abspath(args.corpus)

def fail(msg, code=1):
    print(f"incident-scan: {msg}", file=sys.stderr)
    sys.exit(code)

if args.window_days is not None and args.window_days < 1:
    fail("--window-days must be a positive integer", 2)
if not re.match(r"^[A-Za-z0-9._/-]+$", args.main_ref):
    fail("--main-ref: a ref name", 2)

def git(*a, check=True):
    p = subprocess.run(["git", "-C", REPO, *a], capture_output=True, text=True, errors="replace")
    if check and p.returncode != 0:
        fail(f"git {' '.join(a[:3])} failed: {p.stderr.strip()[:300]}")
    return p.stdout

def rev(r):
    p = subprocess.run(["git", "-C", REPO, "rev-parse", "--verify", "--quiet", f"{r}^{{commit}}"], capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else None

def parse_iso(s):
    s = s.strip().replace("Z", "+00:00")
    if re.match(r"^\d{4}-\d{2}-\d{2}$", s):
        s += "T00:00:00+00:00"
    d = dt.datetime.fromisoformat(s)
    if d.tzinfo is None:
        d = d.replace(tzinfo=dt.timezone.utc)
    return d.astimezone(dt.timezone.utc)

def iso(d):
    return d.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# --- fixture ------------------------------------------------------------------------
if re.match(r"^pr-[0-9]{2}$", args.fixture):
    fdir, fx = os.path.join(CORPUS, args.fixture), args.fixture
else:
    fdir = os.path.abspath(args.fixture); fx = os.path.basename(fdir.rstrip("/"))
    if not re.match(r"^pr-[0-9]{2}$", fx):
        fail(f"fixture directory must be named pr-NN: {args.fixture}", 2)
fy, hd = os.path.join(fdir, "fixture.yaml"), os.path.join(fdir, "head.diff")
if not (os.path.isfile(fy) and os.path.isfile(hd)):
    fail(f"{fx}: fixture.yaml or head.diff missing under {fdir}")
meta_y = {}
for l in open(fy, encoding="utf-8"):
    m = re.match(r'^(sprint|head_commit|fix_commit):\s*"?([0-9A-Za-z]+)"?\s*(#.*)?$', l.strip())
    if m:
        meta_y[m.group(1)] = m.group(2)
if "fix_commit" not in meta_y or "head_commit" not in meta_y:
    fail(f"{fx}: fixture.yaml needs head_commit and fix_commit")
fix = rev(meta_y["fix_commit"])
if fix is None:
    fail(f"{fx}: fix commit {meta_y['fix_commit'][:12]} not in {REPO}")
main_sha = rev(args.main_ref)
if main_sha is None:
    fail(f"main ref not found: {args.main_ref}")

files = set()
for l in open(hd, encoding="utf-8", errors="replace"):
    m = re.match(r"^(?:\+\+\+ b/|--- a/)(.+?)\s*$", l.rstrip("\n"))
    if m and m.group(1) != "/dev/null":
        files.add(m.group(1))
files = sorted(files)
if not files:
    fail(f"{fx}: head.diff names no file")

# --- the merge -----------------------------------------------------------------------
first_parent = git("rev-list", "--first-parent", main_sha).split()
fp_set = set(first_parent)
if fix in fp_set:
    merge = fix
else:
    desc = set(git("rev-list", "--ancestry-path", f"{fix}..{main_sha}").split())
    cands = [c for c in first_parent if c in desc]
    if not cands:
        fail(f"{fx}: fix commit {fix[:12]} is not on {args.main_ref}")
    merge = cands[-1]   # first_parent is newest first: the oldest descendant on the chain
merge_line = git("log", "-1", "--format=%cI%x09%s", merge).strip().split("\t", 1)
merge_date, merge_subject = parse_iso(merge_line[0]), (merge_line[1] if len(merge_line) > 1 else "")
mpr = re.search(r"Merge pull request #(\d+)", merge_subject) or re.search(r"\(#(\d+)\)\s*$", merge_subject)
pr = int(mpr.group(1)) if mpr else None
scan = parse_iso(args.scan_date) if args.scan_date else dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
if scan < merge_date:
    fail(f"--scan-date {iso(scan)} precedes the merge {iso(merge_date)}", 2)
w_to = scan if args.window_days is None else min(scan, merge_date + dt.timedelta(days=args.window_days))
def in_window(d):
    return d is not None and merge_date <= d <= w_to

# --- text hygiene ----------------------------------------------------------------------
SECRET_RX = [re.compile(p) for p in (
    r"AKIA[0-9A-Z]{16}", r"sk-[a-zA-Z0-9]{20,}", r"ghp_[a-zA-Z0-9]{36}", r"gho_[a-zA-Z0-9]{36}",
    r"github_pat_[A-Za-z0-9_]{20,}", r"gh[su]_[a-zA-Z0-9]{36}",
    r"glpat-[a-zA-Z0-9\-]{20,}", r"xox[bpors]-[a-zA-Z0-9\-]+", r"sk-ant-[a-zA-Z0-9\-]{20,}",
    r"AIza[0-9A-Za-z\-_]{35}", r"(?:sk|rk)_(?:live|test)_[0-9a-zA-Z]{20,}",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----[^-]*-----END [A-Z ]*PRIVATE KEY-----",
    r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")]
def redact(t):
    for r in SECRET_RX:
        t = r.sub("REDACTED-SECRET", t)
    return t
CTRL_ALL = re.compile("[\x00-\x1f\x7f-\x9f  ]")
CTRL_KEEP_NL = re.compile("[\x00-\x08\x0b-\x1f\x7f-\x9f  ]")
def excerpt(t, cap=400):
    t = re.sub(r"\s+", " ", CTRL_ALL.sub(" ", redact(t))).strip()
    return t if len(t) <= cap else t[: cap - 1].rstrip() + "…"
def body_text(t):
    return CTRL_KEEP_NL.sub(" ", redact(t.replace("\r\n", "\n")))
def fenced(text, info):
    """text inside a tilde fence longer than any tilde run it holds (third-party data stays quoted)"""
    n = max([3] + [len(m) for m in re.findall(r"~{3,}", text)]) + 1
    return "~" * n + info + "\n" + text + ("" if text.endswith("\n") else "\n") + "~" * n + "\n"
def cited(text):
    return [f for f in files if f in text]

incidents = []   # {kind, ref, date(datetime), files[], excerpt, evidence: (ext, text)}

# (a) fix commits on main after the merge -------------------------------------------------
for l in git("log", "--no-merges", "--format=%H%x09%cI%x09%s", f"{merge}..{main_sha}", "--", *files).splitlines():
    sha, cdate, subj = (l.split("\t", 2) + ["", ""])[:3]
    d = parse_iso(cdate)
    if not re.match(r"^fix\b", subj, re.I) or not in_window(d):
        continue
    touched = sorted(set(git("show", "--no-renames", "--name-only", "--format=", sha, "--", *files).split()) & set(files))
    if not touched:
        continue
    msg = git("log", "-1", "--format=%B", sha)
    diff = git("show", "--no-color", "--no-ext-diff", "--format=commit %H%nDate: %cI%n%n%B", sha, "--", *touched)
    incidents.append({"kind": "fix-commit", "ref": sha[:12], "date": d, "files": touched,
                      "excerpt": excerpt(msg), "evidence": (".diff", body_text(diff))})

# (b) GitHub issues / PRs citing a changed path -------------------------------------------
gh_queries, truncated = [], False
if not args.no_gh:
    if shutil.which("gh") is None:
        fail("gh not found (use --no-gh to skip the issue source)")
    names = sorted({f.rsplit("/", 1)[-1] for f in files})
    batches, cur = [], []
    for n in names:
        q = " OR ".join(f'"{x}"' for x in cur + [n])
        if cur and (len(cur) >= 5 or len(q) > 180):
            batches.append(cur); cur = [n]
        else:
            cur.append(n)
    if cur:
        batches.append(cur)
    seen = {}
    for b in batches:
        q = f"repo:{GH_REPO} created:>={merge_date.strftime('%Y-%m-%d')} " + " OR ".join(f'"{x}"' for x in b)
        for attempt in range(4):
            p = subprocess.run(["gh", "api", "--paginate", "-X", "GET", "search/issues", "-f", f"q={q}", "-f", "per_page=100"],
                               capture_output=True, text=True)
            if p.returncode == 0:
                break
            if "rate limit" in (p.stderr + p.stdout).lower() and attempt < 3:
                time.sleep(30 * (attempt + 1)); continue
            fail(f"gh search failed for {q!r}: {p.stderr.strip()[:300]}")
        dec, pos, pages = json.JSONDecoder(), 0, []
        s = p.stdout
        while pos < len(s):
            while pos < len(s) and s[pos].isspace():
                pos += 1
            if pos >= len(s):
                break
            obj, pos = dec.raw_decode(s, pos)
            pages.append(obj)
        items = [it for pg in pages for it in (pg.get("items") or [])]
        total = pages[0].get("total_count", 0) if pages else 0
        incomplete = any(pg.get("incomplete_results") for pg in pages)
        short = len(items) < min(total, 1000)
        capped = total > 1000
        truncated = truncated or incomplete or short or capped
        kept = 0
        for it in items:
            num = it.get("number")
            if num in seen:
                continue
            text = (it.get("title") or "") + "\n" + (it.get("body") or "")
            c = cited(text)
            d = parse_iso(it["created_at"]) if it.get("created_at") else None
            if not c or not in_window(d):
                continue
            kind_word = "pull request" if it.get("pull_request") else "issue"
            ev = (f"# {kind_word} #{num}: {CTRL_ALL.sub(' ', it.get('title') or '')}\n\n"
                  f"- url: {it.get('html_url', '')}\n- created_at: {it.get('created_at')}\n- state: {it.get('state')}\n\n"
                  "The text below is third-party data, quoted verbatim (control characters and secret-shaped strings replaced).\n\n"
                  + fenced(body_text(it.get("body") or ""), "text"))
            seen[num] = {"kind": "issue", "ref": f"#{num}", "date": d, "files": c,
                         "excerpt": excerpt((it.get("title") or "") + " — " + (it.get("body") or "")), "evidence": (".md", ev)}
            kept += 1
        gh_queries.append({"q": q, "pages": len(pages), "total_count": total, "items": len(items),
                           "incomplete_results": incomplete, "kept": kept})
        time.sleep(GH_PAUSE)   # the search API allows 30 requests a minute
    incidents.extend(seen[k] for k in sorted(seen))

# (c) Bridgebuilder rounds on the record branches -------------------------------------------
if args.record_refs:
    refs = [r for r in args.record_refs.split(",") if r]
    for r in refs:
        if rev(r) is None:
            fail(f"record ref not found: {r}")
else:
    refs = sorted(l.strip()[len("refs/remotes/"):] for l in git("for-each-ref", "--format=%(refname)", "refs/remotes/origin/record/").splitlines() if l.strip())
BB_NAME = re.compile(r"^(?:bridgebuilder|bb-triage)[^/]*\.md$")
if pr is not None:
    pr_rx = re.compile(r"(?:PR\s*#|pull/|#)" + str(pr) + r"\b")
    for r in refs:
        for path in git("ls-tree", "-r", "--name-only", r, "--", "grimoires/loa/a2a").splitlines():
            if not BB_NAME.match(path.rsplit("/", 1)[-1]):
                continue
            text = git("show", f"{r}:{path}")
            # the round is ON the PR: its number in the file name or the first heading
            # (a round on another PR that mentions this one in its body is not)
            heading = next((l for l in text.splitlines() if l.startswith("#")), "")
            if not (re.search(r"(?<!\d)" + str(pr) + r"(?!\d)", path.rsplit("/", 1)[-1]) or pr_rx.search(heading)):
                continue
            m = re.search(r"bridgebuilder-(\d{8}T\d{6})", text)
            if m:
                d = dt.datetime.strptime(m.group(1), "%Y%m%dT%H%M%S").replace(tzinfo=dt.timezone.utc)
            else:
                m = re.search(r"\*\*Date:?\*\*:?\s*(\d{4}-\d{2}-\d{2})", text)
                if m:
                    d = parse_iso(m.group(1))
                else:
                    first = git("log", "--diff-filter=A", "--format=%cI", r, "--", path).split()
                    d = parse_iso(first[-1]) if first else None
            if not in_window(d):
                continue
            incidents.append({"kind": "bridgebuilder", "ref": f"{r}:{path}", "date": d, "files": cited(text),
                              "excerpt": excerpt(text), "evidence": (".md", fenced(body_text(text), "markdown"))})

# (d) known-failures entries on the main ref ---------------------------------------------
kf = subprocess.run(["git", "-C", REPO, "show", f"{main_sha}:grimoires/loa/known-failures.md"], capture_output=True, text=True, errors="replace")
if kf.returncode == 0:
    parts = re.split(r"(?m)^(?=## KF-\d+)", kf.stdout)
    for e in parts:
        m = re.match(r"^## (KF-\d+)", e)
        if not m:
            continue
        c = cited(e)
        if not c:
            continue
        # KF dates are days: an entry dated the merge day is inside the window
        dates = sorted(d for d in (parse_iso(x) for x in set(re.findall(r"\b(20\d\d-\d\d-\d\d)\b", e)))
                       if merge_date.date() <= d.date() and d <= w_to)
        if not dates:
            continue
        incidents.append({"kind": "kf", "ref": m.group(1), "date": dates[0], "files": c,
                          "excerpt": excerpt(e), "evidence": (".md", fenced(body_text(e), "markdown"))})

# --- write -------------------------------------------------------------------------------
KIND_ORDER = {"fix-commit": 0, "issue": 1, "bridgebuilder": 2, "kf": 3}
incidents.sort(key=lambda x: (x["date"], KIND_ORDER[x["kind"]], x["ref"]))
out = os.path.abspath(args.out) if args.out else os.path.join(CORPUS, "incidents")
os.makedirs(out, exist_ok=True)
stage = tempfile.mkdtemp(dir=out, prefix=f".{fx}.")
try:
    ev_dir = os.path.join(stage, fx, "evidence"); os.makedirs(ev_dir)
    rows = ["\t".join(["id", "kind", "ref", "date", "files", "excerpt"])]
    for i, x in enumerate(incidents, 1):
        x["id"] = f"I{i:02d}"
        rows.append("\t".join([x["id"], x["kind"], x["ref"], iso(x["date"]), ",".join(x["files"]) or "-", x["excerpt"] or "-"]))
        ext, text = x["evidence"]
        open(os.path.join(ev_dir, x["id"] + ext), "w", encoding="utf-8").write(text if text.endswith("\n") else text + "\n")
    open(os.path.join(stage, f"{fx}.tsv"), "w", encoding="utf-8").write("\n".join(rows) + "\n")
    counts = {k: sum(1 for x in incidents if x["kind"] == k) for k in KIND_ORDER}
    meta = {"fixture": fx, "main_ref": args.main_ref, "main_sha": main_sha, "merge_commit": merge,
            "merge_date": iso(merge_date), "pr": pr, "scanned_at": iso(scan),
            "window": {"from": iso(merge_date), "to": iso(w_to), "rule": "merge date to scan date (SDD D-7.8)"
                       + (f", capped at {args.window_days} days" if args.window_days else "")},
            "counts": counts, "gh_queries": gh_queries, "gh": "skipped" if args.no_gh else "queried",
            "truncated": truncated, "maturity_days": (scan - merge_date).days, "changed_files": len(files),
            "record_refs": refs}
    open(os.path.join(stage, f"{fx}.meta.json"), "w", encoding="utf-8").write(json.dumps(meta, indent=2, sort_keys=True) + "\n")
    p = subprocess.run(["bash", NO_SECRETS, stage], capture_output=True, text=True)
    if p.returncode != 0:
        fail(f"{fx}: no-secrets.sh failed on the scan output; nothing kept: {p.stdout.strip()[:300]}")
    shutil.rmtree(os.path.join(out, fx), ignore_errors=True)
    os.replace(os.path.join(stage, fx), os.path.join(out, fx))
    for n in (f"{fx}.tsv", f"{fx}.meta.json"):
        os.replace(os.path.join(stage, n), os.path.join(out, n))
finally:
    shutil.rmtree(stage, ignore_errors=True)
print(f"{fx}: {len(incidents)} incident(s) " + " ".join(f"{k}={v}" for k, v in counts.items())
      + f"; window {iso(merge_date)} .. {iso(w_to)}; merge {merge[:12]}" + (f" (PR #{pr})" if pr else "")
      + f"; maturity {meta['maturity_days']} d" + ("; TRUNCATED" if truncated else ""))
PY
