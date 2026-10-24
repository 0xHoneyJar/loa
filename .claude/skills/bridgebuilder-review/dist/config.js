import { execFile, execFileSync, execSync } from "node:child_process";
import { promisify } from "node:util";
import { readFile } from "node:fs/promises";
import { closeSync, existsSync, fstatSync, openSync, readFileSync, statSync } from "node:fs";
import { isIPv6 } from "node:net";
import { join } from "node:path";
import { z } from "zod/v4";
import { GENERATED_MODEL_REGISTRY } from "./config.generated.js";
const execFileAsync = promisify(execFile);
/**
 * Zod schema for multi-model configuration (SDD Section 2.7).
 * Validated at startup; all fields have sensible defaults so partial config works.
 */
const ScoringThresholdsSchema = z.object({
    high_consensus: z.number().default(700),
    disputed_delta: z.number().default(300),
    low_value: z.number().default(400),
    blocker: z.number().default(700),
});
export const MultiModelConfigSchema = z.object({
    enabled: z.boolean().default(false),
    models: z.array(z.object({
        provider: z.string(),
        model_id: z.string(),
        role: z.enum(["primary", "reviewer"]).default("reviewer"),
    })).default([]),
    iteration_strategy: z.union([
        z.enum(["every", "final"]),
        z.array(z.number()),
    ]).default("final"),
    api_key_mode: z.enum(["graceful", "strict"]).default("graceful"),
    consensus: z.object({
        enabled: z.boolean().default(true),
        scoring_thresholds: ScoringThresholdsSchema.default(() => ({ high_consensus: 700, disputed_delta: 300, low_value: 400, blocker: 700 })),
    }).default(() => ({ enabled: true, scoring_thresholds: { high_consensus: 700, disputed_delta: 300, low_value: 400, blocker: 700 } })),
    token_budget: z.object({
        per_model: z.number().nullable().default(null),
        total: z.number().nullable().default(null),
    }).default(() => ({ per_model: null, total: null })),
    depth: z.object({
        structural_checklist: z.boolean().default(true),
        checklist_min_elements: z.number().default(5),
        permission_to_question: z.boolean().default(true),
        lore_active_weaving: z.boolean().default(true),
    }).default(() => ({ structural_checklist: true, checklist_min_elements: 5, permission_to_question: true, lore_active_weaving: true })),
    cross_repo: z.object({
        auto_detect: z.boolean().default(true),
        manual_refs: z.array(z.string()).default([]),
        // #1014: extra owners (beyond the PR own org) whose auto-detected refs may
        // be fetched. Empty default = org-only (secure by default).
        allowed_owners: z.array(z.string()).default([]),
    }).default(() => ({ auto_detect: true, manual_refs: [], allowed_owners: [] })),
    rating: z.object({
        enabled: z.boolean().default(true),
        timeout_seconds: z.number().default(60),
        retrospective_command: z.boolean().default(true),
    }).default(() => ({ enabled: true, timeout_seconds: 60, retrospective_command: true })),
    progress: z.object({
        verbose: z.boolean().default(true),
    }).default(() => ({ verbose: true })),
    max_concurrency: z.number().optional(),
    cost_rates: z.record(z.string(), z.object({
        input: z.number(),
        output: z.number(),
    })).optional(),
});
/**
 * Load multi-model configuration from .loa.config.yaml using yq CLI (SDD Section 2.7).
 * Falls back to defaults (enabled: false) if yq is missing or config absent.
 */
export function loadMultiModelConfig() {
    try {
        // Check if yq is available
        try {
            execSync("command -v yq", { encoding: "utf8", timeout: 2000, stdio: "pipe" });
        }
        catch {
            // Check if multi_model config exists in the file (simple grep)
            try {
                const content = execSync("grep -c 'multi_model:' .loa.config.yaml 2>/dev/null || echo 0", {
                    encoding: "utf8",
                    timeout: 2000,
                    stdio: "pipe",
                }).trim();
                if (parseInt(content, 10) > 0) {
                    console.error("[bridgebuilder] Multi-model config detected but yq is not installed. " +
                        "Install with: brew install yq (macOS) or snap install yq (Linux). " +
                        "Falling back to single-model mode.");
                }
            }
            catch {
                // Ignore grep errors
            }
            return MultiModelConfigSchema.parse({});
        }
        const result = execSync('yq eval ".run_bridge.bridgebuilder.multi_model" .loa.config.yaml -o json', { encoding: "utf8", timeout: 5000, stdio: "pipe" });
        if (!result || result.trim() === "null" || result.trim() === "") {
            return MultiModelConfigSchema.parse({});
        }
        return MultiModelConfigSchema.parse(JSON.parse(result));
    }
    catch (err) {
        // On any error, return safe defaults (disabled)
        if (err instanceof z.ZodError) {
            console.error(`[bridgebuilder] Invalid multi_model config: ${err.issues.map((i) => i.message).join(", ")}. Using defaults.`);
        }
        return MultiModelConfigSchema.parse({});
    }
}
/** Environment variable to API key mapping for multi-model providers. */
export const PROVIDER_API_KEY_ENV = {
    anthropic: "ANTHROPIC_API_KEY",
    openai: "OPENAI_API_KEY",
    google: "GOOGLE_API_KEY",
};
/** A `*-headless` model id: a kind:cli alias, whose CLI hop needs no API key in BB's environment. */
// (case-sensitive, as cheval's alias lookup is — `Claude-Headless` resolves to nothing: thirty-eighth run, e4 DISS-C-002)
// (and a catalog entry, under its own provider when one is named — a suffix alone admitted a typo or a pairing cheval has no
// alias for, past the key gate's fail-fast: thirty-ninth run, e4 DISS-C-002)
export function isHeadlessModelId(modelId, provider) {
    if (typeof modelId !== "string" || !/-headless$/.test(modelId) || !Object.hasOwn(GENERATED_MODEL_REGISTRY, modelId))
        return false;
    return provider === undefined || GENERATED_MODEL_REGISTRY[modelId].provider === provider;
}
/** The Loa config the agy gate reads: the repo root's when one is known, else the cwd's (r251-1 G15 — one path for all callers). */
export function loaConfigPathFor(repoRoot) {
    return repoRoot ? join(repoRoot, ".loa.config.yaml") : ".loa.config.yaml";
}
/** The go-yq "is the key present" program — the same text as the bash lib's `_AGY_YQ_HAS` and the Python loader's
 * `_YQ_HAS` (r251-4 S3): every level a real mapping (`kind` is "alias" for an alias node) and the explicit key only (`has`
 * never sees a merge key's). */
