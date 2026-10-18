"""Conformance: the implementation against the reference model over generated inputs.

Each case draws a fixed-seed sample from one class of inputs and requires the
implementation to agree with the model on every sample, including the exact
error message where one is raised.
"""
import importlib
import io
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _oracle_zq_snap as O  # noqa: E402


def mod(name):
    return importlib.import_module("snapkit." + name)


def impl_glob(pattern, path, fold):
    errors = mod("errors")
    try:
        return ("ok", mod("glob").Glob(pattern, fold).match(path))
    except errors.GlobError as exc:
        return ("err", str(exc))


def model_glob(pattern, path, fold):
    try:
        return ("ok", O.glob_match(pattern, path, fold))
    except O.OracleError as exc:
        return ("err", str(exc))


def segs(rng, pieces, lo, hi):
    return "".join(rng.choice(pieces) for _ in range(rng.randint(lo, hi)))


def gen_path(rng, alphabet, max_segments=3, max_len=4):
    return "/".join(segs(rng, alphabet, 1, max_len) for _ in range(rng.randint(1, max_segments)))


def compare_globs(samples, fold=False):
    bad = []
    for pattern, path in samples:
        f = fold(pattern) if callable(fold) else fold
        want, got = model_glob(pattern, path, f), impl_glob(pattern, path, f)
        if want != got:
            bad.append((pattern, path, f, want, got))
    assert not bad, f"{len(bad)} of {len(samples)} differ; first: {bad[0]!r}"


EDGE_TOKENS = ["[", "]", "!", "^", "-", "a", "b", "z", "\\]", "\\-", "\\[", "[:alpha:]", "[:digit:]",
               "[:", ":]", "*", "?", "[]", "[!]", "[^", "1", "A"]


def test_conformance_bracket_edge_tokens():
    rng = random.Random(8103)
    samples = []
    for _ in range(2500):
        pattern = segs(rng, EDGE_TOKENS, 1, 6)
        samples.append((pattern, segs(rng, "[]!^-abz:1A", 1, 5)))
    compare_globs(samples)


def test_conformance_globstar_segments():
    rng = random.Random(8105)
    seg_pieces = ["**", "**", "*", "a", "b", "a*", "**a", "\\*\\*", "?", "*b"]
    names = ["a", "b", "ab", "**", "x", "ba"]
    samples = []
    for _ in range(2000):
        pattern = "/".join(rng.choice(seg_pieces) for _ in range(rng.randint(1, 4)))
        path = "/".join(rng.choice(names) for _ in range(rng.randint(1, 5)))
        samples.append((pattern, path))
    compare_globs(samples)


def test_conformance_case_folding():
    rng = random.Random(8106)
    pieces = ["a", "A", "b", "B", "z", "Z", "_", "é", "É", "*", "?", "[A-c]", "[Z-a]", "[!a]",
              "[!A-Z]", "[[:upper:]]", "[[:lower:]]", "[^[:alpha:]]", "[b-B]", "[aZ]"]
    samples = []
    for _ in range(2000):
        samples.append((segs(rng, pieces, 1, 4), segs(rng, "aAbBzZ_`[éÉ", 1, 4)))
    compare_globs(samples, fold=True)
    compare_globs(samples[:500], fold=False)


def impl_rules(text, source, base):
    errors = mod("errors")
    try:
        got = mod("rules").parse_rules(text, source, base)
    except errors.RuleError as exc:
        return ("err", str(exc))
    return ("ok", [(r.source, r.line, r.text, r.negated, r.dir_only, r.anchored, r.pattern, r.base)
                   for r in got])


def model_rules(text, source, base):
    try:
        return ("ok", O.parse_rules(text, source, base))
    except O.OracleError as exc:
        return ("err", str(exc))


def test_conformance_rule_lines():
    rng = random.Random(8108)
    pieces = ["!", "#", "\\", " ", " ", "/", "/", "a", "*", "[z-a]", "\r", "\t", "\\#", "\\!", "b", "**",
              "\\ ", "[[:no:]]"]
    bad = []
    for i in range(2000):
        lines = [segs(rng, pieces, 0, 6) for _ in range(rng.randint(1, 4))]
        text = "\n".join(lines) + rng.choice(["", "\n", "\r\n"])
        base = rng.choice(["", "d", "d/e"])
        source = (base + "/" if base else "") + ".snapignore"
        want, got = model_rules(text, source, base), impl_rules(text, source, base)
        if want != got:
            bad.append((text, want, got))
    assert not bad, f"{len(bad)} differ; first: {bad[0]!r}"


