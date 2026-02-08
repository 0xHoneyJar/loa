import type { PullRequestFile } from "../ports/git-provider.js";
import type { BridgebuilderConfig, TruncationResult } from "./types.js";
export declare function truncateFiles(files: PullRequestFile[], config: Pick<BridgebuilderConfig, "excludePatterns" | "maxDiffBytes" | "maxFilesPerPr">): TruncationResult;
//# sourceMappingURL=truncation.d.ts.map