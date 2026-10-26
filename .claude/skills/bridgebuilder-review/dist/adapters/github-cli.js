import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { GitProviderError, } from "../ports/git-provider.js";
const execFileAsync = promisify(execFile);
// Decision: execFile+gh CLI over Octokit SDK.
// gh handles token refresh, SSO, credential helpers, and proxy config automatically.
// execFile avoids shell injection (no shell: true). Tradeoff: shelling out is slower
// than HTTP-direct, but review volume is low (<50 PRs/run) so latency is acceptable.
// If throughput becomes a bottleneck, swap to Octokit behind IGitProvider port.
const GH_TIMEOUT_MS = 30_000;
/**
 * cycle-133 C-1 (`bridgebuilder.gh_max_buffer_bytes`): the per-call stdout buffer for `gh`. 64 MiB by default — the
 * paged fetch bounds what one call receives to one page of 100 files, so this only has to hold the largest page.
 * The pre-cycle-133 value was a fixed 10 MiB that a single `--paginate` call over a 2,000-file PR overflowed (KF-054).
 */
export const DEFAULT_GH_MAX_BUFFER_BYTES = 64 * 1024 * 1024;
/** Error from gh CLI that carries the HTTP status code when available. */
class GhApiError extends GitProviderError {
    httpStatus;
    constructor(code, message, httpStatus) {
        super(code, message);
        this.httpStatus = httpStatus;
    }
}
// SECURITY: Adding endpoints here requires review — each is an attack surface expansion.
// Every regex must anchor start (^) and end ($), use [^/]+ (not .*) for path segments,
// and escape query parameters literally. New entries should get their own PR with justification.
const ALLOWED_API_ENDPOINTS = [
    /^\/rate_limit$/,
    /^\/repos\/[^/]+\/[^/]+$/,
    /^\/repos\/[^/]+\/[^/]+\/pulls\?state=open&per_page=100$/,
    /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/files\?per_page=100$/,
    // cycle-133 C-1: the immutable pair (base/head sha, changed_files) and the paged file list (one page per call)
    /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+$/,
    /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/files\?per_page=100&page=\d{1,2}$/,
    /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/reviews\?per_page=100$/,
    /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/reviews$/,
    // V3-1: compare commits for incremental review
    /^\/repos\/[^/]+\/[^/]+\/compare\/[a-f0-9]{7,40}\.\.\.[a-f0-9]{7,40}$/,
    // Multi-model: post issue comments (per-model reviews + consensus summary)
    /^\/repos\/[^/]+\/[^/]+\/issues\/\d+\/comments$/,
];
/**
 * Strict allowlist for gh api flags.
 * Any flag not explicitly listed here is rejected (default-deny).
 */
const ALLOWED_API_FLAGS = new Set([
    "--paginate",
    "-X",
    "-f",
    "--raw-field",
]);
/** Flags that can redirect requests, alter host/protocol, or inject headers. */
const FORBIDDEN_FLAGS = new Set([
    "--hostname",
    "-H",
    "--header",
    "--method",
    "-F",
    "--field",
    "--input",
    "--jq",
    "--template",
    "--repo",
]);
/** cycle-135 C-3: one owner or repo segment (GitHub's name characters; never a dot-only or option-like name). */
const REPO_SEGMENT = /^[A-Za-z0-9_.-]+$/;
function validRepoSegment(s) {
    return REPO_SEGMENT.test(s) && !/^\.+$/.test(s) && !s.startsWith("-");
}
/**
 * cycle-135 C-3 (sdd.md § 5.3, bd-w5pd9): a repository path for the contents endpoint, checked before encoding and
 * again on the decoded request — non-empty segments, never `.` or `..`, no leading `/`, no `?`, `#` or control
 * character. Returns the reason it is refused, or undefined.
 */