RULE_PIECES = ["a", "b", "*", "?", "*.log", "x.o", "[ab]", "**", "a*", "[!a]"]
NAMES = ["a", "b", "a.log", "x.o", "b.tmp", "ab", "c"]


def gen_rule_line(rng, anchoring=0.4):
    pattern = "/".join(rng.choice(RULE_PIECES) for _ in range(rng.randint(1, 3)))
    if rng.random() < anchoring:
        pattern = "/" + pattern
    if rng.random() < 0.3:
        pattern += "/"
    if rng.random() < 0.35:
        pattern = "!" + pattern
    return pattern


def gen_rel(rng, max_depth=3):
    return "/".join(rng.choice(NAMES) for _ in range(rng.randint(1, max_depth)))


def build_pair(file_texts, casefold=False, fixed=()):
    ig = mod("ignore").IgnoreRules(casefold=casefold, fixed=fixed)
    model_files = {}
    for base, text in file_texts:
        src = (base + "/" if base else "") + ".snapignore"
        ig.add_file(base, mod("rules").parse_rules(text, src, base))
        model_files[base] = O.parse_rules(text, src, base)
    return ig, model_files


def impl_decision(ig, path, is_dir):
    d = ig.check(path, is_dir)
    return (d.excluded, None if d.rule is None else (d.rule.source, d.rule.line, d.rule.text))


def model_decision(files, path, is_dir, casefold, fixed):
    ex, r = O.check(files, path, is_dir, casefold, fixed)
    return (ex, None if r is None else (r[0], r[1], r[2]))


def test_conformance_nested_files_pruning_and_config_entries():
    rng = random.Random(8111)
    bases = ["", "a", "a/b", "b", "a/b/c", "x.o"]
    bad = []
    for _ in range(400):
        chosen = rng.sample(bases, rng.randint(1, 4))
        texts = [(b, "\n".join(gen_rule_line(rng) for _ in range(rng.randint(1, 4)))) for b in chosen]
        rng.shuffle(texts)
        fixed = [gen_rel(rng, 2) for _ in range(rng.randint(0, 2))]
        fold = rng.random() < 0.25
        ig, files = build_pair(texts, fold, fixed)
        for _ in range(6):
            path = "/".join(rng.choice(NAMES + ["A.LOG", "B"]) for _ in range(rng.randint(1, 4)))
            is_dir = rng.random() < 0.4
            want = model_decision(files, path, is_dir, fold, fixed)
            got = impl_decision(ig, path, is_dir)
            if want != got:
                bad.append((texts, fixed, fold, path, is_dir, want, got))
    assert not bad, f"{len(bad)} differ; first: {bad[0]!r}"


def _model_walk(files, dirs):
    """Simulate the walker over a spec; return ('ok', sorted kept files) or ('err', message)."""
    loaded = {}
    kept = []

    def load(d):
        src = (d + "/" if d else "") + ".snapignore"
        if src in files:
            loaded[d] = O.parse_rules(files[src], src, d)

    def children(d):
        prefix = d + "/" if d else ""
        names = set()
        for p in list(files) + list(dirs):
            if p.startswith(prefix) and p != d:
                names.add(p[len(prefix):].split("/")[0])
        return sorted(names)

    def go(d):
        for name in children(d):
            p = (d + "/" if d else "") + name
            is_dir = p in dirs
            if O.check(loaded, p, is_dir)[0]:
                continue
            if is_dir:
                load(p)
                go(p)
            else:
                kept.append(p)

    try:
        load("")
        go("")
    except O.OracleError as exc:
        return ("err", "snapkit: " + str(exc) + "\n")
    return ("ok", sorted(kept))


