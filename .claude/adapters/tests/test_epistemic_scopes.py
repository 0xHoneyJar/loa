"""Tests for epistemic trust scopes and context filtering (Sprint 9, Task 9.3; BB-602).

Validates that context_filter.py correctly filters message content based on
the context_access dimension of a model's trust_scopes. Covers all 4 sub-dimensions
(architecture, business_logic, security, lore), backward compatibility, and
native_runtime bypass.

BB-602 additions: Tests for audit_filter_context, lookup_trust_scopes,
invalidate_permissions_cache, and ARCHITECTURE_SUMMARY_MAX_CHARS constant.
"""

import pytest

from loa_cheval.routing.context_filter import (
    ARCHITECTURE_SUMMARY_MAX_CHARS,
    DEFAULT_CONTEXT_ACCESS,
    audit_filter_context,
    filter_context,
    filter_message_content,
    get_context_access,
    invalidate_permissions_cache,
    is_all_full,
    lookup_trust_scopes,
)

# ============================================================================
# Fixtures — identifiable content for each category
# ============================================================================

ARCHITECTURE_CONTENT = """# Software Design Document

## Overview
This system uses a hexagonal architecture with ports and adapters.

## Components
- **Router**: Handles incoming requests and dispatches to adapters.
- **Adapter Layer**: Implements ProviderAdapter interface per provider.

## Interfaces
The main interface is `ProviderAdapter.complete(request: CompletionRequest)`.
"""

BUSINESS_LOGIC_CONTENT = """Here is the implementation:

```python
def calculate_cost_micro(tokens: int, price_per_mtok: int) -> int:
    raw = tokens * price_per_mtok
    cost = raw // 1_000_000
    remainder = raw % 1_000_000
    return cost, remainder
```

The function handles edge cases for overflow.
"""

SECURITY_CONTENT = """## Security Audit Findings

### Vulnerability: CVE-2024-12345
SQL injection in the query parser allows remote code execution.

### Audit Finding F-001
Secret leakage detected in error responses. Credentials exposed via stack traces.

OWASP Top 10 review identified 3 critical injection vectors.
"""

LORE_CONTENT = """# Lore Index

- id: mibera-001
  term: Conservation Invariant
  short: "sum(input) == sum(output) + sum(remainder)"
  context: |
    The conservation invariant is the most important property in the metering
    pipeline. It spans pricing, budget, and ledger layers. First identified
    in Bridgebuilder Part II as the "social contract" of the economic subsystem.
  tags: [metering, invariant]
"""

MIXED_CONTENT = (
    ARCHITECTURE_CONTENT + "\n---\n" + SECURITY_CONTENT + "\n---\n" + BUSINESS_LOGIC_CONTENT
)


# ============================================================================
# get_context_access tests
# ============================================================================


class TestGetContextAccess:
    def test_none_trust_scopes_returns_defaults(self):
        result = get_context_access(None)
        assert result == DEFAULT_CONTEXT_ACCESS

    def test_empty_trust_scopes_returns_defaults(self):
        result = get_context_access({})
        assert result == DEFAULT_CONTEXT_ACCESS

    def test_missing_context_access_returns_defaults(self):
        """Backward compat: pre-v7 models without context_access get all-full."""
        result = get_context_access({"data_access": "none", "financial": "none"})
        assert result == DEFAULT_CONTEXT_ACCESS

    def test_partial_context_access_fills_defaults(self):
        result = get_context_access(
            {"context_access": {"architecture": "none", "security": "redacted"}}
        )
        assert result["architecture"] == "none"
        assert result["security"] == "redacted"
        assert result["business_logic"] == "full"
        assert result["lore"] == "full"

    def test_full_context_access_preserved(self):
        scopes = {
            "context_access": {
                "architecture": "summary",
                "business_logic": "redacted",
                "security": "none",
                "lore": "summary",
            }
        }
        result = get_context_access(scopes)
        assert result == scopes["context_access"]


# ============================================================================
# is_all_full tests
# ============================================================================


class TestIsAllFull:
    def test_all_full_returns_true(self):
        assert is_all_full(DEFAULT_CONTEXT_ACCESS) is True

    def test_one_non_full_returns_false(self):
        access = dict(DEFAULT_CONTEXT_ACCESS)
        access["security"] = "none"
        assert is_all_full(access) is False


# ============================================================================
# filter_message_content tests
# ============================================================================


