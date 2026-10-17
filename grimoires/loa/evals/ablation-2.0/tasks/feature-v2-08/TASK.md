# Task: glob ignore rules for snapkit

`snapkit` (under `src/snapkit/`) builds a snapshot of a directory tree: a sorted manifest of every file with its digest and size, a diff between two snapshots, and a `du` summary. Today the only way to leave something out is the config file's `exclude` list of exact relative paths. Add glob ignore rules: a glob matcher with extended groups, brace expansion for rules, rules files read from the tree, their evaluation, and the `check-ignore` and `match` commands. Every rule below is binding and exact; read them all before you start.

The public API you add:

- `snapkit.glob.Glob(pattern, casefold=False)` validates the pattern and raises `snapkit.errors.GlobError` when it is invalid. `Glob.match(path)` returns a bool. `snapkit.glob.match(pattern, path, casefold=False)` is the same as `Glob(pattern, casefold).match(path)`.
- `snapkit.braces.expand(text)` returns the list of strings that brace expansion (section 3a) makes of `text`. It raises `snapkit.errors.BraceError` when the expansion is too large.
- `snapkit.rules.parse_rules(text, source, base="")` returns a list of `snapkit.rules.Rule`. It raises `snapkit.errors.RuleError` for a bad line.
- `Rule` has the attributes `source`, `line`, `text`, `negated`, `dir_only`, `anchored`, `pattern` and `base`, and the method `Rule.matches(path, is_dir, casefold=False)`.
- `snapkit.ignore.IgnoreRules(casefold=False, fixed=())` has `add_file(base, rules)` and `check(path, is_dir)`. `check` returns a `snapkit.ignore.Decision` with the attributes `excluded` (a bool) and `rule` (a `Rule` or `None`).
- `GlobError`, `BraceError` and `RuleError` are subclasses of `snapkit.errors.SnapError`. Their `str()` is exactly the message given below.

Paths are relative, `/`-separated, never empty, and never start or end with `/` (the existing `snapkit.paths.normalize` makes them so).

## 1. Glob patterns

G1. Matching is segment by segment. Before anything else is interpreted, the pattern is split at every `/` character, and the path is split at every `/`. A `/` can therefore never be escaped or put in a bracket: `a[/]b` is the two segments `a[` and `]b`.

G2. Apart from `**` segments (G7), pattern segment *i* must match path segment *i*, and both must have the same number of segments.

