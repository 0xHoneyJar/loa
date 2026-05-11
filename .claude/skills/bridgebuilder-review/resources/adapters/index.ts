import type { IGitProvider } from "../ports/git-provider.js";
import type { ILLMProvider } from "../ports/llm-provider.js";
import type { IReviewPoster } from "../ports/review-poster.js";
import type { IOutputSanitizer } from "../ports/output-sanitizer.js";
import type { IHasher } from "../ports/hasher.js";
import type { ILogger } from "../ports/logger.js";
import type { IContextStore } from "../ports/context-store.js";
import type { BridgebuilderConfig } from "../core/types.js";

import { GitHubCLIAdapter } from "./github-cli.js";
import { ChevalDelegateAdapter } from "./cheval-delegate.js";
import { PatternSanitizer } from "./sanitizer.js";
import { NodeHasher } from "./node-hasher.js";
import { ConsoleLogger } from "./console-logger.js";
import { NoOpContextStore } from "./noop-context.js";
import { deriveTimeoutMs } from "../core/multi-model-pipeline.js";

export interface LocalAdapters {
  git: IGitProvider;
  poster: IReviewPoster;
  llm: ILLMProvider;
  sanitizer: IOutputSanitizer;
  hasher: IHasher;
  logger: ILogger;
  contextStore: IContextStore;
}

export function createLocalAdapters(
  config: BridgebuilderConfig,
  anthropicApiKey: string,
): LocalAdapters {
  // cycle-103 T1.4: anthropicApiKey is still required (single-model BB
  // defaults to Anthropic). Credential value crosses the subprocess boundary
  // via env inheritance — passing it here is the operator's pre-flight check
  // that ANTHROPIC_API_KEY is set in the parent environment.
  if (!anthropicApiKey) {
    throw new Error(
      "ANTHROPIC_API_KEY required. Set it in your environment: export ANTHROPIC_API_KEY=sk-ant-...",
    );
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
export type { GitHubCLIAdapterConfig } from "./github-cli.js";
export { ChevalDelegateAdapter } from "./cheval-delegate.js";
export { PatternSanitizer } from "./sanitizer.js";
export { NodeHasher } from "./node-hasher.js";
export { ConsoleLogger } from "./console-logger.js";
export { NoOpContextStore } from "./noop-context.js";