export const AGY_YQ_HAS = '.hounfour | (kind == "map" and (.headless | (kind == "map" and has("agy_opt_in"))))';
/** One NSS lookup through `getent` (the bash lib's account source); undefined when getent is missing or cannot answer. */
function getent(args) {
    try {
        return execFileSync("getent", args, { encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"] });
    }
    catch {
        return undefined;
    }
}
/**
 * Why the file's group is not its owner's USER-PRIVATE group, or undefined when it is (review r251-6 V1, BB #1). ONE rule with
 * cheval's `loader._not_private_group` and the bash lib's `_agy_group_not_private`: the file's gid is the owner's primary gid,
 * the group is NAMED for the owner (a shared `users` / macOS `staff` fails — their member lists are empty for primary members,
 * so emptiness alone never proved privacy: audit LOW-001), no account but the owner is a listed member, no other account has
 * it as its primary group (enumerated last), and no ACL makes the group bits a mask over named grants (`ls -ldL`'s `+`, on
 * the read's own descriptor when one is given). Accounts come from `getent`; a host without it, or one that cannot answer,
 * is no proof: not private.
 */
export function agyGroupNotPrivate(uid, gid, fd, configPath) {
    const pw = (getent(["passwd", String(uid)]) ?? "").split("\n")[0].split(":");
    const owner = pw[0] ?? "";
    const pgid = pw[3] ?? "";
    if (!owner || !/^\d+$/.test(pgid))
        return `its owner uid ${uid} could not be looked up`;
    const gr = (getent(["group", String(gid)]) ?? "").split("\n")[0].split(":");
    const gname = gr[0] ?? "";
    if (!gname)
        return `its group could not be looked up (gid ${gid})`;
    if (String(gid) !== pgid)
        return `its group '${gname}' (gid ${gid}) is not the owner's primary group`;
    if (gname !== owner)
        return `its group '${gname}' is not named for the owner '${owner}' (not a user-private group)`;
    const members = (gr[3] ?? "").split(",").map((m) => m.trim()).filter((m) => m && m !== owner);
    if (members.length)
        return `its group '${gname}' has other members (${members.join(", ")})`;
    const all = getent(["passwd"]);
    if (all === undefined)
        return `the accounts of group '${gname}' could not be enumerated`;
    const primary = all.split("\n").map((l) => l.split(":")).filter((f) => f.length > 3 && f[3] === String(gid) && f[2] !== String(uid)).map((f) => f[0]);
    if (primary.length)
        return `its group '${gname}' is the primary group of another account (${primary.join(", ")})`;
    let ls = "";
    try {
        ls = fd !== undefined
            ? execFileSync("ls", ["-ldL", "/dev/stdin"], { encoding: "utf8", timeout: 5000, stdio: [fd, "pipe", "ignore"] })
            : execFileSync("ls", ["-ldL", "--", configPath ?? ""], { encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"] });
    }
    catch {
        ls = "";
    }
    const lsMode = ls.split(" ")[0] ?? "";
    if (lsMode.length < 10)
        return "its ACL could not be read";
    if (lsMode[10] === "+")
        return "it carries an extended ACL (the group bits are the ACL mask over other accounts' grants)";
    return undefined;
}
/**
 * Why the opt-in config is not the current user's alone to write, or undefined when it is (review r251-5 U1/U2, r251-6 V1):
 * ONE permission rule with cheval's `loader._config_untrusted_reason` and the bash lib's `_agy_config_untrusted` — owned by
 * the current user, never world-writable, and group-writable only for the owner's user-private group (`agyGroupNotPrivate`;
 * Ubuntu's umask 002 makes every checkout 0664). `st` / `fd` are the read's own open file (r251-6 V3, BB #2: the bytes read
 * and the inode judged are one); without them `statSync` follows a symlink: the target decides, as in the other readers. A
 * config that cannot be stat'ed is untrusted (fail closed). Where the platform has no uid (`process.getuid` absent), the
 * owner half is skipped.
 */
export function agyConfigUntrustedReason(configPath, st, fd) {
    if (st === undefined) {
        try {
            st = statSync(configPath);
        }
        catch {
            return `${configPath} could not be stat'ed (owner and mode unknown)`;
        }
    }
    const me = typeof process.getuid === "function" ? process.getuid() : undefined;
    if (me !== undefined && st.uid !== me)
        return `${configPath} is not owned by the current user (uid ${st.uid}, euid ${me})`;
    const mode = `mode ${(st.mode & 0o7777).toString(8).padStart(4, "0")}`;
    if (st.mode & 0o002)
        return `${configPath} is world-writable (${mode})`;
    if (st.mode & 0o020) {
        const why = agyGroupNotPrivate(st.uid, st.gid, fd, configPath);
        if (why !== undefined)
            return `${configPath} is group-writable (${mode}) and ${why}`;
    }
    return undefined;
}
/**
 * Read `hounfour.headless.agy_opt_in` (true only for a YAML boolean true) and `hounfour.headless.mode` from the Loa config
 * with one yq call. LOA_HEADLESS_MODE wins for the mode, as it does in cheval; nothing in the environment opts in. A missing
 * file reads as off; a missing yq or an unreadable config reads as off too (the gate fails closed) and carries `readError`.
 */
export function readAgyGate(configPath) {
    let optIn = false;
    let mode = "";
    let readError;
    let typeWarning;
    if (existsSync(configPath)) {
        let fd;
        let content;
        try {
            // (r251-6 V3, BB #2: the config is opened ONCE — yq parses the bytes read from this descriptor on stdin and the trust
            // rule judges its fstat, so a swap of the path between read and check changes nothing)
            fd = openSync(configPath, "r");
            const st = fstatSync(fd);
            if (!st.isFile())
                throw new Error(`${configPath} is not a regular file`);
            content = readFileSync(fd);
            const out = execFileSync("yq", ["eval", "-o=json", "-I=0",
                `{"has": (${AGY_YQ_HAS}), "kind": (.hounfour.headless.agy_opt_in | kind), "opt": (.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)), "canon": (.hounfour.headless.agy_opt_in | (tag == "!!bool" and (. == true or . == false))), "tag": (.hounfour.headless.agy_opt_in | tag), "mode": (.hounfour.headless.mode // ""), ${AGY_YQ_ANCESTORS}}`,
                "-"], { encoding: "utf8", timeout: 5000, input: content, stdio: ["pipe", "pipe", "pipe"] });
            const parsed = JSON.parse(out);
            // (r251-4 S3: the key must be written at hounfour.headless itself — every level a real mapping, never an alias or a
            // merge key's value — and its node a plain scalar of the exact bool tag; one rule with the bash and Python readers)
            const present = parsed.has === true;
            const alias = parsed.kind === "alias";
            optIn = present && !alias && parsed.opt === true;
            mode = typeof parsed.mode === "string" ? parsed.mode : "";
            const ancestor = present ? undefined : agyAncestorProblem(parsed);
            // (r251-5 U1: a config others can write never opts in — one WARN naming the key and the reason; not a readError:
            // the gate reads off, exactly as the bash and Python readers, rather than blocking the merge. Only a value that
            // would opt in is judged, as there: a config that reads off anyway is not flagged)
            const untrusted = optIn ? agyConfigUntrustedReason(configPath, st, fd) : undefined;
            if (untrusted !== undefined) {
                optIn = false;
                typeWarning = `hounfour.headless.agy_opt_in: ${untrusted} — a config others can write never opts in (own it and \`chmod go-w\` it); the agy route stays off`;
            }
            else if (ancestor !== undefined) {
                typeWarning = `${ancestor} — hounfour.headless.agy_opt_in cannot be read through an alias or merge node (write the mapping inline); the agy route stays off`;
            }
            else if (present && alias) {
                typeWarning = "hounfour.headless.agy_opt_in is present but not a YAML boolean (an alias) — only `agy_opt_in: true` opts in (expected true or false); the agy route stays off";
            }
            else if (present && typeof parsed.tag === "string" && parsed.tag !== "!!null" && parsed.tag !== "!!bool") {
                typeWarning = `hounfour.headless.agy_opt_in is present but not a YAML boolean (${parsed.tag}) — only \`agy_opt_in: true\` opts in (expected true or false); the agy route stays off`;
            }
            else if (present && parsed.tag === "!!bool" && parsed.canon !== true) {
                typeWarning = "hounfour.headless.agy_opt_in is a boolean spelled other than true/false — only `agy_opt_in: true` opts in (the lowercase scalar); the agy route stays off";
            }
        }
        catch (err) {
            // (fail closed: no opt-in — and say why, rather than reading as a plain "opt-in off")
            const e = err;
            const stderr = typeof e.stderr === "string" ? e.stderr.trim() : Buffer.isBuffer(e.stderr) ? e.stderr.toString("utf8").trim() : "";
            optIn = false;
            // (r251-6 V5: a non-mapping ancestor yq cannot index below — `headless: [1]` — is the ancestor warning the bash and
            // Python readers give, not a host read error; the same bytes, the guarded ancestors-only program)
            const ancestor = content !== undefined ? agyAncestorOnly(content) : undefined;
            if (ancestor !== undefined) {
                typeWarning = `${ancestor} — hounfour.headless.agy_opt_in cannot be read through an alias or merge node (write the mapping inline); the agy route stays off`;
            }
            else {
                readError = (stderr || e.message || String(err)).split("\n")[0].slice(0, 300);
            }
        }
        finally {
            if (fd !== undefined)
                closeSync(fd);
        }
    }
    return {
        optIn, mode: process.env.LOA_HEADLESS_MODE || mode || "prefer-api",
        ...(readError !== undefined ? { readError } : {}), ...(typeWarning !== undefined ? { typeWarning } : {}),
    };
}
/** The ancestors' kind and tag (r251-6 V5): `hounfour`, and `hounfour.headless` only below a real mapping. */
export const AGY_YQ_ANCESTORS = '"k1": (.hounfour | kind), "t1": (.hounfour | tag), "k2": ((.hounfour | select(kind == "map") | .headless | kind) // ""), "t2": ((.hounfour | select(kind == "map") | .headless | tag) // "")';
/** The ancestors-only read of `content` (never errors on a non-mapping level: each level is guarded); undefined on any failure. */
function agyAncestorOnly(content) {
    try {
        const out = execFileSync("yq", ["eval", "-o=json", "-I=0", `{${AGY_YQ_ANCESTORS}}`, "-"], { encoding: "utf8", timeout: 5000, input: content, stdio: ["pipe", "pipe", "pipe"] });
        return agyAncestorProblem(JSON.parse(out));
    }
    catch {
        return undefined;
    }
}
/** `<path> is a YAML alias` / `<path> is not a mapping (<kind>)` for an alias or non-mapping ancestor of the key — one WARN,
 * never a silent absent (r251-6 V5, BB #5; the bash and Python readers say the same); undefined when every ancestor is a
 * mapping, absent or null. */
function agyAncestorProblem(p) {
    for (const [path, k, t] of [["hounfour", p.k1, p.t1], ["hounfour.headless", p.k2, p.t2]]) {
        if (k === "map")
            continue;
        if (k === "alias")
            return `${path} is a YAML alias`;
        if (typeof t !== "string" || t === "" || t === "!!null")
            return undefined;
        return `${path} is not a mapping (${t.replace(/^!!/, "")})`;
    }
    return undefined;
}
/**
 * A voice cheval would dispatch through agy: a google headless id of the generated registry (today `gemini-headless`), or
 * any google model when the effective headless mode is cli-only (the bash/Python predicate's shape — lib/agy-gate-lib.sh).
 */
export function isAgyRouted(provider, modelId, mode) {
    if (provider !== "google")
        return false;
    return isHeadlessModelId(modelId, "google") || mode === "cli-only";
}
/**
 * Validate API keys for configured multi-model providers.
 * Returns available and missing provider lists, and the voices not planned because their agy route's opt-in is off
 * (cycle-127 FR-1: neither valid nor missing — a voice that cannot exist on this host is never counted as a failed one).
 */
export function validateApiKeys(config, gate, trusted) {
    const valid = [];
    const missing = [];
    const notPlanned = [];
    for (const model of config.models) {
        // (r251-2 K7b: an unreadable config fails closed for EVERY google voice — its mode is unknown, so is its route: cheval,
        // reading the same file with PyYAML, might route it to agy and refuse; planned-as-HTTP would mis-count a failed voice)
        const gated = gate.readError !== undefined ? model.provider === "google" : isAgyRouted(model.provider, model.model_id, gate.mode);
        if (!gate.optIn && gated) {
            notPlanned.push({ provider: model.provider, modelId: model.model_id, reason: "opt_in_required" });
            continue;
        }
        // (cycle-129 D-7.5: a keyless or insecure declaration the PR head adds and the trusted config does not carry is refused
        // by name — before the key map, so a head that re-declares a built-in provider insecure is refused too)
        if (trusted?.headOnlyRefused.includes(model.provider)) {
            missing.push({ provider: model.provider, envVar: headOnlyRefusal(model.provider) });
            continue;
        }
        // (cycle-129 D-7.5: a provider the TRUSTED config declares keyless needs no env var; cheval authenticates it)
        if (trusted?.providers[model.provider]?.keyless === true) {
            valid.push({ provider: model.provider, modelId: model.model_id });
            continue;
        }
        const envVar = providerKeyEnv(model.provider, trusted);
        if (!envVar) {
            missing.push({
                provider: model.provider,
                envVar: trusted?.providers[model.provider] !== undefined
                    ? `provider ${model.provider} declares no credential (set keyless: true or auth: "{env:VAR}")`
                    : `Unknown provider: ${model.provider}`,
            });
            continue;
        }
        // (a `*-headless` entry is a cheval CLI hop that authenticates itself — every voice dispatches through cheval — so
        // it needs no key; the gate dropped the keyless host's claude-headless entry: cycle-126 thirty-seventh run, e2b DISS-C-003)
        if (isHeadlessModelId(model.model_id, model.provider) || process.env[envVar]) {
            valid.push({ provider: model.provider, modelId: model.model_id });
        }
        else {
            missing.push({ provider: model.provider, envVar });
        }
    }
    return { valid, missing, notPlanned };
}
// ============================================================================
// cycle-129 D-7.5 / D-7.7 / D-8.1 — trusted provider configuration
// ============================================================================
/** The refusal text for a keyless or insecure provider only the PR head declares (D-7.5; tests pin it). */
export function headOnlyRefusal(provider) {
    return `head-only provider declaration refused: ${provider}`;
}
/** The locality refusal text — one sentence with the dissent script and Flatline (SDD §4.3, D-8.1). */
export function localityRefusal(modelId, provider) {
    return `locality: local_voices refuses hosted hop ${modelId} (${provider}); declare a local provider or set hounfour.locality: hosted`;
}
/**
 * The env var holding a provider's credential: the built-in map first, then an `auth: "{env:VAR}"` template from the
 * TRUSTED config (never the head's, so a head cannot point a credential at a provider of its choosing). Undefined when
 * neither names one.
 */
export function providerKeyEnv(provider, trusted) {
    if (Object.hasOwn(PROVIDER_API_KEY_ENV, provider))
        return PROVIDER_API_KEY_ENV[provider];
    return trusted?.providers[provider]?.authEnv;
}
/** Default `bridgebuilder.exit_on_degraded` (DEC-0150): exit 3 when the consensus verdict is DEGRADED. */
export const DEFAULT_EXIT_ON_DEGRADED = 3;
/** The lenient shape of one provider entry (unknown keys pass through: cheval owns the full schema). */
const ProviderEntrySchema = z.looseObject({
    keyless: z.unknown().optional(),
    auth: z.unknown().optional(),
    allow_insecure_endpoint: z.unknown().optional(),
    dispatch_group: z.unknown().optional(),
    endpoint: z.unknown().optional(),
    type: z.unknown().optional(),
    models: z.unknown().optional(),
});
const ENV_AUTH_RE = /^\{env:([A-Za-z_][A-Za-z0-9_]*)\}$/;
/**
 * Normalise `hounfour.providers` (any JSON) into declarations. A non-mapping value or an entry that is not a mapping is
 * dropped with a warning — never admitted. D-8.0: `keyless: true` or a literal `auth` (one without `{env:`) is keyless.
 */
export function parseProviderDecls(raw, label, warnings) {
    const out = {};
    if (raw === null || raw === undefined)
        return out;
    if (typeof raw !== "object" || Array.isArray(raw)) {
        warnings.push(`[bridgebuilder] ${label}: hounfour.providers is not a mapping — no provider declaration is read from it`);
        return out;
    }
    for (const [name, entry] of Object.entries(raw)) {
        const parsed = ProviderEntrySchema.safeParse(entry);
        if (!parsed.success) {
            warnings.push(`[bridgebuilder] ${label}: hounfour.providers.${name} is not a mapping — ignored`);
            continue;
        }
        const e = parsed.data;
        const auth = typeof e.auth === "string" ? e.auth : undefined;
        const envMatch = auth !== undefined ? ENV_AUTH_RE.exec(auth) : null;
        const literalAuth = auth !== undefined && auth !== "" && !auth.includes("{env:");
        const modelGroups = {};
        const modelFallbacks = {};
        let modelCount = 0;
        let cliModels = 0;
        if (e.models !== null && typeof e.models === "object" && !Array.isArray(e.models)) {
            for (const [mid, m] of Object.entries(e.models)) {
                const g = m !== null && typeof m === "object" ? m.dispatch_group : undefined;
                modelGroups[mid] = typeof g === "string" ? g : undefined;
                modelCount += 1;
                if (m !== null && typeof m === "object" && m.kind === "cli")
                    cliModels += 1;
                // (audit a257-1 MEDIUM-A1 (c): the chain cheval walks inside one call; a scalar is a one-entry chain, as in
                // endpoint_policy.validate_local_fallbacks, and a non-string entry is "" — unresolvable, so hosted)
                const fb = m !== null && typeof m === "object" ? m.fallback_chain : undefined;
                if (fb !== undefined && fb !== null) {
                    modelFallbacks[mid] = (Array.isArray(fb) ? fb : [fb]).map((x) => (typeof x === "string" ? x : ""));
                }
            }
        }
        const cli = (typeof e.type === "string" && e.type.endsWith("-headless")) || (modelCount > 0 && cliModels === modelCount);
        out[name] = {
            keyless: e.keyless === true || literalAuth,
            insecure: e.allow_insecure_endpoint !== undefined && e.allow_insecure_endpoint !== null && e.allow_insecure_endpoint !== false,
            ...(envMatch ? { authEnv: envMatch[1] } : {}),
            ...(typeof e.dispatch_group === "string" ? { dispatchGroup: e.dispatch_group } : {}),
            modelGroups,
            ...(typeof e.endpoint === "string" ? { endpoint: e.endpoint } : {}),
            ...(cli ? { cli: true } : {}),
            ...(Object.keys(modelFallbacks).length > 0 ? { modelFallbacks } : {}),
        };
    }
    return out;
}
/** The subtree Bridgebuilder reads from a Loa config, as one yq program (the same yq the agy gate uses). */
const TRUSTED_VIEW_YQ = '{"providers": (.hounfour.providers // null), "locality": (.hounfour.locality // null), "exit": (.bridgebuilder.exit_on_degraded // null), ' +
    '"writer": (.bridgebuilder.writer_role_allowlist // null), ' +
    '"aliases": (.hounfour.aliases // null), "allowlist": (.hounfour.secret_env_allowlist // null), "rootAllowlist": (.secret_env_allowlist // null)}';
/** Parse Loa config text (YAML or JSON) into the trusted view with yq; throws with yq's first stderr line on failure. */
export function yqTrustedView(text) {
    try {
        const out = execFileSync("yq", ["eval", "-o=json", "-I=0", TRUSTED_VIEW_YQ, "-"], {
            encoding: "utf8", timeout: 5000, input: text, stdio: ["pipe", "pipe", "pipe"],
        });
        const parsed = JSON.parse(out);
        return {
            providers: parsed?.providers ?? null, locality: parsed?.locality ?? null, exit: parsed?.exit ?? null,
            ...(parsed?.writer !== undefined && parsed?.writer !== null ? { writer: parsed.writer } : {}),
            aliases: parsed?.aliases ?? null, allowlist: parsed?.allowlist ?? null, rootAllowlist: parsed?.rootAllowlist ?? null,
        };
    }
    catch (err) {
        const e = err;
        const stderr = typeof e.stderr === "string" ? e.stderr.trim() : "";
        throw new Error((stderr || e.message || String(err)).split("\n")[0].slice(0, 300));
    }
}
/** A branch name safe to place in `refs/remotes/origin/<name>` for `git show` (no option, no `..`, no control chars). */
export function isSafeRefName(name) {
    return /^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$/.test(name) && !name.includes("..") && !name.endsWith(".lock") && !name.endsWith("/");
}
function gitArgs(repoRoot, rest) {
    return repoRoot ? ["-C", repoRoot, ...rest] : rest;
}
export const defaultTrustedConfigDeps = {
    env: process.env,
    readWorkingTree: (path) => (existsSync(path) ? readFileSync(path, "utf8") : undefined),
    refExists: (repoRoot, ref) => {
        try {
            execFileSync("git", gitArgs(repoRoot, ["rev-parse", "--verify", "--quiet", `${ref}^{commit}`]), {
                encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"],
            });
            return true;
        }
        catch {
            return false;
        }
    },
    gitShow: (repoRoot, ref) => {
        // (ls-tree first: a base without the file is an EMPTY trusted config, not a read failure)
        const listed = execFileSync("git", gitArgs(repoRoot, ["ls-tree", "--name-only", ref, "--", ".loa.config.yaml"]), {
            encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "pipe"],
        }).trim();
        if (listed === "")
            return undefined;
        return execFileSync("git", gitArgs(repoRoot, ["show", `${ref}:.loa.config.yaml`]), {
            encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "pipe"], maxBuffer: 16 * 1024 * 1024,
        });
    },
    prBaseRef: (pr, repo) => {
        try {
            const out = execFileSync("gh", ["pr", "view", String(pr), "--json", "baseRefName", "-q", ".baseRefName", ...(repo ? ["--repo", repo] : [])], {
                encoding: "utf8", timeout: 15_000, stdio: ["ignore", "pipe", "ignore"],
            }).trim();
            return out || undefined;
        }
        catch {
            return undefined;
        }
    },
    parse: yqTrustedView,
};
/** True when Bridgebuilder runs on a pull request (D-7.5): `--pr`, a PR event, or a base ref in the environment. */
export function isPullRequestContext(pr, env) {
    if (pr !== undefined && pr !== null)
        return true;
    const ev = env.GITHUB_EVENT_NAME ?? "";
    if (ev === "pull_request" || ev === "pull_request_target")
        return true;
    return (env.GITHUB_BASE_REF ?? "") !== "";
}
/** The env var a workflow sets from a repository variable to supply trusted config text (YAML or JSON). */
export const TRUSTED_CONFIG_ENV = "BRIDGEBUILDER_TRUSTED_CONFIG";
/**
 * Load the trusted configuration (D-7.5, DEC-0170). Precedence:
 *   local (no PR context):  the working tree's `.loa.config.yaml`.
 *   pull request:           `BRIDGEBUILDER_TRUSTED_CONFIG` (repository settings) when set, else `.loa.config.yaml` at
 *                           `refs/remotes/origin/<base>` (base from `GITHUB_BASE_REF`, else the PR metadata), else at
 *                           `refs/remotes/origin/main`; when none can be read, no provider declaration is trusted.
 * The head checkout is read on a pull request to find keyless / insecure declarations the trusted source lacks, which
 * are refused by name, and (audit a257-1 MEDIUM-A2) to compute `headDrift` — the keys cheval would read differently from
 * the checkout than the trusted source says; main.ts refuses the run on any. Throws on an invalid `hounfour.locality` (a posture typo never runs hosted silently).
 */
export function loadTrustedConfig(opts, deps = defaultTrustedConfigDeps) {
    const warnings = [];
    const mode = isPullRequestContext(opts.pr, deps.env) ? "pull-request" : "local";
    const wtPath = loaConfigPathFor(opts.repoRoot);
    let source = "none";
    let ref;
    let text;
    if (mode === "local") {
        source = "working-tree";
        text = deps.readWorkingTree(wtPath);
    }
    else {
        const settings = deps.env[TRUSTED_CONFIG_ENV];
        if (settings !== undefined && settings.trim() !== "") {
            source = "repository-settings";
            text = settings;
        }
        else {
            const base = (deps.env.GITHUB_BASE_REF ?? "") !== ""
                ? deps.env.GITHUB_BASE_REF
                : opts.pr !== undefined ? deps.prBaseRef(opts.pr, opts.repo) : undefined;
            const candidates = [];
            if (base !== undefined) {
                if (isSafeRefName(base))
                    candidates.push(`refs/remotes/origin/${base}`);
                else
                    warnings.push(`[bridgebuilder] trusted config: base ref name refused (${JSON.stringify(base.slice(0, 80))}) — falling back to origin/main`);
            }
            if (!candidates.includes("refs/remotes/origin/main"))
                candidates.push("refs/remotes/origin/main");
            const tried = [];
            for (const c of candidates) {
                if (!deps.refExists(opts.repoRoot, c)) {
                    tried.push(`${c} (not found)`);
                    continue;
                }
                try {
                    text = deps.gitShow(opts.repoRoot, c);
                    source = "base-ref";
                    ref = c;
                    break;
                }
                catch (err) {
                    tried.push(`${c} (${(err instanceof Error ? err.message : String(err)).split("\n")[0].slice(0, 120)})`);
                }
            }
            if (source === "none") {
                warnings.push(`[bridgebuilder] trusted config unavailable on a pull request: ${tried.join(", ")} — no keyless or insecure provider ` +
                    `is admitted (fetch the base branch or set ${TRUSTED_CONFIG_ENV} from a repository variable)`);
            }
        }
    }
    let view = { providers: null, locality: null, exit: null };
    if (text !== undefined) {
        try {
            view = deps.parse(text);
        }
        catch (err) {
            warnings.push(`[bridgebuilder] trusted config (${source}${ref ? ` ${ref}` : ""}) unreadable: ${err instanceof Error ? err.message : String(err)} — no provider declaration is trusted`);
            source = "none";
        }
    }
    const providers = parseProviderDecls(view.providers, `trusted config (${source})`, warnings);
    // Head-only refusal: on a PR the head checkout is attacker-controlled.
    const headOnlyRefused = [];
    let headDrift = [];
    if (mode === "pull-request") {
        const headText = deps.readWorkingTree(wtPath);
        let headView;
        let headUnreadable = false;
        if (headText !== undefined) {
            try {
                headView = deps.parse(headText);
            }
            catch {
                headView = undefined; // (an unparsable head declares nothing Bridgebuilder would admit)
                headUnreadable = true;
            }
        }
        // audit a257-1 MEDIUM-A2: cheval reads the CHECKOUT's configuration for the dispatch, so on a pull request every
        // difference in what it would read (providers, aliases, locality, the secret allowlist) is drift, refused by name.
        headDrift = computeHeadDrift(headView, view, headUnreadable);
        if (headText !== undefined) {
            const headWarnings = [];
            const head = headView ? parseProviderDecls(headView.providers, "head config", headWarnings) : {};
            for (const [name, decl] of Object.entries(head)) {
                const t = Object.hasOwn(providers, name) ? providers[name] : undefined;
                const keylessOnlyInHead = decl.keyless && t?.keyless !== true;
                const insecureOnlyInHead = decl.insecure && t?.insecure !== true;
                if (keylessOnlyInHead || insecureOnlyInHead) {
                    headOnlyRefused.push(name);
                    warnings.push(`[bridgebuilder] ${headOnlyRefusal(name)} (${[keylessOnlyInHead ? "keyless" : "", insecureOnlyInHead ? "allow_insecure_endpoint" : ""].filter(Boolean).join(", ")} is declared in the PR head, not in the trusted config)`);
                }
            }
        }
    }
    // hounfour.locality
    let locality = "hosted";
    if (view.locality !== null && view.locality !== undefined) {
        if (view.locality === "hosted" || view.locality === "local_voices")
            locality = view.locality;
        else
            throw new Error(`hounfour.locality: invalid value ${JSON.stringify(view.locality)} (expected hosted or local_voices)`);
    }
    // bridgebuilder.exit_on_degraded
    let exitOnDegraded = DEFAULT_EXIT_ON_DEGRADED;
    if (view.exit !== null && view.exit !== undefined) {
        if (typeof view.exit === "number" && Number.isInteger(view.exit) && view.exit >= 0 && view.exit <= 125) {
            exitOnDegraded = view.exit;
        }
        else {
            warnings.push(`[bridgebuilder] bridgebuilder.exit_on_degraded: invalid value ${JSON.stringify(view.exit)} (expected an integer 0..125) — using ${DEFAULT_EXIT_ON_DEGRADED}`);
        }
    }
    // cycle-133 C-2: bridgebuilder.writer_role_allowlist (a list of route names; anything else → the default, warned)
    let writerRoleAllowlist;
    if (view.writer !== null && view.writer !== undefined) {
        if (Array.isArray(view.writer) && view.writer.every((w) => typeof w === "string"))
            writerRoleAllowlist = [...view.writer];
        else
            warnings.push(`[bridgebuilder] bridgebuilder.writer_role_allowlist: invalid value ${JSON.stringify(view.writer)} (expected a list of route names) — using the default`);
    }
    return {
        mode, source, ...(ref ? { ref } : {}), providers, headOnlyRefused, locality, exitOnDegraded, warnings,
        ...(writerRoleAllowlist ? { writerRoleAllowlist } : {}),
        aliases: stringAliases(view.aliases), headDrift,
    };
}
/** `hounfour.aliases` as a string map (non-string targets — cheval's dict form included — read through `target`/`model`). */
function stringAliases(raw) {
    const out = {};
    if (raw === null || typeof raw !== "object" || Array.isArray(raw))
        return out;
    for (const [k, v] of Object.entries(raw)) {
        let t = v;
        if (t !== null && typeof t === "object" && !Array.isArray(t))
            t = t.target ?? t.model;
        if (typeof t === "string" && t.trim() !== "")
            out[k] = t.trim();
    }
    return out;
}
/** Key-order-independent structural equality over JSON values (the yq view is JSON). */
export function jsonDeepEqual(a, b) {
    if (a === b)
        return true;
    if (a === null || b === null || typeof a !== "object" || typeof b !== "object")
        return false;
    if (Array.isArray(a) !== Array.isArray(b))
        return false;
    if (Array.isArray(a)) {
        const bb = b;
        return a.length === bb.length && a.every((x, i) => jsonDeepEqual(x, bb[i]));
    }
    const ka = Object.keys(a);
    const kb = Object.keys(b);
    if (ka.length !== kb.length)
        return false;
    return ka.every((k) => Object.hasOwn(b, k) && jsonDeepEqual(a[k], b[k]));
}
/** One dotted-key segment for a refusal line: a plain name as-is, anything else JSON-quoted and bounded (head text). */
function driftSegment(name) {
    return /^[A-Za-z0-9_.@+-]{1,64}$/.test(name) ? name : JSON.stringify(name.slice(0, 64));
}
/** The per-entry differences of two mappings (absent ⇒ `{}`); a non-mapping on either side is the whole key. */
function mappingDrift(prefix, head, trusted, out) {
    const h = head ?? {};
    const t = trusted ?? {};
    const isMap = (x) => x !== null && typeof x === "object" && !Array.isArray(x);
    if (!isMap(h) || !isMap(t)) {
        if (!jsonDeepEqual(h, t))
            out.push(prefix);
        return;
    }
    const hm = h;
    const tm = t;
    const names = [...new Set([...Object.keys(hm), ...Object.keys(tm)])].sort();
    for (const n of names) {
        const inH = Object.hasOwn(hm, n);
        const inT = Object.hasOwn(tm, n);
        if (!inH || !inT || !jsonDeepEqual(hm[n], tm[n]))
            out.push(`${prefix}.${driftSegment(n)}`);
    }
}
/**
 * audit a257-1 MEDIUM-A2 (pure): the dotted keys that differ between the PR head's view and the trusted view —
 * `hounfour.providers.<name>` (every field: endpoint, auth template, models, opt-ins), `hounfour.aliases.<alias>`,
 * `hounfour.locality` (absent ⇒ `hosted`), `hounfour.secret_env_allowlist` and a root `secret_env_allowlist` (absent ⇒
 * `[]`). An absent head file reads as all defaults; an unparsable head is drift on `.loa.config.yaml` itself (fail
 * closed: cheval's YAML reader might accept what yq refused).
 */
export function computeHeadDrift(head, trusted, headUnreadable = false) {
    if (headUnreadable)
        return [".loa.config.yaml (unreadable in the PR head)"];
    const h = head ?? {};
    const out = [];
    mappingDrift("hounfour.providers", h.providers, trusted.providers, out);
    mappingDrift("hounfour.aliases", h.aliases, trusted.aliases, out);
    if (!jsonDeepEqual(h.locality ?? "hosted", trusted.locality ?? "hosted"))
        out.push("hounfour.locality");
    if (!jsonDeepEqual(h.allowlist ?? [], trusted.allowlist ?? []))
        out.push("hounfour.secret_env_allowlist");
    if (!jsonDeepEqual(h.rootAllowlist ?? [], trusted.rootAllowlist ?? []))
        out.push("secret_env_allowlist");
    return out;
}
/** Where the trusted config came from, in words, for the drift refusal. */
export function trustedSourceDescription(t) {
    if (t.source === "base-ref")
        return `the trusted config (base-ref ${t.ref ?? "unknown"})`;
    if (t.source === "repository-settings")
        return `the trusted config (${TRUSTED_CONFIG_ENV})`;
    if (t.source === "none")
        return "the trusted config (none could be read)";
    return `the trusted config (${t.source})`;
}
/** Exit code for a multi-model run refused by trusted-config drift (distinct from 0, 3 DEGRADED and 4 FAILED). */
export const EXIT_TRUSTED_CONFIG_DRIFT = 5;
/**
 * The refusal decision for the multi-model run (pure; main.ts prints and exits): the stderr line, or undefined when the
 * run may proceed (local mode, or no drift).
 */
export function headDriftRefusal(t) {
    const drift = t.mode === "pull-request" ? (t.headDrift ?? []) : [];
    if (drift.length === 0)
        return undefined;
    return `[bridgebuilder] trusted config drift refused: ${drift.join(", ")} differ between the PR head and ` +
        `${trustedSourceDescription(t)}; merge the base branch into the head or set ${TRUSTED_CONFIG_ENV}`;
}
/** One startup line naming where the trusted config was read from (main.ts prints it with the warnings). */
export function trustedConfigStartupLine(t) {
    const where = t.source === "base-ref" ? `base-ref ${t.ref}` : t.source;
    const keyless = Object.entries(t.providers).filter(([, d]) => d.keyless).map(([n]) => n);
    return `[bridgebuilder] Trusted config: ${where} (mode: ${t.mode}); locality: ${t.locality}; exit_on_degraded: ${t.exitOnDegraded}` +
        (keyless.length > 0 ? `; keyless providers: ${keyless.join(", ")}` : "");
}
/** The local-hop rule's wording, shared with cheval (endpoint_policy.LOCAL_RULE_TEXT) and the planner. */
export const LOCAL_RULE_TEXT = "a loopback or RFC1918 IP literal or localhost";
function ipv4Octets(host) {
    const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
    if (!m)
        return undefined;
    const parts = m.slice(1).map((s) => (s.length > 1 && s.startsWith("0") ? NaN : Number(s))); // no leading zeros, as Python ipaddress
    return parts.every((n) => Number.isInteger(n) && n >= 0 && n <= 255) ? parts : undefined;
}
/**
 * The local-hop rule (D-8.1, review round r257-1) on a provider endpoint: `ok` when it is an http(s) URL whose host is an
 * IP literal in a loopback (127.0.0.0/8, ::1) or RFC1918 (10/8, 172.16/12, 192.168/16) range, or the literal `localhost`.
 * Link-local, metadata, unique-local IPv6, public ranges and every other DNS name fail. A stdlib mirror of the canonical
 * validator's `check_insecure_optin` host acceptance (the generated TypeScript port does not export it): the authority is
 * split by hand, not by WHATWG `URL`, so a host such as `0x7f.1` stays a DNS name here exactly as it does in Python.
 * `host` is the canonical host for a refusal message ("" when there is no endpoint).
 */
export function localEndpointHost(endpoint) {
    if (typeof endpoint !== "string" || endpoint.trim() === "")
        return { ok: false, host: "" };
    const m = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/([^/?#]*)/.exec(endpoint.trim());
    if (!m)
        return { ok: false, host: "unparseable" };
    const scheme = m[1].toLowerCase();
    let authority = m[2];
    const at = authority.lastIndexOf("@");
    if (at >= 0)
        authority = authority.slice(at + 1);
    let host;
    let port;
    if (authority.startsWith("[")) {
        const close = authority.indexOf("]");
        if (close < 0)
            return { ok: false, host: "unparseable" };
        host = authority.slice(1, close);
        port = authority.slice(close + 1);
    }
    else {
        const colon = authority.indexOf(":");
        host = colon >= 0 ? authority.slice(0, colon) : authority;
        port = colon >= 0 ? authority.slice(colon) : "";
    }
    if (port !== "" && !/^:\d*$/.test(port))
        return { ok: false, host: "unparseable" };
    if (port.length > 1 && Number(port.slice(1)) > 65535)
        return { ok: false, host: "unparseable" };
    host = host.toLowerCase();
    if (host.endsWith(".") && !host.endsWith(".."))
        host = host.slice(0, -1);
    if (host === "")
        return { ok: false, host: "unparseable" };
    if (scheme !== "http" && scheme !== "https")
        return { ok: false, host };
    if (host === "localhost")
        return { ok: true, host };
    const v4 = ipv4Octets(host);
    if (v4) {
        const [a, b] = v4;
        const ok = a === 127 || a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
        return { ok, host: v4.join(".") };
    }
    if (isIPv6(host)) {
        let canonical = host;
        try {
            canonical = new URL(`http://[${host}]/`).hostname.replace(/^\[|\]$/g, "");
        }
        catch {
            return { ok: false, host };
        }
        return { ok: canonical === "::1", host: canonical };
    }
    return { ok: false, host };
}
/**
 * The locality decision for one voice. `declared`: the trusted config marks it `dispatch_group: local` (the model's own
 * entry when declared, else the provider-level key, else every declared model of the provider). `local`: declared AND
 * the provider honours it — not a CLI provider, and its endpoint host passes the local-hop rule (D-8.1, r257-1: a
 * declared locality is enforced, not trusted). `reason` names why a declared voice is still hosted.
 */
export function localVoiceDecision(provider, modelId, trusted) {
    return localVoiceDecisionAt(provider, modelId, trusted, 0, new Set());
}
/** The fallback walk's depth bound (audit a257-1 MEDIUM-A1 (c); endpoint_policy.LOCAL_FALLBACK_MAX_DEPTH). */
export const LOCAL_FALLBACK_MAX_DEPTH = 8;
/**
 * A `fallback_chain` entry as `[provider, model]`: a `provider:model` pin, or an alias followed through the TRUSTED
 * `hounfour.aliases` (depth-limited, cycle-safe). Undefined when it does not resolve — the caller treats that as hosted.
 */
export function resolveFallbackSpec(spec, aliases) {
    let current = spec.trim();
    const seen = new Set();
    for (let i = 0; i <= LOCAL_FALLBACK_MAX_DEPTH; i += 1) {
        if (current === "")
            return undefined;
        const colon = current.indexOf(":");
        if (colon >= 0) {
            const p = current.slice(0, colon);
            const m = current.slice(colon + 1);
            return p !== "" && m !== "" ? [p, m] : undefined;
        }
        if (seen.has(current))
            return undefined;
        seen.add(current);
        current = aliases && Object.hasOwn(aliases, current) ? aliases[current] : "";
    }
    return undefined;
}
function localVoiceDecisionAt(provider, modelId, trusted, depth, seen) {
    const decl = Object.hasOwn(trusted.providers, provider) ? trusted.providers[provider] : undefined;
    if (!decl)
        return { local: false, declared: false };
    let declared;
    if (Object.hasOwn(decl.modelGroups, modelId) && decl.modelGroups[modelId] !== undefined)
        declared = decl.modelGroups[modelId] === "local";
    else if (decl.dispatchGroup !== undefined)
        declared = decl.dispatchGroup === "local";
    else {
        const groups = Object.values(decl.modelGroups);
        declared = groups.length > 0 && groups.every((g) => g === "local");
    }
    if (!declared)
        return { local: false, declared: false };
    const head = `locality: local_voices refuses hosted hop ${modelId} (${provider}): dispatch_group local but`;
    if (decl.cli === true)
        return { local: false, declared: true, reason: `${head} ${provider} is a CLI provider` };
    const verdict = localEndpointHost(decl.endpoint);
    if (!verdict.ok) {
        return { local: false, declared: true, reason: `${head} endpoint host ${verdict.host || "(none declared)"} is not ${LOCAL_RULE_TEXT}` };
    }
    // audit a257-1 MEDIUM-A1 (c): cheval walks the model's own fallback_chain inside one call, so the voice is local only
    // when every entry is (by this same rule, recursively; depth-limited, a cycle back to a voice on the walk is not new).
    const key = `${provider}:${modelId}`;
    if (seen.has(key))
        return { local: true, declared: true };
    seen.add(key);
    const chain = decl.modelFallbacks && Object.hasOwn(decl.modelFallbacks, modelId) ? decl.modelFallbacks[modelId] : [];
    for (const entry of chain) {
        const hosted = { local: false, declared: true, reason: `${head} its fallback_chain reaches hosted hop ${entry || "(unreadable entry)"}` };
        if (depth >= LOCAL_FALLBACK_MAX_DEPTH)
            return hosted;
        const target = resolveFallbackSpec(entry, trusted.aliases);
        if (target === undefined)
            return hosted;
        if (!localVoiceDecisionAt(target[0], target[1], trusted, depth + 1, seen).local)
            return hosted;
    }
    return { local: true, declared: true };
}
/** True when the voice is local by `localVoiceDecision` (declared `dispatch_group: local` AND the endpoint honours it). */
export function isLocalVoice(provider, modelId, trusted) {
    return localVoiceDecision(provider, modelId, trusted).local;
}
/**
 * D-8.1: under `hounfour.locality: local_voices` drop every planned voice whose provider is not local, each with the named
 * reason; never reroute. `hosted` (the default) returns the list unchanged.
 */
export function applyLocality(models, trusted) {
    if (trusted.locality !== "local_voices")
        return { kept: models, refused: [] };
    const kept = [];
    const refused = [];
    for (const m of models) {
        const d = localVoiceDecision(m.provider, m.model_id, trusted);
        if (d.local)
            kept.push(m);
        else
            refused.push({ provider: m.provider, modelId: m.model_id, reason: d.reason ?? localityRefusal(m.model_id, m.provider) });
    }
    return { kept, refused };
}
/**
 * The provider of a single-model `model` value for the locality check: `provider:model`, a generated-registry id, or a
 * model the trusted config declares; undefined when none says.
 */
export function resolveModelProvider(model, trusted) {
    const colon = model.indexOf(":");
    if (colon > 0)
        return model.slice(0, colon);
    if (Object.hasOwn(GENERATED_MODEL_REGISTRY, model))
        return GENERATED_MODEL_REGISTRY[model].provider;
    for (const [name, decl] of Object.entries(trusted.providers)) {
        if (Object.hasOwn(decl.modelGroups, model))
            return name;
    }
    return undefined;
}
/**
 * Under `local_voices`, the single-model path's voice must be local too: returns the refusal text, or undefined when the
 * voice may run (or the posture is hosted).
 */
export function singleModelLocalityRefusal(model, trusted) {
    if (trusted.locality !== "local_voices")
        return undefined;
    const provider = resolveModelProvider(model, trusted);
    const bare = provider !== undefined && model.startsWith(`${provider}:`) ? model.slice(provider.length + 1) : model;
    if (provider === undefined)
        return localityRefusal(model, "unresolved provider");
    const d = localVoiceDecision(provider, bare, trusted);
    if (d.local)
        return undefined;
    return d.reason ?? localityRefusal(model, provider);
}
/**
 * The startup lines for the agy gate (r251-2 K7f): the read error and the type warning each said once, unconditionally —
 * not only when a voice is not planned — and the not-planned voices. main.ts prints them; the pipeline says its own once
 * per review.
 */
export function agyGateStartupLines(gate, keyStatus) {
    const lines = [];
    if (gate.readError !== undefined) {
        lines.push(`[bridgebuilder] agy gate: Loa config unreadable (${gate.readError}) — failing closed: google voices are not planned (hounfour.headless.agy_opt_in)`);
    }
    if (gate.typeWarning !== undefined)
        lines.push(`[bridgebuilder] ${gate.typeWarning}`);
    if (keyStatus.notPlanned.length > 0) {
        lines.push(`[bridgebuilder] Not planned (agy opt-in, hounfour.headless.agy_opt_in): ${keyStatus.notPlanned.map((n) => `${n.provider}/${n.modelId}`).join(", ")}`);
    }
    return lines;
}
/**
 * cycle-133 C-1 (FR-1): exclude patterns every review applies before any patch is retained (prepended to
 * `bridgebuilder.exclude_patterns` and `--exclude`). Frozen review-PR fixtures and ablation grade trees are data, not
 * code under review; they made PR #1289's payload unreadable (KF-054). They apply under self-review too.
 */
export const DEFAULT_EXCLUDE_PATTERNS = Object.freeze([
    "evals/fixtures/review-prs/**",
    "grimoires/loa/reports/ablation-2.0/*-grades/**",
]);
/** cycle-133 C-1: bounds for `bridgebuilder.gh_max_buffer_bytes` (default 64 MiB; 1 MiB … 512 MiB). */
export const GH_MAX_BUFFER_BYTES_DEFAULT = 64 * 1024 * 1024;
const GH_MAX_BUFFER_BYTES_MIN = 1024 * 1024;
const GH_MAX_BUFFER_BYTES_MAX = 512 * 1024 * 1024;
/** Built-in defaults per PRD FR-4 (lowest priority). */
const DEFAULTS = {
    repos: [],
    // cycle-126 FR-1.5 (SDD D-1.5): the `opus` alias (resolved by cheval's alias
    // path, so the default follows the catalog's retarget instead of pinning a
    // snapshot); the input default matches the 200K-class payload the 5-family
    // reviews take, the output default the BB_OUTPUT_CAP of the generated table.
    model: "opus",
    maxPrs: 10,
    maxFilesPerPr: 50,
    maxDiffBytes: 512_000,
    maxInputTokens: 200_000,
    maxOutputTokens: 32_000,
    dimensions: ["security", "quality", "test-coverage"],
    reviewMarker: "bridgebuilder-review",
    repoOverridePath: "grimoires/bridgebuilder/BEAUVOIR.md",
    dryRun: false,
    excludePatterns: [],
    sanitizerMode: "default",
    maxRuntimeMinutes: 30,
    reviewMode: "two-pass",
};
/**
 * Parse CLI arguments from process.argv.
 */
export function parseCLIArgs(argv) {
    const args = {};
    for (let i = 0; i < argv.length; i++) {
        const arg = argv[i];
        if (arg === "--dry-run") {
            args.dryRun = true;
        }
        else if (arg === "--no-auto-detect") {
            args.noAutoDetect = true;
        }
        else if (arg === "--repo" && i + 1 < argv.length) {
            args.repos = args.repos ?? [];
            args.repos.push(argv[++i]);
        }
        else if (arg === "--pr" && i + 1 < argv.length) {
            const n = Number(argv[++i]);
            if (isNaN(n) || n <= 0) {
                throw new Error(`Invalid --pr value: ${argv[i]}. Must be a positive integer.`);
            }
            args.pr = n;
        }
        else if (arg === "--max-input-tokens" && i + 1 < argv.length) {
            const n = Number(argv[++i]);
            if (isNaN(n) || n <= 0) {
                throw new Error(`Invalid --max-input-tokens value: ${argv[i]}. Must be a positive integer.`);
            }
            args.maxInputTokens = n;
        }
        else if (arg === "--max-output-tokens" && i + 1 < argv.length) {
            const n = Number(argv[++i]);
            if (isNaN(n) || n <= 0) {
                throw new Error(`Invalid --max-output-tokens value: ${argv[i]}. Must be a positive integer.`);
            }
            args.maxOutputTokens = n;
        }
        else if (arg === "--max-diff-bytes" && i + 1 < argv.length) {
            const n = Number(argv[++i]);
            if (isNaN(n) || n <= 0) {
                throw new Error(`Invalid --max-diff-bytes value: ${argv[i]}. Must be a positive integer.`);
            }
            args.maxDiffBytes = n;
        }
        else if (arg === "--model" && i + 1 < argv.length) {
            args.model = argv[++i];
        }
        else if (arg === "--persona" && i + 1 < argv.length) {
            args.persona = argv[++i];
        }
        else if (arg === "--exclude" && i + 1 < argv.length) {
            args.exclude = args.exclude ?? [];
            args.exclude.push(argv[++i]);
        }
        else if (arg === "--force-full-review") {
            args.forceFullReview = true;
        }
        else if (arg === "--repo-root" && i + 1 < argv.length) {
            args.repoRoot = argv[++i];
        }
        else if (arg === "--review-mode" && i + 1 < argv.length) {
            const mode = argv[++i];
            if (mode !== "two-pass" && mode !== "single-pass") {
                throw new Error(`Invalid --review-mode value: ${mode}. Must be "two-pass" or "single-pass".`);
            }
            args.reviewMode = mode;
        }
    }
    return args;
}
/**
 * Auto-detect owner/repo from git remote -v.
 */
async function autoDetectRepo() {
    try {
        const { stdout } = await execFileAsync("git", ["remote", "-v"], {
            timeout: 5_000,
        });
        const lines = stdout.split("\n");
        const ghPattern = /(?:github\.com)[:/]([^/\s]+)\/([^/\s.]+?)(?:\.git)?\s/;
        // Prefer "origin" remote — avoids picking framework remote alphabetically (#395)
        const originLine = lines.find((l) => l.startsWith("origin\t") && l.includes("(fetch)"));
        const targetLine = originLine ?? lines.find((l) => l.includes("(fetch)"));
        const match = targetLine?.match(ghPattern);
        if (match) {
            return { owner: match[1], repo: match[2] };
        }
        return null;
    }
    catch {
        return null;
    }
}
/**
 * Parse "owner/repo" string into components.
 */
function parseRepoString(s) {
    const parts = s.split("/");
    if (parts.length !== 2 || !parts[0] || !parts[1]) {
        throw new Error(`Invalid repo format: "${s}". Expected "owner/repo".`);
    }
    return { owner: parts[0], repo: parts[1] };
}
// Decision: Pure regex YAML parser over yaml/js-yaml library.
// Zero runtime dependencies is a hard constraint for this skill (PRD NFR-1).
// The config surface is flat key:value pairs + simple lists — no anchors, aliases,
// multi-line strings, or nested objects needed. A full YAML parser (~50KB min)
// would add attack surface and supply chain risk for features we don't use.
// If nested config objects are ever needed, swap to js-yaml behind this function.
/**
 * Load YAML config from .loa.config.yaml if it exists.
 * Uses a simple key:value parser — no YAML library dependency.
 * Supports scalar values and YAML list syntax (- item).
 */
export async function loadYamlConfig() {
    try {
        const content = await readFile(".loa.config.yaml", "utf-8");
        // Find bridgebuilder section
        const match = content.match(/^bridgebuilder:\s*\n((?:[ \t]+.+\n?)*)/m);
        if (!match)
            return {};
        const section = match[1];
        const config = {};
        const lines = section.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const kv = lines[i].match(/^\s+([\w_]+):\s*(.*)/);
            if (!kv)
                continue;
            const [, key, rawValue] = kv;
            const value = rawValue.replace(/#.*$/, "").trim().replace(/^["']|["']$/g, "");
            // Check if next lines are YAML list items (- value)
            if (value === "" || value === undefined) {
                const items = [];
                while (i + 1 < lines.length) {
                    const listItem = lines[i + 1].match(/^\s+-\s+(.+)/);
                    if (!listItem)
                        break;
                    items.push(listItem[1].replace(/#.*$/, "").trim().replace(/^["']|["']$/g, ""));
                    i++;
                }
                if (items.length > 0) {
                    switch (key) {
                        case "repos":
                            config.repos = items;
                            break;
                        case "dimensions":
                            config.dimensions = items;
                            break;
                        case "exclude_patterns":
                            config.exclude_patterns = items;
                            break;
                    }
                    continue;
                }
            }
            switch (key) {
                case "enabled":
                    config.enabled = value === "true";
                    break;
                case "model":
                    config.model = value;
                    break;
                case "max_prs":
                    config.max_prs = Number(value);
                    break;
                case "max_files_per_pr":
                    config.max_files_per_pr = Number(value);
                    break;
                case "max_diff_bytes":
                    config.max_diff_bytes = Number(value);
                    break;
                case "gh_max_buffer_bytes":
                    config.gh_max_buffer_bytes = Number(value);
                    break;
                case "max_input_tokens":
                    config.max_input_tokens = Number(value);
                    break;
                case "max_output_tokens":
                    config.max_output_tokens = Number(value);
                    break;
                case "review_marker":
                    config.review_marker = value;
                    break;
                case "persona_path":
                    config.persona_path = value;
                    break;
                case "sanitizer_mode":
                    if (value === "default" || value === "strict") {
                        config.sanitizer_mode = value;
                    }
                    break;
                case "max_runtime_minutes":
                    config.max_runtime_minutes = Number(value);
                    break;
                case "loa_aware":
                    config.loa_aware = value === "true";
                    break;
                case "persona":
                    config.persona = value;
                    break;
                case "review_mode":
                    if (value === "two-pass" || value === "single-pass") {
                        config.review_mode = value;
                    }
                    break;
                case "ecosystem_context_path":
                    config.ecosystem_context_path = value;
                    break;
                case "pass1_cache_enabled":
                    config.pass1_cache_enabled = value === "true";
                    break;
            }
        }
        return config;
    }
    catch {
        return {};
    }
}
/**
 * Resolve repoRoot: CLI > env > git auto-detect > undefined.
 * Called once per resolveConfig() invocation (Bug 3 fix — issue #309).
 *
 * Note: uses execSync intentionally (not execFile/await) because this is called
 * once at startup and the calling chain (resolveConfig → truncateFiles) is the
 * only consumer. Matches the sync I/O precedent in truncation.ts:215.
 */
export function resolveRepoRoot(cli, env) {
    if (cli.repoRoot)
        return cli.repoRoot;
    if (env.BRIDGEBUILDER_REPO_ROOT)
        return env.BRIDGEBUILDER_REPO_ROOT;
    try {
        return execSync("git rev-parse --show-toplevel", {
            encoding: "utf-8",
            timeout: 5_000,
            stdio: ["pipe", "pipe", "pipe"],
        }).trim();
    }
    catch {
        return undefined;
    }
}
/**
 * Resolve pass1Cache.enabled: env > yaml > default (false).
 * Returns boolean or null if no explicit config.
 */
function resolvePass1Cache(_cliArgs, env, yaml) {
    if (env.BRIDGEBUILDER_PASS1_CACHE === "true")
        return true;
    if (env.BRIDGEBUILDER_PASS1_CACHE === "false")
        return false;
    if (yaml.pass1_cache_enabled != null)
        return yaml.pass1_cache_enabled;
    return null;
}
/**
 * Resolve config using 5-level precedence: CLI > env > yaml > auto-detect > defaults.
 * Returns config and provenance (where each key value came from).
 */
export async function resolveConfig(cliArgs, env, yamlConfig) {
    const yaml = yamlConfig ?? (await loadYamlConfig());
    // Check enabled flag from YAML
    if (yaml.enabled === false) {
        throw new Error("Bridgebuilder is disabled in .loa.config.yaml. Set bridgebuilder.enabled: true to enable.");
    }
    // Build repos list: first-non-empty-wins (CLI > env > yaml > auto-detect)
    let repos = [];
    let reposSource = "default";
    // CLI --repo flags (highest priority)
    if (cliArgs.repos?.length) {
        for (const r of cliArgs.repos) {
            repos.push(parseRepoString(r));
        }
        reposSource = "cli";
    }
    // Env BRIDGEBUILDER_REPOS (comma-separated) — only if CLI didn't set repos
    if (repos.length === 0 && env.BRIDGEBUILDER_REPOS) {
        for (const r of env.BRIDGEBUILDER_REPOS.split(",")) {
            const trimmed = r.trim();
            if (trimmed)
                repos.push(parseRepoString(trimmed));
        }
        if (repos.length > 0)
            reposSource = "env";
    }
    // YAML repos — only if no higher-priority source set repos
    if (repos.length === 0 && yaml.repos?.length) {
        for (const r of yaml.repos) {
            repos.push(parseRepoString(r));
        }
        reposSource = "yaml";
    }
    // Auto-detect (unless --no-auto-detect) — only if no explicit repos configured
    if (repos.length === 0 && !cliArgs.noAutoDetect) {
        const detected = await autoDetectRepo();
        if (detected) {
            repos.push(detected);
            reposSource = "auto-detect";
        }
    }
    if (repos.length === 0) {
        throw new Error("No repos configured. Use --repo owner/repo, set BRIDGEBUILDER_REPOS, or run from a git repo.");
    }
    // Track model provenance (CLI > env > yaml > default)
    const modelSource = cliArgs.model
        ? "cli"
        : env.BRIDGEBUILDER_MODEL
            ? "env"
            : yaml.model
                ? "yaml"
                : "default";
    // Track dryRun provenance
    const dryRunSource = cliArgs.dryRun != null
        ? "cli"
        : env.BRIDGEBUILDER_DRY_RUN === "true"
            ? "env"
            : "default";
    // Track token/size provenance
    const maxInputTokensSource = cliArgs.maxInputTokens != null
        ? "cli"
        : yaml.max_input_tokens != null
            ? "yaml"
            : "default";
    const maxOutputTokensSource = cliArgs.maxOutputTokens != null
        ? "cli"
        : yaml.max_output_tokens != null
            ? "yaml"
            : "default";
    const maxDiffBytesSource = cliArgs.maxDiffBytes != null
        ? "cli"
        : yaml.max_diff_bytes != null
            ? "yaml"
            : "default";
    // Resolve repoRoot: CLI > env > git auto-detect (Bug 3 fix — issue #309)
    const repoRoot = resolveRepoRoot(cliArgs, env);
    // Resolve remaining fields: CLI > env > yaml > defaults
    const config = {
        repos,
        repoRoot,
        model: cliArgs.model ?? env.BRIDGEBUILDER_MODEL ?? yaml.model ?? DEFAULTS.model,
        maxPrs: yaml.max_prs ?? DEFAULTS.maxPrs,
        maxFilesPerPr: yaml.max_files_per_pr ?? DEFAULTS.maxFilesPerPr,
        maxDiffBytes: cliArgs.maxDiffBytes ?? yaml.max_diff_bytes ?? DEFAULTS.maxDiffBytes,
        maxInputTokens: cliArgs.maxInputTokens ?? yaml.max_input_tokens ?? DEFAULTS.maxInputTokens,
        maxOutputTokens: cliArgs.maxOutputTokens ?? yaml.max_output_tokens ?? DEFAULTS.maxOutputTokens,
        dimensions: yaml.dimensions ?? DEFAULTS.dimensions,
        reviewMarker: yaml.review_marker ?? DEFAULTS.reviewMarker,
        repoOverridePath: yaml.persona_path ?? DEFAULTS.repoOverridePath,
        dryRun: cliArgs.dryRun ??
            (env.BRIDGEBUILDER_DRY_RUN === "true" ? true : undefined) ??
            DEFAULTS.dryRun,
        excludePatterns: [
            ...DEFAULT_EXCLUDE_PATTERNS,
            ...(yaml.exclude_patterns ?? []),
            ...(cliArgs.exclude ?? []),
        ],
        ghMaxBufferBytes: resolveGhMaxBufferBytes(yaml.gh_max_buffer_bytes),
        sanitizerMode: yaml.sanitizer_mode ?? DEFAULTS.sanitizerMode,
        maxRuntimeMinutes: yaml.max_runtime_minutes ?? DEFAULTS.maxRuntimeMinutes,
        ...(cliArgs.pr != null ? { targetPr: cliArgs.pr } : {}),
        ...(yaml.loa_aware != null ? { loaAware: yaml.loa_aware } : {}),
        ...(cliArgs.persona != null || yaml.persona != null
            ? { persona: cliArgs.persona ?? yaml.persona }
            : {}),
        ...(yaml.persona_path != null
            ? { personaFilePath: yaml.persona_path }
            : {}),
        ...(cliArgs.forceFullReview ? { forceFullReview: true } : {}),
        ...(yaml.ecosystem_context_path != null
            ? { ecosystemContextPath: yaml.ecosystem_context_path }
            : {}),
        ...(resolvePass1Cache(cliArgs, env, yaml) != null
            ? { pass1Cache: { enabled: resolvePass1Cache(cliArgs, env, yaml) } }
            : {}),
        reviewMode: cliArgs.reviewMode ??
            (env.LOA_BRIDGE_REVIEW_MODE === "two-pass" || env.LOA_BRIDGE_REVIEW_MODE === "single-pass"
                ? env.LOA_BRIDGE_REVIEW_MODE
                : undefined) ??
            yaml.review_mode ??
            DEFAULTS.reviewMode,
    };
    // Track reviewMode provenance
    const reviewModeSource = cliArgs.reviewMode
        ? "cli"
        : env.LOA_BRIDGE_REVIEW_MODE === "two-pass" || env.LOA_BRIDGE_REVIEW_MODE === "single-pass"
            ? "env"
            : yaml.review_mode
                ? "yaml"
                : "default";
    const provenance = {
        repos: reposSource,
        model: modelSource,
        dryRun: dryRunSource,
        maxInputTokens: maxInputTokensSource,
        maxOutputTokens: maxOutputTokensSource,
        maxDiffBytes: maxDiffBytesSource,
        reviewMode: reviewModeSource,
    };
    return { config, provenance };
}
/**
 * cycle-133 C-1: `bridgebuilder.gh_max_buffer_bytes` — an integer in 1 MiB … 512 MiB, else the default with a warning
 * (a configured buffer bounds memory per call; it is never unbounded).
 */
export function resolveGhMaxBufferBytes(raw) {
    if (raw === undefined)
        return GH_MAX_BUFFER_BYTES_DEFAULT;
    if (Number.isInteger(raw) && raw >= GH_MAX_BUFFER_BYTES_MIN && raw <= GH_MAX_BUFFER_BYTES_MAX)
        return raw;
    process.stderr.write(`[bridgebuilder] WARN: bridgebuilder.gh_max_buffer_bytes: invalid value ${JSON.stringify(raw)} ` +
        `(expected an integer ${GH_MAX_BUFFER_BYTES_MIN}..${GH_MAX_BUFFER_BYTES_MAX}) — using ${GH_MAX_BUFFER_BYTES_DEFAULT}\n`);
    return GH_MAX_BUFFER_BYTES_DEFAULT;
}
/**
 * Validate --pr flag: requires exactly one repo (IMP-008).
 */
export function resolveRepos(config, prNumber) {
    if (prNumber != null && config.repos.length > 1) {
        throw new Error(`--pr ${prNumber} specified but ${config.repos.length} repos configured. ` +
            "Use --repo owner/repo to target a single repo when using --pr.");
    }
    return config.repos;
}
/**
 * Format effective config for logging (secrets redacted).
 * Includes provenance annotations showing where each value originated.
 */
export function formatEffectiveConfig(config, provenance) {
    const repoNames = config.repos
        .map((r) => `${r.owner}/${r.repo}`)
        .join(", ");
    const p = provenance;
    const repoSrc = p ? ` (${p.repos})` : "";
    const modelSrc = p ? ` (${p.model})` : "";
    const drySrc = p ? ` (${p.dryRun})` : "";
    const prFilter = config.targetPr != null ? `, target_pr=#${config.targetPr}` : "";
    const inputSrc = p ? ` (${p.maxInputTokens})` : "";
    const outputSrc = p ? ` (${p.maxOutputTokens})` : "";
    const diffSrc = p ? ` (${p.maxDiffBytes})` : "";
    const personaInfo = config.persona ? `, persona=${config.persona}` : "";
    const excludeInfo = config.excludePatterns.length > 0
        ? `, exclude_patterns=[${config.excludePatterns.join(", ")}]`
        : "";
    return (`[bridgebuilder] Config: repos=[${repoNames}]${repoSrc}, ` +
        `model=${config.model}${modelSrc}, max_prs=${config.maxPrs}, ` +
        `max_input_tokens=${config.maxInputTokens}${inputSrc}, ` +
        `max_output_tokens=${config.maxOutputTokens}${outputSrc}, ` +
        `max_diff_bytes=${config.maxDiffBytes}${diffSrc}, ` +
        `dry_run=${config.dryRun}${drySrc}, sanitizer_mode=${config.sanitizerMode}${prFilter}` +
        `${personaInfo}${excludeInfo}` +
        `, review_mode=${config.reviewMode}${p ? ` (${p.reviewMode})` : ""}`);
}
//# sourceMappingURL=config.js.map