class TestFilterMessageContent:
    def test_full_access_no_filtering(self):
        """All dimensions full → no changes."""
        result = filter_message_content(MIXED_CONTENT, DEFAULT_CONTEXT_ACCESS)
        assert result == MIXED_CONTENT

    def test_architecture_none_strips_sdd(self):
        access = dict(DEFAULT_CONTEXT_ACCESS)
        access["architecture"] = "none"
        result = filter_message_content(ARCHITECTURE_CONTENT, access)
        assert "Software Design Document" not in result
        assert "hexagonal architecture" not in result

    def test_architecture_summary_truncates(self):
        access = dict(DEFAULT_CONTEXT_ACCESS)
        access["architecture"] = "summary"
        result = filter_message_content(ARCHITECTURE_CONTENT, access)
        # Headers should be preserved
        assert "# Software Design Document" in result
        assert "## Overview" in result

    def test_business_logic_redacted_replaces_bodies(self):
        access = dict(DEFAULT_CONTEXT_ACCESS)
        access["business_logic"] = "redacted"
        result = filter_message_content(BUSINESS_LOGIC_CONTENT, access)
        assert "[redacted]" in result
        # Signature should be preserved
        assert "def calculate_cost_micro" in result

    def test_business_logic_none_strips_code_blocks(self):
        access = dict(DEFAULT_CONTEXT_ACCESS)
        access["business_logic"] = "none"
        result = filter_message_content(BUSINESS_LOGIC_CONTENT, access)
        assert "def calculate_cost_micro" not in result
        assert "[code block filtered]" in result

    def test_security_none_strips_findings(self):
        access = dict(DEFAULT_CONTEXT_ACCESS)
        access["security"] = "none"
        result = filter_message_content(SECURITY_CONTENT, access)
        assert "CVE-2024-12345" not in result
        assert "SQL injection" not in result

    def test_security_redacted_masks_cves(self):
        access = dict(DEFAULT_CONTEXT_ACCESS)
        access["security"] = "redacted"
        result = filter_message_content(SECURITY_CONTENT, access)
        assert "CVE-2024-12345" not in result
        assert "[CVE-redacted]" in result

    def test_lore_none_strips_lore_sections(self):
        access = dict(DEFAULT_CONTEXT_ACCESS)
        access["lore"] = "none"
        result = filter_message_content(LORE_CONTENT, access)
        assert "Lore Index" not in result

    def test_lore_summary_keeps_short_strips_context(self):
        access = dict(DEFAULT_CONTEXT_ACCESS)
        access["lore"] = "summary"
        result = filter_message_content(LORE_CONTENT, access)
        # short field preserved
        assert "sum(input) == sum(output) + sum(remainder)" in result
        # context block stripped
        assert "social contract" not in result

    def test_mixed_architecture_full_security_none(self):
        """Architecture preserved, security stripped."""
        access = dict(DEFAULT_CONTEXT_ACCESS)
        access["security"] = "none"
        result = filter_message_content(MIXED_CONTENT, access)
        assert "Software Design Document" in result
        assert "hexagonal architecture" in result
        assert "CVE-2024-12345" not in result

    def test_empty_content_returns_empty(self):
        result = filter_message_content("", DEFAULT_CONTEXT_ACCESS)
        assert result == ""

    def test_none_content_returns_none(self):
        result = filter_message_content(None, DEFAULT_CONTEXT_ACCESS)
        assert result is None


# ============================================================================
# filter_context (full pipeline) tests
# ============================================================================


class TestFilterContext:
    def test_native_runtime_bypasses_filtering(self):
        """Native runtime models skip all filtering regardless of scopes."""
        messages = [{"role": "system", "content": SECURITY_CONTENT}]
        scopes = {"context_access": {"security": "none"}}
        result = filter_context(messages, scopes, is_native_runtime=True)
        assert result[0]["content"] == SECURITY_CONTENT

    def test_all_full_no_filtering(self):
        messages = [{"role": "system", "content": MIXED_CONTENT}]
        result = filter_context(messages, {"context_access": DEFAULT_CONTEXT_ACCESS})
        assert result[0]["content"] == MIXED_CONTENT

    def test_missing_context_access_defaults_to_full(self):
        """Backward compat: no context_access → all-full → no filtering."""
        messages = [{"role": "system", "content": SECURITY_CONTENT}]
        result = filter_context(messages, {"data_access": "none"})
        assert result[0]["content"] == SECURITY_CONTENT

    def test_none_trust_scopes_defaults_to_full(self):
        messages = [{"role": "system", "content": SECURITY_CONTENT}]
        result = filter_context(messages, None)
        assert result[0]["content"] == SECURITY_CONTENT

    def test_does_not_mutate_original(self):
        original = [{"role": "system", "content": SECURITY_CONTENT}]
        original_content = original[0]["content"]
        scopes = {"context_access": {"security": "none"}}
        filter_context(original, scopes)
        assert original[0]["content"] == original_content

    def test_filters_multiple_messages(self):
        messages = [
            {"role": "system", "content": SECURITY_CONTENT},
            {"role": "user", "content": "What vulnerabilities exist?"},
            {"role": "assistant", "content": "The CVE-2024-12345 is critical."},
        ]
        scopes = {"context_access": {"security": "none"}}
        result = filter_context(messages, scopes)
        assert "CVE-2024-12345" not in result[0]["content"]
        assert "CVE-2024-12345" not in result[2]["content"]

    def test_non_string_content_passes_through(self):
        """Messages with non-string content (e.g., tool results) pass unchanged."""
        messages = [{"role": "tool", "content": 42}]
        scopes = {"context_access": {"security": "none"}}
        result = filter_context(messages, scopes)
        assert result[0]["content"] == 42

    def test_deep_research_model_scopes(self):
        """Verify deep-research-pro model gets minimal context."""
        scopes = {
            "context_access": {
                "architecture": "summary",
                "business_logic": "none",
                "security": "none",
                "lore": "summary",
            }
        }
        messages = [{"role": "system", "content": MIXED_CONTENT}]
        result = filter_context(messages, scopes)
        content = result[0]["content"]
        # Code blocks should be filtered
        assert "def calculate_cost_micro" not in content
        # Security content should be stripped
        assert "CVE-2024-12345" not in content

    def test_gpt_reviewer_scopes(self):
        """Verify GPT-5.2 reviewer sees architecture + lore, not security."""
        scopes = {
            "context_access": {
                "architecture": "full",
                "business_logic": "redacted",
                "security": "none",
                "lore": "full",
            }
        }
        messages = [{"role": "system", "content": MIXED_CONTENT}]
        result = filter_context(messages, scopes)
        content = result[0]["content"]
        assert "Software Design Document" in content
        assert "CVE-2024-12345" not in content