def test_conformance_walker_end_to_end(tmp_path):
    cli = mod("cli")
    rng = random.Random(8112)
    dir_names = ["a", "b", "x.o"]
    file_names = ["a.log", "x.o", "b.tmp", "c", "ab"]
    rule_lines = ["*.log", "!a.log", "b/", "/a", "x.o", "!x.o", "*.tmp", "a/*", "!a/c", "**/c", "c/",
                  "!b", "[ab]", "/b/**", "!**/b.tmp", "[!a]*.o ", "\\!x", "[[:lower:]].log", "a/**/c",
                  "*.TMP\r", "x.[o]/", "?.o", "[]a]b", "#a", "", "[z-a]"]
    bad = []
    for n in range(150):
        root = tmp_path / f"t{n}"
        dirs = set()
        files = {}
        for _ in range(rng.randint(3, 10)):
            depth = rng.randint(0, 2)
            parent = "/".join(rng.choice(dir_names) for _ in range(depth))
            for k in range(1, depth + 1):
                dirs.add("/".join(parent.split("/")[:k]))
            name = rng.choice(file_names)
            path = (parent + "/" if parent else "") + name
            if path in dirs:
                continue
            files[path] = "x" * rng.randint(0, 3)
        for d in [""] + sorted(dirs):
            if rng.random() < 0.6:
                src = (d + "/" if d else "") + ".snapignore"
                lines = [rng.choice(rule_lines[:-1] if rng.random() < 0.9 else rule_lines)
                         for _ in range(rng.randint(1, 4))]
                files[src] = "\n".join(lines) + "\n"
        files = {p: c for p, c in files.items() if p not in dirs}
        for d in sorted(dirs):
            os.makedirs(os.path.join(str(root), *d.split("/")), exist_ok=True)
        os.makedirs(str(root), exist_ok=True)
        for p, c in files.items():
            with open(os.path.join(str(root), *p.split("/")), "w", encoding="utf-8") as fh:
                fh.write(c)
        want = _model_walk(files, dirs)
        out, err = io.StringIO(), io.StringIO()
        code = cli.main(["snapshot", "--root", str(root)], out, err)
        if code == 0:
            got = ("ok", [line.split(" ", 2)[2] for line in out.getvalue().splitlines()[1:-1]])
        else:
            got = ("err", err.getvalue())
        if want != got:
            bad.append((files, want, got))
    assert not bad, f"{len(bad)} differ; first: {bad[0]!r}"


MIXED_PIECES = ["a", "b", "A", ".", "*", "?", "**", "/", "\\", "\\*", "[", "]", "!", "^", "-", "[a-c]",
                "[!b]", "[]a]", "[[:alpha:]]", "[[:digit:]]", "[:", ":]", "[z-a]", "[[:x:]]", "[a-", "1",
                "[a-c-e]", "[--0]", "[A-b]"]


def test_conformance_mixed_patterns():
    rng = random.Random(8113)
    samples = []
    for _ in range(2500):
        samples.append((segs(rng, MIXED_PIECES, 1, 7), gen_path(rng, "abA.*?[]!^-:1\\", 3, 4)))
    compare_globs(samples, fold=lambda p: len(p) % 3 == 0)


def test_conformance_mixed_rules_files_and_decisions():
    rng = random.Random(8114)
    line_pieces = [p for p in MIXED_PIECES if p not in ("\\", "[z-a]", "[[:x:]]")] + [
        " ", " ", "\\ ", "#", "\\#", "\r", "*.log", "a/", "/a", "a", "b", "*"]
    bases = ["", "a", "a/b", "b"]
    bad = []
    evaluated = [0]
    for _ in range(300):
        chosen = rng.sample(bases, rng.randint(1, 3))
        texts = []
        for b in chosen:
            lines = []
            for _ in range(rng.randint(1, 5)):
                line = segs(rng, line_pieces, 1, 5)
                if rng.random() < 0.3:
                    line = "!" + line
                lines.append(line)
            texts.append((b, "\n".join(lines)))
        fixed = [gen_rel(rng, 2) for _ in range(rng.randint(0, 2))]
        fold = rng.random() < 0.3
        want_parse = [model_rules(t, (b + "/" if b else "") + ".snapignore", b) for b, t in texts]
        got_parse = [impl_rules(t, (b + "/" if b else "") + ".snapignore", b) for b, t in texts]
        if want_parse != got_parse:
            bad.append(("parse", texts, want_parse, got_parse))
            continue
        if any(w[0] == "err" for w in want_parse):
            continue
        evaluated[0] += 1
        ig, files = build_pair(texts, fold, fixed)
        for _ in range(6):
            path = gen_path(rng, ["a", "b", "A", "a.log", "[a", "1", "!b", "ab"], 4, 2)
            is_dir = rng.random() < 0.4
            want = model_decision(files, path, is_dir, fold, fixed)
            got = impl_decision(ig, path, is_dir)
            if want != got:
                bad.append((texts, fixed, fold, path, is_dir, want, got))
    assert not bad, f"{len(bad)} differ; first: {bad[0]!r}"
    assert evaluated[0] >= 150


# --- extended groups -----------------------------------------------------------


def _glob_cases(seed, n, make_pattern, make_text, fold=False):
    rng = random.Random(seed)
    return [(make_pattern(rng), make_text(rng)) for _ in range(n)], fold


def _ab(rng, lo=1, hi=5, alphabet="ab"):
    return "".join(rng.choice(alphabet) for _ in range(rng.randint(lo, hi)))


