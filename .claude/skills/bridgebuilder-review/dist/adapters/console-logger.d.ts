import type { ILogger } from "../ports/logger.js";
export declare class ConsoleLogger implements ILogger {
    private readonly patterns;
    constructor(extraPatterns?: RegExp[]);
    info(message: string, data?: Record<string, unknown>): void;
    warn(message: string, data?: Record<string, unknown>): void;
    error(message: string, data?: Record<string, unknown>): void;
    debug(message: string, data?: Record<string, unknown>): void;
    private log;
}
//# sourceMappingURL=console-logger.d.ts.map