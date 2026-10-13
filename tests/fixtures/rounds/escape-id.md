# Negative fixture: question ids that carry terminal escapes

Fixture for tools/check-round-independence.sh. Ids are untrusted model output.
The JSON escape below decodes to a raw ESC byte followed by a colour code and
"PASS"; printed with `jq -r` it would repaint the terminal and fake a verdict.
The checker must reject the ids as malformed and print no ESC byte.

<!-- round: 1; questions: [{"id":"\u001b[31mPASS","depends_on":[]},{"id":"Q2","depends_on":[]}] -->

<!-- round: 2; questions: [{"id":"Q3","depends_on":["Q2\u001b[2K"]},{"id":"Q4","depends_on":[]}] -->
