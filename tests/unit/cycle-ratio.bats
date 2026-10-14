#!/usr/bin/env bats
# tools/cycle-ratio.sh: the kind-count and volume-ratio release-notes lines over a fixture
# git repository and a fixture MODELINV log (grimoires/loa/sdd.md D-10.3, PRD FR-10).

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PROJECT_ROOT}/tools/cycle-ratio.sh"
    R="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "$R"
    cd "$R"
    g() { git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
    g init -q .
    printf 'echo 1\necho 2\n' > a.sh
    printf 'hello\nworld\n' > doc.md
    printf 'not counted\n' > notes.txt
    g add -A
    GIT_AUTHOR_DATE='2026-10-01T00:00:00Z' GIT_COMMITTER_DATE='2026-10-01T00:00:00Z' g commit -q -m base
    FROM="$(git rev-parse HEAD)"
    # a.sh: +3 -1; b.py: +2; c.ts: +1; doc.md: -"hello" +"hi there"; notes.txt and a binary not counted
    printf 'echo 1\necho 3\necho 4\necho 5\n' > a.sh
    printf 'x = 1\ny = 2\n' > b.py
    printf 'export {}\n' > c.ts
    printf 'hi there\nworld\n' > doc.md
    printf 'more\nlines\n' >> notes.txt
    printf '\000\001\002' > blob.sh
    g add -A
    GIT_AUTHOR_DATE='2026-10-02T00:00:00Z' GIT_COMMITTER_DATE='2026-10-02T00:00:00Z' g commit -q -m change
    TO="$(git rev-parse HEAD)"
    mkdir -p grimoires/loa .run
    {
        printf '# Sprint Plan: fixture\n\n**Date:** 2026-10-14\n\n## Sprint 1: One\n\n'
        printf '### Acceptance Criteria\n- [ ] AC-1 not a task · kind: operator\n\n'
        printf '### Technical Tasks\n'
        printf -- '- [ ] Task 1.1: a → **[G-1]** ⇐ none · kind: mechanical\n'
        printf -- '- [x] Task 1.2: b → **[G-1]** · kind:mechanical\n'
        printf -- '- [ ] Task 1.3: c → **[G-1]** · kind: judgment\n'
        printf -- '- [ ] Task 1.4: d → **[G-1]** · kind: operator\n'
        printf -- '- [ ] Task 1.5: untagged → **[G-1]**\n'
        printf '```\n- [ ] Task 9.9: fenced · kind: mechanical\n```\n\n'
        printf '## Sprint 2 (Final): Two\n\n### Task 2.E2E: End-to-End Goal Validation\n'
        printf -- '- [ ] Task 2.E2E: validate → **[G-1]** · kind: judgment\n\n'
        printf '**Acceptance Criteria:**\n- [ ] Each goal validated · kind: mechanical\n\n'
        printf '## Appendix\n\n- [ ] Task 3.1: outside a sprint · kind: mechanical\n'
    } > grimoires/loa/sprint.md
    {
        printf '%s\n' '{"primitive_id":"MODELINV","ts_utc":"2026-09-30T23:59:59.500000Z"}'
        printf '%s\n' '{"primitive_id":"MODELINV","ts_utc":"2026-10-01T12:00:00.123456Z"}'
        printf '%s\n' '{"primitive_id":"MODELINV","ts_utc":"2026-10-02T00:00:00Z"}'
        printf '%s\n' '{"primitive_id":"MODELINV","ts_utc":"2026-10-02T00:00:01Z"}'
        printf '%s\n' '{"primitive_id":"OTHER","ts_utc":"2026-10-01T12:00:00Z"}'
        printf '%s\n' 'not json at all'
        printf '%s\n' '{"primitive_id":"MODELINV","ts_utc":"garbage"}'
    } > .run/model-invoke.jsonl
}

