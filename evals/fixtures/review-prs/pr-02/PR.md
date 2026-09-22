# refactor(audit,spiral,semver): drop strict-verify plumbing, backtick masking and prerelease branches

Removes the verify-for-merge strictness knobs from audit_envelope.py (single code path again), lets the spiral evidence gate scan prose without the backtick pre-pass, and returns semver-bump.sh to release-only version parsing.
