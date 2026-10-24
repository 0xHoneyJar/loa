/**
 * cycle-133 C-2 (sdd.md § 1.4, FR-2, D-1.7 DEC-0853): the no-tool stance a cheval route enforces at dispatch.
 *
 * ChevalDelegateAdapter reports the stance of the route it dispatched in every ReviewResponse; the writer-role check
 * (core/writer-role.ts) verifies that report. The stance is keyed by the model id the adapter dispatched (cheval's
 * reply names the provider and the underlying model, not the transport) and cross-checked against the provider cheval
 * reports: a reply from another provider than the one requested carries no stance.
 *
 * `enforced: true` means a dispatch-level restriction the argv or wire format carries, verified by
 * __tests__/writer-role.test.ts against the Python adapters:
 *  - claude-headless: `claude -p --tools "" --permission-mode plan` (claude_headless_adapter.py build_headless_argv);
 *  - the HTTP API adapters: cheval's CLI request carries no tool definitions and each adapter adds them only under
 *    `if request.tools:` (anthropic, openai, bedrock) or never (google).
 * codex-headless is a posture (`--sandbox read-only`, four agent features disabled), not an all-tools restriction.
 */
import { GENERATED_MODEL_REGISTRY } from "../config.generated.js";
import type { ToolStance } from "../ports/llm-provider.js";

/** Bump when a stance's mechanism changes; the role check refuses a version it does not know. */
export const TOOL_STANCE_VERSION = "1";

export type { ToolStance };

const HEADLESS: Record<string, Omit<ToolStance, "adapter_version">> = {
  "claude-headless": {
    adapter: "claude-headless",
    tools: "none",
    enforced: true,
    mechanism: 'claude -p --tools "" --permission-mode plan --no-session-persistence (claude_headless_adapter.py build_headless_argv)',
  },
  "codex-headless": {
    adapter: "codex-headless",
    tools: "native",
    enforced: false,
    mechanism: "codex exec --sandbox read-only --ignore-user-config --disable shell_tool,browser_use,browser_use_external,computer_use " +
      "(a posture: no all-tools switch; the remaining native tools follow codex defaults)",
  },
};

const API_PROVIDERS = new Set(["anthropic", "openai", "google", "bedrock"]);

/**
 * The stance of the route that dispatching `model` takes; `answeredProvider` is the provider cheval reported.
 * Undefined when the route is unknown (gemini-headless, the grok and cursor CLIs, an unregistered id) — refused.
 */
export function toolStanceFor(model: string, answeredProvider?: string): ToolStance | undefined {
  const colon = model.indexOf(":");
  const prefixed = colon > 0 && API_PROVIDERS.has(model.slice(0, colon)) ? model.slice(0, colon) : undefined;
  const id = prefixed ? model.slice(colon + 1) : model;
  const headless = Object.hasOwn(HEADLESS, id) ? HEADLESS[id] : undefined;
  if (headless) {
    const provider = GENERATED_MODEL_REGISTRY[id]?.provider;
    if (answeredProvider !== undefined && provider !== undefined && answeredProvider !== provider) return undefined;
    return { ...headless, adapter_version: TOOL_STANCE_VERSION };
  }
  if (/-headless$/.test(id)) return undefined;
  const entry = Object.hasOwn(GENERATED_MODEL_REGISTRY, id) ? GENERATED_MODEL_REGISTRY[id] : undefined;
  const provider = entry?.provider ?? prefixed;
  if (provider === undefined || !API_PROVIDERS.has(provider)) return undefined;
  if (prefixed !== undefined && entry !== undefined && entry.provider !== prefixed) return undefined;
  if (answeredProvider !== undefined && answeredProvider !== provider) return undefined;
  return {
    adapter: `${provider}-api`,
    adapter_version: TOOL_STANCE_VERSION,
    tools: "none",
    enforced: true,
    mechanism: `${provider} HTTP API request without tool definitions (cheval CompletionRequest.tools unset)`,
  };
}
