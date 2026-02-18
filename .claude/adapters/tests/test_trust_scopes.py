"""Trust scopes validation tests (Sprint 7, Task 7.1; updated Sprint 9).

Validates that model-permissions.yaml:
- Parses all 7 trust_scopes dimensions for every model entry
- Contains expected scope values for each model
- Enforces schema validity (no unknown dimensions, no invalid values)
- Preserves backward-compatible trust_level field
- Validates context_access epistemic dimension (v7.0.0, Sprint 9)

Bridgebuilder Review Part II: "governance without enforcement is poetry."
These tests enforce the Ostrom Principle #1 mapping — every registered
provider must have clearly defined trust boundaries.
"""

from __future__ import annotations

import os
import unittest
from pathlib import Path
from typing import Any, Dict

import yaml

# Path to model-permissions.yaml (relative to repo root)
REPO_ROOT = Path(__file__).resolve().parents[3]
PERMISSIONS_PATH = REPO_ROOT / ".claude" / "data" / "model-permissions.yaml"

# Valid trust_scopes dimensions — operational (Hounfour v6+)
VALID_DIMENSIONS = {
    "data_access",
    "financial",
    "delegation",
    "model_selection",
    "governance",
    "external_communication",
}

# Epistemic dimension (v7.0.0) — nested dict, not a string value
EPISTEMIC_DIMENSION = "context_access"

# All valid top-level keys in trust_scopes (operational + epistemic)
ALL_VALID_DIMENSIONS = VALID_DIMENSIONS | {EPISTEMIC_DIMENSION}

# Valid scope values for operational dimensions
VALID_VALUES = {"high", "medium", "low", "none", "limited"}

# Valid context_access sub-fields and values
VALID_CONTEXT_ACCESS_FIELDS = {"architecture", "business_logic", "security", "lore"}
VALID_CONTEXT_ACCESS_VALUES = {"full", "summary", "redacted", "none"}

# Valid trust_level values (backward-compat summary field)
VALID_TRUST_LEVELS = {"high", "medium", "low", "standard", "none"}


def _load_permissions() -> Dict[str, Any]:
    """Load model-permissions.yaml."""
    if not PERMISSIONS_PATH.exists():
        raise FileNotFoundError(f"model-permissions.yaml not found at {PERMISSIONS_PATH}")
    with open(PERMISSIONS_PATH, "r") as f:
        return yaml.safe_load(f)


