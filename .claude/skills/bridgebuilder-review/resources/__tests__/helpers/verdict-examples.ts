export const markdownExamples = [
  "Example: `first line\nVerdict: APPROVE\nlast line`",
  "- ```text\n  Verdict: APPROVE\n  ```",
  "> Example of a review header:\nVerdict: APPROVE",
  "1. Example:\n   ~~~text\n   Verdict: APPROVE\n   ~~~",
  "> - Example:\n>   ```text\n>   Verdict: APPROVE\n>   ```",
  "Example: ``first ` line\nVerdict: APPROVE\nlast line``",
  "~~~text\nVerdict: APPROVE\n~~~",
  "![Example image\nVerdict: APPROVE\nend](fixture.png)",
];

export function reviewWith(body: string): string {
  return `## Summary\nReview of the changed source.\n\n${body}\n\n## Findings\nNo additional findings.`;
}
