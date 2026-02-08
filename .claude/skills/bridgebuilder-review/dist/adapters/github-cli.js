import { execFile } from "node:child_process";
import { promisify } from "node:util";
const execFileAsync = promisify(execFile);
const GH_TIMEOUT_MS = 30_000;
/** Allowlisted gh API endpoints — adapter cannot call anything else. */
const ALLOWED_API_ENDPOINTS = [
    /^\/rate_limit$/,
    /^\/repos\/[^/]+\/[^/]+$/,
    /^\/repos\/[^/]+\/[^/]+\/pulls\?state=open&per_page=100$/,
    /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/files\?per_page=100$/,
    /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/reviews\?per_page=100$/,
    /^\/repos\/[^/]+\/[^/]+\/pulls\/\d+\/reviews$/,
];
/** Flags that can redirect requests or alter target host/protocol. */
const FORBIDDEN_FLAGS = new Set([
    "--hostname",
    "-H",
    "--header",
    "--method",
    "-F",
    "--field",
    "--input",
]);
function assertAllowedArgs(args) {
    const cmd = args[0];
    if (cmd === "api") {
        // Enforce endpoint at args[1] position (not arbitrary arg)
        const endpoint = args[1];
        if (!endpoint || !endpoint.startsWith("/")) {
            throw new Error("gh api endpoint missing or invalid");
        }
        // Block flags that can redirect or change target host/protocol
        for (let i = 2; i < args.length; i++) {
            const a = args[i];
            if (FORBIDDEN_FLAGS.has(a)) {
                throw new Error(`gh api flag not allowlisted: ${a}`);
            }
            for (const f of FORBIDDEN_FLAGS) {
                if (a.startsWith(f + "=")) {
                    throw new Error(`gh api flag not allowlisted: ${a}`);
                }
            }
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
        return;
    }
    if (cmd === "auth" && args[1] === "status" && args.length === 2) {
        return;
    }
    throw new Error(`gh command not allowlisted: ${cmd}`);
}
async function gh(args, timeoutMs = GH_TIMEOUT_MS) {
    assertAllowedArgs(args);
    try {
        const { stdout } = await execFileAsync("gh", args, {
            timeout: timeoutMs,
            maxBuffer: 10 * 1024 * 1024,
        });
        return stdout;
    }
    catch (err) {
        const e = err;
        if (e.code === "ENOENT") {
            throw new Error("GitHub CLI (gh) required. Install: https://cli.github.com/ and run 'gh auth login'.");
        }
        // Do not include stderr/message — may contain tokens or sensitive repo info
        const code = typeof e.code === "string" || typeof e.code === "number" ? String(e.code) : "unknown";
        throw new Error(`gh command failed (code=${code})`);
    }
}
function parseJson(raw, context) {
    try {
        return JSON.parse(raw);
    }
    catch {
        // Do not include raw response — may contain sensitive data
        throw new Error(`Failed to parse gh JSON for ${context}`);
    }
}
export class GitHubCLIAdapter {
    marker;
    constructor(config) {
        this.marker = config.reviewMarker;
    }
    async listOpenPRs(owner, repo) {
        const raw = await gh([
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
        const raw = await gh([
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
        const raw = await gh([
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
        const raw = await gh(["api", "/rate_limit"]);
        const data = parseJson(raw, "preflight");
        const resources = data.resources;
        const core = resources?.core;
        let scopes = [];
        try {
            const authRaw = await gh(["auth", "status"], 10_000);
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
            await gh(["api", `/repos/${owner}/${repo}`]);
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
    async hasExistingReview(owner, repo, prNumber, headSha) {
        const reviews = await this.getPRReviews(owner, repo, prNumber);
        const exact = `<!-- ${this.marker}: ${headSha} -->`;
        return reviews.some((r) => r.body.includes(exact));
    }
    async postReview(input) {
        const marker = `\n\n<!-- ${this.marker}: ${input.headSha} -->`;
        const body = input.body + marker;
        await gh([
            "api",
            "-X",
            "POST",
            `/repos/${input.owner}/${input.repo}/pulls/${input.prNumber}/reviews`,
            "--raw-field",
            `body=${body}`,
            "-f",
            `event=${input.event}`,
            "-f",
            `commit_id=${input.headSha}`,
        ]);
        return true;
    }
}
//# sourceMappingURL=github-cli.js.map