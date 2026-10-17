# Task: Markdown block structure renders wrongly

`mdblocks` (under `src/mdblocks/`) parses the block structure of a Markdown document, following a stated subset of CommonMark 0.31.2, and renders it as HTML in the exact form markdown-it 14 produces. The public API is `render(text) -> str`, the HTML of a document, and `parse(text) -> Node`, the block tree, both importable from `mdblocks`. A `Node` has `kind`, `children`, `start_line` and `end_line`, and leaf-specific fields.

**Bug (observed):** The rules below are the specification. The implementation deviates from it in several places across the package, and the symptoms below are only the ones reported so far. The fix must make `render` conform to every rule of § Expected, not only to these symptoms.
- `- - -` and `* * *` come out as nested lists instead of thematic breaks.
- A paragraph followed by `2. two` swallows the line into a new ordered list. `0. zero` renders as `<ol>` without `start="0"`.
- `- a` followed by `+ b` gives one list instead of two.
- Some lists with a blank line between two paragraphs of one item render tight, without `<p>` tags.
- A fenced code block opened with four backticks is closed by a line of three.
- The language class of a fence with the info string `c extra` is `language-c extra`.

**Expected:**

*Input and text*
1. The input never contains a tab, and every document ends with a line ending. A line ends at `\n`, `\r\n` or `\r`. A line is blank when it is empty or holds only spaces. Columns and indentation are counted in spaces.
2. Inline syntax is not interpreted. The text of a paragraph or heading is rendered with only `&`, `<`, `>` and `"` escaped, as `&amp;`, `&lt;`, `&gt;` and `&quot;`. The documents checked never contain, in paragraph or heading text, a character that markdown-it's inline rules would interpret: `` ` `` `*` `_` `~` `[` `]` `\`. HTML blocks and link reference definitions are not part of this subset.
3. The text of a paragraph, and of a heading, is its lines in order. Each line has its leading and trailing spaces removed, the lines are joined with `\n`, and the result is trimmed.

*The parsing strategy: each line, in order, goes through three steps*

4. **Step 1, continuation.** Walk the chain of open blocks from the document inwards, the innermost open child of each block in turn. For each open block, apply its continuation rule (rules 12–18) to the rest of the line, starting at the current position. A block that continues consumes its prefix, and the walk goes on to its open child. At the first block that does not continue, the walk stops. That block and every block inside it are *unmatched*, and the block before it is the *last matched* block. A closing code fence (rule 17) ends the processing of the line.
5. **Step 2, new blocks.** If the last matched block is a code block, skip this step. Otherwise, at the first non-space character of the rest of the line, try these starts in this order: block quote, ATX heading, fenced code, setext underline, thematic break, list item, indented code. The *current block* is the last matched block, or the block most recently opened in this step. A start that opens a container (a block quote or list item) consumes its marker, and the search repeats on what follows. A start that opens a leaf ends the step. Before a start adds anything, the unmatched blocks are closed.
6. **Step 3, the rest of the line.** Suppose no start was found in step 2, some block was unmatched, the line is not blank, and the innermost open block is a paragraph. Then the rest of the line is a *lazy continuation* line of that paragraph: it is appended to the paragraph, and nothing is closed. Otherwise the unmatched blocks are closed. If the current block is a paragraph or a code block, the rest of the line is added to it. Otherwise, if the rest is not blank, a paragraph is opened, and the rest from its first non-space character is its first line.
7. Adding a block to a block that cannot contain it closes the receiving block first, and so on outwards. A list contains only list items. A list item cannot directly contain a list item. Leaves contain nothing. At the end of the document every open block is closed.

*Starts (step 2). "Indent" is the number of spaces before the first non-space character of the rest of the line. A start needs an indent of at most 3, except indented code.*

