#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TOOL="$REPO_ROOT/tools/aleph-release-ingest.py"
    PIN="$REPO_ROOT/.loa-aleph.lock.json"
    PIN_BUNDLE_DIGEST="$(
        jq -er '.bundle.digest | select(test("^sha256:[0-9a-f]{64}$"))' "$PIN"
    )"
    COMPARE_FIXTURES="$REPO_ROOT/tests/fixtures/aleph-release-compare"
    FIX="$BATS_TEST_TMPDIR/aleph-ingest"
    mkdir -p "$FIX"
}

copy_installed_tree() {
    local destination="$1"
    mkdir -p "$destination/.claude/commands" "$destination/.claude/skills"
    cp -R "$REPO_ROOT/.claude/aleph" "$destination/.claude/aleph"
    cp "$REPO_ROOT/.claude/commands/loa-aleph.md" \
        "$destination/.claude/commands/loa-aleph.md"
    cp -R "$REPO_ROOT/.claude/skills/loa-aleph" \
        "$destination/.claude/skills/loa-aleph"
    cp "$PIN" "$destination/.loa-aleph.lock.json"
}

make_release() {
    local output="$1"
    mkdir -p "$output"
    python3 - "$TOOL" "$REPO_ROOT" "$output" <<'PY'
import hashlib
import importlib.util
import json
import pathlib
import sys

tool_path = pathlib.Path(sys.argv[1])
repo = pathlib.Path(sys.argv[2])
output = pathlib.Path(sys.argv[3])
spec = importlib.util.spec_from_file_location("loa_aleph_ingest_fixture", tool_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

bundle_root = repo / ".claude/aleph/runtime/bundle"
entries = []
for path in bundle_root.rglob("*"):
    if path.is_symlink():
        raise SystemExit(f"fixture bundle contains symlink: {path}")
    if path.is_file():
        relative = path.relative_to(bundle_root).as_posix()
        entries.append((f"aleph-for-loa/{relative}", path.read_bytes()))
entries.sort(key=lambda item: item[0].encode("utf-8"))
archive = module._encode_gzip(module._encode_tar(entries))

lock = json.loads((bundle_root / "bundle.lock.json").read_bytes())
pin = json.loads((repo / ".loa-aleph.lock.json").read_bytes())
bundle_hex = lock["bundle"]["digest"].removeprefix("sha256:")
base = f"aleph-for-loa-{lock['bundle']['version']}-sha256-{bundle_hex}"
archive_name = f"{base}.tar.gz"
checksum_name = f"{base}.sha256"
metadata_name = f"{base}.release.json"
archive_digest = hashlib.sha256(archive).hexdigest()
metadata = {
    "format": "aleph-loa-release/v1",
    "release": {
        "id": "aleph-for-loa",
        "version": lock["bundle"]["version"],
        "maturity": "structural-prerelease",
    },
    "source": {
        "build_commit": pin["release"]["commit"],
        "dependency_closure_commit": pin["source"]["dependency_closure_commit"],
        "provenance_digest": pin["source"]["provenance_digest"],
    },
    "bundle": {
        "digest": lock["bundle"]["digest"],
        "payload_digest": lock["bundle"]["payload_digest"],
        "lock_digest": lock["lock_digest"],
        "core_digest": lock["core"]["tree_digest"],
        "adapter_digest": lock["adapter"]["tree_digest"],
        "checker_digest": lock["checker_digest"],
        "adapter_lifecycle": lock["adapter"]["lifecycle"],
    },
    "asset": {
        "filename": archive_name,
        "digest": f"sha256:{archive_digest}",
        "checksum_filename": checksum_name,
    },
}
(output / archive_name).write_bytes(archive)
(output / checksum_name).write_bytes(
    f"{archive_digest}  {archive_name}\n".encode("ascii")
)
(output / metadata_name).write_bytes(module._canonical_json_bytes(metadata))
PY
}

assert_ancestry_rejected() {
    local case_name="$1"
    local base="${2:-c86f0a02aa01d2b8304b62ff8406dcc31ad0af83}"
    local head="${3:-dd3b6ce9ada397b8126c2283d23bd1073b1ff322}"
    local page_size="${4:-100}"
    run python3 "$TOOL" verify-ancestry \
        --compare-pages "$COMPARE_FIXTURES/$case_name" \
        --base "$base" \
        --head "$head" \
        --page-size "$page_size"
    if [ "$status" -eq 0 ]; then
        echo "expected ancestry fixture to fail: $case_name"
        echo "$output"
        return 1
    fi
}

@test "cycle-115 release ingestion: real GitHub compare shape proves strict ancestry without head_commit" {
    ! grep -R -q '"head_commit"' "$COMPARE_FIXTURES/real-no-head-commit"
    run python3 "$TOOL" verify-ancestry \
        --compare-pages "$COMPARE_FIXTURES/real-no-head-commit" \
        --base c86f0a02aa01d2b8304b62ff8406dcc31ad0af83 \
        --head dd3b6ce9ada397b8126c2283d23bd1073b1ff322
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS verify-ancestry"* ]]
    [[ "$output" == *"commits=1"* ]]
}

@test "cycle-115 release ingestion: complete paginated compare records are accepted" {
    run python3 "$TOOL" verify-ancestry \
        --compare-pages "$COMPARE_FIXTURES/paginated" \
        --base 0ec1a8b54971784c4dbb27aef4220279071c521b \
        --head dd3b6ce9ada397b8126c2283d23bd1073b1ff322 \
        --page-size 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"commits=2"* ]]
}

