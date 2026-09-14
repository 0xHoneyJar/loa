# Headless test consolidation — 2026-09-14

This completes the test-consolidation portion of #1027. The shared runtime
already exists on base `80be4b0f57b39eb05c77b0a738a2797afac635a7`; this change
does not modify provider implementations. Fifty duplicated test definitions
move into shared parametrized contracts. The 129 definitions retained in the
four original adapter suites have unchanged ASTs.

The shared suite grows from 30 to 138 collected cases, covering all six
adapters. Provider-specific parsing, command construction, diagnostic and
permission controls remain in their original suites. The table maps each
removed definition to its shared replacement.

Validation: 337 offline Python cases passed. Six explicit live cases remain
in source and were excluded. The baseline had 276 passing cases, with those
six live cases and three tests that mutated HOME excluded; the latter three
have passing replacements that preserve HOME. Case inventory verification
found no unmapped original and no unexecuted offline replacement. All 24
tracked provider-source files match the base byte-for-byte.

The companion model-adapter help correction describes unconditional Cheval
dispatch, retired flags and registry-resolved aliases. All four shim tests
pass, including the actual help path with both retired flag values and no
provider dispatch. This is offline validation, not current native-CLI or
subscription-billing evidence for #1099.

| Original suite | Removed definition | Shared replacement |
| --- | --- | --- |
| `test_claude_headless_adapter.py` | `TestPromptFlattening::test_system_user_assistant_sequence` | `shared::test_prompt_formatting[claude-conversation-order]` |
| `test_claude_headless_adapter.py` | `TestPromptFlattening::test_anthropic_style_list_content` | `shared::test_prompt_formatting[claude-list-content]` |
| `test_claude_headless_adapter.py` | `TestErrorClassification::test_timeout_raises_provider_unavailable` | `shared::test_completion_subprocess_errors[claude-timeout]` |
| `test_claude_headless_adapter.py` | `TestErrorClassification::test_claude_not_on_path_raises_config_error` | `shared::test_completion_subprocess_errors[claude-missing-binary]` |
| `test_claude_headless_adapter.py` | `TestValidateAndHealth::test_validate_config_clean_when_claude_present` | `shared::test_validation_contract[claude-valid]` |
| `test_claude_headless_adapter.py` | `TestValidateAndHealth::test_validate_config_complains_when_claude_missing` | `shared::test_validation_contract[claude-missing-binary]` |
| `test_claude_headless_adapter.py` | `TestValidateAndHealth::test_validate_config_complains_on_wrong_type` | `shared::test_validation_contract[claude-wrong-type]` |
| `test_claude_headless_adapter.py` | `TestValidateAndHealth::test_health_check_returns_true_on_zero_exit` | `shared::test_health_check_version_contract[claude-success]` |
| `test_claude_headless_adapter.py` | `TestValidateAndHealth::test_health_check_false_when_binary_missing` | `shared::test_missing_binary_health_is_false[claude]` |
| `test_claude_headless_adapter.py` | `TestSubprocessEnvFilter::test_anthropic_api_key_stripped_by_default` | `shared::test_subprocess_environment_contract[claude-strip]` |
| `test_claude_headless_adapter.py` | `TestSubprocessEnvFilter::test_opt_out_keeps_api_key` | `shared::test_subprocess_environment_contract[claude-keep]` |
| `test_claude_headless_adapter.py` | `TestSubprocessEnvFilter::test_no_api_key_in_parent_env_still_passes_clean_env` | `shared::test_subprocess_environment_contract[claude-absent]` |
| `test_claude_headless_adapter.py` | `TestSubprocessEnvFilter::test_path_and_home_preserved` | `shared::test_subprocess_environment_contract[claude-strip]` |
| `test_codex_headless_adapter.py` | `TestPromptFlattening::test_single_user_message` | `shared::test_prompt_formatting[codex-single-user]` |
| `test_codex_headless_adapter.py` | `TestPromptFlattening::test_system_user_assistant_sequence` | `shared::test_prompt_formatting[codex-conversation-order]` |
| `test_codex_headless_adapter.py` | `TestPromptFlattening::test_anthropic_style_list_content` | `shared::test_prompt_formatting[codex-list-content]` |
| `test_codex_headless_adapter.py` | `TestPromptFlattening::test_tool_role_inlined` | `shared::test_prompt_formatting[codex-tool-result]` |
| `test_codex_headless_adapter.py` | `TestErrorClassification::test_timeout_raises_provider_unavailable` | `shared::test_completion_subprocess_errors[codex-timeout]` |
| `test_codex_headless_adapter.py` | `TestErrorClassification::test_codex_not_on_path_raises_config_error` | `shared::test_completion_subprocess_errors[codex-missing-binary]` |
| `test_codex_headless_adapter.py` | `TestValidateAndHealth::test_validate_config_clean_when_codex_present` | `shared::test_validation_contract[codex-valid]` |
| `test_codex_headless_adapter.py` | `TestValidateAndHealth::test_validate_config_complains_when_codex_missing` | `shared::test_validation_contract[codex-missing-binary]` |
| `test_codex_headless_adapter.py` | `TestValidateAndHealth::test_validate_config_complains_on_wrong_type` | `shared::test_validation_contract[codex-wrong-type]` |
| `test_codex_headless_adapter.py` | `TestValidateAndHealth::test_health_check_returns_true_on_zero_exit` | `shared::test_health_check_version_contract[codex-success]` |
| `test_codex_headless_adapter.py` | `TestValidateAndHealth::test_health_check_false_when_binary_missing` | `shared::test_missing_binary_health_is_false[codex]` |
| `test_codex_headless_adapter.py` | `TestSubprocessEnvFilter::test_openai_api_key_stripped_by_default` | `shared::test_subprocess_environment_contract[codex-strip]` |
| `test_codex_headless_adapter.py` | `TestSubprocessEnvFilter::test_opt_out_keeps_api_key` | `shared::test_subprocess_environment_contract[codex-keep]` |
| `test_codex_headless_adapter.py` | `TestSubprocessEnvFilter::test_path_and_home_preserved` | `shared::test_subprocess_environment_contract[codex-strip]` |
| `test_gemini_headless_adapter.py` | `TestPromptFlattening::test_system_user_assistant_sequence` | `shared::test_prompt_formatting[gemini-conversation-order]` |
| `test_gemini_headless_adapter.py` | `TestPromptFlattening::test_anthropic_style_list_content` | `shared::test_prompt_formatting[gemini-list-content]` |
| `test_gemini_headless_adapter.py` | `TestErrorClassification::test_timeout_raises_provider_unavailable` | `shared::test_completion_subprocess_errors[gemini-timeout]` |
| `test_gemini_headless_adapter.py` | `TestErrorClassification::test_gemini_not_on_path_raises_config_error` | `shared::test_completion_subprocess_errors[gemini-missing-binary]` |
| `test_gemini_headless_adapter.py` | `TestValidateAndHealth::test_validate_config_clean_when_gemini_present` | `shared::test_validation_contract[gemini-valid]` |
| `test_gemini_headless_adapter.py` | `TestValidateAndHealth::test_validate_config_complains_when_gemini_missing` | `shared::test_validation_contract[gemini-missing-binary]` |
| `test_gemini_headless_adapter.py` | `TestValidateAndHealth::test_validate_config_complains_on_wrong_type` | `shared::test_validation_contract[gemini-wrong-type]` |
| `test_gemini_headless_adapter.py` | `TestValidateAndHealth::test_health_check_returns_true_on_zero_exit` | `shared::test_health_check_version_contract[gemini-success]` |
| `test_gemini_headless_adapter.py` | `TestValidateAndHealth::test_health_check_false_when_binary_missing` | `shared::test_missing_binary_health_is_false[gemini]` |
| `test_gemini_headless_adapter.py` | `TestSubprocessEnvFilter::test_google_api_keys_stripped_by_default` | `shared::test_subprocess_environment_contract[gemini-strip]` |
| `test_gemini_headless_adapter.py` | `TestSubprocessEnvFilter::test_opt_out_keeps_api_keys` | `shared::test_subprocess_environment_contract[gemini-keep]` |
| `test_gemini_headless_adapter.py` | `TestSubprocessEnvFilter::test_path_and_home_preserved` | `shared::test_subprocess_environment_contract[gemini-strip]` |
| `test_cursor_headless_adapter.py` | `TestPromptFlattening::test_roles_prefixed` | `shared::test_prompt_formatting[cursor-conversation-order]` |
| `test_cursor_headless_adapter.py` | `TestPromptFlattening::test_list_content_blocks` | `shared::test_prompt_and_timeout_contract[cursor]` |
| `test_cursor_headless_adapter.py` | `TestErrorClassification::test_timeout_raises_unavailable` | `shared::test_completion_subprocess_errors[cursor-timeout]` |
| `test_cursor_headless_adapter.py` | `TestErrorClassification::test_output_cap_exceeded_is_unavailable` | `shared::test_completion_subprocess_errors[cursor-output-cap]` |
| `test_cursor_headless_adapter.py` | `TestErrorClassification::test_missing_cli_is_configerror` | `shared::test_completion_subprocess_errors[cursor-missing-binary]` |
| `test_cursor_headless_adapter.py` | `TestErrorClassification::test_semaphore_exhausted_is_chain_exhausted_concurrency` | `shared::test_semaphore_failure_never_spawns[cursor-default-limit]` |
| `test_cursor_headless_adapter.py` | `TestValidateAndHealth::test_validate_ok` | `shared::test_validation_contract[cursor-valid]` |
| `test_cursor_headless_adapter.py` | `TestValidateAndHealth::test_validate_missing_cli` | `shared::test_validation_contract[cursor-missing-binary]` |
| `test_cursor_headless_adapter.py` | `TestValidateAndHealth::test_validate_wrong_type` | `shared::test_validation_contract[cursor-wrong-type]` |
| `test_cursor_headless_adapter.py` | `TestValidateAndHealth::test_health_check_true` | `shared::test_health_check_version_contract[cursor-success]` |
| `test_cursor_headless_adapter.py` | `TestValidateAndHealth::test_health_check_missing_cli` | `shared::test_missing_binary_health_is_false[cursor]` |