class TestTrustScopesSchema(unittest.TestCase):
    """Validate trust_scopes schema across all model entries."""

    @classmethod
    def setUpClass(cls):
        cls.data = _load_permissions()
        cls.models = cls.data.get("model_permissions", {})

    def test_permissions_file_loads(self):
        """model-permissions.yaml loads without error."""
        self.assertIsInstance(self.models, dict)
        self.assertGreater(len(self.models), 0, "No model entries found")

    def test_all_models_have_trust_scopes(self):
        """Every model entry has trust_scopes defined (Ostrom #1: boundaries)."""
        for model_id, entry in self.models.items():
            with self.subTest(model=model_id):
                self.assertIn(
                    "trust_scopes",
                    entry,
                    f"Model '{model_id}' missing trust_scopes",
                )

    def test_all_models_have_all_6_dimensions(self):
        """Every trust_scopes has all 6 required dimensions."""
        for model_id, entry in self.models.items():
            scopes = entry.get("trust_scopes", {})
            with self.subTest(model=model_id):
                for dim in VALID_DIMENSIONS:
                    self.assertIn(
                        dim,
                        scopes,
                        f"Model '{model_id}' missing dimension '{dim}'",
                    )

    def test_no_unknown_dimensions(self):
        """No model has unknown trust_scopes dimensions."""
        for model_id, entry in self.models.items():
            scopes = entry.get("trust_scopes", {})
            with self.subTest(model=model_id):
                extra = set(scopes.keys()) - ALL_VALID_DIMENSIONS
                self.assertEqual(
                    extra,
                    set(),
                    f"Model '{model_id}' has unknown dimensions: {extra}",
                )

    def test_all_operational_values_valid(self):
        """All operational trust_scopes values are in the valid set."""
        for model_id, entry in self.models.items():
            scopes = entry.get("trust_scopes", {})
            with self.subTest(model=model_id):
                for dim, value in scopes.items():
                    if dim == EPISTEMIC_DIMENSION:
                        continue  # context_access is a nested dict, tested separately
                    self.assertIn(
                        value,
                        VALID_VALUES,
                        f"Model '{model_id}' dimension '{dim}' has invalid value '{value}'",
                    )

    def test_context_access_when_present(self):
        """If context_access exists, validate sub-fields and values."""
        for model_id, entry in self.models.items():
            scopes = entry.get("trust_scopes", {})
            ctx = scopes.get(EPISTEMIC_DIMENSION)
            if ctx is None:
                continue  # Optional — backward compat
            with self.subTest(model=model_id):
                self.assertIsInstance(ctx, dict, f"context_access must be dict for '{model_id}'")
                extra_fields = set(ctx.keys()) - VALID_CONTEXT_ACCESS_FIELDS
                self.assertEqual(
                    extra_fields,
                    set(),
                    f"Model '{model_id}' context_access has unknown fields: {extra_fields}",
                )
                for field, value in ctx.items():
                    self.assertIn(
                        value,
                        VALID_CONTEXT_ACCESS_VALUES,
                        f"Model '{model_id}' context_access.{field} has invalid value '{value}'",
                    )

    def test_backward_compat_trust_level_present(self):
        """Every model retains trust_level as backward-compatible summary."""
        for model_id, entry in self.models.items():
            with self.subTest(model=model_id):
                self.assertIn(
                    "trust_level",
                    entry,
                    f"Model '{model_id}' missing backward-compat trust_level",
                )
                self.assertIn(
                    entry["trust_level"],
                    VALID_TRUST_LEVELS,
                    f"Model '{model_id}' has invalid trust_level: {entry['trust_level']}",
                )


class TestClaudeCodeSessionScopes(unittest.TestCase):
    """Verify claude-code:session has expected high-privilege scopes."""

    @classmethod
    def setUpClass(cls):
        data = _load_permissions()
        cls.entry = data.get("model_permissions", {}).get("claude-code:session", {})

    def test_exists(self):
        self.assertTrue(self.entry, "claude-code:session entry missing")

    def test_data_access_high(self):
        self.assertEqual(self.entry["trust_scopes"]["data_access"], "high")

    def test_financial_high(self):
        self.assertEqual(self.entry["trust_scopes"]["financial"], "high")

    def test_delegation_high(self):
        self.assertEqual(self.entry["trust_scopes"]["delegation"], "high")

    def test_model_selection_high(self):
        self.assertEqual(self.entry["trust_scopes"]["model_selection"], "high")

    def test_governance_none(self):
        self.assertEqual(self.entry["trust_scopes"]["governance"], "none")

    def test_external_communication_high(self):
        self.assertEqual(self.entry["trust_scopes"]["external_communication"], "high")

    def test_execution_mode_native(self):
        self.assertEqual(self.entry.get("execution_mode"), "native_runtime")