@test "cycle-115 release ingestion: malformed and incomplete compare responses fail closed" {
    assert_ancestry_rejected malformed
    assert_ancestry_rejected truncated
    assert_ancestry_rejected pagination-gap
    assert_ancestry_rejected pagination-metadata-mismatch \
        0ec1a8b54971784c4dbb27aef4220279071c521b \
        dd3b6ce9ada397b8126c2283d23bd1073b1ff322 1
}

@test "cycle-115 release ingestion: non-descendant compare responses fail closed" {
    assert_ancestry_rejected divergent
    assert_ancestry_rejected behind
    assert_ancestry_rejected unrelated
    assert_ancestry_rejected wrong-base
    assert_ancestry_rejected wrong-merge-base
    assert_ancestry_rejected wrong-head
}

@test "cycle-115 release ingestion: invalid commit ordering and records fail closed" {
    assert_ancestry_rejected unordered \
        0ec1a8b54971784c4dbb27aef4220279071c521b \
        c86f0a02aa01d2b8304b62ff8406dcc31ad0af83
    assert_ancestry_rejected duplicate
    assert_ancestry_rejected malformed-parent
}

@test "cycle-115 release ingestion: committed pin and installation verify offline" {
    run python3 "$TOOL" verify-installed --root "$REPO_ROOT" --pin "$PIN"
    [ "$status" -eq 0 ]
    [ "$output" = "PASS verify-installed $PIN_BUNDLE_DIGEST" ]
}

@test "cycle-115 release ingestion: canonical reconstructed release verifies" {
    make_release "$FIX/release"
    run python3 "$TOOL" verify-release --release "$FIX/release" --pin "$PIN"
    [ "$status" -eq 0 ]
    [ "$output" = "PASS verify-release $PIN_BUNDLE_DIGEST" ]
}

@test "cycle-115 release ingestion: checksum and archive tamper fail closed" {
    make_release "$FIX/release"
    local sidecar archive
    sidecar=$(find "$FIX/release" -maxdepth 1 -name '*.sha256' -type f)
    archive=$(find "$FIX/release" -maxdepth 1 -name '*.tar.gz' -type f)
    printf 'tamper' >> "$sidecar"
    run python3 "$TOOL" verify-release --release "$FIX/release" --pin "$PIN"
    [ "$status" -ne 0 ]
    [[ "$output" == *"checksum sidecar"* ]]

    make_release "$FIX/release-archive"
    archive=$(find "$FIX/release-archive" -maxdepth 1 -name '*.tar.gz' -type f)
    printf 'tamper' >> "$archive"
    run python3 "$TOOL" verify-release --release "$FIX/release-archive" --pin "$PIN"
    [ "$status" -ne 0 ]
    [[ "$output" == *"asset identity mismatch"* || "$output" == *"gzip"* ]]
}

@test "cycle-115 release ingestion: release rejects an extra empty directory" {
    make_release "$FIX/release"
    mkdir "$FIX/release/extra"
    run python3 "$TOOL" verify-release --release "$FIX/release" --pin "$PIN"
    [ "$status" -ne 0 ]
    [[ "$output" == *"non-regular top-level entry"* ]]
}

