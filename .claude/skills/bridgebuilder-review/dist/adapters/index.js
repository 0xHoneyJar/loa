import { GitHubCLIAdapter } from "./github-cli.js";
import { ChevalDelegateAdapter } from "./cheval-delegate.js";
import { PatternSanitizer } from "./sanitizer.js";
import { NodeHasher } from "./node-hasher.js";
import { ConsoleLogger } from "./console-logger.js";
import { NoOpContextStore } from "./noop-context.js";
import { deriveTimeoutMs } from "../core/multi-model-pipeline.js";
// cycle-109 followup #880 Defect 1: the precondition skips when the
// operator-selected model is a kind:cli headless alias. Those models
// route through claude-headless / codex-headless / gemini-headless
// CLIs which use their own OAuth subscription paths (no API key
// required at the BB layer). The `*-headless` suffix is the framework
// convention for kind:cli aliases.
function isHeadlessModel(model) {
    return typeof model === "string" && model.endsWith("-headless");
}
export function createLocalAdapters(config, anthropicApiKey) {
    // cycle-103 T1.4 + cycle-109 followup #880 Defect 1: pre-flight check
    // that ANTHROPIC_API_KEY is set in the parent environment. Skipped
    // when the operator routes BB through a kind:cli headless alias —
    // ChevalDelegateAdapter handles its own auth routing internally (and
    // PR #892 ensures the subprocess env is stripped of ANTHROPIC_API_KEY
    // so claude -p reaches OAuth subscription).
    if (!anthropicApiKey && !isHeadlessModel(config.model)) {
        throw new Error("ANTHROPIC_API_KEY required. Set it in your environment: export ANTHROPIC_API_KEY=sk-ant-... " +
            "(or set BRIDGEBUILDER_MODEL=<provider>-headless to route through an OAuth CLI subscription).");
    }
    const ghAdapter = new GitHubCLIAdapter({
        reviewMarker: config.reviewMarker,
    });
    // Sprint-bug-143 #789a: shared deriveTimeoutMs helper. For Anthropic
    // single-model the reasoning-class branch never fires (provider !== openai),
    // so this preserves the existing tiered ladder for the default path.
    const timeoutMs = deriveTimeoutMs("anthropic", config.model, config);
    return {
        git: ghAdapter,
        poster: ghAdapter,
        llm: new ChevalDelegateAdapter({
            model: config.model,
            timeoutMs,
        }),
        sanitizer: new PatternSanitizer(),
        hasher: new NodeHasher(),
        logger: new ConsoleLogger(),
        contextStore: new NoOpContextStore(),
    };
}
// Re-export individual adapters for testing.
// cycle-103 T1.4: AnthropicAdapter / OpenAIAdapter / GoogleAdapter retired —
// see git history for the legacy per-provider implementations.
export { GitHubCLIAdapter } from "./github-cli.js";
export { ChevalDelegateAdapter } from "./cheval-delegate.js";
export { PatternSanitizer } from "./sanitizer.js";
export { NodeHasher } from "./node-hasher.js";
export { ConsoleLogger } from "./console-logger.js";
export { NoOpContextStore } from "./noop-context.js";
//# sourceMappingURL=index.js.map