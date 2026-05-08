"""Pytest conftest for tests/red-team/jailbreak/.

The path contains a dash (`red-team`), which is not a valid Python module
identifier. We inject the `lib/` dir onto sys.path so `corpus_loader`
imports as a top-level module from any test file.
"""

import sys
from pathlib import Path

_LIB_DIR = Path(__file__).resolve().parent / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))
