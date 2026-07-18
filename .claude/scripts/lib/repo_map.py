#!/usr/bin/env python3
# =============================================================================
# repo_map.py -- deterministic, stdlib-only symbol map for loa's framework code
#
# Engine behind .claude/scripts/repo-map-gen.sh (cycle-116 D4,
# bd-c116-d4-repo-map-x69d). Closes the semantic-retrieval gap named in
# grimoires/loa/proposals/okf-icm-comparative-analysis-2026-06-27.md:91 with a
# LEXICAL PageRank v1 (Aider-repo-map-style) -- NOT embeddings, NOT a call graph.
#
# DETERMINISM CONTRACT: output is a pure function of the byte contents of the
#   *.sh / *.py files under the scan root. No wall-clock timestamp, no head_sha,
#   no mtime -- provenance is the generator name + a content hash of the inputs,
#   so the map changes ONLY when the mapped code changes. Every set/dict that
#   feeds float accumulation is iterated as a sorted list, scores are rounded to
#   6 decimals, and PageRank runs a FIXED iteration count (no convergence-driven
#   early exit) so the byte output is identical across platforms and float impls.
#
# Extraction (lexical, deliberately coarse -- see the honesty disclaimer in the
#   rendered REPO-MAP.md):
#   * bash: `^\s*name() {` (column-0 + legitimately-indented nested form). The
#     `function name` keyword form is intentionally NOT matched -- every such
#     hit in this repo is an AWK function embedded in a bash heredoc, not a bash
#     function (grounded false-positive census, cycle-116 D4 spec).
#   * python: ast def / async def (kind=function) + class (kind=class).
#   * xref: word-boundary token occurrences of a symbol name across all files
#     EXCLUDING that symbol's own defining file(s). Same-file caller->callee is
#     therefore not counted (a v1 coarseness, labeled in the output).
#
# Invocation (by the bash wrapper): repo_map.py --root DIR --scan SUBDIR --emit json|md
# =============================================================================
import argparse
import ast
import hashlib
import json
import os
import re
import sys

