#!/usr/bin/env python3
# =============================================================================
# evals/analysis/c132/registration.py — the cycle-132 hashed registration (SDD §3.2 "Entity:
# REGISTRATION.json", D-5.2, D-7.2; sprint Task 1.7c; PRD FR-7)
#
# Builds REGISTRATION.json, the JCS-canonical (RFC 8785) record that binds a batch to every input
# of the measurement — the pre-registration text, the corpus sums, the frozen suite root, the
# analysis code tree, the pin, the image digest, the arm routing with k per task, the groups and
# looks, the calibrated boundary constant, the cap and the seed — and prints its sha256 (the
# registration_sha256 run-ablation.sh --registration records and reads-c132.py checks); or
# verifies one by recomputing every input.
#
# Usage:
#   registration.py build --prereg PATH --corpus-sums PATH --suite-root DIR --analysis-tree REV:PATH
#                         --pin SHA --suite-file PATH --arms CSV --groups JSON --looks JSON
#                         --boundary-constant X --cap-usd N --seed N [--supersedes SHA256]
#                         [--kickoff TS] [--image-digest D] [--cycle ID] [--label-set v2]
#                         [--repo DIR] [--looks-seen JSON [--looks-root DIR]] --out REGISTRATION.json
#   registration.py verify REGISTRATION.json [--repo DIR]
#
# Options (build):
#   --prereg PATH        PREREGISTRATION.md (sha256 of its bytes → preregistration_sha256)
#   --corpus-sums PATH   evals/fixtures/review-prs/SHA256SUMS (→ corpus_sha256sums_sha256)
#   --suite-root DIR     the frozen suite root (its MANIFEST.sha256 → suite_manifest_sha256; its
#                        tasks/<id>/task.yaml give the groups' task ids and the matched arms' k)
#   --analysis-tree REV:PATH  e.g. HEAD:evals/analysis/c132 — `git rev-parse REV:PATH` in --repo, the
#                        git tree id of the analysis code (→ analysis_tree_sha256; the SDD's name for it)
#   --pin SHA            the commit every Phase 1 cell runs (7 … 40 lowercase hex)
#   --suite-file PATH    evals/suites/ablation-2.0.yaml (read through `yq -o=json`): each --arms id's
#                        toggles and phase models
#   --arms CSV           the registered arm ids, in order; each must be declared and not absent
#   --groups JSON        [[task id, …], …] — the PR groups in their seeded order; every id a task of
#                        --suite-root, none twice
#   --looks JSON         [n, …] — the cumulative PR counts at the looks, strictly increasing, the last at
#                        most the number of grouped tasks
#   --boundary-constant X  the simulation-calibrated boundary multiplier (> 0)
#   --cap-usd N          the binding cycle cap (> 0); run-ablation.sh derives each batch's --max-usd from it
#   --seed N             the analysis seed (a non-negative integer)
#   --supersedes SHA256  an addendum (REGISTRATION-N.json): the sha256 of the registration it replaces
#   --kickoff TS         the cycle meter's start (spend.sh --since), ISO 8601 UTC
#   --image-digest D     the container image digest the batches run (pipeline.json image_digest)
#   --cycle ID           default cycle-132; --label-set default v2
#   --repo DIR           the repository the paths are relative to and git runs in (default: the one
#                        holding this file); every input path must lie inside it
#   --out PATH           where the canonical bytes go (no trailing newline; written atomically)
#   --looks-seen JSON    v2 (cycle-133 FR-12, SDD C-12): [{look, suite, registration_sha256, rows_sha256}, …] — every
#                        committed look the authors had seen; makes the record schema_version 2 (the chain version)
#   --looks-root DIR     the looks inventory root (default grimoires/loa/reports/ablation-2.0): its committed
#                        c*-looks/<look>/rows.jsonl files, each with <look>/<look>.json
#
# Registration v2 (looks_seen): `look` is the inventory id `c<N>-looks/<dir>` (dir `look-<i>` or `look-<i>-<suffix>`);
#   `suite` the rows' one suite_manifest_sha256; `registration_sha256` the look's inputs.registration_sha256 (the
#   registration it was read under); `rows_sha256` the sha256 of its rows.jsonl (= its inputs.rows_sha256). Rules,
#   checked by build and verify against the inventory as committed (git ls-files): every entry is an inventory look
#   with equal fields; entries strictly increase by (N, i, suffix — none first); no entry names this registration
#   itself or a registration that supersedes it (a successor: a look read later cannot have been seen); every
#   inventory look not listed was read under this registration or a successor (REGISTRATION*.json beside it whose
#   supersedes chain reaches it) — completeness is verified against the inventory, not merely declared. A v1 record
#   (schema_version 1) has no looks_seen and builds and verifies byte for byte as before.
#
# Record (every path relative to --repo, no timestamp): {schema_version: 1, cycle,
#   preregistration_path, preregistration_sha256, corpus_sums_path, corpus_sha256sums_sha256,
#   suite_root, suite_manifest_sha256, suite_file, analysis_tree, analysis_tree_sha256, pin,
#   image_digest, label_set, seed, arms: [{id, toggles, phase_models: {<phase>: <model id>},
#   k_by_task: {<task>: k}}], groups, looks, boundary_constant, cap_usd, kickoff, supersedes,
#   addenda: []} (v2 adds looks_root and looks_seen). The bytes are the RFC 8785 canonical form through lib/jcs.sh (the repository's
#   canonicaliser, which needs the rfc8785 package; never jq -S): the same inputs give the same
#   bytes and the same sha256. A matched arm (toggles bare_sessions: matched) has k_by_task from each
#   grouped review-catch task's review_catch.bare_sessions_matched (an arm with bare_model: fable reads
#   bare_sessions_matched_fable first); a matched arm on a task without k is an error.
#
# verify: the file must be JCS-canonical; every hash is recomputed from the recorded paths (the
#   pre-registration, the corpus sums, the suite manifest, the analysis tree at the recorded REV:PATH)
#   and the arms from the recorded suite file and suite root; a v2 record's looks_seen against the inventory. Prints one `drift: <field>: registered
#   <a>, now <b>` line per difference, else `ok <sha256>`.
#
# Exit: 0 written / verified; 1 verify found drift; 2 usage, an unreadable input, a failed
#   canonicalisation (rfc8785 missing), or an invalid argument.
# Stdlib only (yq and git are called as tools; lib/jcs.sh canonicalises). Tested by
# evals/analysis/c132/tests/test_registration.py and evals/tests/registration.bats.
# =============================================================================
import argparse
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
FABLE = "global.anthropic.claude-fable-5-1"
BUILTIN_MODEL = {"REVIEW": FABLE, "AUDIT": FABLE}
OPUS = "global.anthropic.claude-opus-5-5"


