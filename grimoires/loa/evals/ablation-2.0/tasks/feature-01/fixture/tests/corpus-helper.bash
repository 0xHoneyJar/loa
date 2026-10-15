# corpus-helper.bash — builds a throwaway review-prs corpus for the manifest tests.
#
#   make_corpus <corpus-dir> <label-row>...
#
# Writes <corpus>/pr-01/fixture.yaml, one head/<file> per distinct file the rows
# name (30 lines "row-001" … "row-030") and <corpus>/labels/pr-01.tsv with the
# pending approval line, the header and the rows (each row is one tab-separated
# line: defect_id severity category file must_match label_source source).

SEED="${BATS_TEST_DIRNAME}/../evals/harness/seed-corpus-from-record.sh"

make_corpus() {
  local c="$1"; shift
  mkdir -p "$c/pr-01/head" "$c/labels"
  printf 'sprint: 901\nhead_commit: "1111111111111111111111111111111111111111"\nfix_commit: "2222222222222222222222222222222222222222"\nrecord_ref: "record/cycle-901-a2a"\n' > "$c/pr-01/fixture.yaml"
  {
    printf '# approved-by: pending\n'
    printf 'defect_id\tseverity\tcategory\tfile\tmust_match\tlabel_source\tsource\n'
  } > "$c/labels/pr-01.tsv"
  local row file
  for row in "$@"; do
    printf '%s\n' "$row" >> "$c/labels/pr-01.tsv"
    file="$(printf '%s' "$row" | cut -f4)"
    if [[ ! -f "$c/pr-01/head/$file" ]]; then
      mkdir -p "$(dirname "$c/pr-01/head/$file")"
      local i=1
      while [[ $i -le 30 ]]; do printf 'row-%03d\n' "$i"; i=$((i+1)); done > "$c/pr-01/head/$file"
    fi
  done
}

# fix_row <id> <file> <start> <end> — one label_source=fix row
fix_row() { printf '%s\tlow\tfix\t%s\t-\tfix\tfix/abcdef12:%s-%s' "$1" "$2" "$3" "$4"; }
# review_row <id> <file> <must_match> [severity] — one label_source=review row
review_row() { printf '%s\t%s\tlogic\t%s\t%s\treview\tengineer-feedback-r1.md' "$1" "${4:-medium}" "$2" "$3"; }