G3. Within a segment, a character other than `*`, `?`, `[` and `\` matches itself, except where it starts an extended group (section 2a). `*` matches any run of characters, including the empty run. `?` matches exactly one character.

G4. `\` followed by any character matches that character literally, so `\*`, `\?`, `\[`, `\\` and `\a` are literals. A segment that ends in an odd number of consecutive backslashes is an error: `GlobError` with the message `trailing backslash in pattern <repr>`, where `<repr>` is `repr()` of the whole pattern.

G5. A leading dot is not special: `*` matches `.env`, and `?bc` matches `.bc`.

G6. Case: with `casefold=False` every comparison is exact. With `casefold=True`, a literal character or a bracket member matches an ASCII letter of the path when it matches that letter or the letter's other-case form. So with folding `A` matches `a`, `[A-C]` matches `b`, `[[:upper:]]` matches every ASCII letter, and `[!a]` matches neither `a` nor `A` (B6 applies to members matching in this sense). Non-ASCII characters are never folded.

G7. A segment that is exactly the two characters `**` matches zero or more whole path segments. As the last segment of a pattern that has more than one segment, it matches one or more. So `**/x` matches `x` and `a/b/x`. `a/**/b` matches `a/b` and `a/q/r/b`. `a/**` matches `a/b` and `a/b/c` but not `a`. `**` alone matches every path. A segment where `**` is not the whole segment, such as `a**b`, `**x` or `\*\*`, has no special meaning: each unescaped `*` is an ordinary `*` (G3), and an escaped one is a literal.

## 2. Bracket expressions

B1. A `[` that is not escaped starts a bracket expression when a closing `]` exists in the same segment, found by the tokenising rules below. When none exists, the `[` is a literal `[`, and matching goes on with the character after it as ordinary pattern text. So `[ab` matches the name `[ab`, `[]` matches `[]`, and `[!]` matches `[!]`.

B2. After the `[`, an optional `!` or `^` makes the expression negated. Then the members are read as tokens, left to right:
   - a class token: `[:` followed by one or more lowercase ASCII letters and then `:]`, for example `[:digit:]`;
   - an escaped character: `\` followed by any character, which is that character;
   - any other single character, `[` and `-` included.

B3. The first unescaped `]` closes the expression, except when it is the first member token, right after `[` or after the negation mark. That `]` is a member. So `[]a]` has the members `]` and `a`, and `[!]a]` matches any one character except `]` and `a`.

B4. A range is three tokens in a row: a character token, an unescaped `-`, and a character token. Class tokens are not character tokens. Ranges are read left to right, and the three tokens of a range are used up. Every other `-` is a literal member. So `[a-]`, `[-a]` and `[\-a]` have the members `a` and `-`. `[a-c-e]` is the range `a-c` and the literal members `-` and `e`. `[a-[:digit:]]` is the members `a`, `-` and every digit. A range matches the characters whose code points lie between those of its ends, both ends included. A range whose start has a greater code point than its end is an error: `GlobError` with the message `invalid range <repr start>-<repr end> in pattern <repr>`. For example, `[z-a]` gives `invalid range 'z'-'a' in pattern '[z-a]'`.

B5. The classes are ASCII only. `alpha` is `A-Z a-z`. `digit` is `0-9`. `alnum` is alpha and digit together. `upper` is `A-Z`. `lower` is `a-z`. `space` is space, tab, newline, carriage return, form feed and vertical tab. `punct` is the 32 characters of Python's `string.punctuation`. Any other name is an error: `GlobError` with the message `unknown class <repr name> in pattern <repr>`. For example, `[[:foo:]]` gives `unknown class 'foo' in pattern '[[:foo:]]'`.

B6. A bracket expression matches exactly one character. A plain expression matches a character that some member matches. A negated expression matches a character that no member matches.

B7. Errors are checked in this order. First, the segments are checked left to right for a trailing backslash (G4). Then the pattern is read left to right, and the first of these problems met is raised: a bad range (B4) or an unknown class (B5) in a bracket expression, or an unclosed group (X3). Only an expression that has a closing `]` is checked, so `[z-a` is valid and matches the literal name `[z-a`. An unclosed group is met where its segment ends, so `@(a[z-a]` reports the range and `@(a/[z-a]` reports the unclosed group.

## 2a. Extended groups

X1. Inside a segment, an unescaped `?`, `*`, `+`, `@` or `!` immediately followed by `(` starts an extended group, for example `@(a|b)`. Anywhere else, `(`, `)`, `|`, `+`, `@` and `!` are ordinary characters, and `?` and `*` keep their G3 meaning. So `a|b`, `(a)`, `+a` and `@` match themselves.

X2. A group's text, between its `(` and its closing `)`, is split into alternatives at every `|` that is at the group's own level. An alternative is any glob text: literals, `*`, `?`, escapes, bracket expressions (read by section 2 against the rest of the segment) and nested groups. An alternative may be empty, so `@(|b)` has the alternatives `""` and `b`, and `@()` has the single alternative `""`. `\|` and `\)` are literal characters. A `|` or `)` inside a bracket expression is a member and does not split or close.

X3. When the segment ends before the group's `)`, the error is `GlobError` with the message `unclosed group in pattern <repr>`. Because of G1 a group never spans a `/`, so `@(a/b)` is an unclosed group.

X4. The meaning is defined by sets of strings, where a string is any sequence of characters, the empty one included. Let *U* be the set of strings that match at least one alternative, a string matching an alternative exactly as a whole segment would (G3, G6, B6). Then:
   - `@(…)` matches exactly the strings in *U*;
   - `?(…)` matches the empty string and the strings in *U*;
   - `+(…)` matches every concatenation of one or more strings of *U*;
   - `*(…)` matches the empty string and every concatenation of one or more strings of *U*;
   - `!(…)` matches every string that is not in *U*, the empty string included when it is not in *U*.

X5. A segment matches a path segment exactly when the path segment can be cut into consecutive pieces, one per element of the pattern segment and in order, such that each element matches its piece. An element is a literal character, `?` or a bracket expression (each matches a one-character piece), `*` (any piece) or a group (X4). Every possible cut counts. So `a!(b)c` does not match `abc`, because the only cut gives `!(b)` the piece `b`. It matches `ac` and `abbc`. `!(foo)*` matches `foo`, because `!(foo)` can take the empty piece.

X6. A segment such as `@(**)` is not exactly `**`, so G7 does not apply: inside a group `**` is two ordinary stars.

X7. Case folding (G6) applies to every literal and bracket member inside a group. `!(a)` with folding matches neither `a` nor `A`.

X8. In a rules file, R4 removes a leading `!` before the glob is read. So the line `!(a)` is a negated rule with the pattern `(a)`, and `!!(a)` is a negated rule whose pattern is the group `!(a)`. Write `@(!(a))` for a rule that is not negated but whose pattern starts with a `!(` group.

## 3. Rules files

R1. `parse_rules(text, source, base)` reads the text line by line, splitting at `\n`, and removes one `\r` at the end of a line. Lines are numbered from 1. `source` is the name used in messages and output. `base` is the directory the rules apply to (`""` for the root).

R2. Trailing spaces (U+0020) are removed one at a time. A space is kept, and the removal stops, when the character before it is a backslash preceded by an even number of further consecutive backslashes, which means an odd run of backslashes in total. Other whitespace is never removed, and leading spaces are kept. The resulting line is the rule's `text`.

R3. An empty line is skipped, and so is a line whose first character is `#`. Write `\#` for a pattern that starts with a literal `#`; the backslash stays in the pattern, and G4 makes it a literal.

R4. When the first character is `!`, the rule is `negated` and that one `!` is removed. Write `\!` for a pattern that starts with a literal `!`.

R4a. The rest of the line is then brace-expanded (section 3a). Each resulting string, in expansion order, goes through R5 to R8 on its own and becomes one rule. All of these rules share the line's `source`, `line`, `text` and `negated`. When an expansion is too large, the error is `RuleError` with the message `<source>:<line>: <the BraceError message>`. When one of the strings is bad, the first bad one in expansion order is raised.

R5. When the pattern then ends with `/`, the rule is `dir_only`, and every trailing `/` is removed.

R6. When the pattern is now empty, `RuleError` is raised with the message `<source>:<line>: empty pattern`. So `!`, `/` and `!//` are errors.

R7. When the pattern now contains a `/`, at the start or anywhere else, the rule is `anchored`, and one leading `/` is removed if there is one. A rule that is not anchored matches a path's last segment, at any depth below `base`. So `build/` is unanchored and matches a directory named `build` anywhere. `doc/build` and `/build` are anchored.

R8. The remaining text is the rule's `pattern`. It is validated as a glob (sections 1 and 2). An invalid one raises `RuleError` with the message `<source>:<line>: <the GlobError message for the pattern>`. A file's lines are checked in order, and the first bad line is raised.

R9. `Rule.matches(path, is_dir, casefold=False)` is true when all of these hold. The path lies inside `base`: any path when `base` is `""`, otherwise a path that starts with `base + "/"`. Let *rel* be the part after that prefix. The rule is not `dir_only`, or `is_dir` is true. Finally, the pattern matches *rel* when the rule is anchored, or matches the last segment of *rel* when it is not. Negation does not affect `matches`.

## 3a. Brace expansion

Brace expansion applies to rules-file lines (R4a) and to the `match` command's pattern (C6). `Glob` itself treats `{`, `}` and `,` as ordinary characters. Brace expansion reads only backslash escapes and braces. Bracket expressions and groups mean nothing to it, and it never removes a backslash: `\{`, `\}` and `\,` stay in the result as written, so the glob reads them as literals.

BR1. For an unescaped `{`, its matching `}` is found by scanning forward, counting unescaped `{` up and unescaped `}` down. The match is the `}` at which the count returns to zero. Without one, the `{` is an ordinary character.

BR2. The text between a `{` and its matching `}` is the body. The braces form a list when the body has an unescaped `,` that is not inside a nested `{`…`}` pair. The list's items are the body split at those commas. An item may be empty, so `a{,b}` gives `a` and `ab`.

BR3. Otherwise the braces form a sequence when the whole body is `X..Y` or `X..Y..S`. Here X and Y are both integers, written as an optional `-` and one or more digits, or both single lowercase ASCII letters, or both single uppercase ASCII letters. S is an integer of the same form other than zero. The sequence runs from X towards Y, both ends included when reached, in steps of the absolute value of S (default 1). The sign of S is ignored, so `{1..10..-3}` gives `1 4 7 10` and `{10..1..3}` gives `10 7 4 1`. Letters step by code point, so `{a..e..2}` gives `a c e`.

BR4. Zero padding: when X or Y, written without its `-`, has more than one digit and starts with `0`, every number of the sequence is written with width *w*, the longer of the lengths of X and Y as written, sign included. A negative number is a `-` followed by its absolute value padded with zeros to *w* − 1 digits. A non-negative number is padded with zeros to *w* digits. So `{01..10..3}` gives `01 04 07 10` and `{-05..2}` gives `-05 -04 -03 -02 -01 000 001 002`. Without padding, numbers are written plainly.

BR5. Braces that form neither a list nor a sequence are not special: the `{` is an ordinary character, and scanning goes on with the character after it, so braces inside it can still expand. So `{a}`, `{}`, `{1..a}`, `{a..Z}`, `{+1..3}` and `{1..3..0}` stay as they are, and `{a{b,c}}` gives `{ab}` and `{ac}`.

BR6. The result is every combination, the leftmost braces varying slowest, and each item is expanded in turn. So `{a,b}{1,2}` gives `a1 a2 b1 b2`, and `a{b,c{d,e}}f` gives `abf acdf acef`. A text without special braces expands to itself.

BR7. Duplicates are removed at the end, keeping the first occurrence: `{a,b,a}` gives `a b`.

BR8. When the expansion has more than 256 strings, counted before duplicates are removed, `BraceError` is raised with the message `brace expansion exceeds 256 patterns`.

## 4. Evaluation

E1. `IgnoreRules.add_file(base, rules)` adds the rules of the rules file in directory `base`. The rules that apply to a path are ordered by the depth of their file's `base`, where `""` is depth 0 and `a/b` is depth 2, and within one file by line. So the root file comes first and deeper files come later. The order of the `add_file` calls does not matter.

E2. `fixed` is the config file's `exclude` list. Entry *n*, counting from 1, is a rule with `source` `"config"`, `line` *n*, `text` equal to the entry, and `negated`, `dir_only` and `anchored` all false. It excludes exactly the path equal to the entry, and nothing is folded. An entry outranks every rules file: a path equal to an entry is excluded whatever the rules say. When two entries are equal, the first one counts.

E3. One path is judged as follows. If it equals a `fixed` entry, it is excluded by that entry. Otherwise the last rule, in the E1 order, whose `matches` is true for the path decides. It excludes the path unless it is negated. When no rule matches, the path is not excluded and the deciding rule is `None`.

E4. `check(path, is_dir)` judges each proper ancestor directory of the path in turn, shallowest first, as a directory (for `a/b/c` these are `a`, then `a/b`), and then judges the path itself with the given `is_dir`. The first excluded one decides: the result is `Decision(excluded=True, rule=<the rule that excluded that ancestor or the path>)`. A path inside an excluded directory can therefore never be included again, not even by a later `!` rule. When nothing on the way is excluded, the result is `excluded=False`, and `rule` is the path's own deciding rule, which is a negated rule or `None`.

E5. `IgnoreRules(casefold=True)` folds case when matching rules (G6). The `fixed` entries are always exact.

## 5. Config, walking and commands

C1. The config file accepts two new keys. `ignore_file` names the rules file and defaults to `.snapignore`. Its value must be a plain file name: non-empty, with no `/`, and neither `.` nor `..`. Otherwise the error is `ConfigError` with the message `<source>:<line>: ignore_file must be a plain file name`. `ignore_case` is one of `yes`, `no`, `true` or `false` and defaults to no. Otherwise the error is `ConfigError` with the message `<source>:<line>: ignore_case must be yes, no, true or false`. These follow the existing config error form.

C2. The walker judges with `IgnoreRules(casefold=<ignore_case>, fixed=<the config's exclude list>)`. It reads the rules file of every directory it enters, including the root, before it judges that directory's entries. A rules file is a regular file named `ignore_file` inside the directory. Its `source` is its path relative to the root, such as `.snapignore` or `src/.snapignore`, and its `base` is the directory's path. A rules file is read whether or not it is itself excluded. Exclusion only decides whether the file is listed. The rules file of an excluded directory is never read, so an error in it is never raised. The walker never enters an excluded directory. Every entry is judged with `check(path, is_dir)`. Symbolic links are still skipped, as they are today. Rules files are read as UTF-8. The walk order does not change: depth first, parents before children, each directory's entries in name order. So when several rules files are bad, the error raised is for the first one met in that order.

C3. `snapshot` and `du` use the walker, so excluded files are neither listed nor counted. Their output formats do not change.

C4. `snapkit check-ignore [--root DIR] [--config FILE] PATH...` takes one or more paths relative to the root. `--root` defaults to `.`, and the config file is found as for the other commands. Each `PATH` is normalised with `snapkit.paths.normalize`. It is a directory when it was given with a trailing `/` or when it exists as a directory under the root; otherwise it is a file. The path need not exist. The rules files read are those of the root and of each ancestor directory of the path, down to the first excluded one, following C2 (a rules file is read only when it is a regular file). For each path, one line goes to standard output:
   - when a rule decides, `<source>:<line>:<text>\t<path>`, where `<text>` is the rule's `text` exactly as in R2, with its `!` and slashes. A negated rule prints too. A config entry prints as `config:<n>:<entry>`.
   - when no rule decides, `::\t<path>`.

   `<path>` is the normalised path. The exit status is 0 when at least one path is excluded and 1 when none is.

C5. Errors keep today's form: `snapkit: <message>` on standard error and exit status 2. This covers a bad path, a bad rules file, a bad config and a missing argument. For `check-ignore` and `match`, the lines already printed for earlier paths stay.

C6. `snapkit match [--ignore-case] PATTERN PATH...` brace-expands PATTERN (section 3a) and validates every resulting glob in expansion order before printing anything. Each PATH is normalised with `snapkit.paths.normalize`. For each path it prints `yes\t<path>` when at least one of the globs matches the normalised path, folding case with `--ignore-case`, and `no\t<path>` otherwise. The exit status is 0 when at least one path matched and 1 when none did. A bad pattern prints `snapkit: <the BraceError or the first GlobError message>` and exits with status 2.

The existing suite must stay green. Run it with `python3 -m pytest -q tests`, and add tests of your own for the new rules.
