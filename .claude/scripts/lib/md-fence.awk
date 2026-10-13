# md-fence.awk: fenced-code tracking for markdown readers written in awk.
#
# md_fence(line) returns 1 when the line opens, closes or sits inside a fenced
# code block and 0 for a line of ordinary text. Call it once per line, in order.
# A fence opens on a line of at least three backticks or tildes (leading
# whitespace allowed); a backtick opener's info string may not contain a
# backtick. It closes only on a line of the same character, at least as long
# as the opener, followed by nothing but whitespace (CommonMark). So a
# four-backtick block may contain three-backtick lines, and a tilde line
# inside a backtick block is plain content.
#
# Shared by tools/check-glossary-terms.sh and validate-artifact.sh
# --type glossary; they prepend this text to their own program, so it must
# stay POSIX awk (mawk, one-true-awk and busybox awk all run it).
function md_fence(line,   t, ch, n, rest) {
    t = line
    sub(/^[[:space:]]+/, "", t)
    ch = substr(t, 1, 1)
    n = 0
    if (ch == "`" || ch == "~") {
        while (substr(t, n + 1, 1) == ch) n++
    }
    rest = substr(t, n + 1)
    if (!_md_fence_len) {
        if (n < 3) return 0
        if (ch == "`" && index(rest, "`")) return 0
        _md_fence_ch = ch; _md_fence_len = n
        return 1
    }
    if (ch == _md_fence_ch && n >= _md_fence_len && rest !~ /[^[:space:]]/) _md_fence_len = 0
    return 1
}
