#!/usr/bin/env bash
# ship-0-release-files.sh — cut the 2.0.0-rc.9 release files on the cycle branch BEFORE the final gate pass (PRD R-1/R-3):
#   CHANGELOG: [Unreleased] → fresh placeholder + `## [2.0.0-rc.9] — <date> — Performance follow-ups (release candidate)` with the intro
#   from ~/.cache/loa/cycle-137/ship/rc9-intro.md (one paragraph, starts with "> ");
#   update-loa-bump-version.sh --target 2.0.0-rc.9 under the bounded zone marker (CLAUDE.loa.md header + .loa-version.json);
#   README: version line, version + release badges, install --tag, "What's new" heading and the rc.9 paragraph from
#   ~/.cache/loa/cycle-137/ship/rc9-readme.md; release notes copied from ~/.cache/loa/cycle-137/ship/release-notes-2.0.0-rc.9.md;
#   checksums + REPO-MAP regenerated; semver-bump --from-tag must read next 2.0.0-rc.9. Commits with ship/msg-release-files.txt.
set -euo pipefail
ROOT=/home/merlin/Documents/thj/code/loa; cd "$ROOT"; S=~/.cache/loa/cycle-137/ship; V=2.0.0-rc.9; DATE="$(date -u +%F)"
[[ "$(git branch --show-current)" == feature/cycle-137-performance ]] || { echo "not on the cycle branch" >&2; exit 2; }
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "tracked tree not clean" >&2; exit 2; }
for f in rc9-intro.md rc9-readme.md release-notes-$V.md msg-release-files.txt; do [[ -s "$S/$f" ]] || { echo "missing $S/$f" >&2; exit 2; }; done
grep -q '^## \[2.0.0-rc.9\]' CHANGELOG.md && { echo "rc.9 heading already present" >&2; exit 2; }
for f in rc9-intro.md rc9-readme.md release-notes-$V.md msg-release-files.txt; do grep -qE '\{[A-Z0-9_]+\}' "$S/$f" && { echo "placeholder left in $S/$f" >&2; exit 2; }; done
M="$ROOT/.run/zone-guard-authorization.json"; marker_off() { rm -f -- "$M"; }; trap marker_off EXIT
jq -n --arg e "$(date -u -d '+2 hours' +%FT%TZ)" --arg i "$(date -u +%FT%TZ)" '{scope:"framework", reason:"cycle-137 rc.9 release files (version markers, manifests)", expires_at:$e, issued_at:$i, cycle:"cycle-137-performance-followups"}' > "$M"
python3 - "$S/rc9-intro.md" "$DATE" <<'PY'
import sys, pathlib
intro = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8').strip(); date = sys.argv[2]
p = pathlib.Path('CHANGELOG.md'); t = p.read_text(encoding='utf-8')
head = "## [Unreleased]\n"
i = t.index(head)  # the FIRST [Unreleased] heading (an old one exists deep in history — never count==1)
j = i + len(head)
new = head + f"\n_(nothing yet — rc.9 was cut on {date})_\n\n## [2.0.0-rc.9] — {date} — Performance follow-ups (release candidate)\n\n{intro}\n"
# the former Unreleased body follows the new heading unchanged (it becomes the rc.9 body)
t = t[:i] + new + t[j:]
p.write_text(t, encoding='utf-8'); print("CHANGELOG: rc.9 heading inserted; former Unreleased body is the rc.9 body")
PY
bash .claude/scripts/update-loa-bump-version.sh --target "$V" 2>&1 | tail -2
python3 - "$S/rc9-readme.md" "$V" <<'PY'
import sys, pathlib, re
para = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8').strip(); V = sys.argv[2]; Vb = V.replace('-', '--')
p = pathlib.Path('README.md'); t = p.read_text(encoding='utf-8')
def rep1(pat, new, flags=0):
    global t
    n = len(re.findall(pat, t, flags)); assert n == 1, (pat, n)
    t = re.sub(pat, new, t, count=1, flags=flags)
rep1(r'^Version: 2\.0\.0-rc\.8$', f'Version: {V}', re.M)
rep1(r'badge/version-2\.0\.0--rc\.8-blue\.svg', f'badge/version-{Vb}-blue.svg')
rep1(r'\[!\[Release\]\(https://img\.shields\.io/badge/release-v2\.0\.0--rc\.8%20The%20follow--through-purple\.svg\)\]\(https://github\.com/0xHoneyJar/loa/releases/tag/v2\.0\.0-rc\.8\)',
     f'[![Release](https://img.shields.io/badge/release-v{Vb}%20Performance%20follow--ups-purple.svg)](https://github.com/0xHoneyJar/loa/releases/tag/v{V})')
rep1(r'^## What\'s new in v2\.0\.0-rc\.8 \(release candidate\)$', f"## What's new in v{V} (release candidate)", re.M)
rep1(r'--tag v2\.0\.0-rc\.8$', f'--tag v{V}', re.M)
anchor = '**rc.8 — the follow-through**'
i = t.index(anchor); t = t[:i] + para + "\n\n" + t[i:]
p.write_text(t, encoding='utf-8'); print("README: version, badges, heading, pin, rc.9 paragraph")
PY
cp "$S/release-notes-$V.md" "grimoires/loa/reports/release-notes-$V.md"
bash tools/gen-checksums.sh --root "$ROOT" >/dev/null; bash tools/gen-checksums.sh --check --root "$ROOT"
bash .claude/scripts/repo-map-gen.sh >/dev/null; bash .claude/scripts/repo-map-gen.sh --validate
bash tools/check-manifest-paths.sh; marker_off; trap - EXIT
bash .claude/scripts/check-loa.sh 2>&1 | tail -1
bash .claude/scripts/semver-bump.sh --from-tag 2>/dev/null | jq -r '"semver: current \(.current) → next \(.next)"'
bash tools/check-prompt-budget.sh 2>&1 | tail -2 || true
git add CHANGELOG.md README.md .loa-version.json .claude/loa/CLAUDE.loa.md .claude/checksums.json grimoires/loa/REPO-MAP.md grimoires/loa/REPO-MAP.md.checksum "grimoires/loa/reports/release-notes-$V.md"
git diff --cached --stat | tail -9
git commit -q -F "$S/msg-release-files.txt"; git rev-parse --short HEAD
