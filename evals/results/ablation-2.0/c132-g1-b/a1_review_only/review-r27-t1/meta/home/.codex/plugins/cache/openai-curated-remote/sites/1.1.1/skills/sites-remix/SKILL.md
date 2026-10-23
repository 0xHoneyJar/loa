---
name: sites-remix
description: Remix a Site built with the Sites plugin into a new Site. Use when the user has identified the source Site and asks to remix it.
---

# Remix a Site

A remix is a new Site built by adapting an existing Site.

- Remix creates an unpublished Site from the **published source**, with fresh Git history and destination hosting identity.
- Runtime settings, database records, and stored files are **not copied**. Bundled content is copied. Database schema may be recoverable from source, but source access does not guarantee a complete schema.

## Workflow

Follow these five steps when a user requests a remix.

1. **Create.** If the source is unclear, follow [source clarification](../sites/SKILL.md#1-select-and-open). Use a supplied Site mention's project ID, or resolve the supplied URL/slug with `search_sites`; do not infer IDs, explore unrelated Sites, or require editor-only `get_site` on the original. Choose an initial title/slug and call `remix_site`. Stop if unavailable. Retry an explicitly rejected slug; reconcile uncertain creation before retrying.
2. **Inspect.** [Open the destination](../sites/SKILL.md#1-select-and-open) as an existing hosted Site. Inspect its content, features, storage schema, integrations, and required runtime environment variables from source and documentation. Do not invent missing requirements.
3. **Decide content and features.** Check copied-content treatment and feature choices separately using [Intake questions](#intake-questions). Skip only decisions already supplied. Finish these decisions before asking for configuration values or confirmation.
4. **Configure, adapt and publish.** After intake, handle [Setup](#setup) instructions and confirmations in plain chat. Work in the destination checkout without registering again or generating a starter. Apply [Implementation requirements](#implementation-requirements), then use the [Sites workflow](../sites/SKILL.md#workflow) to build, save, and deploy. Verify retained features work or are intentionally disabled, and respect requests not to publish. Return here for the remix handoff.
5. **Follow up.** Deployment does not finish the remix response. Use [Final handoff](#final-handoff), including when setup issues dominated the conversation.

## Intake questions

- Resolve unclear copied-content treatment and undecided features. A vague request needs useful intake. Skip supplied decisions; preserve the design and unspecified features. Ask about intended use only if it changes the work, as a separate decision; do not offer a generic design refresh.
- For unresolved copied-content treatment, offer two outcomes: keep the copied content, or clear it for replacement content added later. Apply replacement details already supplied. Decide content treatment before proposing new wording; title, audience, and feature changes are separate decisions.
- Use `request_user_input_async` or its available equivalent for intake, falling back to chat. Limit intake to **three questions total**. Offer two or three concrete choices where useful, recommended first, with neutral labels avoiding first- or second-person pronouns.
- Ask one decision per question. Every option must answer that same decision and make sense when selected alone. The tool already provides custom input; never add an option that merely asks for a typed answer. Unanswered questions are not consent.
- For an undecided feature requiring environment variables or an account connection, briefly explain what is needed and who supplies or connects it. Keep inspection summaries, setup instructions, identifiers, and test logistics outside question titles/options. Configuration values and confirmations belong to [Setup](#setup), after intake.
- Explain uncopied data once. Missing content starts empty and can be added after publishing; do not ask users to choose between an empty start and later content, or request uploads during intake.

## Implementation requirements

Apply these requirements while adapting the copied Site.

- **Content and features:** Preserve the design unless a change is explicitly requested; keep unspecified features. Apply confirmed removals to UI and behavior. For temporary disabling, preserve client and server implementations, including inputs and action handlers; guard execution so re-enabling does not require rebuilding the feature. Adapt or clear source-specific links and stored-file dependencies along with their content. Missing or deferred content starts empty, with useful empty states and supported add/upload actions; add samples only when requested. External content needs supported access before it can be used.
- **Storage:** For retained functionality, [recreate required D1 schema and R2 bindings](../sites/references/storage.md) without asking infrastructure questions. Skip resources used only by removed or disabled features. Distinguish required reference data from user records; report incomplete schema rather than guessing. Validate migrations locally and verify hosted storage after deployment applies them.

## Setup

After content and feature decisions, use plain chat for configuration instructions and confirmations, not the intake question tool. A request to keep a feature working resolves only that feature choice; resolve any unspecified copied-content treatment before proceeding to its missing setup.

- **Environment variables and connections:** Required environment variables supply runtime configuration read by the code. Guard calls when required values are missing; preserve normal visitor account-connection flows. Unavailable verification is not consent to add disable switches or disable a retained feature; report it as unverified. If missing owner-provided variables block requested functionality, ask for setup or explicit deferral before publishing. Configure only variables needed by retained features; keep explicitly deferred features disabled. Continue independent work while waiting; do not claim unverified features work.
- **Secret entry:** Collect non-sensitive environment-variable values in plain chat and save them with `update_environment_variables`. Users save secrets directly in Site settings → **Environment variables**, with **Secret** enabled; never collect secret values in chat or source. Wait for confirmation, then use `get_environment_variables` to verify presence without reading values; redacted values are not missing. Deploy a saved version after environment variables change to apply them. Follow [Secrets](../sites/references/identity-and-secrets.md#secrets) for supported `OPENAI_API_KEY` setup.

## Final handoff

Before sending the post-publish response, include each applicable item:

- **Deferred content, including uncopied records/files:** Offer a warm, optional invitation in plain chat to share content or a source when ready, and explain how it will be used. Acknowledge known sources and the next step. Do not require an answer or upload now.
- **Remaining setup:** Name the affected feature, exact missing environment variable/enable flag and non-secret value, configuration location or connection step, and any code toggle/redeploy still needed. Include these in the response, not only a source file. Direct secret entry to Site settings; verify presence after confirmation and functionality before claiming readiness.
