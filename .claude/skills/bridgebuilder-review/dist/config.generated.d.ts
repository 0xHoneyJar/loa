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
}
export declare const GENERATED_MODEL_REGISTRY: Record<string, GeneratedModelEntry>;
//# sourceMappingURL=config.generated.d.ts.map