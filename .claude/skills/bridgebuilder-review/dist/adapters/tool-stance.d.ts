import type { ToolStance } from "../ports/llm-provider.js";
/** Bump when a stance's mechanism changes; the role check refuses a version it does not know. */
export declare const TOOL_STANCE_VERSION = "1";
export type { ToolStance };
/**
 * The stance of the route that dispatching `model` takes; `answeredProvider` is the provider cheval reported.
 * Undefined when the route is unknown (gemini-headless, the grok and cursor CLIs, an unregistered id) — refused.
 */
export declare function toolStanceFor(model: string, answeredProvider?: string): ToolStance | undefined;
//# sourceMappingURL=tool-stance.d.ts.map