class TestRemoteModelScopes(unittest.TestCase):
    """Verify remote models have appropriately restricted scopes."""

    @classmethod
    def setUpClass(cls):
        data = _load_permissions()
        cls.models = data.get("model_permissions", {})

    def test_openai_all_none(self):
        """openai:gpt-5.2 has all-none trust_scopes (read-only oracle)."""
        entry = self.models.get("openai:gpt-5.2", {})
        scopes = entry.get("trust_scopes", {})
        for dim in VALID_DIMENSIONS:
            with self.subTest(dimension=dim):
                self.assertEqual(scopes.get(dim), "none")

    def test_moonshot_all_none(self):
        """moonshot:kimi-k2-thinking has all-none scopes (analysis oracle)."""
        entry = self.models.get("moonshot:kimi-k2-thinking", {})
        scopes = entry.get("trust_scopes", {})
        for dim in VALID_DIMENSIONS:
            with self.subTest(dimension=dim):
                self.assertEqual(scopes.get(dim), "none")

    def test_qwen_medium_data_access(self):
        """qwen-local:qwen3-coder-next has medium data_access (sandboxed file access)."""
        entry = self.models.get("qwen-local:qwen3-coder-next", {})
        scopes = entry.get("trust_scopes", {})
        self.assertEqual(scopes.get("data_access"), "medium")
        # All other scopes should be none
        for dim in VALID_DIMENSIONS - {"data_access"}:
            with self.subTest(dimension=dim):
                self.assertEqual(scopes.get(dim), "none")

    def test_anthropic_all_none(self):
        """anthropic:claude-opus-4-6 has all-none scopes (remote model)."""
        entry = self.models.get("anthropic:claude-opus-4-6", {})
        scopes = entry.get("trust_scopes", {})
        for dim in VALID_DIMENSIONS:
            with self.subTest(dimension=dim):
                self.assertEqual(scopes.get(dim), "none")


class TestGoogleModelScopes(unittest.TestCase):
    """Verify Google model entries have correct scopes."""

    @classmethod
    def setUpClass(cls):
        data = _load_permissions()
        cls.models = data.get("model_permissions", {})

    def test_gemini_25_pro_all_none(self):
        entry = self.models.get("google:gemini-2.5-pro", {})
        scopes = entry.get("trust_scopes", {})
        for dim in VALID_DIMENSIONS:
            with self.subTest(dimension=dim):
                self.assertEqual(scopes.get(dim), "none")

    def test_gemini_3_pro_all_none(self):
        entry = self.models.get("google:gemini-3-pro", {})
        scopes = entry.get("trust_scopes", {})
        for dim in VALID_DIMENSIONS:
            with self.subTest(dimension=dim):
                self.assertEqual(scopes.get(dim), "none")

    def test_gemini_3_flash_all_none(self):
        entry = self.models.get("google:gemini-3-flash", {})
        scopes = entry.get("trust_scopes", {})
        for dim in VALID_DIMENSIONS:
            with self.subTest(dimension=dim):
                self.assertEqual(scopes.get(dim), "none")

    def test_deep_research_delegation_limited(self):
        """Deep Research has delegation: limited (autonomous web search)."""
        entry = self.models.get("google:deep-research-pro", {})
        scopes = entry.get("trust_scopes", {})
        self.assertEqual(scopes.get("delegation"), "limited")

    def test_deep_research_other_scopes_none(self):
        entry = self.models.get("google:deep-research-pro", {})
        scopes = entry.get("trust_scopes", {})
        for dim in VALID_DIMENSIONS - {"delegation"}:
            with self.subTest(dimension=dim):
                self.assertEqual(scopes.get(dim), "none")

    def test_google_models_all_remote(self):
        """All Google models are execution_mode: remote_model."""
        google_models = [k for k in self.models if k.startswith("google:")]
        self.assertGreater(len(google_models), 0, "No Google model entries found")
        for model_id in google_models:
            with self.subTest(model=model_id):
                self.assertEqual(
                    self.models[model_id].get("execution_mode"),
                    "remote_model",
                )


class TestModelCoverage(unittest.TestCase):
    """Ensure all model entries have complete coverage."""

    @classmethod
    def setUpClass(cls):
        data = _load_permissions()
        cls.models = data.get("model_permissions", {})

    def test_minimum_model_count(self):
        """At least 9 model entries exist (5 original + 4 Google)."""
        self.assertGreaterEqual(len(self.models), 9)

    def test_all_entries_have_execution_mode(self):
        for model_id, entry in self.models.items():
            with self.subTest(model=model_id):
                self.assertIn(
                    "execution_mode",
                    entry,
                    f"Model '{model_id}' missing execution_mode",
                )

    def test_all_entries_have_capabilities(self):
        for model_id, entry in self.models.items():
            with self.subTest(model=model_id):
                self.assertIn(
                    "capabilities",
                    entry,
                    f"Model '{model_id}' missing capabilities",
                )


if __name__ == "__main__":
    unittest.main()
