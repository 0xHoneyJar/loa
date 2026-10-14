export interface GeneratedModelEntry {
    provider: string;
    modelId: string;
    contextWindow: number;
    endpointFamily?: string;
    capabilities?: readonly string[];
    pricing?: {
        inputPerMtok: number;
        outputPerMtok: number;
    };
    /** cycle-126 FR-1.5: thinking_adaptive or thinking_traces in the yaml */
    reasoning: boolean;
}
export declare const GENERATED_MODEL_REGISTRY: Record<string, GeneratedModelEntry>;
export declare const GENERATED_REASONING: Record<string, boolean>;
//# sourceMappingURL=config.generated.d.ts.map