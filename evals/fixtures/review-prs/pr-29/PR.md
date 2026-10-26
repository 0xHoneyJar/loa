# [ty] Clamp notebook cell positions to the end of the cell

## Summary

We now clamp notebook request positions to the end of the requested cell's content. For example, `(0, 1)` in an empty cell resolves to `(0, 0)`, consistent with the [LSP rule for character offsets beyond the end of a line](https://github.com/microsoft/language-server-protocol/blob/gh-pages/_specifications/lsp/3.17/types/position.md).

Previously, we converted positions against the concatenated notebook source, allowing a position past the end of a cell to resolve into a later cell. Hovering just past an empty cell could show the type of `x` from a following `x = 1` cell, and an inlay hint request could return hints from the next cell.

We now bound position conversion by the cell's content range, excluding its synthetic separator newline. If the cell has no source range, we return `None` instead of falling back to the start of the notebook.
