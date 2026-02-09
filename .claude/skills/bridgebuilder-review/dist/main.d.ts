import type { BridgebuilderConfig } from "./core/types.js";
/**
 * Discover available persona packs from the personas/ directory.
 * Returns pack names (e.g., ["default", "security", "dx", "architecture", "quick"]).
 */
export declare function discoverPersonas(): Promise<string[]>;
/**
 * Load persona using 5-level CLI-wins precedence chain:
 * 1. --persona <name> CLI flag → resources/personas/<name>.md
 * 2. persona: <name> YAML config → resources/personas/<name>.md
 * 3. persona_path: <path> YAML config → load custom file path
 * 4. grimoires/bridgebuilder/BEAUVOIR.md (repo-level override)
 * 5. resources/personas/default.md (built-in default)
 *
 * Returns { content, source } for logging.
 */
export declare function loadPersona(config: BridgebuilderConfig, logger?: {
    warn: (msg: string) => void;
}): Promise<{
    content: string;
    source: string;
}>;
//# sourceMappingURL=main.d.ts.map