class Fail(Exception):
    pass


def sha256_file(path):
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            for b in iter(lambda: f.read(1 << 20), b""):
                h.update(b)
    except OSError as e:
        raise Fail(f"cannot read {path}: {e.strerror}")
    return h.hexdigest()


def sha256_file_or_pinned(repo, rec, rel, registered):
    """sha256 of <repo>/<rel>; when it differs from `registered`, the sha256 of <rel> at the registration's pin
    commit (a later extension of the corpus or suite is not drift of the record). Returns the working-tree hash
    when the pin is absent, not a commit, or lacks the path, so the caller reports drift as before."""
    now = sha256_file(os.path.join(repo, rel))
    if now == registered or not re.fullmatch(r"[0-9a-f]{7,40}", str(rec.get("pin") or "")):
        return now
    p = subprocess.run(["git", "-C", repo, "show", f"{rec['pin']}:{rel}"], capture_output=True)
    if p.returncode != 0:
        return now
    pinned = hashlib.sha256(p.stdout).hexdigest()
    return pinned if pinned == registered else now


def inside(repo, path):
    """the path relative to repo; an input outside it is refused (the record carries no absolute path)"""
    real, root = os.path.realpath(path), os.path.realpath(repo)
    if real != root and not real.startswith(root + os.sep):
        raise Fail(f"{path} is not inside the repository {repo}")
    return os.path.relpath(real, root)


