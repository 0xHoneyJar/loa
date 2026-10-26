#!/usr/bin/env python3
"""reads-c132.py — CLI wrapper for c132.reads (usage, modes and exit codes: reads.py header).

Run as `python3 -I evals/analysis/c132/reads-c132.py …`: -I keeps the cwd and the run
directories off sys.path; the package directory is added explicitly from this file's path.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from c132 import reads  # noqa: E402

if __name__ == "__main__":
    sys.exit(reads.main())
