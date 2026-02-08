/** Patterns to redact from log output. */
const DEFAULT_REDACT_PATTERNS = [
    /gh[ps]_[A-Za-z0-9_]{36,}/g,
    /github_pat_[A-Za-z0-9_]{22,}/g,
    /sk-ant-[A-Za-z0-9-]{20,}/g,
    /sk-[A-Za-z0-9]{20,}/g,
    /AKIA[A-Z0-9]{16}/g,
    /xox[bprs]-[A-Za-z0-9-]{10,}/g,
];
function redact(value, patterns) {
    let result = value;
    for (const pattern of patterns) {
        result = result.replace(new RegExp(pattern.source, pattern.flags), "[REDACTED]");
    }
    return result;
}
function safeStringify(data, patterns) {
    if (!data)
        return "";
    const raw = JSON.stringify(data);
    return redact(raw, patterns);
}
export class ConsoleLogger {
    patterns;
    constructor(extraPatterns) {
        this.patterns = [...DEFAULT_REDACT_PATTERNS, ...(extraPatterns ?? [])];
    }
    info(message, data) {
        this.log("info", message, data);
    }
    warn(message, data) {
        this.log("warn", message, data);
    }
    error(message, data) {
        this.log("error", message, data);
    }
    debug(message, data) {
        this.log("debug", message, data);
    }
    log(level, message, data) {
        const entry = {
            level,
            message: redact(message, this.patterns),
            ...(data ? { data: JSON.parse(safeStringify(data, this.patterns)) } : {}),
            timestamp: new Date().toISOString(),
        };
        const out = level === "error" ? console.error : console.log;
        out(JSON.stringify(entry));
    }
}
//# sourceMappingURL=console-logger.js.map