def yq_json(path):
    try:
        p = subprocess.run(["yq", "-o=json", ".", path], capture_output=True, text=True)
    except OSError:
        raise Fail("yq is not installed (mikefarah yq v4)")
    if p.returncode != 0:
        raise Fail(f"{path} does not parse as YAML")
    try:
        return json.loads(p.stdout)
    except ValueError:
        raise Fail(f"{path} does not parse as YAML")


def git_tree(repo, rev_path):
    if not re.fullmatch(r"[A-Za-z0-9._/~^@{}-]+:[A-Za-z0-9._/-]*", rev_path or ""):
        raise Fail(f"--analysis-tree must be REV:PATH (got {rev_path!r})")
    p = subprocess.run(["git", "-C", repo, "rev-parse", "--verify", "--quiet", rev_path], capture_output=True, text=True)
    out = p.stdout.strip()
    if p.returncode != 0 or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", out):
        raise Fail(f"git rev-parse {rev_path} gave no tree id in {repo}")
    t = subprocess.run(["git", "-C", repo, "cat-file", "-t", out], capture_output=True, text=True)
    if t.stdout.strip() != "tree":
        raise Fail(f"{rev_path} is not a tree")
    return out


def jcs(obj, repo):
    """RFC 8785 bytes through the repository's lib/jcs.sh (rfc8785 under jcs-helper.py)"""
    lib = os.path.join(repo, "lib", "jcs.sh")
    if not os.path.isfile(lib):
        lib = os.path.join(DEFAULT_REPO, "lib", "jcs.sh")
    fd, tmp = tempfile.mkstemp(prefix="registration.", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False)
        p = subprocess.run(["bash", "-c", 'source "$1" && jcs_canonicalize_file "$2"', "_", lib, tmp], capture_output=True)
    finally:
        os.unlink(tmp)
    if p.returncode != 0 or not p.stdout:
        raise Fail("lib/jcs.sh could not canonicalise the record (rfc8785 installed?): "
                   + p.stderr.decode("utf-8", "replace").strip()[-300:])
    return p.stdout


def task_dirs(suite_root):
    d = os.path.join(suite_root, "tasks")
    if not os.path.isdir(d):
        raise Fail(f"no tasks/ under {suite_root}")
    return sorted(n for n in os.listdir(d) if os.path.isfile(os.path.join(d, n, "task.yaml")))


def arm_records(suite_file, suite_root, arm_ids, task_ids):
    suite = yq_json(suite_file)
    defs = {a.get("id"): a for a in suite.get("arms") or [] if isinstance(a, dict)}
    models = ((suite.get("phase_defaults") or {}).get("models") or {})
    tasks = {}
    out = []
    for aid in arm_ids:
        a = defs.get(aid)
        if a is None or a.get("absent") is True:
            raise Fail(f"arm {aid} is not a runnable arm of {suite_file}")
        tg = a.get("toggles") or {}
        phases = a.get("phases") or (suite.get("phase_sets") or {}).get("review-catch") or ["REVIEW", "AUDIT"]
        if tg.get("loa_mount") is False:
            phases = ["BARE"]
        pm = {}
        for ph in phases:
            m = models.get(ph) or BUILTIN_MODEL.get(ph, OPUS)
            if ph == "BARE" and tg.get("bare_model") == "fable":
                m = FABLE
            pm[ph] = m
        kbt = {}
        if tg.get("bare_sessions") == "matched":
            if not tasks:
                for tid in sorted(set(task_ids)):   # the registered tasks: the groups
                    tasks[tid] = yq_json(os.path.join(suite_root, "tasks", tid, "task.yaml"))
            for tid, t in sorted(tasks.items()):
                if t.get("type") != "review-catch":
                    continue
                rc = t.get("review_catch") or {}
                k = rc.get("bare_sessions_matched_fable") if tg.get("bare_model") == "fable" else None
                k = k if k is not None else rc.get("bare_sessions_matched")
                if not (isinstance(k, int) and not isinstance(k, bool) and 2 <= k <= 30):
                    raise Fail(f"matched arm {aid}: task {tid} has no review_catch.bare_sessions_matched (2 … 30)")
                kbt[tid] = k
        out.append({"id": aid, "toggles": tg, "phase_models": pm, "k_by_task": kbt})
    return out