@test "cycle-115 release ingestion: archive rejects traversal, links, modes, and ordering" {
    run python3 - "$TOOL" <<'PY'
import importlib.util
import pathlib
import struct
import sys

spec = importlib.util.spec_from_file_location("loa_aleph_archive_cases", pathlib.Path(sys.argv[1]))
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

def reject(raw, label):
    try:
        module._parse_tar(raw)
    except module.VerificationError:
        return
    raise SystemExit(f"malformed tar case passed: {label}")

reject(module._encode_tar([("aleph-for-loa/../escape", b"x")]), "traversal")
reject(module._encode_tar([("aleph-for-loa/.git/config", b"x")]), "nested git metadata")
reject(module._encode_tar([("aleph-for-loa/.GiT/config", b"x")]), "case-folded git metadata")
reject(module._encode_tar([
    ("aleph-for-loa/z", b"z"),
    ("aleph-for-loa/a", b"a"),
]), "unsorted")

def mutated_header(typeflag=None, mode=None):
    data = b"x"
    header = bytearray(module._tar_header("aleph-for-loa/file", len(data)))
    if typeflag is not None:
        header[156] = ord(typeflag)
    if mode is not None:
        header[100:108] = module._tar_octal(mode, 8)
    header[148:156] = b" " * 8
    header[148:156] = f"{sum(header):06o}\0 ".encode("ascii")
    return bytes(header) + data + b"\0" * 511 + b"\0" * 1024

reject(mutated_header(typeflag="2"), "symlink")
reject(mutated_header(mode=0o755), "mode")
print("PASS archive adversarial cases")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS archive adversarial cases"* ]]
}

