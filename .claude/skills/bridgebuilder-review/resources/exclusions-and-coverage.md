# Bridgebuilder — exclusion patterns, protected paths, `.reviewignore` provenance, content fetch and the coverage record

Reference for `SKILL.md` § "Large pull requests" and § "Configuration" (cycle-135, bd-ow72o / bd-i4fyw / bd-w5pd9). Read on
demand; `SKILL.md` keeps the short form. The sections below are the full rules the code implements
(`resources/core/truncation.ts`, `resources/core/paged-fetch.ts`, `resources/config.ts`).

## Large pull requests: the paged, SHA-pinned fetch (cycle-128 C-3; cycle-135 C-3)


The file list is read in two passes, never with `--paginate`. Pass 1 pages `pulls/N/files?per_page=100&page=K`
and keeps names, stats and patch sizes only. The selection (Loa tier, `exclude_patterns`, `max_files_per_pr`, tier
order) runs once over the complete list, and `max_diff_bytes` is planned on the recorded sizes. A file that fits is
kept whole. The first that does not is kept cut and recorded `patch_truncated`; the rest are `byte_budget`. Pass 2
re-reads only the pages that hold selected files. `pulls/N` is re-read before every page and after pass 2: a base or
head move restarts the fetch once, and a second move degrades as `pr_head_moved`. One `gh` call receives one page,
bounded by `gh_max_buffer_bytes`.


## Coverage record: the cycle-135 fields

The record is `{base_sha, head_sha, changed_files, listed, reviewed: [{file, bytes, hunks, source?}], omitted: [{file,
reason, reviewable, pattern?, fetch?}], unknown_omitted, degraded, degraded_reasons, mergeBlockedReason, restarts,
protected_kept, reviewignore_source?, reviewignore_changed_in_pr}`. The cycle-135 fields (all optional, so older records
stay readable):

- `omitted[].pattern` names the default or user pattern that excluded an `excluded_loa` or `excluded_pattern` file.
  The posted line reads `` `file` — excluded_pattern · pattern `<p>` ``.
- `protected_kept: [{file, pattern}]` lists protected files that a wildcard user exclusion would have removed, with the
  first matching wildcard. The posted review renders them under "Protected paths kept (n)" as
  `` `file` — kept despite `<pattern>` ``, followed by `then omitted (<reason>)` when a budget still cut the file.
- `reviewignore_source` is `base`, `checkout`, `base_unavailable` or `none`, the place `.reviewignore` was read from.
  `reviewignore_changed_in_pr` is true when the PR's file list contains `.reviewignore`. The posted review shows one
  `.reviewignore: <source>` line, with `(changed in this PR)` when it applies.
- `base_unavailable` means the PR base's copy could not be read, so the checkout's copy was applied. The PR head
  controls that copy, so the record degrades with the fetch-side reason `reviewignore_unavailable` and the merge is
  blocked as `incomplete_coverage`. The posted line reads
  `.reviewignore: base_unavailable (checkout copy applied; review degraded)`.
- Every name and pattern in the posted text is escaped: backticks and line breaks become `'`, and `<`/`>` are
  percent-encoded.

**Added files without a patch (cycle-135 C-3, bd-w5pd9).** GitHub's files list sometimes names an added file without
a patch. When such a file survives the exclusions and the file cap and has `additions > 0`, pass 1 reads its content
with `gh api /repos/<o>/<r>/contents/<path>?ref=<head sha>`. The read is pinned to the listing's head sha and has one
allowlisted shape with no headers. It runs before the byte planning. The synthesized patch is `@@ -0,0 +1,N @@` plus
`+` lines, with CRLF kept and git's `\ No newline at end of file` marker when needed. Its bytes, header and prefixes
included, count against `max_diff_bytes` in selection order. Each read is bounded by what the budget has left at the
file's place in that order, after the GitHub patches and the synthesized patches selected ahead of it. A file that
cannot fit is not read at all. To place the files, the selection runs once with the candidates at size 0 and again on
the real sizes. So whenever a candidate exists the selection runs twice, and a selection WARN (for example a rejected
`.reviewignore` line) can print twice. The file is then reviewed like any other and recorded with
`reviewed[].source: "contents"`; the posted review lists it under "Reviewed from file contents (n)" as
`` `file` (source: contents) ``. Every other outcome leaves today's `no_patch` omission and records why in
`omitted[].fetch`, shown as `· fetch: <outcome>`:

