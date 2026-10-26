"""Put evals/analysis on sys.path so `from c132 import …` resolves from any cwd."""
import os
import sys

ANALYSIS_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if ANALYSIS_DIR not in sys.path:
    sys.path.insert(0, ANALYSIS_DIR)
FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
