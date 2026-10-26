# sprint-279 — contract commit and Q-1 probe (lead, Task 1.0)

## Shared types (types.ts, this commit)
- `CoverageRecord.reviewed[].source?: "contents"`; `omitted[].pattern?: string`; `omitted[].fetch?: "binary" | "too_large" | "error" | "skipped_cap" | "deadline"`; `protected_kept?: Array<{file, pattern}>`; `reviewignore_source?: "base" | "checkout" | "none"`; `reviewignore_changed_in_pr?: boolean`.
- `TruncationResult.protectedKept?: Array<{file, pattern}>`.
- `BridgebuilderConfig.protectedPaths?: string[]` (undefined = DEFAULT_PROTECTED_PATHS; [] disables; set = replaces), `fetchMissingPatches?: boolean` (undefined = true), `maxContentFetches?: number` (undefined = 20). Optional so the contract compiles before A populates them in config.ts; consumers read `?? default`.
- `FileContentResult` and the optional `getFileContent?` are B's, in `ports/git-provider.ts`.

## Q-1 — GitHub contents envelope (read-only probe, 2026-10-26, gh 2.46.0)
`gh api /repos/0xHoneyJar/loa/contents/README.md?ref=<main sha>` returned a JSON object with keys `_links, content, download_url, encoding, git_url, html_url, name, path, sha, size, type, url`; `type: "file"`, `encoding: "base64"`, `size: 23632` (decoded bytes), `content`: base64 **with embedded newlines every 60 characters** (length 32038 for 23632 bytes) — strip all whitespace before decoding; `sha` is the blob sha. Above 1 MiB GitHub documents `encoding: "none"` with empty `content` (not probed; treat as too_large). The default media type is JSON; no `Accept` header is needed or allowed in the allowlisted shape.
