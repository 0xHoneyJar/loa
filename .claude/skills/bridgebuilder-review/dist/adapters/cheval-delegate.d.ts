import { spawn } from "node:child_process";
import { LLMProviderError } from "../ports/llm-provider.js";
import type { ILLMProvider, ReviewRequest, ReviewResponse } from "../ports/llm-provider.js";
export interface ChevalDelegateOptions {
    /** Provider:model-id string passed to cheval `--model`. */
    model: string;
    /** Wall-clock timeout for the entire spawn. SIGTERM at timeout, SIGKILL at timeout+5s. */
    timeoutMs?: number;
    /** Sprint 1 AC-1.2 — pass-through for `--mock-fixture-dir`. T1.5 wires the flag inside cheval. */
    mockFixtureDir?: string;
    /** Reserved for cycle-104+ daemon-mode. Currently only "spawn" is honored. */
    mode?: "spawn" | "daemon";
    /** Cheval agent binding name (e.g., "reviewing-code"). T1.4 will pass per-provider names. */
    agent?: string;
    /** Override for the cheval.py script path. Tests pass a fixture path; production resolves from repo root. */
    chevalScript?: string;
    /** Override for the python executable. Defaults to `python3`. */
    pythonBin?: string;
    /** Override for child-process spawn (test hook). Defaults to Node's `child_process.spawn`. */
    spawnFn?: typeof spawn;
}
export declare class ChevalDelegateAdapter implements ILLMProvider {
    private readonly opts;
    constructor(options: ChevalDelegateOptions);
    generateReview(request: ReviewRequest): Promise<ReviewResponse>;
}
/**
 * Translate a cheval exit code + stderr tail into a typed LLMProviderError per
 * SDD §5.3 table. Stderr classification disambiguates exit-1 (RATE_LIMITED vs
 * PROVIDER_ERROR) by reading the JSON error envelope cheval emits last line.
 */
export declare function translateExitCode(exitCode: number | null, stderr: string): LLMProviderError;
//# sourceMappingURL=cheval-delegate.d.ts.map