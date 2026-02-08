import type { IGitProvider } from "../ports/git-provider.js";
import type { ILLMProvider } from "../ports/llm-provider.js";
import type { IReviewPoster } from "../ports/review-poster.js";
import type { IOutputSanitizer } from "../ports/output-sanitizer.js";
import type { ILogger } from "../ports/logger.js";
import type { PRReviewTemplate } from "./template.js";
import type { BridgebuilderContext } from "./context.js";
import type { BridgebuilderConfig, RunSummary } from "./types.js";
export declare class ReviewPipeline {
    private readonly template;
    private readonly context;
    private readonly git;
    private readonly poster;
    private readonly llm;
    private readonly sanitizer;
    private readonly logger;
    private readonly persona;
    private readonly config;
    private readonly now;
    constructor(template: PRReviewTemplate, context: BridgebuilderContext, git: IGitProvider, poster: IReviewPoster, llm: ILLMProvider, sanitizer: IOutputSanitizer, logger: ILogger, persona: string, config: BridgebuilderConfig, now?: () => number);
    run(runId: string): Promise<RunSummary>;
    private processItem;
    private classifyError;
    private skipResult;
    private errorResult;
    private buildSummary;
}
//# sourceMappingURL=reviewer.d.ts.map