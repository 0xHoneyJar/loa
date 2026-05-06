export interface AllowlistEntry {
    host: string;
    ports: number[];
}
export interface Allowlist {
    [providerId: string]: AllowlistEntry[];
}
export interface ValidationResult {
    valid: boolean;
    url: string;
    code?: string;
    detail?: string;
    scheme?: string;
    host?: string;
    port?: number;
    path?: string;
    matched_provider?: string;
}
export declare function loadAllowlist(raw: {
    providers?: Allowlist;
}): Allowlist;
export declare function validate(url: string, allowlist: Allowlist): ValidationResult;
//# sourceMappingURL=endpoint-validator.generated.d.ts.map