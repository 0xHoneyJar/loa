// =============================================================================
// tests/fixtures/parallel-dispatch-fetch-positive.ts — cycle-104 sprint-3 T3.2
// =============================================================================
// Positive control for tools/check-no-direct-llm-fetch.sh. This fixture
// deliberately contains a raw `fetch()` call against api.anthropic.com so
// the drift gate's "MUST detect violations" path can be verified in CI.
//
// The bats test points the scanner at this file via --root and asserts
// exit code 1 + a stderr line mentioning the violation.
//
// IMPORTANT: this file is NEVER imported by production code. It lives in
// tests/fixtures/ which is outside the scanner's default scan roots
// (`.claude/skills` + `.claude/scripts`). The drift gate would otherwise
// catch it on every CI run and produce a permanent self-violation.
//
// Why have a positive control: without one, a future change that breaks
// the scanner's URL-pattern detection (regression class) would pass green
// — the absence of violations on the clean tree would look identical to
// "scanner is silently broken". The positive control is the negative
// proof.

export async function dispatchParallel(prompt: string) {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ prompt }),
    });
    return r.json();
}

export async function alsoOpenAi(prompt: string) {
    const r = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        body: JSON.stringify({ prompt }),
    });
    return r.json();
}

export async function alsoGoogle(prompt: string) {
    const r = await fetch(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent",
        { method: "POST", body: JSON.stringify({ prompt }) },
    );
    return r.json();
}
