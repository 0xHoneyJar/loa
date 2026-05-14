# cycle-109 Sprint 4 T4.9 — repro fixtures

Reproduction fixtures pinning the bug shapes Sprint 4's chunking
substrate is designed to close:

  - **#866**: large-doc empty-content (>70KB FL input → cheval empty
    response). Pre-Sprint-4 the substrate had no chunking path, so
    oversized inputs preempted with CONTEXT_TOO_LARGE OR (worse) silently
    returned empty content. Post-Sprint-4 the pre-flight gate routes
    through the chunking package → finds findings.
  - **#823**: adversarial-review.sh claude-opus-4-7 empty-content at
    >40K reasoning-class input. Pre-Sprint-4: empty content. Post:
    streaming-with-recovery aborts the empty-content stream early with
    typed EmptyContent error (then upstream retry / chain-walk fires).

Each fixture is a JSON file documenting:

```json
{
  "issue": "#866",
  "input_size_chars": 75000,
  "estimated_input_tokens": 25000,
  "effective_input_ceiling": 40000,
  "should_chunk": true,
  "pre_sprint_4_behavior": "...",
  "post_sprint_4_behavior": "..."
}
```

The bats harness at `tests/unit/cycle-109-t4-9-repro-fixtures.bats`
exercises each fixture through the substrate (mock-mode for safety)
and asserts the pre/post comparison.