VERSION = "1.0.0"
GENERATOR = "repo-map-gen.sh"
DAMPING = 0.85
ITERATIONS = 50
EXCLUDE_DIRS = {"__pycache__", ".pytest_cache", "fixtures", "tests", "__tests__"}
BASH_DEF_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{")
TOKEN_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

# Definitions whose name is a bash builtin/reserved word or a python keyword are
# skipped: a lexical ranker cannot distinguish such a def (almost always a test
# mock or a shadowing wrapper) from the language token itself, so its xref count
# is pure noise (e.g. a mock `exit()` scoring 2825 "references"). The name still
# counts as a token in OTHER symbols' reference scans; it just gets no node.
STOPWORD_DEFS = frozenset("""
    alias bg bind break builtin caller case cd command compgen complete continue
    coproc declare dirs disown do done echo elif else enable esac eval exec exit
    export false fc fg fi for function getopts hash help history if in jobs kill
    let local logout popd printf pushd pwd read readonly return select set shift
    shopt source suspend test then time times trap true type ulimit umask unalias
    unset until wait while
    False None True and as assert async await class def del except finally from
    global import is lambda nonlocal not or pass raise try with yield
""".split())


def walk_files(scan_root, project_root):
    """Deterministic sorted walk; yields (relpath, abspath) for *.sh / *.py."""
    out = []
    for dirpath, dirnames, filenames in os.walk(scan_root):
        dirnames[:] = sorted(d for d in dirnames if d not in EXCLUDE_DIRS)
        for fn in sorted(filenames):
            if fn.endswith(".sh") or fn.endswith(".py"):
                ab = os.path.join(dirpath, fn)
                rel = os.path.relpath(ab, project_root)
                out.append((rel, ab))
    out.sort(key=lambda t: t[0])
    return out


def extract_bash(text):
    """Yield (name, lineno, 'function') for `name() {` defs, line by line."""
    for i, line in enumerate(text.splitlines(), start=1):
        m = BASH_DEF_RE.match(line)
        if m:
            yield (m.group(1), i, "function")


def extract_python(text):
    """Yield (name, lineno, kind) via ast; caller handles SyntaxError fail-soft."""
    tree = ast.parse(text)
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            yield (node.name, node.lineno, "function")
        elif isinstance(node, ast.ClassDef):
            yield (node.name, node.lineno, "class")


def build_map(scan_root, project_root):
    files = walk_files(scan_root, project_root)
    file_texts = {}     # rel -> decoded text
    file_bytes = {}     # rel -> raw bytes (for input hash)
    token_counts = {}   # rel -> {token: count}
    defs = {}           # name -> list of (rel, lineno, kind)
    def_files = {}      # name -> set of rel
    skipped = []        # rel of files that failed python parse

    for rel, ab in files:
        with open(ab, "rb") as fh:
            raw = fh.read()
        file_bytes[rel] = raw
        text = raw.decode("utf-8", errors="replace")
        file_texts[rel] = text
        counts = {}
        for tok in TOKEN_RE.findall(text):
            counts[tok] = counts.get(tok, 0) + 1
        token_counts[rel] = counts

        if rel.endswith(".sh"):
            site_iter = extract_bash(text)
        else:  # .py
            try:
                site_iter = list(extract_python(text))
            except (SyntaxError, ValueError) as exc:
                skipped.append(rel)
                site_iter = []
                sys.stderr.write("repo_map: skipped (parse error) %s: %s\n" % (rel, exc))
        for name, lineno, kind in site_iter:
            if name in STOPWORD_DEFS:
                continue
            defs.setdefault(name, []).append((rel, lineno, kind))
            def_files.setdefault(name, set()).add(rel)

    for name in defs:
        defs[name].sort(key=lambda t: (t[0], t[1]))
    known_names = set(defs.keys())

    # xref counts + directed endorsement graph in one pass over cross-file tokens.
    xref = {n: 0 for n in known_names}
    out_edges = {n: {} for n in known_names}  # a -> {b: weight}
    for rel, _ab in files:
        counts = token_counts[rel]
        refs = {}  # name -> count, cross-file references only
        for name, c in counts.items():
            if name in known_names and rel not in def_files[name]:
                xref[name] += c
                refs[name] = c
        if not refs:
            continue
        defs_in_f = [d for d in known_names if rel in def_files[d]]
        for a in defs_in_f:
            ea = out_edges[a]
            for b, w in refs.items():
                ea[b] = ea.get(b, 0) + w

    # PageRank -- sorted-list iteration, dangling-mass redistribution, fixed count.
    nodes = sorted(known_names)
    n = len(nodes)
    scores = {}
    if n > 0:
        out_weight = {a: sum(out_edges[a].values()) for a in nodes}
        dangling = [a for a in nodes if out_weight[a] == 0]
        base = (1.0 - DAMPING) / n
        rank = {node: 1.0 / n for node in nodes}
        for _ in range(ITERATIONS):
            dangling_mass = 0.0
            for d in dangling:
                dangling_mass += rank[d]
            redistributed = DAMPING * dangling_mass / n
            new = {node: base + redistributed for node in nodes}
            for a in nodes:
                ow = out_weight[a]
                if ow == 0:
                    continue
                ra = rank[a]
                for b, w in sorted(out_edges[a].items()):
                    new[b] += DAMPING * ra * w / ow
            rank = new
        scores = {node: round(rank[node], 6) for node in nodes}

    ranked = sorted(known_names, key=lambda s: (-scores[s], s))

    # input hash: sha256 over (relpath + '\n' + bytes) in sorted relpath order.
    h = hashlib.sha256()
    for rel, _ab in files:
        h.update(rel.encode("utf-8"))
        h.update(b"\n")
        h.update(file_bytes[rel])
    input_hash = h.hexdigest()

    symbols = []
    for name in ranked:
        sites = defs[name]
        symbols.append({
            "name": name,
            "kind": sites[0][2],
            "score": scores[name],
            "xref_count": xref[name],
            "def_sites": [{"file": s[0], "line": s[1]} for s in sites],
            "collision": len(sites) > 1,
        })

    return {
        "generator": GENERATOR,
        "version": VERSION,
        "input_hash": input_hash,
        "damping": DAMPING,
        "iterations": ITERATIONS,
        "file_count": len(files),
        "symbol_count": len(symbols),
        "skipped_files": sorted(skipped),
        "symbols": symbols,
    }


def emit_json(data):
    return json.dumps(data, indent=2, ensure_ascii=True, sort_keys=False)


def _sites_str(sym, cap=3):
    sites = sym["def_sites"]
    shown = ", ".join("%s:%d" % (s["file"], s["line"]) for s in sites[:cap])
    if len(sites) > cap:
        shown += " (+%d more)" % (len(sites) - cap)
    return shown


def _md_escape(text):
    return text.replace("|", "\\|")


def emit_md(data, scan_rel):
    lines = []
    a = lines.append
    a("<!-- generated by %s v%s -- DO NOT EDIT. Regenerate: bash .claude/scripts/repo-map-gen.sh"
      % (data["generator"], data["version"]))
    a("     Provenance is the generator + input content-hash below; NO timestamp / head_sha")
    a("     is emitted, so this file changes ONLY when the mapped %s/ code changes. -->" % scan_rel)
    a("")
    a("# REPO-MAP -- loa framework (`%s/`)" % scan_rel)
    a("")
    a("> **Reference-weighted, NOT semantic.** Symbols are ranked by a fixed-iteration damped "
      "PageRank over a graph built from lexical word-boundary occurrences of symbol names across "
      "files (bash `name() {` defs + python `def`/`class` via `ast`). This is NOT a call graph or "
      "an import graph: a name inside a comment, a string, or an unrelated same-named local counts "
      "the same as a real call. Symbols sharing a name across files **collapse into one node** whose "
      "score aggregates every definition site (marked `collision`). Treat this as a navigation hint, "
      "not verified truth. Test/fixture directories (`tests`, `__tests__`, `fixtures`) are excluded "
      "from the scan, and definitions named after bash builtins / python keywords (test mocks like "
      "`exit()`) are skipped as unrankable noise.")
    a("")
    a("- **Generator:** `%s` v%s" % (data["generator"], data["version"]))
    a("- **Input content hash (sha256):** `%s`" % data["input_hash"])
    a("- **Method:** damped PageRank, damping=%s, %d fixed iterations, ties lexicographic."
      % (data["damping"], data["iterations"]))
    a("")

    symbols = data["symbols"]

    a("## Top 50 Overall")
    a("")
    a("| # | Symbol | Kind | Score | Xrefs | Def sites |")
    a("|---|--------|------|-------|-------|-----------|")
    for i, sym in enumerate(symbols[:50], start=1):
        a("| %d | `%s` | %s | %.6f | %d | %s |"
          % (i, _md_escape(sym["name"]), sym["kind"], sym["score"], sym["xref_count"],
             _md_escape(_sites_str(sym))))
    a("")

    # First-level subdirectories under the scan root, from actual def sites.
    prefix = scan_rel + "/"
    subdirs = set()
    for sym in symbols:
        for site in sym["def_sites"]:
            f = site["file"]
            if f.startswith(prefix):
                rest = f[len(prefix):]
                if "/" in rest:
                    subdirs.add(rest.split("/", 1)[0])
    for sub in sorted(subdirs):
        sub_prefix = prefix + sub + "/"
        slice_ = [s for s in symbols
                  if any(site["file"].startswith(sub_prefix) for site in s["def_sites"])][:15]
        if not slice_:
            continue
        a("### `%s/`" % (scan_rel + "/" + sub))
        a("")
        a("Top-15 slice of the global ranking with a definition under this directory.")
        a("")
        a("| # | Symbol | Kind | Score | Xrefs | Def sites |")
        a("|---|--------|------|-------|-------|-----------|")
        for i, sym in enumerate(slice_, start=1):
            a("| %d | `%s` | %s | %.6f | %d | %s |"
              % (i, _md_escape(sym["name"]), sym["kind"], sym["score"], sym["xref_count"],
                 _md_escape(_sites_str(sym))))
        a("")

    collisions = sum(1 for s in symbols if s["collision"])
    a("---")
    a("")
    a("**Totals:** %d symbols across %d files. %d symbols collide (>1 definition site). "
      "%d files skipped (unparseable)." % (data["symbol_count"], data["file_count"],
                                           collisions, len(data["skipped_files"])))
    if data["skipped_files"]:
        a("")
        a("Skipped: %s" % ", ".join("`%s`" % f for f in data["skipped_files"]))
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description="deterministic stdlib repo-map engine")
    ap.add_argument("--root", required=True, help="project root")
    ap.add_argument("--scan", default=".claude", help="subdir under root to map")
    ap.add_argument("--emit", choices=["json", "md"], default="json")
    args = ap.parse_args()

    scan_root = os.path.join(args.root, args.scan)
    data = build_map(scan_root, args.root)
    if args.emit == "json":
        sys.stdout.write(emit_json(data) + "\n")
    else:
        sys.stdout.write(emit_md(data, args.scan))


if __name__ == "__main__":
    main()
