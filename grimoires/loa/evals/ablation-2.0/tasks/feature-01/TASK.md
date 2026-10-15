# Task: keep generated artefacts out of a manifest's fix regions

`evals/harness/seed-corpus-from-record.sh` builds review-recall fixtures from a shipped sprint. Its `--build-manifest pr-NN` mode (and the seed mode, which builds the same manifest at its end) turns the curated label file `labels/pr-NN.tsv` of a corpus into `manifests/pr-NN.json`. Every label row whose `label_source` is `fix` becomes one entry of the manifest's `fix_regions` list: a hunk the fix commit changed. The grader uses fix regions to decide whether a finding outside every label was refuted.

Today a fix row on a generated artefact (a bundled `dist/` file, a source map, a checksum file, the repository map) becomes a fix region too. Those files are mechanical by-products of the fix commit, so they make a finding near them look supported when nothing was really fixed there.

## Required behaviour

When the manifest is built, a `fix` row whose `file` is a generated path is skipped: it produces no fix region. A path (relative, `/`-separated, as written in the label file) is generated when any of these holds:

1. one of its directory components (any component except the last) is exactly `dist` — `dist/x.js` and `tools/bb/resources/dist/main.js` are generated; `distribution/a.sh`, `src/redist.sh` and a file named `dist.sh` are not;
2. its file name ends in `.map` or `.d.ts` — `web/app.js.map`, `types/index.d.ts`; but `docs/map.md` and `src/types.ts` are not;
3. its file name is exactly `.checksum`, `checksums.json`, `REPO-MAP.md` or `.build-manifest.json`, at any depth — `skills/x/.checksum`, `.claude/checksums.json`, `grimoires/loa/REPO-MAP.md`; but `my-checksums.json` and `REPO-MAP.md.txt` are not.

Everything else stays exactly as it is:

- fix rows on other paths become fix regions as before, with the same `id`, `file`, `start`, `end` and `source`, in label-file order;
- rows whose `label_source` is `review`, `audit` or `bridgebuilder` are never filtered: a review or audit label on `dist/x.js` or `checksums.json` is still a defect with its anchor line;
- the summary line the mode prints (`pr-NN: <n> label(s), <m> fix region(s); …`) counts only the fix regions that were kept, and `SHA256SUMS` is refreshed as before;
- every existing error (bad label source, missing head file for a kept row, a `must_match` that is not on exactly one line, a bad fixture id) behaves as before.

The test suite runs with `bats tests` from the repository root; `tests/corpus-helper.bash` builds a throwaway corpus. Add a test of your own for the new behaviour.