DEFAULT_LOOKS_ROOT = os.path.join("grimoires", "loa", "reports", "ablation-2.0")
LOOK_ID = re.compile(r"c([0-9]{1,5})-looks/look-([1-9][0-9]{0,3})(?:-([a-z0-9][a-z0-9-]{0,40}))?")
LOOK_KEYS = ("look", "suite", "registration_sha256", "rows_sha256")
HEX64 = re.compile(r"[0-9a-f]{64}")


def look_order(look_id):
    m = LOOK_ID.fullmatch(look_id)
    return (int(m.group(1)), int(m.group(2)), m.group(3) is not None, m.group(3) or "")


def looks_inventory(repo, root):
    """{look id: {look, suite, registration_sha256, rows_sha256}} of the committed looks under root (git ls-files)"""
    rel = inside(repo, root) if os.path.isabs(root) else root
    p = subprocess.run(["git", "-C", repo, "ls-files", "-z", "--", rel], capture_output=True)
    if p.returncode != 0:
        raise Fail(f"git ls-files {rel} failed in {repo}")
    inv = {}
    for f in sorted(x.decode("utf-8", "replace") for x in p.stdout.split(b"\0") if x):
        parts = os.path.relpath(f, rel).split(os.sep) if rel not in ("", ".") else f.split("/")
        if len(parts) != 3 or parts[2] != "rows.jsonl" or not re.fullmatch(r"c[0-9]+-looks", parts[0]):
            continue
        look_id = parts[0] + "/" + parts[1]
        if not LOOK_ID.fullmatch(look_id):
            raise Fail(f"committed look {look_id}: the directory is not look-<i> or look-<i>-<suffix>")
        rows_path = os.path.join(repo, f)
        rows_sha = sha256_file(rows_path)
        suites = set()
        with open(rows_path, encoding="utf-8") as fh:
            for n, line in enumerate(fh, 1):
                if line.strip():
                    try:
                        suites.add(json.loads(line).get("suite_manifest_sha256"))
                    except (ValueError, AttributeError):
                        raise Fail(f"committed look {look_id}: rows.jsonl line {n} is not a JSON object")
        if len(suites) != 1 or not isinstance(next(iter(suites)), str):
            raise Fail(f"committed look {look_id}: its rows do not share one suite_manifest_sha256")
        meta_path = os.path.join(repo, os.path.dirname(f), parts[1] + ".json")
        try:
            with open(meta_path, encoding="utf-8") as fh:
                meta = json.load(fh)
        except (OSError, ValueError):
            raise Fail(f"committed look {look_id}: no readable {parts[1]}.json beside its rows")
        inputs = meta.get("inputs") if isinstance(meta, dict) else None
        reg_sha = inputs.get("registration_sha256") if isinstance(inputs, dict) else None
        if not isinstance(reg_sha, str) or not HEX64.fullmatch(reg_sha):
            raise Fail(f"committed look {look_id}: {parts[1]}.json has no inputs.registration_sha256")
        if inputs.get("rows_sha256") != rows_sha:
            raise Fail(f"committed look {look_id}: rows.jsonl sha256 {rows_sha[:12]} differs from its inputs.rows_sha256")
        index = meta.get("look")
        if index != look_order(look_id)[1]:
            raise Fail(f"committed look {look_id}: look index {index!r} disagrees with the directory name")
        inv[look_id] = {"look": look_id, "suite": next(iter(suites)), "registration_sha256": reg_sha, "rows_sha256": rows_sha}
    return inv