8. **Block quote:** a `>`. It consumes the `>` and one following space, if there is one.
9. **ATX heading:** 1 to 6 `#` followed by a space or the end of the line. The level is the number of `#`. The content is the rest of the line after the `#` and the spaces after them, with any closing sequence removed. If the content is a single run of `#` and nothing else, the heading is empty. Otherwise a final run of `#`, preceded by at least one space and followed only by spaces, is removed together with those spaces. So `# foo#` has the text `foo#`. A heading is one line.
10. **Fenced code:** 3 or more backticks, with no backtick in the rest of the line, or 3 or more tildes. The fence character, the fence length and the fence indent are recorded. The rest of the opening line, trimmed, is the info string.
11. **Setext underline:** only when the current block is a paragraph. The line is one or more `=`, or one or more `-`, followed only by spaces. The paragraph becomes a heading of level 1 (`=`) or 2 (`-`) with the paragraph's lines, and the underline line is consumed. A lazy continuation line can never be an underline, because the paragraph is then not the current block.
12. **Thematic break:** three or more `-`, or three or more `*`, or three or more `_`, all the same character, with only spaces between and after them. Because of the order in rule 5, `a` then `---` is a setext heading, and `- - -` and `* * *` are thematic breaks, not list items.
13. **List item:** a bullet `-`, `+` or `*`, or an ordered marker of 1 to 9 digits followed by `.` or `)`, followed by a space or the end of the line. When the current block is a paragraph, two restrictions apply: an ordered marker must have the number 1, and the item must not be empty (the rest of the line after the marker must not be blank). Let `S` be the number of spaces after the marker. If `S` is 0 (the end of the line), or the rest after the marker is blank, or `S` ≥ 5, the content starts one column after the marker, consuming one space if there is one. Otherwise the content starts after the `S` spaces. The item's content column `W` is the marker's indent plus the marker's width plus those spaces. So `-     code` is an item holding an indented code block.
14. **Lists:** a list item is added to the open list when the innermost open block (after closing the unmatched blocks) is a list of the same type. For bullets that means the same bullet character, and for ordered lists the same delimiter. Otherwise a new list is opened. An ordered list's start number is its first item's number, with leading zeros dropped.
15. **Indented code:** the line is not blank, its indent is 4 or more, and the innermost open block is not a paragraph. So an indented line after a paragraph, lazy or not, is paragraph text. Four spaces are consumed, and the rest of the line is the first content line.

*Continuation (step 1)*

16. A **block quote** continues on a line whose indent is at most 3 and whose first non-space character is `>`, consuming the `>` and one following space if there is one. A **list** always continues. A **list item** continues on a blank line, unless it has no children yet: an item that is still empty when a blank line comes is ended by it. On a blank line it consumes all the spaces. On a non-blank line it continues if the indent is at least `W`, consuming `W` spaces. A **paragraph** continues on any non-blank line. A **heading** and a **thematic break** never continue.
17. **Fenced code** continues on every line. A line whose indent is at most 3 and which consists of a run of the fence character at least as long as the opening fence, followed only by spaces, is the closing fence: it closes the block and is not content. Any other line is content, with up to the fence indent of leading spaces removed. A fenced code block without a closing fence ends when its container closes, or at the end of the document.
18. **Indented code** continues on a line with an indent of 4 or more, consuming 4 spaces, and on a blank line, consuming all its spaces when the indent is below 4. When it closes, its trailing blank lines are removed from it.

*Tight and loose lists*

19. Every block has a first and a last line. A paragraph ends on its last line, including lazy lines. A heading and a thematic break end on their own line. A fenced code block ends on its closing fence, or on the last line before it was closed by its container, which may be a blank line. An indented code block ends on its last non-blank line. A block quote ends on the line before the line that closed it (at the end of the document, on the last line). A list item ends where its last child ends, and an empty item ends on its first line. A list ends where its last item ends. Any other block still open at the end of the document ends on the document's last line.
20. A list is **loose** if, between two consecutive items, or between two consecutive children of one of its items, the second does not start on the line right after the first ends. Otherwise it is **tight**. In a tight list, the paragraphs that are direct children of its items are rendered without `<p>` tags.

*Rendering (markdown-it's exact output)*

21. The blocks of the document are rendered in order, with these forms:
    - A paragraph is `<p>` + text + `</p>` + `\n`.
    - A heading is `<hN>` + text + `</hN>` + `\n`.
    - A thematic break is `<hr>` + `\n`.
    - A block quote is `<blockquote>` + `\n` + its children + `</blockquote>` + `\n`. A block quote with no children is `<blockquote></blockquote>` + `\n` (no newline between the tags, as for an empty item in rule 22).
    - A list is `<ul>` + `\n`, or `<ol>` + `\n`, or `<ol start="n">` + `\n` when the start number is not 1, then its items, then `</ul>` or `</ol>` + `\n`.
    - A code block is `<pre><code>` + content + `</code></pre>` + `\n`. A fenced block with a non-empty info string uses `<pre><code class="language-L">`, where `L` is the info string's first space-separated word. The content is escaped as in rule 2, and every content line ends with `\n`.
22. A list item is `<li>` + `\n` + its children + `</li>` + `\n`, with these exceptions. An empty item is `<li></li>` + `\n`. When the item's first child is a paragraph rendered without tags, there is no `\n` after `<li>`. After a paragraph rendered without tags comes `\n` when the next child of the item is a block rendered with a tag other than a code block (`<p>`, `<hN>`, `<hr>`, `<blockquote>`, `<ul>` or `<ol>`). Nothing comes after it when the next child is a code block, or when it is the item's last child. So a tight item `a` holding a nested list is `<li>a\n<ul>\n…</ul>\n</li>\n`.

Fix the package in place. Keep the existing tests green. Run the suite with `python3 -m pytest -q tests`.