@test "CR-1 prints both lines with the counts, the mapping and the provenance" {
    run "$SCRIPT" --from "$FROM" --to "$TO"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"kinds: mechanical 2 · judgment 2 · operator 1"* ]]
    [[ "$output" == *"volume: script lines changed 7 (*.sh *.py *.ts *.js) · prose bytes changed 15 (*.md) · model calls 2 (MODELINV rows between the two commits' timestamps) · scope: host · modelinv: ${R}/.run/model-invoke.jsonl"* ]]
    # the untagged task line is named on stderr (bats merges it into output)
    [[ "$output" == *"WARN: 1 task line(s)"*"carry no kind: tag"* ]]
}

@test "CR-2 --json carries the same figures, the window and the untagged count" {
    run bash -c '"$0" --from "$1" --to "$2" --json 2>/dev/null' "$SCRIPT" "$FROM" "$TO"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [ "$(jq -r '.kinds.mechanical' <<< "$output")" = 2 ]
    [ "$(jq -r '.kinds.judgment' <<< "$output")" = 2 ]
    [ "$(jq -r '.kinds.operator' <<< "$output")" = 1 ]
    [ "$(jq -r '.kinds.untagged' <<< "$output")" = 1 ]
    [ "$(jq -r '.volume.script_lines_changed' <<< "$output")" = 7 ]
    [ "$(jq -r '.volume.prose_bytes_changed' <<< "$output")" = 15 ]
    [ "$(jq -r '.volume.model_calls' <<< "$output")" = 2 ]
    [ "$(jq -r '.volume.scope' <<< "$output")" = host ]
    [ "$(jq -r '.window.from' <<< "$output")" = "2026-10-01T00:00:00Z" ]
    [ "$(jq -r '.window.to' <<< "$output")" = "2026-10-02T00:00:00Z" ]
    [ "$(jq -r '.from' <<< "$output")" = "$FROM" ]
}

@test "CR-3 a missing MODELINV log yields model calls n/a and a WARN, exit 0" {
    run "$SCRIPT" --from "$FROM" --to "$TO" --modelinv "$R/.run/absent.jsonl"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"model calls n/a (MODELINV rows"* ]]
    [[ "$output" == *"WARN: MODELINV log not found at $R/.run/absent.jsonl"* ]]
    run bash -c '"$0" --from "$1" --to "$2" --modelinv /nonexistent --json 2>/dev/null' "$SCRIPT" "$FROM" "$TO"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.volume.model_calls' <<< "$output")" = null ]
}

@test "CR-4 an unknown SHA exits 3; a SHA shaped like a flag exits 3" {
    run "$SCRIPT" --from 0123456789abcdef0123456789abcdef01234567 --to "$TO"
    [ "$status" -eq 3 ]
    [[ "$output" == *"unknown commit"* ]]
    run "$SCRIPT" --from "$FROM" --to --output=/tmp/x
    [ "$status" -eq 3 ]
}

@test "CR-5 usage errors exit 2: a missing --to, an unknown flag, an unreadable plan, outside a repo" {
    run "$SCRIPT" --from "$FROM"
    [ "$status" -eq 2 ]
    run "$SCRIPT" --from "$FROM" --to "$TO" --bogus
    [ "$status" -eq 2 ]
    run "$SCRIPT" --from "$FROM" --to "$TO" --sprint-plan "$R/nope.md"
    [ "$status" -eq 2 ]
    mkdir -p "${BATS_TEST_TMPDIR}/norepo"
    cd "${BATS_TEST_TMPDIR}/norepo"
    run env GIT_CEILING_DIRECTORIES="${BATS_TEST_TMPDIR}" "$SCRIPT" --from "$FROM" --to "$TO"
    [ "$status" -eq 2 ]
}

@test "CR-6 an explicit --sprint-plan is read; a plan with no task lines counts zero" {
    printf '# Plan\n\n## Sprint 1: x\n\n### Technical Tasks\n- [ ] T · kind: operator\n' > "$R/other.md"
    run bash -c '"$0" --from "$1" --to "$2" --sprint-plan "$3" 2>/dev/null' "$SCRIPT" "$FROM" "$TO" "$R/other.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"kinds: mechanical 0 · judgment 0 · operator 1"* ]]
}