def test_conformance_at_and_question_groups():
    pieces = ["a", "b", "@(a|b)", "?(a)", "@(ab|a)", "?(ab|b)", "*", "@(b|ba)", "@(!(a)|b)", "?(!(b))"]
    samples, _ = _glob_cases(8201, 800, lambda r: segs(r, pieces, 1, 4), lambda r: _ab(r))
    compare_globs(samples)


def test_conformance_star_and_plus_groups_with_overlapping_alternatives():
    pieces = ["+(a|ab)", "*(ab|ba)", "+(b|ab|ba)", "*(a)", "a", "b", "*(aa|b)", "+(aba|b)", "+(!(a)b)", "*(!(b)|a)"]
    samples, _ = _glob_cases(8202, 800, lambda r: segs(r, pieces, 1, 3), lambda r: _ab(r, 1, 6))
    compare_globs(samples)


def test_conformance_not_group_with_inner_globs():
    inner = ["*.c", "a*", "?", "ab", "*b*", "[ab]", "", "*", "a.c", "*a"]
    samples, _ = _glob_cases(
        8203, 800, lambda r: "!(" + "|".join(r.choice(inner) for _ in range(r.randint(1, 3))) + ")"
        + r.choice(["", "", "c", ".c", "*", "?"]),
        lambda r: _ab(r, 1, 5, "ab.c"))
    compare_globs(samples)


def test_conformance_not_group_composed_with_neighbours():
    pieces = ["!(a)", "!(ab)", "!(b|ba)", "a", "b", "*", "?", "!(*a)"]

    def pattern(r):
        p = segs(r, pieces, 1, 3)
        return p + "!(" + r.choice(["a", "b", "ab", "a*"]) + ")" if "!(" not in p else p

    samples, _ = _glob_cases(8204, 800, pattern, lambda r: _ab(r, 1, 5))
    compare_globs(samples)


def _gen_group(r, depth):
    op = r.choice("?*+@!")
    alts = ["".join(_gen_piece(r, depth - 1) for _ in range(r.randint(1, 2))) for _ in range(r.randint(1, 2))]
    return op + "(" + "|".join(alts) + ")"


def _gen_piece(r, depth):
    if depth > 0 and r.random() < 0.4:
        return _gen_group(r, depth)
    return r.choice(["a", "b", "a", "b", "*", "?"])


def test_conformance_nested_groups():
    samples, _ = _glob_cases(8205, 600, lambda r: "".join(_gen_piece(r, 2) for _ in range(r.randint(1, 3))),
                             lambda r: _ab(r, 1, 5))
    compare_globs(samples)


def test_conformance_groups_with_brackets_classes_and_escapes():
    inner = ["[ab]", "[!a]", "[[:digit:]]", "\\|", "\\)", "\\*", "1", "a", "[)]", "[|]", "*", "[!|)]", "!([ab])"]

    def pattern(r):
        alts = ["".join(r.choice(inner) for _ in range(r.randint(0, 2))) for _ in range(r.randint(1, 3))]
        return r.choice("?*+@!") + "(" + "|".join(alts) + ")" + r.choice(["", "*", "a", "[|]", "1"])

    samples, _ = _glob_cases(8206, 800, pattern, lambda r: _ab(r, 1, 4, "ab1|)*"))
    compare_globs(samples)


def test_conformance_empty_alternatives_and_empty_groups():
    pieces = ["@()", "?()", "+()", "*()", "!()", "@(|a)", "+(|ab)", "!(|a)", "*(|b)", "a", "b", "!(|)"]
    samples, _ = _glob_cases(8207, 800, lambda r: segs(r, pieces, 1, 4), lambda r: _ab(r, 1, 4))
    compare_globs(samples)


def test_conformance_case_folding_inside_groups():
    pieces = ["@(A|b)", "!(a)", "+([A-B])", "*([[:upper:]])", "?(B)", "!([!a])", "A", "b", "@(*A)"]
    samples, _ = _glob_cases(8208, 800, lambda r: segs(r, pieces, 1, 3), lambda r: _ab(r, 1, 4, "aAbB"))
    compare_globs(samples, fold=True)
    compare_globs(samples[:300], fold=False)


def test_conformance_group_error_messages():
    pieces = ["@(", "!(", "+(", ")", "|", "[z-a]", "[[:x:]]", "\\", "/", "a", "*(", "[", "]", "\\)", "?", "!(a)"]
    samples, _ = _glob_cases(8209, 1000, lambda r: segs(r, pieces, 1, 6), lambda r: _ab(r, 1, 3, "a|)("))
    compare_globs(samples)
    assert sum(1 for p, t in samples if model_glob(p, t, False)[0] == "err") > 300