export function contentsPathProblem(path) {
    if (path.length === 0)
        return "empty path";
    if (path.startsWith("/"))
        return "leading /";
    if (/[?#\u0000-\u001f\u007f]/.test(path))
        return "?, # or a control character";
    for (const seg of path.split("/")) {
        if (seg === "")
            return "empty segment";
        if (seg === "." || seg === "..")
            return "dot segment";
    }
    return undefined;
}
/** The canonical request: each path segment encoded with encodeURIComponent (so `/` inside a name is `%2F`). */
export function contentsEndpoint(owner, repo, path, ref) {
    return `/repos/${owner}/${repo}/contents/${path.split("/").map(encodeURIComponent).join("/")}?ref=${ref}`;
}
const CONTENTS_ENDPOINT = /^\/repos\/([^/?#]+)\/([^/?#]+)\/contents\/([^?#]*)\?ref=([0-9a-f]{40})$/;
const CONTENTS_ENDPOINT_MAX = 2048;
/**
 * cycle-135 C-3: the only shape of the contents read — `api /repos/<o>/<r>/contents/<path>?ref=<40-hex>`, nothing
 * after it (no header: the default JSON media type is the one the adapter parses). The decoded path is re-validated and
 * must re-encode to exactly the request, so an encoded separator, dot segment or non-canonical escape is refused.
 */
function assertContentsArgs(args) {
    const endpoint = args[1];
    if (args.length !== 2)
        throw new Error("gh api contents: no flags or extra arguments are allowed");
    if (endpoint.length > CONTENTS_ENDPOINT_MAX)
        throw new Error("gh api contents: endpoint too long");
    const m = CONTENTS_ENDPOINT.exec(endpoint);
    if (!m)
        throw new Error(`gh api endpoint not allowlisted: ${endpoint}`);
    const [, owner, repo, encoded, ref] = m;
    if (!validRepoSegment(owner) || !validRepoSegment(repo))
        throw new Error("gh api contents: invalid owner or repo");
    let decoded;
    try {
        decoded = encoded.split("/").map((seg) => {
            const d = decodeURIComponent(seg);
            if (d.includes("/"))
                throw new Error("encoded separator");
            return d;
        }).join("/");
    }
    catch {
        throw new Error("gh api contents: path is not a canonical per-segment encoding");
    }
    const problem = contentsPathProblem(decoded);
    if (problem)
        throw new Error(`gh api contents: path refused (${problem})`);
    if (contentsEndpoint(owner, repo, decoded, ref) !== endpoint) {
        throw new Error("gh api contents: path is not a canonical per-segment encoding");
    }
}
/** Exported for the allowlist tests (cycle-135 C-3); the adapter is the only caller. */
export function assertAllowedArgs(args) {
    const cmd = args[0];
    if (cmd === "api") {
        // cycle-135 C-3: the contents read has its own exact validator (its paths may exceed the generic 200-char bound)
        if (typeof args[1] === "string" && /^\/repos\/[^/]+\/[^/]+\/contents\//.test(args[1])) {
            assertContentsArgs(args);
            return;
        }
        // Enforce endpoint at args[1] position (not arbitrary arg)
        // Length bound prevents oversized path segments from reaching execFile
        const endpoint = args[1];
        if (!endpoint || endpoint.length > 200 || !endpoint.startsWith("/")) {
            throw new Error("gh api endpoint missing or invalid");
        }
        if (!ALLOWED_API_ENDPOINTS.some((re) => re.test(endpoint))) {
            throw new Error(`gh api endpoint not allowlisted: ${endpoint}`);
        }
        // Only allow POST via -X POST (for review posting); default is GET
        const xIndex = args.indexOf("-X");
        if (xIndex !== -1) {
            const method = args[xIndex + 1];
            if (method !== "POST") {
                throw new Error(`gh api method not allowlisted: ${method ?? "(missing)"}`);
            }
        }
        // Strict flag validation: reject anything not explicitly allowed
        for (let i = 2; i < args.length; i++) {
            const a = args[i];
            // Skip non-flag arguments (values for preceding flags)
            if (!a.startsWith("-"))
                continue;
            // Check combined flag forms (--flag=value)
            const flagName = a.includes("=") ? a.slice(0, a.indexOf("=")) : a;
            // Reject explicitly forbidden flags (belt-and-suspenders)
            if (FORBIDDEN_FLAGS.has(flagName)) {
                throw new Error(`gh api flag not allowlisted: ${a}`);
            }
            // Reject any flag not in the strict allowlist
            if (!ALLOWED_API_FLAGS.has(flagName)) {
                throw new Error(`gh api flag not allowlisted: ${a}`);
            }
            // Validate -f/--raw-field values are key=value format
            if (flagName === "-f" || flagName === "--raw-field") {
                const value = a.includes("=") ? a.slice(a.indexOf("=") + 1) : args[i + 1];
                if (!value || !value.includes("=")) {
                    throw new Error(`gh api ${flagName} value must be key=value format`);
                }
                if (!a.includes("="))
                    i++; // skip the value arg
                continue;
            }
            // Skip value for -X (already validated above)
            if (flagName === "-X") {
                i++; // skip the method value
                continue;
            }
        }
        return;
    }
    if (cmd === "auth" && args[1] === "status" && args.length === 2) {
        return;
    }
    throw new Error(`gh command not allowlisted: ${cmd}`);
}
const defaultExec = (file, args, options) => execFileAsync(file, args, options);
async function gh(args, timeoutMs = GH_TIMEOUT_MS, exec = defaultExec, maxBuffer = DEFAULT_GH_MAX_BUFFER_BYTES) {
    assertAllowedArgs(args);
    try {
        const { stdout } = await exec("gh", args, {
            timeout: timeoutMs,
            maxBuffer,
        });
        return stdout;
    }
    catch (err) {
        const e = err;
        if (e.code === "ENOENT") {
            throw new GitProviderError("NETWORK", "GitHub CLI (gh) required. Install: https://cli.github.com/ and run 'gh auth login'.");
        }
        // cycle-133 C-1 (KF-054): a payload larger than the per-call buffer is a typed, recoverable condition — the paged
        // fetch records it as files_payload_oversize — never a Fatal.
        if (e.code === "ERR_CHILD_PROCESS_STDIO_MAXBUFFER") {
            throw new GhApiError("PAYLOAD_OVERSIZE", `gh output exceeded the ${maxBuffer}-byte buffer (bridgebuilder.gh_max_buffer_bytes)`);
        }
        // Do not include stderr/message — may contain tokens or sensitive repo info
        const code = typeof e.code === "string" || typeof e.code === "number" ? String(e.code) : "unknown";
        // Extract HTTP status from gh stderr: "gh: ... (HTTP NNN)"
        const httpMatch = e.stderr?.match(/\(HTTP (\d{3})\)/);
        const httpStatus = httpMatch ? parseInt(httpMatch[1], 10) : undefined;
        // Classify by exit code: 1 = general failure, 4 = auth/forbidden in gh; a rate limit (HTTP 429, or GitHub's
        // 403 "rate limit exceeded") is RATE_LIMITED (cycle-133 C-1: patch_fetch_rate_limited).
        const rateLimited = httpStatus === 429 || /rate limit/i.test(e.stderr ?? "");
        const errorCode = rateLimited ? "RATE_LIMITED" : code === "4" ? "FORBIDDEN" : "NETWORK";
        throw new GhApiError(errorCode, `gh command failed (code=${code})`, httpStatus);
    }
}
function parseJson(raw, context) {
    try {
        return JSON.parse(raw);
    }
    catch {
        // Do not include raw response — may contain sensitive data
        throw new GitProviderError("NETWORK", `Failed to parse gh JSON for ${context}`);
    }
}
/**
 * Split a long comment into chunks at natural boundaries (paragraph breaks).
 * Each chunk stays under maxChars. Falls back to hard split if no boundary found.
 */
function splitComment(body, maxChars) {
    const chunks = [];
    let remaining = body;
    while (remaining.length > maxChars) {
        // Try to split at a paragraph break (double newline)
        let splitIdx = remaining.lastIndexOf("\n\n", maxChars);
        if (splitIdx < maxChars * 0.5) {
            // No good paragraph break — try single newline
            splitIdx = remaining.lastIndexOf("\n", maxChars);
        }
        if (splitIdx < maxChars * 0.5) {
            // Hard split at limit
            splitIdx = maxChars;
        }
        chunks.push(remaining.slice(0, splitIdx));
        remaining = remaining.slice(splitIdx).trimStart();
    }
    if (remaining.length > 0) {
        chunks.push(remaining);
    }
    return chunks;
}
export class GitHubCLIAdapter {
    marker;
    exec;
    maxBuffer;
    constructor(config) {
        this.marker = config.reviewMarker;
        this.exec = config.exec ?? defaultExec;
        this.maxBuffer = config.ghMaxBufferBytes ?? DEFAULT_GH_MAX_BUFFER_BYTES;
    }
    gh(args, timeoutMs = GH_TIMEOUT_MS) {
        return gh(args, timeoutMs, this.exec, this.maxBuffer);
    }
    /** cycle-133 C-1: the pair the review is pinned to (`pulls/N`). */
    async getPR(owner, repo, prNumber) {
        const raw = await this.gh(["api", `/repos/${owner}/${repo}/pulls/${prNumber}`]);
        const data = parseJson(raw, `getPR(${owner}/${repo}#${prNumber})`);
        const base = data.base?.sha;
        const head = data.head?.sha;
        const changed = data.changed_files;
        if (typeof base !== "string" || typeof head !== "string" || typeof changed !== "number" || !Number.isInteger(changed) || changed < 0) {
            throw new GitProviderError("NETWORK", `getPR(${owner}/${repo}#${prNumber}): response lacks base.sha, head.sha or changed_files`);
        }
        return { base_sha: base, head_sha: head, changed_files: changed };
    }
    /** cycle-133 C-1: one page of the files list (≤ 100 entries, patch text included — the endpoint has no other mode). */
    async getPRFilesPage(owner, repo, prNumber, page) {
        if (!Number.isInteger(page) || page < 1 || page > 30) {
            throw new GitProviderError("NETWORK", `getPRFilesPage: page ${page} outside 1..30 (the endpoint lists at most 3,000 files)`);
        }
        const raw = await this.gh(["api", `/repos/${owner}/${repo}/pulls/${prNumber}/files?per_page=100&page=${page}`]);
        const data = parseJson(raw, `getPRFilesPage(${owner}/${repo}#${prNumber}, page ${page})`);
        if (!Array.isArray(data)) {
            throw new GitProviderError("NETWORK", `getPRFilesPage(${owner}/${repo}#${prNumber}, page ${page}): not a JSON array`);
        }
        return data.map((f) => ({
            filename: f.filename,
            status: f.status,
            additions: f.additions,
            deletions: f.deletions,
            patch: typeof f.patch === "string" ? f.patch : undefined,
        }));
    }
    /**
     * cycle-135 C-3 (sdd.md § 5.3, bd-w5pd9): one file's content at a pinned commit, for an added file the files list
     * returned without a patch. Default JSON media type (Q-1: `type`, `encoding: base64`, `size` = decoded bytes,
     * `content` wrapped every 60 characters); the buffer is sized for the envelope of `maxBytes`, so an overflow is
     * `too_large`; the envelope is validated strictly and the bytes are tested for binary before any string is made.
     */
    async getFileContent(owner, repo, path, ref, maxBytes) {
        const problem = contentsPathProblem(path);
        if (problem)
            throw new GitProviderError("NETWORK", `getFileContent: path refused (${problem})`);
        if (!validRepoSegment(owner) || !validRepoSegment(repo))
            throw new GitProviderError("NETWORK", "getFileContent: invalid owner or repo");
        if (!/^[0-9a-f]{40}$/.test(ref))
            throw new GitProviderError("NETWORK", "getFileContent: ref must be a 40-hex commit sha");
        if (!Number.isInteger(maxBytes) || maxBytes < 0)
            throw new GitProviderError("NETWORK", "getFileContent: maxBytes must be a non-negative integer");
        const maxBuffer = Math.ceil((maxBytes * 4) / 3) + 4096;
        let raw;
        try {
            // (the envelope is ASCII JSON — base64 content — so the decoded string is the bytes; the content bytes come from
            // the base64 below, never from the stdout encoding)
            raw = await gh(["api", contentsEndpoint(owner, repo, path, ref)], GH_TIMEOUT_MS, this.exec, maxBuffer);
        }
        catch (err) {
            if (err instanceof GitProviderError && err.code === "PAYLOAD_OVERSIZE")
                return { kind: "too_large" };
            throw err;
        }
        const data = parseJson(raw, "getFileContent");
        if (typeof data !== "object" || data === null || Array.isArray(data)) {
            throw new GitProviderError("NETWORK", "getFileContent: the contents response is not a file envelope");
        }
        const env = data;
        if (env.type !== "file")
            throw new GitProviderError("NETWORK", "getFileContent: the contents response is not type file");
        if (env.encoding === "none")
            return { kind: "too_large" }; // GitHub's answer above 1 MiB (Q-1)
        if (env.encoding !== "base64")
            throw new GitProviderError("NETWORK", "getFileContent: unexpected contents encoding");
        if (typeof env.size !== "number" || !Number.isInteger(env.size) || env.size < 0) {
            throw new GitProviderError("NETWORK", "getFileContent: contents size is not a non-negative integer");
        }
        if (env.size > maxBytes)
            return { kind: "too_large" };
        if (typeof env.content !== "string")
            throw new GitProviderError("NETWORK", "getFileContent: contents content is not a string");
        const b64 = env.content.replace(/\s+/g, "");
        if (b64.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(b64)) {
            throw new GitProviderError("NETWORK", "getFileContent: malformed base64 content");
        }
        const bytes = Buffer.from(b64, "base64");
        if (bytes.length !== env.size)
            throw new GitProviderError("NETWORK", "getFileContent: contents size disagrees with the decoded bytes");
        if (bytes.subarray(0, 8192).includes(0))
            return { kind: "binary" };
        let content;
        try {
            content = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes); // (ignoreBOM keeps a BOM verbatim)
        }
        catch {
            return { kind: "binary" };
        }
        return { kind: "text", content, bytes: bytes.length };
    }
    async listOpenPRs(owner, repo) {
        const raw = await this.gh([
            "api",
            `/repos/${owner}/${repo}/pulls?state=open&per_page=100`,
            "--paginate",
        ]);
        const data = parseJson(raw, `listOpenPRs(${owner}/${repo})`);
        return data.map((pr) => ({
            number: pr.number,
            title: pr.title,
            headSha: pr.head.sha,
            baseBranch: pr.base.ref,
            labels: (pr.labels ?? []).map((l) => l.name),
            author: pr.user.login,
        }));
    }
    async getPRFiles(owner, repo, prNumber) {
        const raw = await this.gh([
            "api",
            `/repos/${owner}/${repo}/pulls/${prNumber}/files?per_page=100`,
            "--paginate",
        ]);
        const data = parseJson(raw, `getPRFiles(${owner}/${repo}#${prNumber})`);
        return data.map((f) => ({
            filename: f.filename,
            status: f.status,
            additions: f.additions,
            deletions: f.deletions,
            patch: f.patch,
        }));
    }
    async getPRReviews(owner, repo, prNumber) {
        const raw = await this.gh([
            "api",
            `/repos/${owner}/${repo}/pulls/${prNumber}/reviews?per_page=100`,
            "--paginate",
        ]);
        const data = parseJson(raw, `getPRReviews(${owner}/${repo}#${prNumber})`);
        return data.map((r) => ({
            id: r.id,
            body: r.body ?? "",
            user: r.user?.login ?? "",
            state: r.state,
            submittedAt: r.submitted_at ?? "",
        }));
    }
    async preflight() {
        const raw = await this.gh(["api", "/rate_limit"]);
        const data = parseJson(raw, "preflight");
        const resources = data.resources;
        const core = resources?.core;
        let scopes = [];
        try {
            const authRaw = await this.gh(["auth", "status"], 10_000);
            const scopeMatch = authRaw.match(/Token scopes: (.+)/);
            if (scopeMatch) {
                scopes = scopeMatch[1].split(",").map((s) => s.trim());
            }
        }
        catch {
            // auth status may fail — scopes optional
        }
        return {
            remaining: core?.remaining ?? 0,
            scopes,
        };
    }
    async preflightRepo(owner, repo) {
        try {
            await this.gh(["api", `/repos/${owner}/${repo}`]);
            return { owner, repo, accessible: true };
        }
        catch (err) {
            return {
                owner,
                repo,
                accessible: false,
                error: err.message,
            };
        }
    }
    async getCommitDiff(owner, repo, base, head) {
        const raw = await this.gh([
            "api",
            `/repos/${owner}/${repo}/compare/${base}...${head}`,
        ]);
        const data = parseJson(raw, `getCommitDiff(${owner}/${repo}, ${base.slice(0, 7)}...${head.slice(0, 7)})`);
        const files = data.files ?? [];
        return {
            filesChanged: files.map((f) => f.filename),
            totalCommits: data.total_commits ?? 0,
        };
    }
    async hasExistingReview(owner, repo, prNumber, headSha, markerKind = "review") {
        const reviews = await this.getPRReviews(owner, repo, prNumber);
        // bug-1004: skip notices carry a distinct `-skip` marker — the genuine
        // matcher must never treat a skip-stamped sha as reviewed (that made
        // bridgebuilder:self-review unreachable without API surgery).
        const name = markerKind === "skip" ? `${this.marker}-skip` : this.marker;
        const exact = `<!-- ${name}: ${headSha} -->`;
        return reviews.some((r) => r.body.includes(exact));
    }
    async postReview(input) {
        const name = input.markerKind === "skip" ? `${this.marker}-skip` : this.marker;
        const marker = `\n\n<!-- ${name}: ${input.headSha} -->`;
        const body = input.body + marker;
        const makeArgs = (event) => [
            "api",
            `/repos/${input.owner}/${input.repo}/pulls/${input.prNumber}/reviews`,
            "-X",
            "POST",
            "--raw-field",
            `body=${body}`,
            "-f",
            `event=${event}`,
            "-f",
            `commit_id=${input.headSha}`,
        ];
        try {
            await this.gh(makeArgs(input.event));
        }
        catch (err) {
            // GitHub returns 422 when REQUEST_CHANGES targets own PR.
            // Fall back to COMMENT so the review content is still posted.
            if (input.event === "REQUEST_CHANGES" &&
                err instanceof GhApiError &&
                err.httpStatus === 422) {
                await this.gh(makeArgs("COMMENT"));
                return true;
            }
            throw err;
        }
        return true;
    }
    /**
     * Post an issue comment (not a review). Used for multi-model per-model comments
     * and consensus summary. Splits long comments at 65K chars with continuation headers.
     */
    async postComment(input) {
        const MAX_COMMENT_CHARS = 65_000;
        const body = input.body;
        if (body.length <= MAX_COMMENT_CHARS) {
            await this.postSingleComment(input.owner, input.repo, input.prNumber, body);
            return true;
        }
        // Split into chunks with continuation headers
        const chunks = splitComment(body, MAX_COMMENT_CHARS);
        for (let i = 0; i < chunks.length; i++) {
            const header = `**[${i + 1}/${chunks.length}]** _(continued)_\n\n`;
            const chunkBody = i === 0 ? chunks[i] : header + chunks[i];
            await this.postSingleComment(input.owner, input.repo, input.prNumber, chunkBody);
        }
        return true;
    }
    async postSingleComment(owner, repo, prNumber, body) {
        // GitHub PR comments use the issues endpoint (PRs are issues in GitHub's model)
        await this.gh([
            "api",
            `/repos/${owner}/${repo}/issues/${prNumber}/comments`,
            "-X",
            "POST",
            "--raw-field",
            `body=${body}`,
        ]);
    }
}
//# sourceMappingURL=github-cli.js.map