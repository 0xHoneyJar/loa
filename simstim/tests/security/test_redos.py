"""Security tests for SIMSTIM-004: ReDoS Vulnerability.

Tests verify that:
- Regex patterns complete in O(n) time
- Input length limits are enforced
- Long malicious inputs don't cause hangs
"""

import time
import pytest
from simstim.bridge.stdout_parser import (
    StdoutParser,
    ActionType,
    PERMISSION_PATTERNS,
    MAX_PATTERN_INPUT_LENGTH,
)


class TestRegexPerformance:
    """Test regex patterns complete quickly."""

    @pytest.fixture
    def parser(self):
        return StdoutParser()

    def test_patterns_complete_quickly_with_normal_input(self, parser):
        """Test normal inputs match quickly."""
        normal_inputs = [
            'Create file `src/main.py`?',
            'Edit file "/path/to/file.ts"?',
            'Run `npm install`?',
            'Delete files in tests/?',
            'Use MCP tool `github`',
        ]

        for line in normal_inputs:
            start = time.monotonic()
            parser.parse_permission(line)
            elapsed = time.monotonic() - start
            assert elapsed < 0.01, f"Pattern took too long: {elapsed}s for {line}"

    def test_long_input_doesnt_hang(self, parser):
        """Test that very long inputs don't cause hangs."""
        # Create input that could cause ReDoS with vulnerable patterns
        long_input = "Create file `" + "a" * 10000 + "`?"

        start = time.monotonic()
        result = parser.parse_permission(long_input)
        elapsed = time.monotonic() - start

        # Should complete in under 100ms even with long input
        assert elapsed < 0.1, f"Long input caused slow matching: {elapsed}s"

    def test_nested_quotes_dont_cause_backtracking(self, parser):
        """Test nested quotes don't cause catastrophic backtracking."""
        # Pattern that could cause backtracking with .+?
        tricky_input = 'Edit file `' + '`a`' * 100 + '`?'

        start = time.monotonic()
        parser.parse_permission(tricky_input)
        elapsed = time.monotonic() - start

        assert elapsed < 0.1, f"Nested quotes caused slow matching: {elapsed}s"

    def test_repeated_special_chars_safe(self, parser):
        """Test repeated special characters don't cause issues."""
        special_inputs = [
            "Create file " + "?" * 1000,  # Repeated question marks
            "Edit file " + "`" * 1000 + "?",  # Repeated backticks
            "Run " + "'" * 1000 + "?",  # Repeated quotes
        ]

        for line in special_inputs:
            start = time.monotonic()
            parser.parse_permission(line)
            elapsed = time.monotonic() - start
            assert elapsed < 0.1, f"Special chars caused slow matching: {elapsed}s"


class TestInputLengthLimit:
    """Test input length limiting."""

    @pytest.fixture
    def parser(self):
        return StdoutParser()

    def test_max_length_constant_defined(self):
        """Test MAX_PATTERN_INPUT_LENGTH is defined."""
        assert MAX_PATTERN_INPUT_LENGTH > 0
        assert MAX_PATTERN_INPUT_LENGTH <= 10000

    def test_long_input_truncated(self, parser):
        """Test that inputs over max length are truncated."""
        # Create input much longer than limit
        long_input = "Run `" + "x" * (MAX_PATTERN_INPUT_LENGTH * 2) + "`?"

        # Should still work (truncated internally)
        start = time.monotonic()
        result = parser.parse_permission(long_input)
        elapsed = time.monotonic() - start

        assert elapsed < 0.1

    def test_parse_phase_also_limited(self, parser):
        """Test parse_phase also has length limiting."""
        long_input = "Starting /implement " + "sprint-" + "1" * 10000

        start = time.monotonic()
        parser.parse_phase(long_input)
        elapsed = time.monotonic() - start

        assert elapsed < 0.1


class TestPatternCorrectness:
    """Test patterns still match correctly after O(n) rewrite."""

    @pytest.fixture
    def parser(self):
        return StdoutParser()

    @pytest.mark.parametrize("line,expected_action,expected_target", [
        ("Create file `src/main.py`?", ActionType.FILE_CREATE, "src/main.py"),
        ('Create files in "/home/user/project"?', ActionType.FILE_CREATE, "/home/user/project"),
        ("Write file `output.txt`?", ActionType.FILE_CREATE, "output.txt"),
        ("Edit file `config.json`?", ActionType.FILE_EDIT, "config.json"),
        ('Modify file "/etc/hosts"?', ActionType.FILE_EDIT, "/etc/hosts"),
        ("Update file 'package.json'?", ActionType.FILE_EDIT, "package.json"),
        ("Delete file `temp.txt`?", ActionType.FILE_DELETE, "temp.txt"),
        ("Remove files in `/tmp`?", ActionType.FILE_DELETE, "/tmp"),
        ("Run `npm install`?", ActionType.BASH_EXECUTE, "npm install"),
        ("Execute `git push`?", ActionType.BASH_EXECUTE, "git push"),
        ("Use MCP tool `github`", ActionType.MCP_TOOL, "github"),
        ("Call MCP tool 'linear'", ActionType.MCP_TOOL, "linear"),
    ])
    def test_patterns_match_correctly(self, parser, line, expected_action, expected_target):
        """Test patterns still match valid inputs correctly."""
        result = parser.parse_permission(line)

        assert result is not None, f"Failed to match: {line}"
        assert result.action == expected_action, f"Wrong action for: {line}"
        assert result.target == expected_target, f"Wrong target for: {line}"

    def test_non_matching_input_returns_none(self, parser):
        """Test non-matching inputs return None."""
        non_matches = [
            "Just some text",
            "Thinking about creating a file",
            "File created successfully",
            "Command completed",
        ]

        for line in non_matches:
            result = parser.parse_permission(line)
            assert result is None, f"Should not match: {line}"


class TestPhasePatternPerformance:
    """Test phase transition patterns are also safe."""

    @pytest.fixture
    def parser(self):
        return StdoutParser()

    def test_phase_patterns_fast(self, parser):
        """Test phase patterns complete quickly."""
        inputs = [
            "Starting /plan-and-analyze",
            "Starting /implement sprint-1",
            "Starting /review-sprint sprint-5",
            "Starting /deploy",
        ]

        for line in inputs:
            start = time.monotonic()
            parser.parse_phase(line)
            elapsed = time.monotonic() - start
            assert elapsed < 0.01

    def test_phase_patterns_with_long_suffix(self, parser):
        """Test phase patterns with long trailing text."""
        long_input = "Starting /implement sprint-1 " + "extra text " * 500

        start = time.monotonic()
        parser.parse_phase(long_input)
        elapsed = time.monotonic() - start

        assert elapsed < 0.1
