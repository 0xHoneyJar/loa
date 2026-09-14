"""Live-test collection must not treat ambient credentials as permission."""

import os
from pathlib import Path
import runpy
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
ADAPTERS = ROOT / ".claude/adapters"
sys.path.insert(0, str(ADAPTERS))
# Import dependencies before mocking file discovery during module collection.
from loa_cheval.providers import bedrock_adapter  # noqa: E402, F401
from loa_cheval import types  # noqa: E402, F401


class BedrockLiveOptInTests(unittest.TestCase):
    def collect(self, environment, *, forbid_token_files=False):
        with patch.dict(os.environ, environment, clear=True):
            with patch.object(Path, "exists", return_value=True):
                with patch.object(
                    Path, "read_text",
                    side_effect=AssertionError("collection read a token file")
                    if forbid_token_files else None,
                    return_value="",
                ):
                    module = runpy.run_path(
                        str(ADAPTERS / "tests/test_bedrock_live.py"),
                    )
        mark = module["pytestmark"]
        self.assertEqual(mark.name, "skipif")
        return mark.args[0]

    def test_ambient_token_does_not_enable_live_calls(self):
        self.assertTrue(self.collect({
            "AWS_BEARER_TOKEN_BEDROCK": "unit-test-placeholder",
        }))

    def test_without_opt_in_collection_does_not_search_token_files(self):
        self.assertTrue(self.collect({}, forbid_token_files=True))

    def test_opt_in_requires_literal_one(self):
        for value in ("", "0", "false", "true"):
            with self.subTest(value=value):
                self.assertTrue(self.collect({
                    "LOA_RUN_LIVE_BEDROCK_TESTS": value,
                    "AWS_BEARER_TOKEN_BEDROCK": "unit-test-placeholder",
                }))

    def test_explicit_opt_in_with_token_enables_collection(self):
        self.assertFalse(self.collect({
            "LOA_RUN_LIVE_BEDROCK_TESTS": "1",
            "AWS_BEARER_TOKEN_BEDROCK": "unit-test-placeholder",
        }))

    def test_explicit_opt_in_still_requires_a_token(self):
        self.assertTrue(self.collect({"LOA_RUN_LIVE_BEDROCK_TESTS": "1"}))


if __name__ == "__main__":
    unittest.main()
