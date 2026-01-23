"""Pytest configuration and fixtures for Simstim tests."""

import pytest

from simstim.bridge.stdout_parser import StdoutParser


@pytest.fixture
def parser() -> StdoutParser:
    """Create a fresh stdout parser for testing."""
    return StdoutParser()


@pytest.fixture
def parser_with_context() -> StdoutParser:
    """Create a parser with some context already loaded."""
    p = StdoutParser()
    p.add_line("Processing files...")
    p.add_line("Working on sprint-1 tasks")
    p.add_line("Creating component structure")
    return p
