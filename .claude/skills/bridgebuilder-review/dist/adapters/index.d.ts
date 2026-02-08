import type { IGitProvider } from "../ports/git-provider.js";
import type { ILLMProvider } from "../ports/llm-provider.js";
import type { IReviewPoster } from "../ports/review-poster.js";
import type { IOutputSanitizer } from "../ports/output-sanitizer.js";
import type { IHasher } from "../ports/hasher.js";
import type { ILogger } from "../ports/logger.js";
import type { IContextStore } from "../ports/context-store.js";
import type { BridgebuilderConfig } from "../core/types.js";
export interface LocalAdapters {
    git: IGitProvider;
    poster: IReviewPoster;
    llm: ILLMProvider;
    sanitizer: IOutputSanitizer;
    hasher: IHasher;
    logger: ILogger;
    contextStore: IContextStore;
}
export declare function createLocalAdapters(config: BridgebuilderConfig, anthropicApiKey: string): LocalAdapters;
export { GitHubCLIAdapter } from "./github-cli.js";
export type { GitHubCLIAdapterConfig } from "./github-cli.js";
export { AnthropicAdapter } from "./anthropic.js";
export { PatternSanitizer } from "./sanitizer.js";
export { NodeHasher } from "./node-hasher.js";
export { ConsoleLogger } from "./console-logger.js";
export { NoOpContextStore } from "./noop-context.js";
//# sourceMappingURL=index.d.ts.map