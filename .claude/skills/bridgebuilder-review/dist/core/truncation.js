import { existsSync, readFileSync, statSync, openSync, fstatSync, closeSync, constants as fsConstants, } from "node:fs";
import { resolve } from "node:path";
import path from "node:path";
// --- Security Patterns Registry (Task 1.1 — SDD Section 3.6) ---
export const SECURITY_PATTERNS = [
    // Authentication & Authorization
    { pattern: /(?:^|\/)auth/i, category: "auth", rationale: "Authentication modules" },
    { pattern: /(?:^|\/)login/i, category: "auth", rationale: "Login endpoints" },
    { pattern: /(?:^|\/)oauth/i, category: "auth", rationale: "OAuth flows" },
    { pattern: /(?:^|\/)session/i, category: "auth", rationale: "Session management" },
    { pattern: /(?:^|\/)acl/i, category: "auth", rationale: "Access control lists" },
    { pattern: /(?:^|\/)permissions?[./]/i, category: "auth", rationale: "Permission checks" },
    { pattern: /(?:^|\/)rbac/i, category: "auth", rationale: "Role-based access control" },
    { pattern: /(?:^|\/)middleware\/auth/i, category: "auth", rationale: "Auth middleware" },
    // Cryptography & Secrets
    { pattern: /(?:^|\/)crypto/i, category: "crypto", rationale: "Cryptographic operations" },
    { pattern: /(?:^|\/)secret/i, category: "crypto", rationale: "Secret management" },
    { pattern: /(?:^|\/)password/i, category: "crypto", rationale: "Password handling" },
    { pattern: /(?:^|\/)credential/i, category: "crypto", rationale: "Credential storage" },
    { pattern: /(?:^|\/)security/i, category: "crypto", rationale: "Security configurations" },
    { pattern: /\.pem$/i, category: "crypto", rationale: "PEM certificates" },
    { pattern: /\.key$/i, category: "crypto", rationale: "Private key files" },
    { pattern: /(?:^|\/)\.env/i, category: "crypto", rationale: "Environment secrets" },
    { pattern: /(?:^|\/)vault/i, category: "crypto", rationale: "Secret vault config" },
    // CI/CD & Supply Chain
    { pattern: /(?:^|\/)\.github\/workflows\//i, category: "cicd", rationale: "GitHub Actions workflows" },
    { pattern: /(?:^|\/)\.gitlab-ci/i, category: "cicd", rationale: "GitLab CI config" },
    { pattern: /(?:^|\/)Jenkinsfile/i, category: "cicd", rationale: "Jenkins pipeline" },
    { pattern: /(?:^|\/)Dockerfile/i, category: "cicd", rationale: "Container build definition" },
    { pattern: /(?:^|\/)docker-compose/i, category: "cicd", rationale: "Container orchestration" },
    { pattern: /(?:^|\/)Makefile/i, category: "cicd", rationale: "Build system commands" },
    // Infrastructure as Code
    { pattern: /\.tf$/i, category: "iac", rationale: "Terraform configs" },
    { pattern: /(?:^|\/)helm\//i, category: "iac", rationale: "Helm charts" },
    { pattern: /(?:^|\/)k8s\//i, category: "iac", rationale: "Kubernetes manifests" },
    { pattern: /(?:^|\/)kubernetes\//i, category: "iac", rationale: "Kubernetes manifests" },
    { pattern: /(?:^|\/)pulumi/i, category: "iac", rationale: "Pulumi infrastructure" },
    // Dependency Lockfiles
    { pattern: /(?:^|\/)package-lock\.json$/i, category: "lockfile", rationale: "npm dependency lock" },
    { pattern: /(?:^|\/)yarn\.lock$/i, category: "lockfile", rationale: "Yarn dependency lock" },
    { pattern: /(?:^|\/)pnpm-lock\.yaml$/i, category: "lockfile", rationale: "pnpm dependency lock" },
    { pattern: /(?:^|\/)go\.sum$/i, category: "lockfile", rationale: "Go dependency checksums" },
    { pattern: /(?:^|\/)Cargo\.lock$/i, category: "lockfile", rationale: "Rust dependency lock" },
    { pattern: /(?:^|\/)Gemfile\.lock$/i, category: "lockfile", rationale: "Ruby dependency lock" },
    { pattern: /(?:^|\/)poetry\.lock$/i, category: "lockfile", rationale: "Python dependency lock" },
    { pattern: /(?:^|\/)composer\.lock$/i, category: "lockfile", rationale: "PHP dependency lock" },
    // Security Policy Files
    { pattern: /(?:^|\/)SECURITY\.md$/i, category: "policy", rationale: "Security policy" },
    { pattern: /(?:^|\/)CODEOWNERS$/i, category: "policy", rationale: "Code ownership rules" },
    { pattern: /(?:^|\/)\.github\/CODEOWNERS$/i, category: "policy", rationale: "GitHub CODEOWNERS" },
];
export function isHighRisk(filename) {
    return SECURITY_PATTERNS.some((p) => p.pattern.test(filename));
}
export function getSecurityCategory(filename) {
    const match = SECURITY_PATTERNS.find((p) => p.pattern.test(filename));
    return match?.category;
}
// --- Pattern Matching (SDD Section 3.8) ---
/** Detect if Node 22+ path.matchesGlob is available (BB-F4). */
const hasNativeGlob = typeof path.matchesGlob === "function";
/**
 * Simple glob matcher fallback for Node <22.
 * Supports: `*.ext`, `prefix*`, `prefix*suffix`, exact match, substring match,
 * `?` single character wildcards, and `**` recursive directory matching.
 */
function simplifiedGlobMatch(filename, pattern) {
    // Handle ** recursive patterns: src/**/*.ts
    if (pattern.includes("**")) {
        // Convert glob to regex: ** matches any number of path segments
        const escaped = pattern
            .split("**")
            .map((part) => part
            .split("*")
            .map((seg) => seg.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\?/g, "[^/]"))
            .join("[^/]*"))
            .join(".*");
        return new RegExp(`^${escaped}$`).test(filename);
    }
    // Handle ? single character wildcard (matches any char except /)
    if (pattern.includes("?")) {
        const escaped = pattern
            .split("*")
            .map((part) => part.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\?/g, "[^/]"))
            .join("[^/]*");
        return new RegExp(`^${escaped}$`).test(filename);
    }
    // Original simplified matching for basic patterns
    if (pattern.startsWith("*")) {
        const suffix = pattern.slice(1);
        if (filename.endsWith(suffix))
            return true;
    }
    else if (pattern.endsWith("*")) {
        const prefix = pattern.slice(0, -1);
        if (filename.startsWith(prefix))
            return true;
    }
    else if (pattern.includes("*")) {
        const [before, after] = pattern.split("*", 2);
        if (filename.startsWith(before) && filename.endsWith(after))
            return true;
    }
    else {
        if (filename === pattern || filename.includes(pattern))
            return true;
    }
    return false;
}
export function matchesExcludePattern(filename, patterns) {
    for (const pattern of patterns) {
        if (hasNativeGlob) {
            // Node 22+: use native path.matchesGlob() for full glob support
            if (path.matchesGlob(filename, pattern)) {
                return true;
            }
            // Fallback to simplified match for non-glob patterns (exact/substring)
            if (!pattern.includes("*") && !pattern.includes("?")) {
                if (filename === pattern || filename.includes(pattern))
                    return true;
            }
        }
        else {
            if (simplifiedGlobMatch(filename, pattern))
                return true;
        }
    }
    return false;
}
// --- Self-Review Opt-In (#796 / vision-013) ---
/**
 * The PR label that operators apply to opt into bridgebuilder self-review —
 * BB will admit framework files (`.claude/`, `grimoires/`, etc.) into the
 * review payload instead of stripping them via the Loa-aware filter.
 *
 * The label name is intentionally a single source of truth; truncation logic,
 * caller-side label detection in reviewer.ts/template.ts, and operator-facing
 * docs all reference this constant.
 */
export const SELF_REVIEW_LABEL = "bridgebuilder:self-review";
/**
 * Derive the per-call `selfReview` flag from a PR's labels.
 * Returns true iff the PR carries SELF_REVIEW_LABEL.
 *
 * Centralized so the label string lives in one place and call sites
 * (reviewer.ts processItemTwoPass; template.ts buildPrompt + buildPromptWithMeta;
 * main.ts multi-model entry) cannot drift from each other.
 */
export function isSelfReviewOptedIn(prLabels) {
    return (prLabels ?? []).includes(SELF_REVIEW_LABEL);
}
/**
 * Build a per-call truncate config from a base config and a PR's labels.
 *
 * BB-004 (PR #797 iter-2): four call sites (template.ts × 2, reviewer.ts,
 * main.ts) duplicated `{ ...config, selfReview: isSelfReviewOptedIn(pr.labels) }`.
 * BB iter-1 caught a missed call site that silently nullified the feature for
 * the multi-model pipeline — a duplication-as-correctness-hazard pattern. This
 * helper is the single chokepoint, so adding new call sites OR new per-PR
 * configuration knobs requires touching ONE function, and tests can pin the
 * derivation here.
 */
export function deriveCallConfig(config, pr) {
    return {
        ...config,
        selfReview: isSelfReviewOptedIn(pr.labels),
    };
}
// --- Loa Detection (Task 1.2 — SDD Section 3.1) ---
/** Default Loa framework exclude patterns.
 * Use ** for recursive directory matching (BB-F4). */
export const LOA_EXCLUDE_PATTERNS = [
    // Core framework (existing)
    ".claude/**",
    "grimoires/**",
    ".beads/**",
    ".loa-version.json",
    ".loa.config.yaml",
    ".loa.config.yaml.example",
    // State & runtime (Bug 1 — issue #309)
    "evals/**",
    ".run/**",
    ".flatline/**",
    // Docs & config (Bug 1 — issue #309)
    "PROCESS.md",
    "BUTTERFREEZONE.md",
    "INSTALLATION.md",
    "grimoires/**/NOTES.md",
];
/**
 * Parse a `.reviewignore` file's user-curated patterns from disk.
 *
 * BB-797-003-duplication (iter-4): one grammar deserves one parser.
 *
 * BB-797-001-security (iter-4): ONLY ENOENT means "file absent" → []. ANY
 * OTHER error throws — caller decides fail-open vs fail-closed. cycle-098 L2
 * fail-closed: uncertain signals halt, never permit.
 *
 * BB-797-SEC-002 (iter-6): use readFileSync directly; classify ONLY
 * `code === "ENOENT"` as "absent". Earlier `existsSync` gate collapsed four
 * distinct states (absent, present-readable, present-unreadable, broken-link)
 * into one boolean — broken symlinks, EACCES, and ENOTDIR all returned `false`,
 * silently coercing unreadable to "no rules". Errno-explicit handling closes
 * the TOCTOU/ambiguous-stat class (Go's golang/go#41112 lesson applied here).
 *
 * @throws Error when `.reviewignore` exists but cannot be read or parsed.
 */
function parseReviewignoreFile(repoRoot) {
    // BB-801-002-gpt (iter-1 MEDIUM): validate repoRoot resolves to a
    // directory BEFORE proceeding.
    //
    // BB801-REVIEW-001 (iter-2 MEDIUM, conf 0.88): use statSync (NOT lstatSync)
    // for repoRoot — lstat would reject valid symlinked repo roots (macOS
    // /tmp → /private/tmp, CI checkout caches, monorepo worktrees). repoRoot
    // is a CONTAINER check; symlink-as-convenience is normal here.
    let rootStat;
    try {
        rootStat = statSync(repoRoot);
    }
    catch (err) {
        const code = err.code;
        const enriched = new Error(`repoRoot does not exist or is unreadable: ${repoRoot} (code=${code ?? "unknown"})`);
        enriched.code = "EBADREPOROOT";
        throw enriched;
    }
    if (!rootStat.isDirectory()) {
        const enriched = new Error(`repoRoot is not a directory: ${repoRoot}`);
        enriched.code = "EBADREPOROOT";
        throw enriched;
    }
    const reviewignorePath = resolve(repoRoot, ".reviewignore");
    // BB801-002 (iter-3 MEDIUM, conf 0.82): TOCTOU-resistant validation +
    // read. Previously: lstatSync, then readFileSync(path). Path-based
    // validation followed by path-based read is provably racy on every
    // POSIX system (CWE-367). OpenSSH's authorized_keys loader is the
    // canonical reference: openSync with O_NOFOLLOW, fstatSync the
    // descriptor, validate, readFileSync(fd) on the SAME descriptor.
    //
    // BB801-REVIEW-002 (iter-2 HIGH, closed iter-2): O_NOFOLLOW on the
    // leaf file rejects symlinks at the kernel layer — the open syscall
    // itself fails with ELOOP if `.reviewignore` is a symlink. Same Linux
    // kernel discipline that hardened path-based file ops in 2.6.
    //
    // Windows: O_NOFOLLOW is a Linux/POSIX flag. Node accepts the constant
    // on Windows but it's a no-op (Windows symlinks behave differently and
    // this codebase targets Linux/macOS — `bridgebuilder-review` package
    // doesn't support Windows CI).
    // BB801-REVIEW-001 (PR #801 iter-4 MEDIUM, conf 0.7): O_NONBLOCK in
    // the open flags. openSync on a FIFO without O_NONBLOCK blocks until a
    // writer connects — fstatSync never runs. An adversarial or accidental
    // FIFO at `.reviewignore` would wedge the review forever. Same class
    // Borglet config readers caught early at Google. After fstat confirms
    // regular file, the flag is harmless for read(2).
    let fd;
    try {
        fd = openSync(reviewignorePath, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW | fsConstants.O_NONBLOCK);
    }
    catch (err) {
        const code = err.code;
        if (code === "ENOENT") {
            // O_NOFOLLOW: ENOENT only on genuine absence (broken symlink → ELOOP)
            return [];
        }
        if (code === "ELOOP") {
            // BB801-R8 (iter-4 LOW): ESYMLINKREJECTED — the policy is "we reject
            // symlinks at .reviewignore", not "we detect dangling links". ELOOP
            // under O_NOFOLLOW fires for ANY symlink (intact or dangling), so
            // the error code MUST reflect the policy, not the substrate.
            const enriched = new Error(`.reviewignore is a symbolic link — rejected to prevent symlink-follow-on-read TOCTOU (BB801-REVIEW-002 + BB801-R8): ${reviewignorePath}`);
            enriched.code = "ESYMLINKREJECTED";
            throw enriched;
        }
        // EACCES, EISDIR, etc. propagate so caller fail-closes.
        throw err;
    }
    let content;
    try {
        // fstatSync on the SAME descriptor — no path is re-evaluated.
        const fdStat = fstatSync(fd);
        if (!fdStat.isFile()) {
            const enriched = new Error(`.reviewignore is not a regular file (BB801-REVIEW-002 fail-closed): ${reviewignorePath}`);
            enriched.code = "ENOTAFILE";
            throw enriched;
        }
        // Read from the validated fd — no path re-evaluation, no TOCTOU window.
        content = readFileSync(fd, "utf-8");
    }
    finally {
        try {
            closeSync(fd);
        }
        catch {
            // Best-effort close
        }
    }
    const patterns = [];
    for (const rawLine of content.split("\n")) {
        const line = rawLine.trim();
        if (!line || line.startsWith("#"))
            continue;
        const pattern = line.endsWith("/") ? `${line}**` : line;
        if (!patterns.includes(pattern)) {
            patterns.push(pattern);
        }
    }
    return patterns;
}
/**
 * Load `.reviewignore` operator-curated patterns from repo root.
 * Returns ONLY the user patterns — does NOT merge with LOA_EXCLUDE_PATTERNS.
 *
 * `.reviewignore` carries operator-curated exclusions (secrets/, vendor blobs,
 * private internal docs) that are distinct from the framework's built-in
 * exclusion list. The self-review opt-in (#796 / vision-013) bypasses the
 * framework patterns but MUST continue to honor `.reviewignore` — BB-001-security
 * surfaced this as a MEDIUM finding on PR #797 iter-2.
 *
 * BB-797-001-security (PR #797 iter-4): fail-CLOSED on read errors. Caller
 * (truncateFiles self-review branch) propagates the error to halt the review
 * rather than silently admitting files that may have been excluded by an
 * unreadable `.reviewignore`. ENOENT (no file) is "no rules" and returns [];
 * any other error throws.
 *
 * @throws Error when `.reviewignore` exists but cannot be read or parsed —
 *         caller MUST handle and decide whether to halt or fall back.
 */
export function loadReviewIgnoreUserPatterns(repoRoot) {
    const root = repoRoot ?? process.cwd();
    return parseReviewignoreFile(root);
}
/**
 * @deprecated PR #801 iter-4 BB801-R4 (MEDIUM): this is the legacy
 *   merged-list API that retains pre-fix fail-soft semantics — exactly
 *   the trust-origin bug #800 fixed for the default-mode path. Mixing
 *   user `.reviewignore` patterns with LOA_EXCLUDE_PATTERNS routes
 *   operator-authored denies through the framework tier classifier
 *   (which has security-pattern "exception" branches), and the catch
 *   block silently swallows non-ENOENT errors that should fail-closed.
 *
 *   Internal callers MUST use the two-phase flow in `truncateFiles`
 *   (loadReviewIgnoreUserPatterns → matchesExcludePattern STRICT →
 *   applyLoaTierExclusion(LOA_EXCLUDE_PATTERNS)). This function
 *   remains exported only for backward-compat with external callers;
 *   removal is planned in the next minor.
 *
 * Emits a one-time stderr deprecation notice on first call (Meta Hack
 * @@Deprecated discipline — runtime breadcrumbs drive migration; pure
 * JSDoc gets ignored).
 */
let _loadReviewIgnoreDeprecationWarned = false;
export function loadReviewIgnore(repoRoot) {
    if (!_loadReviewIgnoreDeprecationWarned) {
        _loadReviewIgnoreDeprecationWarned = true;
        process.stderr.write("[bridgebuilder] DEPRECATED: loadReviewIgnore(repoRoot) is deprecated — " +
            "use the two-phase flow in truncateFiles (loadReviewIgnoreUserPatterns + " +
            "matchesExcludePattern strict-deny + applyLoaTierExclusion(LOA_EXCLUDE_PATTERNS)). " +
            "Removal planned in the next minor (BB801-R4).\n");
    }
    const root = repoRoot ?? process.cwd();
    const basePatterns = [...LOA_EXCLUDE_PATTERNS];
    try {
        const userPatterns = parseReviewignoreFile(root);
        for (const pattern of userPatterns) {
            if (!basePatterns.includes(pattern)) {
                basePatterns.push(pattern);
            }
        }
    }
    catch (err) {
        // Legacy fail-soft retained for backward-compat. New code MUST NOT
        // rely on this path — see @deprecated note above. The two-phase flow
        // in truncateFiles is fail-CLOSED on the same conditions.
        process.stderr.write(`[bridgebuilder] WARN: legacy loadReviewIgnore swallowed .reviewignore error — see deprecation. Detail: ${err.message}\n`);
    }
    return basePatterns;
}
/**
 * Detect if repo is Loa-mounted by reading .loa-version.json.
 * Resolves paths against repoRoot (git root), NOT cwd (SKP-001, IMP-004).
 *
 * Decision: sync I/O (existsSync/readFileSync) is intentional here.
 * truncateFiles() — the only caller — is synchronous (SDD §3.1), so async
 * would require a cascading refactor for zero runtime benefit.
 */
export function detectLoa(config) {
    // Config override takes precedence
    if (config.loaAware === true) {
        return { isLoa: true, source: "config_override" };
    }
    if (config.loaAware === false) {
        return { isLoa: false, source: "config_override" };
    }
    // Resolve against repo root (SKP-001)
    const root = config.repoRoot ?? process.cwd();
    if (!config.repoRoot) {
        process.stderr.write("[bridgebuilder] WARN: repoRoot not set, using cwd for Loa detection\n");
    }
    const versionFile = resolve(root, ".loa-version.json");
    if (!existsSync(versionFile)) {
        return { isLoa: false, source: "file" };
    }
    try {
        const content = readFileSync(versionFile, "utf-8");
        const parsed = JSON.parse(content);
        if (typeof parsed.framework_version !== "string" ||
            !/^\d+\.\d+\.\d+/.test(parsed.framework_version)) {
            process.stderr.write(`[bridgebuilder] WARN: .loa-version.json malformed (missing valid framework_version)\n`);
            return { isLoa: false, source: "file" };
        }
        return {
            isLoa: true,
            version: parsed.framework_version,
            source: "file",
        };
    }
    catch {
        process.stderr.write(`[bridgebuilder] WARN: .loa-version.json could not be parsed\n`);
        return { isLoa: false, source: "file" };
    }
}
// --- Loa System Zone Detection (Bug 2 fix — issue #309) ---
/** Paths that are definitively Loa framework system zones.
 * Security pattern matches in these zones get demoted to tier2 (summary)
 * instead of exception (full diff) to prevent framework file leakage. */
const LOA_SYSTEM_ZONE_PREFIXES = [
    ".claude/",
    "grimoires/",
    ".beads/",
    "evals/",
    ".run/",
    ".flatline/",
];
export function isLoaSystemZone(filename) {
    return LOA_SYSTEM_ZONE_PREFIXES.some(prefix => filename.startsWith(prefix));
}
// --- Two-Tier Loa Exclusion (Task 1.3 — SDD Section 3.2) ---
/** Tier 1 extensions: content-excluded (stats only). */
const TIER1_EXTENSIONS = new Set([
    ".md", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico",
    ".lock", ".woff", ".woff2", ".ttf", ".eot", ".bmp", ".webp",
]);
/** Tier 2 extensions: summary-included (first hunk + stats). */
const TIER2_EXTENSIONS = new Set([
    ".sh", ".js", ".ts", ".py", ".yml", ".yaml", ".json", ".toml",
    ".mjs", ".cjs", ".jsx", ".tsx",
]);
/** Paths that should be Tier 2 minimum even if extension says Tier 1 (SKP-002). */
const TIER2_MIN_PATHS = [
    /(?:^|\/)\.github\//i,
    /(?:^|\/)infra\//i,
    /(?:^|\/)deploy\//i,
    /(?:^|\/)k8s\//i,
];
export function classifyLoaFile(filename) {
    // Security pattern match: full diff for app code, but demoted to tier2
    // for Loa system zone files (Bug 2 fix — issue #309)
    if (isHighRisk(filename)) {
        if (isLoaSystemZone(filename)) {
            return "tier2";
        }
        return "exception";
    }
    const basename = filename.split("/").pop() ?? "";
    const ext = basename.includes(".") ? "." + basename.split(".").pop().toLowerCase() : "";
    // SKP-002: path-based heuristics → Tier 2 minimum
    if (TIER2_MIN_PATHS.some((p) => p.test(filename))) {
        return "tier2";
    }
    if (TIER1_EXTENSIONS.has(ext)) {
        return "tier1";
    }
    if (TIER2_EXTENSIONS.has(ext)) {
        return "tier2";
    }
    // Default unknown extensions under Loa paths: Tier 1 (conservative — stats only)
    return "tier1";
}
/** Extract the first hunk from a unified diff patch. */
export function extractFirstHunk(patch) {
    if (!patch)
        return patch;
    const lines = patch.split("\n");
    const hunkStarts = [];
    for (let i = 0; i < lines.length; i++) {
        if (lines[i].startsWith("@@")) {
            hunkStarts.push(i);
        }
    }
    if (hunkStarts.length <= 1) {
        return patch; // Single hunk or no hunks — return as-is
    }
    // Return everything up to the second hunk header
    return lines.slice(0, hunkStarts[1]).join("\n");
}
/**
 * Apply two-tier Loa exclusion to files under Loa paths.
 * Security check runs BEFORE tier classification (SDD 3.6).
 */
export function applyLoaTierExclusion(files, loaPatterns) {
    const passthrough = [];
    const tier1Excluded = [];
    const tier2Summary = [];
    let bytesSaved = 0;
    for (const file of files) {
        // Check if file is under a Loa path
        if (!matchesExcludePattern(file.filename, loaPatterns)) {
            passthrough.push(file);
            continue;
        }
        const tier = classifyLoaFile(file.filename);
        if (tier === "exception") {
            // Security files pass through even under Loa paths
            passthrough.push(file);
            continue;
        }
        const pBytes = file.patch ? new TextEncoder().encode(file.patch).byteLength : 0;
        bytesSaved += pBytes;
        if (tier === "tier1") {
            tier1Excluded.push({
                filename: file.filename,
                stats: `+${file.additions} -${file.deletions} (Loa framework, content excluded)`,
            });
        }
        else {
            // tier2: include first hunk summary
            const summary = file.patch ? extractFirstHunk(file.patch) : "";
            tier2Summary.push({
                filename: file.filename,
                stats: `+${file.additions} -${file.deletions} (Loa framework, summary only)`,
                summary,
            });
        }
    }
    return { passthrough, tier1Excluded, tier2Summary, bytesSaved };
}
// --- Token Budget Constants (IMP-001) ---
// Coefficients are chars-per-token ratios: 0.25 ≈ 4 chars/token (cl100k_base
// average for English prose + code). GPT-5.2 uses 0.23 per OpenAI's tokenizer
// calibration. These are intentionally conservative (over-estimate) to leave
// headroom and avoid context-window overflows at runtime.
export const TOKEN_BUDGETS = {
    "claude-sonnet-4-6": { maxInput: 200_000, maxOutput: 8_192, coefficient: 0.25 },
    "claude-sonnet-4-5-20250929": { maxInput: 200_000, maxOutput: 8_192, coefficient: 0.25 },
    "claude-opus-4-7": { maxInput: 200_000, maxOutput: 8_192, coefficient: 0.25 },
    "claude-opus-4-6": { maxInput: 200_000, maxOutput: 8_192, coefficient: 0.25 },
    "gpt-5.2": { maxInput: 128_000, maxOutput: 4_096, coefficient: 0.23 },
    default: { maxInput: 100_000, maxOutput: 4_096, coefficient: 0.25 },
};
export function getTokenBudget(model) {
    return TOKEN_BUDGETS[model] ?? TOKEN_BUDGETS["default"];
}
/** Estimate tokens from string using model-specific coefficient. */
export function estimateTokens(text, model) {
    const { coefficient } = getTokenBudget(model);
    return Math.ceil(text.length * coefficient);
}
// --- Progressive Truncation Helpers (Task 1.7) ---
/** Size threshold for security files to get hunk summary instead of full diff (SKP-005). */
const SECURITY_FILE_SIZE_CAP = 50_000; // 50KB
const SECURITY_MAX_HUNKS = 10;
/** Check if a test file is adjacent to a changed non-test file (IMP-002). */
export function isAdjacentTest(filename, allFiles) {
    if (!isTestFile(filename))
        return false;
    const dir = filename.substring(0, filename.lastIndexOf("/") + 1);
    return allFiles.some((f) => f.filename !== filename &&
        !isTestFile(f.filename) &&
        f.filename.startsWith(dir));
}
function isTestFile(filename) {
    return /\.(test|spec)\.[^.]+$/.test(filename);
}
function isEntryOrConfig(filename) {
    const basename = filename.split("/").pop() ?? "";
    return (/^(index|main|app)\.[^.]+$/.test(basename) ||
        /\.config\.[^.]+$/.test(basename) ||
        /\.(json|yaml|yml)$/.test(basename));
}
/** Parse unified diff into hunks. Returns null on parse failure (SKP-003 fallback). */
export function parseHunks(patch) {
    if (!patch)
        return [];
    try {
        const lines = patch.split("\n");
        const hunks = [];
        let current = null;
        for (const line of lines) {
            if (line.startsWith("@@")) {
                if (current)
                    hunks.push(current);
                current = { header: line, lines: [] };
            }
            else if (current) {
                current.lines.push(line);
            }
            // Lines before first @@ (diff header) are ignored in hunk parsing
        }
        if (current)
            hunks.push(current);
        return hunks;
    }
    catch {
        return null; // SKP-003: fallback to full patch
    }
}
/** Reduce context lines around changed hunks (3→1→0). */
export function reduceHunkContext(hunks, contextLines) {
    return hunks.map((hunk) => {
        const kept = [];
        const lines = hunk.lines;
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            // Always keep changed lines
            if (line.startsWith("+") || line.startsWith("-")) {
                kept.push(line);
                continue;
            }
            // Keep context lines within range of a changed line
            if (line.startsWith(" ") || line === "") {
                let nearChange = false;
                for (let j = Math.max(0, i - contextLines); j <= Math.min(lines.length - 1, i + contextLines); j++) {
                    if (lines[j] &&
                        (lines[j].startsWith("+") || lines[j].startsWith("-"))) {
                        nearChange = true;
                        break;
                    }
                }
                if (nearChange) {
                    kept.push(line);
                }
            }
            else {
                // Non-standard line (e.g., "\ No newline at end of file") — keep
                kept.push(line);
            }
        }
        return { header: hunk.header, lines: kept };
    });
}
/** Rebuild a patch string from hunks. */
function rebuildPatch(hunks) {
    return hunks.map((h) => h.header + "\n" + h.lines.join("\n")).join("\n");
}
/**
 * Apply size-aware handling for large security files (SKP-005).
 * Files >50KB get hunk summary instead of full diff.
 */
export function capSecurityFile(file) {
    if (!file.patch)
        return file;
    const bytes = new TextEncoder().encode(file.patch).byteLength;
    if (bytes <= SECURITY_FILE_SIZE_CAP)
        return file;
    const hunks = parseHunks(file.patch);
    if (!hunks || hunks.length === 0)
        return file;
    const capped = hunks.slice(0, SECURITY_MAX_HUNKS);
    const rebuilt = rebuildPatch(capped);
    // Validation: if rebuilt is empty or larger than original, use original (SKP-003)
    if (!rebuilt || rebuilt.length >= file.patch.length)
        return file;
    return {
        ...file,
        patch: rebuilt +
            `\n\n[${capped.length} of ${hunks.length} hunks included — file truncated due to size]`,
    };
}
/**
 * Deterministic file priority for Level 1 truncation (IMP-002).
 * Returns files sorted by retention priority (highest first).
 */
export function prioritizeFiles(files) {
    const scored = files.map((f) => ({
        file: f,
        priority: getFilePriority(f, files),
        changeSize: f.additions + f.deletions,
    }));
    scored.sort((a, b) => {
        // Higher priority first
        if (a.priority !== b.priority)
            return b.priority - a.priority;
        // Within same priority: larger change size first
        if (a.changeSize !== b.changeSize)
            return b.changeSize - a.changeSize;
        // Tie-breaker: alphabetical for determinism
        return a.file.filename.localeCompare(b.file.filename);
    });
    return scored.map((s) => s.file);
}
function getFilePriority(file, allFiles) {
    if (isHighRisk(file.filename))
        return 4; // Priority 1 (highest)
    if (isAdjacentTest(file.filename, allFiles))
        return 3; // Priority 2
    if (isEntryOrConfig(file.filename))
        return 2; // Priority 3
    return 1; // Priority 4 (lowest)
}
// --- Truncation Level Disclaimers ---
// Context reduction spans Level 1 → Level 2:
//   Level 1 uses full patches which include default git context (3 lines around changes).
//   Level 2 reduces context: first to 1 line, then to 0 lines.
//   The "3→1→0" reduction in the PR description spans Level 1 → Level 2 sub-steps.
//   Level 3 drops diff content entirely, showing stats-only.
const LEVEL_DISCLAIMERS = {
    1: "[Partial Review: {n} low-priority files excluded]",
    2: "[Partial Review: patches truncated to changed hunks]",
    3: "[Summary Review: diff content unavailable, reviewing file structure only]",
};
/**
 * Progressive truncation engine (Task 1.7 — SDD Section 3.3).
 * Attempts 3 levels of truncation to fit within token budget.
 * Budget target: 90% of maxInputTokens (SKP-004).
 */
export function progressiveTruncate(files, budgetTokens, model, systemPromptLen, metadataLen) {
    const targetBudget = Math.floor(budgetTokens * 0.9);
    const { coefficient } = getTokenBudget(model);
    const fixedTokens = Math.ceil((systemPromptLen + metadataLen) * coefficient);
    // Apply size-aware security handling first (SKP-005)
    const capped = files.map((f) => isHighRisk(f.filename) ? capSecurityFile(f) : f);
    // Prioritize files (IMP-002)
    const prioritized = prioritizeFiles(capped);
    // --- Level 1: Drop low-priority files ---
    {
        const included = [];
        const excluded = [];
        let diffTokens = 0;
        for (const file of prioritized) {
            const patchLen = file.patch?.length ?? 0;
            const fileTokens = Math.ceil(patchLen * coefficient);
            if (fixedTokens + diffTokens + fileTokens <= targetBudget) {
                included.push(file);
                diffTokens += fileTokens;
            }
            else {
                excluded.push({
                    filename: file.filename,
                    stats: `+${file.additions} -${file.deletions}`,
                });
            }
        }
        if (included.length > 0) {
            const totalBytes = included.reduce((sum, f) => sum +
                (f.patch ? new TextEncoder().encode(f.patch).byteLength : 0), 0);
            return {
                success: true,
                level: 1,
                files: included,
                excluded,
                totalBytes,
                disclaimer: LEVEL_DISCLAIMERS[1].replace("{n}", String(excluded.length)),
                tokenEstimate: {
                    persona: Math.ceil(systemPromptLen * coefficient),
                    template: 0,
                    metadata: Math.ceil(metadataLen * coefficient),
                    diffs: diffTokens,
                    total: fixedTokens + diffTokens,
                },
            };
        }
    }
    // --- Level 2: Hunk-based truncation with context reduction ---
    // Level 1 uses full patches which include default git context (3 lines).
    // Level 2 reduces: context=1, then context=0. The "3→1→0" reduction
    // spans Level 1 → Level 2.
    for (const contextLines of [1, 0]) {
        const included = [];
        const excluded = [];
        let diffTokens = 0;
        for (const file of prioritized) {
            if (!file.patch) {
                excluded.push({
                    filename: file.filename,
                    stats: `+${file.additions} -${file.deletions} (diff unavailable)`,
                });
                continue;
            }
            const hunks = parseHunks(file.patch);
            if (!hunks) {
                // SKP-003: parse failure → use full patch
                const patchTokens = Math.ceil(file.patch.length * coefficient);
                if (fixedTokens + diffTokens + patchTokens <= targetBudget) {
                    included.push(file);
                    diffTokens += patchTokens;
                }
                else {
                    excluded.push({
                        filename: file.filename,
                        stats: `+${file.additions} -${file.deletions}`,
                    });
                }
                continue;
            }
            const reduced = reduceHunkContext(hunks, contextLines);
            const rebuilt = rebuildPatch(reduced);
            // SKP-003: validate rebuilt patch
            if (!rebuilt || rebuilt.length >= (file.patch?.length ?? 0)) {
                // Fallback: use original patch
                const patchTokens = Math.ceil(file.patch.length * coefficient);
                if (fixedTokens + diffTokens + patchTokens <= targetBudget) {
                    included.push(file);
                    diffTokens += patchTokens;
                }
                else {
                    excluded.push({
                        filename: file.filename,
                        stats: `+${file.additions} -${file.deletions}`,
                    });
                }
                continue;
            }
            const patchTokens = Math.ceil(rebuilt.length * coefficient);
            if (fixedTokens + diffTokens + patchTokens <= targetBudget) {
                const annotation = `[${reduced.length} of ${hunks.length} hunks included]`;
                included.push({
                    ...file,
                    patch: rebuilt + "\n" + annotation,
                });
                diffTokens += patchTokens;
            }
            else {
                excluded.push({
                    filename: file.filename,
                    stats: `+${file.additions} -${file.deletions}`,
                });
            }
        }
        if (included.length > 0) {
            const totalBytes = included.reduce((sum, f) => sum +
                (f.patch ? new TextEncoder().encode(f.patch).byteLength : 0), 0);
            return {
                success: true,
                level: 2,
                files: included,
                excluded,
                totalBytes,
                disclaimer: LEVEL_DISCLAIMERS[2],
                tokenEstimate: {
                    persona: Math.ceil(systemPromptLen * coefficient),
                    template: 0,
                    metadata: Math.ceil(metadataLen * coefficient),
                    diffs: diffTokens,
                    total: fixedTokens + diffTokens,
                },
            };
        }
    }
    // --- Level 3: Stats only (no diff content) ---
    {
        const excluded = prioritized.map((f) => ({
            filename: f.filename,
            stats: `+${f.additions} -${f.deletions} (stats only)`,
        }));
        const statsText = excluded.map((e) => `${e.filename}: ${e.stats}`).join("\n");
        const statsTokens = Math.ceil(statsText.length * coefficient);
        if (fixedTokens + statsTokens <= targetBudget) {
            return {
                success: true,
                level: 3,
                files: [],
                excluded,
                totalBytes: 0,
                disclaimer: LEVEL_DISCLAIMERS[3],
                tokenEstimate: {
                    persona: Math.ceil(systemPromptLen * coefficient),
                    template: 0,
                    metadata: Math.ceil(metadataLen * coefficient),
                    diffs: statsTokens,
                    total: fixedTokens + statsTokens,
                },
            };
        }
    }
    // All levels failed
    return {
        success: false,
        files: [],
        excluded: [],
        totalBytes: 0,
    };
}
// --- Main Truncation Pipeline ---
function changeSize(file) {
    return file.additions + file.deletions;
}
function patchBytes(file) {
    return file.patch ? new TextEncoder().encode(file.patch).byteLength : 0;
}
export function truncateFiles(files, config) {
    const patterns = config.excludePatterns ?? [];
    // Step 0: Loa-aware filtering (prepended, not replacing user patterns)
    // Load .reviewignore and merge with LOA_EXCLUDE_PATTERNS (#303)
    // Self-review opt-in (#796 / vision-013): when the PR carries the
    // `bridgebuilder:self-review` label, reviewer.ts sets selfReview=true on
    // the per-call config and the entire Loa filter is skipped — framework
    // files become reviewable. Default behavior (no label) is unchanged.
    const loaDetection = detectLoa(config);
    let loaBanner;
    let loaStats;
    let allExcluded = false;
    const loaExcludedEntries = [];
    let afterLoa = files;
    // BB-797-001 (iter-3): typed self-review boolean — downstream prose-free.
    // BB-797-002 (iter-5): tri-state preserves the active-vs-rejected
    // distinction the boolean lossy-encodes; cache keys MUST use this field.
    let selfReviewState = loaDetection.isLoa && config.selfReview === true ? "active" : "inactive";
    let selfReviewActive = selfReviewState === "active";
    // BB-797-002 (PR #797 iter-3): nested if/else makes the branches mutually
    // exclusive at the type level — future edits cannot cause both to run.
    if (loaDetection.isLoa) {
        if (selfReviewActive) {
            // Self-review opt-in path: caller (reviewer.ts/main.ts/template.ts) detected
            // the `bridgebuilder:self-review` label on the PR.
            //
            // BB-001-security (PR #797 iter-2): the bypass MUST scope to LOA framework
            // patterns only — operator-curated `.reviewignore` patterns (secrets/,
            // vendor blobs, private docs) MUST still apply. This is the AWS-IAM rule:
            // an Allow grant never overrides a Deny. The self-review label is an Allow
            // on framework files, NOT a global Deny suppressor.
            //
            // Use matchesExcludePattern directly (NOT applyLoaTierExclusion) — the
            // tier classifier is for LOA framework files and would route a .env file
            // through the high-risk "exception" branch back into passthrough,
            // defeating the .reviewignore intent. user-curated patterns are simple
            // matches: present → exclude, absent → include. No tiering.
            // BB-797-001-security (PR #797 iter-4): fail-CLOSED if `.reviewignore`
            // exists but is unreadable. Empty result must NOT silently admit files
            // that should have been excluded — we fall back to the default LOA
            // filter path, which preserves the framework-exclusion safety floor.
            let userPatterns = [];
            try {
                userPatterns = loadReviewIgnoreUserPatterns(config.repoRoot);
            }
            catch (err) {
                // BB-797-001 iter-5 (HIGH): fail-CLOSED on EVERY axis the operator
                // was governing — not just the framework gate. The earlier iter-4
                // fix fell back to loadReviewIgnore() which catches the same error
                // and returns LOA defaults only — leaking user-curated exclusions
                // (e.g., secrets/api-keys.env) into the review payload.
                //
                // The right semantic when `.reviewignore` exists but is unreadable:
                // we cannot determine what the operator wanted excluded. AWS-IAM
                // analogue: an unreachable policy collapses evaluation to deny-all,
                // not deny-known-subset. Result is allExcluded=true with a banner
                // citing the rejection — operators see WHY no files were admitted
                // and can fix the .reviewignore (permissions, parse error, etc.).
                process.stderr.write(`[bridgebuilder] WARN: .reviewignore unreadable under self-review — halt-uncertainty: returning allExcluded=true (BB-797-001 iter-5). Detail: ${err.message}\n`);
                selfReviewState = "rejected";
                selfReviewActive = false;
                return {
                    included: [],
                    excluded: files.map((f) => ({
                        filename: f.filename,
                        stats: `+${f.additions} -${f.deletions} (.reviewignore unreadable, fail-closed)`,
                    })),
                    totalBytes: 0,
                    allExcluded: true,
                    loaBanner: "[Loa-aware: self-review opt-in REJECTED — .reviewignore unreadable; " +
                        "halt-uncertainty: ALL files excluded until .reviewignore is readable " +
                        "(BB-797-001 iter-5 — fail-closed on every governed axis, not just framework)]",
                    loaStats: { filesExcluded: files.length, bytesSaved: 0 },
                    selfReviewActive: false,
                    selfReviewState: "rejected",
                };
            }
            // BB-797-RV-011 iter-5: the catch path now early-returns, so the rest
            // of the self-review block runs unconditionally — the bypass-flag and
            // its guarding `if` are no longer needed. Branches stay flat.
            let frameworkFilesAdmitted = 0;
            let frameworkFilesExcludedByUser = 0;
            if (userPatterns.length > 0) {
                const passthrough = [];
                let userBytesSaved = 0;
                for (const f of files) {
                    if (matchesExcludePattern(f.filename, userPatterns)) {
                        loaExcludedEntries.push({
                            filename: f.filename,
                            stats: `+${f.additions} -${f.deletions} (.reviewignore user pattern)`,
                        });
                        userBytesSaved += f.patch ? new TextEncoder().encode(f.patch).byteLength : 0;
                        if (matchesExcludePattern(f.filename, LOA_EXCLUDE_PATTERNS)) {
                            frameworkFilesExcludedByUser++;
                        }
                    }
                    else {
                        passthrough.push(f);
                        if (matchesExcludePattern(f.filename, LOA_EXCLUDE_PATTERNS)) {
                            frameworkFilesAdmitted++;
                        }
                    }
                }
                afterLoa = passthrough;
                if (loaExcludedEntries.length > 0) {
                    loaStats = {
                        filesExcluded: loaExcludedEntries.length,
                        bytesSaved: userBytesSaved,
                    };
                }
            }
            else {
                // No user patterns: count framework files in payload
                for (const f of files) {
                    if (matchesExcludePattern(f.filename, LOA_EXCLUDE_PATTERNS)) {
                        frameworkFilesAdmitted++;
                    }
                }
            }
            // BB-797-002-banner (PR #797 iter-4): banner states what the system DID,
            // not what it intended to enable. If user patterns excluded all framework
            // paths, "framework files included" would mislead.
            const userPatternCount = userPatterns.length;
            const frameworkSummary = frameworkFilesAdmitted > 0
                ? `${frameworkFilesAdmitted} framework files admitted` +
                    (frameworkFilesExcludedByUser > 0
                        ? `, ${frameworkFilesExcludedByUser} excluded by .reviewignore`
                        : "")
                : (frameworkFilesExcludedByUser > 0
                    ? `LOA defaults bypassed but .reviewignore excluded all framework files (${frameworkFilesExcludedByUser})`
                    : "no framework files in PR");
            loaBanner = userPatternCount > 0
                ? `[Loa-aware: self-review opt-in active — ${frameworkSummary}; .reviewignore (${userPatternCount} user patterns) still honored (vision-013 / #796)]`
                : `[Loa-aware: self-review opt-in active — ${frameworkSummary} (vision-013 / #796)]`;
            // BR-001 (iter-3): hoist the all-excluded guard into the self-review
            // branch too. If every file matches a `.reviewignore` user pattern, an
            // empty `included=[]` payload would otherwise flow downstream with
            // `allExcluded=false` — the silent-empty-response class Netflix Hystrix
            // encoded as a separate circuit-breaker for fallback paths.
            if (afterLoa.length === 0) {
                allExcluded = true;
                return {
                    included: [],
                    excluded: loaExcludedEntries,
                    totalBytes: 0,
                    allExcluded: true,
                    loaBanner,
                    loaStats,
                    selfReviewActive,
                    selfReviewState,
                };
            }
        }
        else {
            // BB801-001 (PR #801 iter-3 HIGH_CONSENSUS, conf 0.9, 3-model agreement):
            // default-mode MUST fail-closed on .reviewignore load anomalies. The
            // iter-1 fail-loud rationale assumed the LOA framework filter was the
            // safety floor for ALL files — but it's not: user patterns govern paths
            // (secrets/, vendor/, private docs) that LOA defaults DON'T cover.
            // Silent skip on non-ENOENT errors admits files the operator excluded.
            //
            // AWS IAM analogue: malformed bucket policy = deny-all, not allow-all.
            // cycle-098 L2 fail-closed cost gate principle: when the policy oracle
            // is uncertain, the safe default is the most restrictive interpretation.
            //
            // ENOENT (genuine absence) → user patterns simply []
            // EBADREPOROOT, EBROKENSYMLINK, ENOTAFILE, EACCES, ELOOP, etc. → fail-closed.
            // Operator-authored `.reviewignore` patterns are STRICT denies; they
            // MUST short-circuit framework tier classification. The previous
            // implementation merged user patterns into LOA_EXCLUDE_PATTERNS and
            // passed the union to `applyLoaTierExclusion` — but that function has
            // tier-classification logic for FRAMEWORK files (security-pattern
            // detection, "exception" tier passthrough). A user-authored
            // `secrets/**` pattern matching `secrets/api-keys.env` could be routed
            // through the security-tier exception branch and admitted despite
            // explicit operator deny. AWS-IAM analogue: explicit-deny beats
            // allow; same shape Netflix learned in 2017 with mixed allowlists.
            //
            // Fix: two-phase filter. Phase 1 applies user patterns as strict
            // denies (matchesExcludePattern, no tiering). Phase 2 applies LOA
            // defaults to whatever survived phase 1.
            let userPatterns = [];
            try {
                userPatterns = loadReviewIgnoreUserPatterns(config.repoRoot);
            }
            catch (err) {
                // Fail-CLOSED. ENOENT was handled inside parseReviewignoreFile
                // (returns [] for genuine absence), so any error reaching here is
                // an anomaly: bad repoRoot, symlink, EACCES, etc.
                //
                // BB801-REVIEW-002 (iter-4 MEDIUM): preserve upstream selfReview
                // bindings — do NOT hardcode "inactive". This branch IS the default-
                // mode arm (else of `if (selfReviewActive)`), so selfReviewState is
                // already "inactive" by the outer initialization — but the principle
                // matters: fail-closed guards halt action, not classifications.
                // Reading the live binding makes future restructures safe.
                //
                // BB801-REVIEW-003 (iter-4 LOW): bytesSaved should reflect the
                // bytes we actually withheld (sum of patch byte-lengths) so
                // operator dashboards aren't internally inconsistent.
                const code = err.code ?? "unknown";
                const bytesSaved = files.reduce((sum, f) => sum + (f.patch ? new TextEncoder().encode(f.patch).byteLength : 0), 0);
                process.stderr.write(`[bridgebuilder] ERROR: .reviewignore anomaly in default-mode path — fail-closed (allExcluded=true). Fix the file to restore review. Code: ${code}, Detail: ${err.message} (BB801-001 iter-3 HIGH_CONSENSUS)\n`);
                return {
                    included: [],
                    excluded: files.map((f) => ({
                        filename: f.filename,
                        stats: `+${f.additions} -${f.deletions} (.reviewignore anomaly: ${code}, fail-closed)`,
                    })),
                    totalBytes: 0,
                    allExcluded: true,
                    loaBanner: `[Loa-aware: default-mode fail-closed — .reviewignore anomaly (${code}); ` +
                        `ALL files excluded until .reviewignore is valid (BB801-001 iter-3)]`,
                    loaStats: { filesExcluded: files.length, bytesSaved },
                    selfReviewActive,
                    selfReviewState,
                };
            }
            // Phase 1: user .reviewignore patterns as strict denies. Trust-origin
            // preservation: operator intent never gets tier-routed.
            //
            // BB-801-003-opus (PR #801 iter-1 MEDIUM): capture per-phase counts
            // as named const scalars at phase end, NEVER derive them from
            // loaExcludedEntries.length-at-time-T. Future code that pushes
            // between phases must not silently corrupt the merged stats.
            let phase1Survivors = files;
            let userExcludedCount = 0;
            let userBytesSaved = 0;
            if (userPatterns.length > 0) {
                const survivors = [];
                for (const f of files) {
                    if (matchesExcludePattern(f.filename, userPatterns)) {
                        loaExcludedEntries.push({
                            filename: f.filename,
                            stats: `+${f.additions} -${f.deletions} (.reviewignore user pattern, strict deny)`,
                        });
                        userExcludedCount++;
                        userBytesSaved += f.patch ? new TextEncoder().encode(f.patch).byteLength : 0;
                    }
                    else {
                        survivors.push(f);
                    }
                }
                phase1Survivors = survivors;
            }
            // Phase 2: LOA framework filter (tier-classified) on phase-1 survivors.
            const tierResult = applyLoaTierExclusion(phase1Survivors, [...LOA_EXCLUDE_PATTERNS]);
            afterLoa = tierResult.passthrough;
            // Collect Loa-tier excluded entries (separate from user-pattern entries
            // so the per-line stats stay accurate to the trust-origin that excluded
            // each file).
            for (const entry of tierResult.tier1Excluded) {
                loaExcludedEntries.push(entry);
            }
            for (const entry of tierResult.tier2Summary) {
                loaExcludedEntries.push({
                    filename: entry.filename,
                    stats: entry.stats,
                });
            }
            const totalLoaExcluded = tierResult.tier1Excluded.length + tierResult.tier2Summary.length;
            const kbSavedFramework = Math.round(tierResult.bytesSaved / 1024);
            if (totalLoaExcluded > 0 || userExcludedCount > 0) {
                const parts = [];
                if (totalLoaExcluded > 0) {
                    parts.push(`${totalLoaExcluded} framework files excluded (${kbSavedFramework} KB saved)`);
                }
                if (userExcludedCount > 0) {
                    parts.push(`${userExcludedCount} files excluded by .reviewignore (strict deny)`);
                }
                loaBanner = `[Loa-aware: ${parts.join("; ")}]`;
                // Sum user-pattern + framework counts/bytes — both are scalars
                // captured at their respective phase boundaries; no array re-read.
                loaStats = {
                    filesExcluded: userExcludedCount + totalLoaExcluded,
                    bytesSaved: userBytesSaved + tierResult.bytesSaved,
                };
            }
            // IMP-004: all files excluded by Loa filtering (or user phase)
            if (afterLoa.length === 0) {
                allExcluded = true;
                return {
                    included: [],
                    excluded: loaExcludedEntries,
                    totalBytes: 0,
                    allExcluded: true,
                    loaBanner,
                    loaStats,
                    selfReviewActive,
                    selfReviewState,
                };
            }
        }
    }
    // Step 1: Separate files matching excludePatterns (sole enforcement point — IMP-005)
    const afterExclude = [];
    const excludedByPattern = [];
    for (const f of afterLoa) {
        if (matchesExcludePattern(f.filename, patterns)) {
            excludedByPattern.push({
                filename: f.filename,
                stats: `+${f.additions} -${f.deletions} (excluded by pattern)`,
            });
        }
        else {
            afterExclude.push(f);
        }
    }
    // Step 2: Classify into high-risk and normal
    const highRisk = [];
    const normal = [];
    for (const file of afterExclude) {
        if (isHighRisk(file.filename)) {
            highRisk.push(file);
        }
        else {
            normal.push(file);
        }
    }
    // Step 3: Sort each tier by change size (descending)
    highRisk.sort((a, b) => changeSize(b) - changeSize(a));
    normal.sort((a, b) => changeSize(b) - changeSize(a));
    // Interleave: high-risk first, then normal
    const sorted = [...highRisk, ...normal];
    // Apply maxFilesPerPr cap
    const capped = sorted.slice(0, config.maxFilesPerPr);
    // Step 4: Include full diff content until byte budget exhausted
    const included = [];
    const excluded = [];
    let totalBytes = 0;
    for (const file of capped) {
        const bytes = patchBytes(file);
        // Step 6: Handle patch-optional files (binary/large — GitHub omits patch)
        if (file.patch == null) {
            excluded.push({
                filename: file.filename,
                stats: `+${file.additions} -${file.deletions} (diff unavailable)`,
            });
            continue;
        }
        if (totalBytes + bytes <= config.maxDiffBytes) {
            included.push(file);
            totalBytes += bytes;
        }
        else {
            // Step 5: Remaining files get name + stats only
            excluded.push({
                filename: file.filename,
                stats: `+${file.additions} -${file.deletions}`,
            });
        }
    }
    // Files beyond maxFilesPerPr cap also go to excluded
    for (const file of sorted.slice(config.maxFilesPerPr)) {
        excluded.push({
            filename: file.filename,
            stats: `+${file.additions} -${file.deletions}`,
        });
    }
    return {
        included,
        excluded: [...loaExcludedEntries, ...excludedByPattern, ...excluded],
        totalBytes,
        allExcluded,
        loaBanner,
        loaStats,
        selfReviewActive,
        selfReviewState,
    };
}
//# sourceMappingURL=truncation.js.map