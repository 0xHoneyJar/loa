import { GitHubCLIAdapter } from "./github-cli.js";
import { AnthropicAdapter } from "./anthropic.js";
import { PatternSanitizer } from "./sanitizer.js";
import { NodeHasher } from "./node-hasher.js";
import { ConsoleLogger } from "./console-logger.js";
import { NoOpContextStore } from "./noop-context.js";
export function createLocalAdapters(config, anthropicApiKey) {
    if (!anthropicApiKey) {
        throw new Error("ANTHROPIC_API_KEY required. Set it in your environment: export ANTHROPIC_API_KEY=sk-ant-...");
    }
    const ghAdapter = new GitHubCLIAdapter({
        reviewMarker: config.reviewMarker,
    });
    return {
        git: ghAdapter,
        poster: ghAdapter,
        llm: new AnthropicAdapter(anthropicApiKey, config.model),
        sanitizer: new PatternSanitizer(),
        hasher: new NodeHasher(),
        logger: new ConsoleLogger(),
        contextStore: new NoOpContextStore(),
    };
}
// Re-export individual adapters for testing
export { GitHubCLIAdapter } from "./github-cli.js";
export { AnthropicAdapter } from "./anthropic.js";
export { PatternSanitizer } from "./sanitizer.js";
export { NodeHasher } from "./node-hasher.js";
export { ConsoleLogger } from "./console-logger.js";
export { NoOpContextStore } from "./noop-context.js";
//# sourceMappingURL=index.js.map