def successors_of(reg_path, self_sha):
    """sha256s of the REGISTRATION*.json beside reg_path whose supersedes chain reaches self_sha"""
    by_sha = {}
    d = os.path.dirname(os.path.abspath(reg_path))
    for name in sorted(os.listdir(d)):
        fp = os.path.join(d, name)
        if name.startswith("REGISTRATION") and name.endswith(".json") and os.path.isfile(fp):
            try:
                with open(fp, "rb") as fh:
                    b = fh.read()
                doc = json.loads(b.decode("utf-8"))
            except (OSError, ValueError, UnicodeDecodeError):
                continue
            by_sha[hashlib.sha256(b).hexdigest()] = doc.get("supersedes") if isinstance(doc, dict) else None
    out = set()
    for h in by_sha:
        cur, seen = by_sha.get(h), {h}
        while isinstance(cur, str) and cur not in seen:
            if cur == self_sha:
                out.add(h)
                break
            seen.add(cur)
            cur = by_sha.get(cur)
    return out


def looks_seen_errors(seen, inv, self_sha=None, successors=frozenset()):
    """the v2 rules (see the header) — [] when looks_seen is sound and complete"""
    if not isinstance(seen, list):
        return ["looks_seen must be a list of {look, suite, registration_sha256, rows_sha256}"]
    errs, prev, listed = [], None, set()
    for i, e in enumerate(seen):
        if not isinstance(e, dict) or tuple(sorted(e)) != tuple(sorted(LOOK_KEYS)):
            errs.append(f"looks_seen[{i}] must have exactly the keys {', '.join(LOOK_KEYS)}"); continue
        lid = e["look"]
        if not isinstance(lid, str) or not LOOK_ID.fullmatch(lid):
            errs.append(f"looks_seen[{i}].look {lid!r} is not c<N>-looks/look-<i>[-<suffix>]"); continue
        key = look_order(lid)
        if prev is not None and key <= prev:
            errs.append(f"looks_seen[{i}] {lid}: the looks must be strictly increasing (N, i, suffix) with no repeat")
        prev = key
        listed.add(lid)
        if self_sha is not None and e.get("registration_sha256") == self_sha:
            errs.append(f"looks_seen[{i}] {lid} names this registration itself (a look read under it cannot precede it)")
        elif e.get("registration_sha256") in successors:
            errs.append(f"looks_seen[{i}] {lid} was read under a successor of this registration (a cycle)")
        have = inv.get(lid)
        if have is None:
            errs.append(f"looks_seen[{i}] {lid} is not a committed look of the inventory"); continue
        for k in ("suite", "registration_sha256", "rows_sha256"):
            if e.get(k) != have[k]:
                errs.append(f"{lid}: {k} {str(e.get(k))[:12]} differs from the committed look's {have[k][:12]}")
    for lid in sorted(inv, key=look_order):
        if lid in listed:
            continue
        r = inv[lid]["registration_sha256"]
        if self_sha is not None and (r == self_sha or r in successors):
            continue    # read under this registration or a later one
        errs.append(f"looks_seen omits the committed look {lid} (read under {r[:12]})")
    return errs


def parse_json_arg(name, text):
    try:
        return json.loads(text)
    except ValueError:
        raise Fail(f"--{name} is not JSON")