| `fetch` | Meaning |
|---|---|
| `binary` | a NUL byte in the first 8 KiB, or bytes that are not UTF-8 |
| `budget` | the patch cannot fit what `max_diff_bytes` has left at the file's place: no read was issued, or the read succeeded and its synthesized patch did not fit (never cut) |
| `too_large` | the content's `size` exceeds the bound the read was given, GitHub answered `encoding: none` (> 1 MiB), or the response overflowed the read's buffer |
| `error` | the read failed or returned a malformed envelope or base64 |
| `aborted` | not attempted: an earlier read was refused for a rate limit or authorisation (`RATE_LIMITED`, `FORBIDDEN`, HTTP 401/403), which stops the remaining reads |
| `skipped_cap` | beyond `bridgebuilder.max_content_fetches` (default 20; `0` reads nothing) |
| `deadline` | beyond the 120 s budget for all content reads of the review |

`bridgebuilder.fetch_missing_patches: false` turns the read off: such files stay `no_patch` with no `fetch` field. A
head move that restarts the fetch discards every synthesized patch. Modified, renamed and removed files without a
patch are unchanged.

## Exclusion patterns (cycle-135 C-1, bd-ow72o)

`exclude_patterns`, `--exclude`, `.reviewignore` lines and the built-in defaults share one grammar and one matcher, on
every Node version (`path.matchesGlob` is never consulted). Patterns are repository-relative. Each is normalised
when it is loaded: surrounding whitespace is trimmed, blank lines are dropped, and one leading `./` or `/` is
stripped.

- **A pattern without `*`, `?`, `{` or `[` names whole path segments**, like gitignore. One trailing `/` is ignored.
  Without a `/` it matches that segment at any depth: `PROCESS.md` excludes `docs/PROCESS.md` but not
  `MYPROCESS.md` or `PROCESS.md.old`. With a `/` it is anchored at the root and covers the path and its subtree:
  `a/b` excludes `a/b` and `a/b/c` but not `x/a/b`. A `.reviewignore` line such as `secrets/` is such a pattern; it
  is no longer rewritten to `secrets/**`.
- **A wildcard pattern** uses `*` and `?` within one segment, `**` as a whole segment for zero or more segments,
  one level of `{a,b}` alternation, and `[ab]`, `[a-z]` or `[!ab]` classes. All of them match names that start
  with a dot: `**/*.{json,md}` excludes `.claude/x.json`. A wildcard without a `/` floats like gitignore: `*.pem`
  means `**/*.pem` and excludes `keys/a.pem` as well as `a.pem`. A wildcard with a `/` is anchored at the root:
  `docs/*.md` excludes `docs/a.md` but not `x/docs/a.md`.
- **Rejected patterns** are dropped with one `WARN` naming them, so they match nothing: a `!` negation line,
  backslash escapes, extglob (`+(`, `@(`, `!(`, `?(`, `*(`), nested or unbalanced braces, and unterminated, empty
  or nested classes.

A pattern that relied on substring matching stops matching: `.env` no longer excludes `.env.local`. Write `.env*`
for that.

## Protected paths (cycle-135 C-2, bd-i4fyw)

A wildcard user exclusion cannot remove a protected path from the review. The default list is
`.github/workflows/**`, `.github/actions/**`, `.github/CODEOWNERS`, `.claude/settings.json`,
`.claude/settings.local.json`, `.claude/hooks/**`, `.husky/**` and `.reviewignore`.

| Setting | Default |
|---|---|
| `protected_paths` | the list above; a set list replaces it, and `[]` disables protection. Entries use the exclusion grammar. A leading `/` or `./` is stripped. A non-string, an empty entry, a `..` segment or a rejected construct is a config error naming the entry. |
| `fetch_missing_patches` | `true` |
| `max_content_fetches` | `20` (an integer of 0 or more, else a config error) |