# --- brace expansion -------------------------------------------------------------


def impl_expand(text):
    errors = mod("errors")
    try:
        return ("ok", mod("braces").expand(text))
    except errors.BraceError as exc:
        return ("err", str(exc))


def model_expand(text):
    try:
        return ("ok", O.expand(text))
    except O.OracleError as exc:
        return ("err", str(exc))


def compare_expansions(texts):
    bad = [(t, model_expand(t), impl_expand(t)) for t in texts]
    bad = [b for b in bad if b[1] != b[2]]
    assert not bad, f"{len(bad)} of {len(texts)} differ; first: {bad[0]!r}"


def _gen_list(r, depth):
    items = []
    for _ in range(r.randint(1, 3)):
        if depth > 0 and r.random() < 0.35:
            items.append(_gen_brace_text(r, depth - 1))
        else:
            items.append(r.choice(["a", "b", "", "ab", "a"]))
    return "{" + ",".join(items) + "}"


def _gen_brace_text(r, depth):
    return "".join(_gen_list(r, depth) if r.random() < 0.6 else r.choice(["x", "y", ""]) for _ in range(r.randint(1, 3)))


def test_conformance_brace_lists_nesting_order_and_duplicates():
    rng = random.Random(8210)
    compare_expansions([_gen_brace_text(rng, 2) for _ in range(800)])


def _num(r):
    v = r.randint(-12, 12)
    s = str(abs(v))
    if r.random() < 0.3:
        s = "0" * r.randint(1, 2) + s
    return ("-" if v < 0 else "") + s


def test_conformance_brace_sequences_padding_and_steps():
    rng = random.Random(8211)
    texts = []
    for _ in range(800):
        if rng.random() < 0.75:
            body = _num(rng) + ".." + _num(rng)
        else:
            alphabet = rng.choice(["abcdefghij", "ABCDEFGHIJ"])
            body = rng.choice(alphabet) + ".." + rng.choice(alphabet)
        if rng.random() < 0.5:
            body += ".." + rng.choice(["1", "2", "3", "-2", "-1", "0", "02", "5"])
        texts.append(rng.choice(["", "f", "x."]) + "{" + body + "}" + rng.choice(["", "z", "{a,b}"]))
    compare_expansions(texts)


def test_conformance_brace_literal_fallbacks_and_escapes():
    rng = random.Random(8212)
    pieces = ["{", "}", ",", "..", "\\", "a", "1", "-", "{a,b}", "{1..3}", "\\{", "\\,", "\\}", "{a}", "[", "]"]
    compare_expansions([segs(rng, pieces, 1, 7) for _ in range(1000)])


def test_conformance_rules_with_braces_and_groups():
    rng = random.Random(8213)
    pieces = ["{a,b}", "{x.o,*.log}", "@(a|b)", "!(a)", "+(ab|a)", "*", "a", "/", "{1..2}", "?(b)", "!(*.log)",
              "{a,b/}", "[ab]", "{01..2}", "{a{b,c}}", "{,b}", "\\{a,b}", "{a,{b,ab}}", "{b..a}"]
    bases = ["", "a", "b"]
    bad = []
    evaluated = 0
    for _ in range(300):
        chosen = rng.sample(bases, rng.randint(1, 2))
        texts = []
        for b in chosen:
            lines = []
            for _ in range(rng.randint(1, 4)):
                line = segs(rng, pieces, 1, 3)
                if rng.random() < 0.3:
                    line = "!" + line
                lines.append(line)
            texts.append((b, "\n".join(lines)))
        want_parse = [model_rules(t, (b + "/" if b else "") + ".snapignore", b) for b, t in texts]
        got_parse = [impl_rules(t, (b + "/" if b else "") + ".snapignore", b) for b, t in texts]
        if want_parse != got_parse:
            bad.append(("parse", texts, want_parse, got_parse))
            continue
        if any(w[0] == "err" for w in want_parse):
            continue
        evaluated += 1
        ig, files = build_pair(texts)
        for _ in range(6):
            path = "/".join(rng.choice(["a", "b", "ab", "x.o", "a.log", "aab", "1", "01", "{ab}", "{a"])
                            for _ in range(rng.randint(1, 3)))
            is_dir = rng.random() < 0.4
            want, got = model_decision(files, path, is_dir, False, ()), impl_decision(ig, path, is_dir)
            if want != got:
                bad.append((texts, path, is_dir, want, got))
    assert not bad, f"{len(bad)} differ; first: {bad[0]!r}"
    assert evaluated >= 150