def build(a):
    repo = os.path.abspath(a.repo or DEFAULT_REPO)
    if not re.fullmatch(r"[0-9a-f]{7,40}", a.pin or ""):
        raise Fail("--pin must be 7 … 40 lowercase hex")
    if a.supersedes is not None and not re.fullmatch(r"[0-9a-f]{64}", a.supersedes):
        raise Fail("--supersedes must be a sha256 (64 lowercase hex)")
    if a.kickoff is not None and not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?Z", a.kickoff):
        raise Fail("--kickoff must be an ISO-8601 UTC timestamp (2026-10-21T00:23:00Z)")
    if a.image_digest is not None and not re.fullmatch(r"[A-Za-z0-9._:/@+-]{1,200}", a.image_digest):
        raise Fail("--image-digest has unexpected characters")
    try:
        bc, cap, seed = float(a.boundary_constant), float(a.cap_usd), int(a.seed)
    except ValueError:
        raise Fail("--boundary-constant and --cap-usd must be numbers, --seed an integer")
    if not (math.isfinite(bc) and bc > 0) or not (math.isfinite(cap) and cap > 0) or seed < 0:
        raise Fail("--boundary-constant and --cap-usd must be > 0, --seed >= 0")
    bc = int(bc) if bc.is_integer() else bc
    cap = int(cap) if cap.is_integer() else cap
    suite_root = os.path.abspath(a.suite_root)
    man = os.path.join(suite_root, "MANIFEST.sha256")
    if not os.path.isfile(man):
        raise Fail(f"{suite_root} has no MANIFEST.sha256 (freeze the suite root first)")
    arm_ids = [x for x in (a.arms or "").split(",") if x]
    if not arm_ids or len(set(arm_ids)) != len(arm_ids) or not all(re.fullmatch(r"[a-z][a-z0-9_]{0,63}", x) for x in arm_ids):
        raise Fail("--arms must be a comma list of distinct arm ids")
    groups, looks = parse_json_arg("groups", a.groups), parse_json_arg("looks", a.looks)
    known = set(task_dirs(suite_root))
    if not (isinstance(groups, list) and groups and all(isinstance(g, list) and g and all(isinstance(x, str) for x in g) for g in groups)):
        raise Fail("--groups must be a non-empty list of non-empty lists of task ids")
    flat = [x for g in groups for x in g]
    if len(set(flat)) != len(flat) or not set(flat) <= known:
        raise Fail("--groups must name each task of the suite root at most once (unknown: %s)" % ", ".join(sorted(set(flat) - known)))
    if not (isinstance(looks, list) and looks and all(isinstance(n, int) and not isinstance(n, bool) and n > 0 for n in looks)
            and all(x < y for x, y in zip(looks, looks[1:])) and looks[-1] <= len(flat)):
        raise Fail("--looks must be strictly increasing positive PR counts, the last at most the grouped tasks")
    rec = {"schema_version": 1, "cycle": a.cycle, "preregistration_path": inside(repo, a.prereg),
           "preregistration_sha256": sha256_file(a.prereg), "corpus_sums_path": inside(repo, a.corpus_sums),
           "corpus_sha256sums_sha256": sha256_file(a.corpus_sums), "suite_root": inside(repo, suite_root),
           "suite_manifest_sha256": sha256_file(man), "suite_file": inside(repo, a.suite_file),
           "analysis_tree": a.analysis_tree, "analysis_tree_sha256": git_tree(repo, a.analysis_tree), "pin": a.pin,
           "image_digest": a.image_digest, "label_set": a.label_set, "seed": seed,
           "arms": arm_records(a.suite_file, suite_root, arm_ids, flat), "groups": groups, "looks": looks,
           "boundary_constant": bc, "cap_usd": cap, "kickoff": a.kickoff, "supersedes": a.supersedes, "addenda": []}
    if a.looks_seen is not None:
        seen = parse_json_arg("looks-seen", a.looks_seen)
        root = os.path.abspath(a.looks_root) if a.looks_root else os.path.join(repo, DEFAULT_LOOKS_ROOT)
        errs = looks_seen_errors(seen, looks_inventory(repo, root))
        if errs:
            raise Fail("--looks-seen: " + "; ".join(errs[:10]))
        rec.update({"schema_version": 2, "looks_root": inside(repo, root), "looks_seen": seen})
    elif a.looks_root:
        raise Fail("--looks-root needs --looks-seen")
    data = jcs(rec, repo)
    out = os.path.abspath(a.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, out)
    print(hashlib.sha256(data).hexdigest())
    return 0