The rule does not depend on pattern order. All user patterns that match a file are resolved first, from
`--exclude`, `exclude_patterns` and `.reviewignore`. If one of them is explicit, the file is excluded, because an
explicit name wins over protection. Explicit means a non-wildcard pattern that is anchored at the root, i.e. it
contains a `/` once one trailing `/` is ignored, or one equal to the file's full path. Wildcards and floating segment
names such as `ci.yml`, `workflows`, `.github`, `.github/` or `settings.json` do not defeat protection. A protected
file they match is kept, and the first matching pattern is recorded in `protectedKept`. So `**/*.yml`, `*.yml` and
`ci.yml` keep `.github/workflows/ci.yml`, while `.github/workflows/ci.yml` or the `.reviewignore` line
`.github/workflows/` excludes it. Kept files come first in the selection order, so the file cap and the byte budget
reach them last. The Loa framework tier is not subject to the list: in a Loa repository without the self-review
label it still strips `.claude/settings.json`. Every omission names the default or user pattern that excluded it, in
the `pattern` field and, for one release, as a ` [pattern: <p>]` suffix on its stats.

On a pull request, `protected_paths`, `exclude_patterns`, `fetch_missing_patches` and `max_content_fetches` come from
the trusted config, the same source the provider keys use: `BRIDGEBUILDER_TRUSTED_CONFIG`, else the base branch's
`.loa.config.yaml`, else `origin/main`. A PR head value that differs is ignored with one `WARN` naming the key. These
keys change review scope, not provider identity, so the run is not refused. `--exclude` stays additive. Locally, or
when no trusted source can be read, the checkout's values apply.

`.reviewignore` is read from the PR's base commit when the review knows it (`git show <base_sha>:.reviewignore`, the
same line rules, 10 s and 1 MiB bounds, symlinks refused). A PR therefore cannot change the exclusions of its own
review. Without a base it is read from the checkout. When the base read fails, for example because the base commit is
not in the local clone, the checkout copy governs. The source is then `base_unavailable`, one `WARN` names why, and
the review degrades as `reviewignore_unavailable`. The source is `none` only when neither the base nor the checkout
has the file. It is recorded as `base`, `checkout`, `base_unavailable` or `none`.

## Trusted provider configuration (cycle-129 D-7.5, DEC-0170; cycle-135 adds the review-scope keys)


`hounfour.providers` (keyless and insecure-endpoint declarations, `auth: "{env:VAR}"` key names, `dispatch_group`),
`hounfour.locality` and `bridgebuilder.exit_on_degraded` are read only from trusted configuration:

| Mode | Detected by | Read from |
|------|-------------|-----------|
| local | no PR context | the working tree's `.loa.config.yaml` |
| pull request | `--pr`, `GITHUB_EVENT_NAME` = `pull_request`/`pull_request_target`, or `GITHUB_BASE_REF` set | 1. `BRIDGEBUILDER_TRUSTED_CONFIG` (YAML or JSON text set from a repository variable); 2. `.loa.config.yaml` at `refs/remotes/origin/<base>` (base from `GITHUB_BASE_REF`, else `gh pr view --json baseRefName`); 3. `refs/remotes/origin/main`; 4. none: no keyless or insecure provider is admitted |

On a pull request the head checkout is read only to refuse: a keyless or `allow_insecure_endpoint`
provider the trusted source does not declare that way fails with
`head-only provider declaration refused: <name>`. A provider the trusted config does not declare at
all still fails with `Unknown provider: <name>`. A provider declared `keyless: true` (or with a
literal `auth`) needs no env var. Under `hounfour.locality: local_voices` every voice whose provider
is not `dispatch_group: local` in the trusted config is dropped from the plan with
`locality: local_voices refuses hosted hop <model_id> (<provider>); …` and never rerouted. In CI,
fetch the base branch (`git fetch origin <base>`) before running so step 2 can answer.