@test "cycle-115 release ingestion: pin asset filenames are bound to version and digest" {
    python3 - "$PIN" "$FIX/bad-pin.json" <<'PY'
import json
import pathlib
import sys
value = json.loads(pathlib.Path(sys.argv[1]).read_bytes())
value["assets"][0]["name"] = "arbitrary.release.json"
value["assets"].sort(key=lambda item: item["name"].encode("utf-8"))
pathlib.Path(sys.argv[2]).write_text(
    json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
    run python3 "$TOOL" verify-installed --root "$REPO_ROOT" --pin "$FIX/bad-pin.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"asset names disagree"* ]]
}

@test "cycle-115 release ingestion: installed extra Aleph file is rejected" {
    copy_installed_tree "$FIX/root"
    printf 'not managed\n' > "$FIX/root/.claude/aleph/extra"
    run python3 "$TOOL" verify-installed \
        --root "$FIX/root" --pin "$FIX/root/.loa-aleph.lock.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"inventory disagrees"* ]]
}

@test "cycle-115 release ingestion: installed pin mode drift is rejected" {
    copy_installed_tree "$FIX/root"
    chmod 0600 "$FIX/root/.loa-aleph.lock.json"
    run python3 "$TOOL" verify-installed \
        --root "$FIX/root" --pin "$FIX/root/.loa-aleph.lock.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"pin mode must be 0644"* ]]
}

@test "cycle-115 release ingestion: candidate forbids extra directory topology" {
    copy_installed_tree "$FIX/candidate"
    mkdir -p "$FIX/candidate/unauthorized/empty"
    run python3 "$TOOL" seal-candidate \
        --candidate "$FIX/candidate" \
        --pin "$FIX/candidate/.loa-aleph.lock.json" \
        --output "$FIX/seal.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"directory topology exceeds exact allowlist"* ]]
}

@test "cycle-115 release ingestion: candidate explicitly forbids settings and checksums" {
    copy_installed_tree "$FIX/candidate"
    printf '{}\n' > "$FIX/candidate/.claude/settings.json"
    run python3 "$TOOL" seal-candidate \
        --candidate "$FIX/candidate" \
        --pin "$FIX/candidate/.loa-aleph.lock.json" \
        --output "$FIX/seal.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"explicitly forbidden paths: .claude/settings.json"* ]]

    rm "$FIX/candidate/.claude/settings.json"
    printf '{}\n' > "$FIX/candidate/.claude/checksums.json"
    run python3 "$TOOL" seal-candidate \
        --candidate "$FIX/candidate" \
        --pin "$FIX/candidate/.loa-aleph.lock.json" \
        --output "$FIX/seal.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"explicitly forbidden paths: .claude/checksums.json"* ]]
}

@test "cycle-115 release ingestion: sealed writer installs and upgrades without nesting" {
    copy_installed_tree "$FIX/candidate"
    mkdir "$FIX/destination"
    run python3 "$TOOL" seal-candidate \
        --candidate "$FIX/candidate" \
        --pin "$FIX/candidate/.loa-aleph.lock.json" \
        --output "$FIX/seal.json"
    [ "$status" -eq 0 ]

    run python3 "$TOOL" write-candidate \
        --candidate "$FIX/candidate" \
        --pin "$FIX/candidate/.loa-aleph.lock.json" \
        --seal "$FIX/seal.json" \
        --root "$FIX/destination"
    [ "$status" -eq 0 ]
    [ ! -e "$FIX/destination/.claude/aleph/runtime/bundle/bundle" ]

    run python3 "$TOOL" write-candidate \
        --candidate "$FIX/candidate" \
        --pin "$FIX/candidate/.loa-aleph.lock.json" \
        --seal "$FIX/seal.json" \
        --root "$FIX/destination"
    [ "$status" -eq 0 ]
    [ ! -e "$FIX/destination/.claude/aleph/runtime/bundle/bundle" ]
    [ -z "$(find "$FIX/destination/.claude/aleph/runtime" -maxdepth 1 -name '.bundle.aleph-*' -print)" ]
}

@test "cycle-115 release ingestion: staged index must preserve sealed bytes and modes" {
    copy_installed_tree "$FIX/candidate"
    mkdir "$FIX/destination"
    git -C "$FIX/destination" init -q -b main
    printf '* text=auto\n' > "$FIX/destination/.gitattributes"
    git -C "$FIX/destination" add .gitattributes
    git -C "$FIX/destination" \
        -c user.name='Aleph Fixture' \
        -c user.email='aleph-fixture@example.invalid' \
        commit -qm 'initialize attributed destination'
    python3 "$TOOL" seal-candidate \
        --candidate "$FIX/candidate" \
        --pin "$FIX/candidate/.loa-aleph.lock.json" \
        --output "$FIX/seal.json"
    python3 "$TOOL" write-candidate \
        --candidate "$FIX/candidate" \
        --pin "$FIX/candidate/.loa-aleph.lock.json" \
        --seal "$FIX/seal.json" \
        --root "$FIX/destination"
    git -C "$FIX/destination" add -A -- \
        .loa-aleph.lock.json .claude/aleph \
        .claude/commands/loa-aleph.md .claude/skills/loa-aleph/SKILL.md

    run python3 "$TOOL" verify-index \
        --candidate "$FIX/candidate" \
        --pin "$FIX/candidate/.loa-aleph.lock.json" \
        --seal "$FIX/seal.json" \
        --root "$FIX/destination"
    [ "$status" -eq 0 ]

    local path='.claude/commands/loa-aleph.md' object_id
    object_id=$(printf 'index byte drift\r\n' | git -C "$FIX/destination" hash-object -w --stdin)
    git -C "$FIX/destination" update-index --cacheinfo 100644 "$object_id" "$path"
    run python3 "$TOOL" verify-index \
        --candidate "$FIX/candidate" \
        --pin "$FIX/candidate/.loa-aleph.lock.json" \
        --seal "$FIX/seal.json" \
        --root "$FIX/destination"
    [ "$status" -ne 0 ]
    [[ "$output" == *"staged blob differs from sealed candidate bytes"* ]]
}

@test "cycle-115 release ingestion: managed-byte tamper is detected" {
    copy_installed_tree "$FIX/root"
    printf 'tamper\n' >> "$FIX/root/.claude/aleph/bin/loa-aleph.mjs"
    run python3 "$TOOL" verify-installed \
        --root "$FIX/root" --pin "$FIX/root/.loa-aleph.lock.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"digest mismatch"* ]]
}

@test "cycle-115 release ingestion: workflows preserve the read-then-write boundary" {
    local sync="$REPO_ROOT/.github/workflows/aleph-release-sync.yml"
    local integrity="$REPO_ROOT/.github/workflows/aleph-bundle-integrity.yml"
    grep -q 'release verify "$RELEASE_TAG"' "$sync"
    grep -q 'release verify-asset "$RELEASE_TAG"' "$sync"
    grep -q 'current-digest:' "$sync"
    grep -q 'Upstream comparison:' "$sync"
    grep -q 'pull-requests: write' "$sync"
    grep -Fq 'GH_TOKEN: ${{ github.token }}' "$sync"
    grep -q 'verify-index' "$sync"
    grep -q 'verify-ancestry' "$sync"
    grep -Fq 'per_page=100&page=$page' "$sync"
    ! grep -q 'head_commit' "$sync"
    [ "$(grep -c "'.claude/commands/loa-aleph\*\.md'" "$integrity")" -eq 2 ]
    grep -q 'node:.*\[' "$integrity"
    ! grep -Eq 'gh pr (merge|review)|--auto|enablePullRequestAutoMerge' "$sync"

    python3 - "$sync" "$integrity" <<'PY'
import pathlib
import re
import sys
for filename in sys.argv[1:]:
    text = pathlib.Path(filename).read_text(encoding="utf-8")
    uses = re.findall(r"^\s*uses:\s*([^\s#]+)", text, flags=re.MULTILINE)
    if not uses or any(not re.fullmatch(r"[^@]+@[0-9a-f]{40}", value) for value in uses):
        raise SystemExit(f"workflow action is not commit pinned: {filename}")
PY
}