# ============================================================================
# BB-602: Tests for audit_filter_context, lookup_trust_scopes, and cache
# ============================================================================


class TestArchitectureSummaryConstant:
    """BB-505: Verify constant is extracted and accessible."""

    def test_constant_exists(self):
        assert ARCHITECTURE_SUMMARY_MAX_CHARS == 500

    def test_constant_is_integer(self):
        assert isinstance(ARCHITECTURE_SUMMARY_MAX_CHARS, int)


class TestLookupTrustScopes:
    """BB-602: Verify trust scopes lookup from model-permissions.yaml."""

    def test_lookup_known_model(self):
        """claude-code:session should return trust_scopes dict."""
        scopes = lookup_trust_scopes("claude-code", "session")
        # Should return a dict (model exists in permissions)
        assert scopes is not None
        assert isinstance(scopes, dict)
        assert "data_access" in scopes

    def test_lookup_unknown_model(self):
        """Unknown model should return None."""
        scopes = lookup_trust_scopes("nonexistent", "fake-model")
        assert scopes is None

    def test_lookup_google_model(self):
        """Google model should have trust_scopes."""
        scopes = lookup_trust_scopes("google", "gemini-3-pro")
        assert scopes is not None
        assert scopes.get("data_access") == "none"

    def test_lookup_returns_context_access(self):
        """Models with context_access should include it in scopes."""
        scopes = lookup_trust_scopes("openai", "gpt-5.2")
        if scopes and "context_access" in scopes:
            ctx = scopes["context_access"]
            assert isinstance(ctx, dict)


class TestInvalidatePermissionsCache:
    """BB-601: Verify cache invalidation works."""

    def test_invalidate_and_reload(self):
        """Cache should reload after invalidation."""
        # First lookup populates cache
        scopes1 = lookup_trust_scopes("claude-code", "session")
        # Invalidate
        invalidate_permissions_cache()
        # Second lookup should reload (same result since file unchanged)
        scopes2 = lookup_trust_scopes("claude-code", "session")
        assert scopes1 == scopes2

    def test_invalidate_resets_state(self):
        """After invalidation, a fresh load should succeed."""
        invalidate_permissions_cache()
        scopes = lookup_trust_scopes("claude-code", "session")
        assert scopes is not None


class TestAuditFilterContext:
    """BB-602: Verify audit mode returns original messages unchanged."""

    def test_audit_returns_original_messages(self):
        """Audit mode must return original messages unmodified."""
        messages = [
            {"role": "system", "content": MIXED_CONTENT},
            {"role": "user", "content": "What is the architecture?"},
        ]
        # Use scopes that would trigger filtering
        result = audit_filter_context(
            messages, "openai", "gpt-5.2", is_native_runtime=False
        )
        # Result should be the exact same list object (audit = no modification)
        assert result is messages

    def test_audit_skips_native_runtime(self):
        """Native runtime should be skipped in audit mode too."""
        messages = [{"role": "user", "content": "test"}]
        result = audit_filter_context(
            messages, "claude-code", "session", is_native_runtime=True
        )
        assert result is messages

    def test_audit_with_all_full_scopes(self):
        """Models with all-full context_access should pass through."""
        messages = [{"role": "user", "content": MIXED_CONTENT}]
        result = audit_filter_context(
            messages, "claude-code", "session", is_native_runtime=False
        )
        # claude-code:session has all-full context_access, so no filtering
        assert result is messages

    def test_audit_with_unknown_model(self):
        """Unknown models default to all-full (no filtering)."""
        messages = [{"role": "user", "content": "test"}]
        result = audit_filter_context(
            messages, "unknown", "model", is_native_runtime=False
        )
        assert result is messages