def verify(a):
    repo = os.path.abspath(a.repo or DEFAULT_REPO)
    try:
        with open(a.registration, "rb") as f:
            raw = f.read()
    except OSError as e:
        raise Fail(f"cannot read {a.registration}: {e.strerror}")
    try:
        rec = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        raise Fail(f"{a.registration} is not JSON")
    if not isinstance(rec, dict) or rec.get("schema_version") not in (1, 2):
        raise Fail(f"{a.registration} is not a schema_version 1 or 2 registration")
    drift = []
    if jcs(rec, repo) != raw:
        drift.append(("canonical_form", "JCS bytes", "not JCS-canonical"))
    p = lambda k: os.path.join(repo, rec.get(k) or "")

    def check(field, fn):
        try:
            now = fn()
        except Fail as e:
            now = f"<{e}>"
        if now != rec.get(field):
            drift.append((field, rec.get(field), now))
    check("preregistration_sha256", lambda: sha256_file(p("preregistration_path")))
    # The corpus and the suite manifest grow after a cycle closes (new fixtures, new tasks). The record binds
    # them AT THE PIN: when the working-tree file no longer hashes to the registered value, the file at the
    # registration's pin commit is checked instead (`git show <pin>:<path>`), and only a mismatch there is drift.
    check("corpus_sha256sums_sha256", lambda: sha256_file_or_pinned(repo, rec, rec.get("corpus_sums_path") or "",
                                                                     rec.get("corpus_sha256sums_sha256")))
    check("suite_manifest_sha256", lambda: sha256_file_or_pinned(repo, rec, os.path.join(rec.get("suite_root") or "", "MANIFEST.sha256"),
                                                                 rec.get("suite_manifest_sha256")))
    check("analysis_tree_sha256", lambda: git_tree(repo, rec.get("analysis_tree")))
    check("arms", lambda: arm_records(p("suite_file"), p("suite_root"), [x.get("id") for x in rec.get("arms") or []],
                                      [x for g in rec.get("groups") or [] if isinstance(g, list) for x in g]))
    if rec.get("schema_version") == 1 and ("looks_seen" in rec or "looks_root" in rec):
        drift.append(("looks_seen", "absent (schema_version 1)", "present: a v1 record carries no looks_seen"))
    if rec.get("schema_version") == 2:
        try:
            if not isinstance(rec.get("looks_root"), str) or "looks_seen" not in rec:
                raise Fail("a schema_version 2 record needs looks_root and looks_seen")
            self_sha = hashlib.sha256(raw).hexdigest()
            errs = looks_seen_errors(rec["looks_seen"], looks_inventory(repo, os.path.join(repo, rec["looks_root"])),
                                     self_sha, successors_of(a.registration, self_sha))
        except Fail as e:
            errs = [str(e)]
        if errs:
            drift.append(("looks_seen", "sound and complete against the committed looks", "; ".join(errs[:10])))
    for field, was, now in drift:
        print(f"drift: {field}: registered {json.dumps(was, sort_keys=True)}, now {json.dumps(now, sort_keys=True)}")
    if drift:
        return 1
    print(f"ok {hashlib.sha256(raw).hexdigest()}")
    return 0


class Parser(argparse.ArgumentParser):
    def error(self, message):
        print(f"registration.py: {message}", file=sys.stderr)
        sys.exit(2)


def main(argv):
    ap = Parser(prog="registration.py")
    sub = ap.add_subparsers(dest="cmd", required=True, parser_class=Parser)
    b = sub.add_parser("build")
    for k in ("prereg", "corpus-sums", "suite-root", "analysis-tree", "pin", "suite-file", "arms", "groups", "looks",
              "boundary-constant", "cap-usd", "seed", "out"):
        b.add_argument("--" + k, required=True)
    b.add_argument("--supersedes")
    b.add_argument("--kickoff")
    b.add_argument("--image-digest")
    b.add_argument("--cycle", default="cycle-132")
    b.add_argument("--label-set", default="v2")
    b.add_argument("--repo")
    b.add_argument("--looks-seen")
    b.add_argument("--looks-root")
    v = sub.add_parser("verify")
    v.add_argument("registration")
    v.add_argument("--repo")
    a = ap.parse_args(argv)
    try:
        return build(a) if a.cmd == "build" else verify(a)
    except Fail as e:
        print(f"registration.py: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
