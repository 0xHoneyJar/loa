import { appendFile } from "node:fs/promises";

/**
 * 8 structural depth elements for Bridgebuilder review quality assessment.
 * Each element represents a dimension of review depth beyond basic code analysis.
 */
export interface DepthElements {
  /** FAANG/industry system parallels (e.g., "Netflix's Zuul", "Google's Borg") */
  faangParallel: boolean;
  /** Metaphors or analogies that illuminate concepts */
  metaphor: boolean;
  /** Teachable moments extending beyond the specific fix */
  teachableMoment: boolean;
  /** Technical history or evolution context */
  techHistory: boolean;
  /** Revenue, business, or organizational impact analysis */
  businessImpact: boolean;
  /** Social or team dynamics implications */
  socialDynamics: boolean;
  /** Cross-repository pattern connections */
  crossRepoConnection: boolean;
  /** Frame-questioning or reframing of the problem */
  frameQuestion: boolean;
}

export interface DepthResult {
  elements: DepthElements;
  score: number;
  total: number;
  passed: boolean;
  minThreshold: number;
}

export interface DepthCheckerConfig {
  minElements?: number;
  logPath?: string;
}

/** Pattern matchers for each depth element. */
const ELEMENT_PATTERNS: Record<keyof DepthElements, RegExp[]> = {
  faangParallel: [
    /\b(?:google|facebook|meta|amazon|netflix|apple|microsoft|uber|airbnb|twitter|linkedin|stripe|spotify)\b.*?\b(?:system|architecture|pattern|approach|practice|design|service|framework|protocol|paper)\b/i,
    /\b(?:borg|omega|spanner|bigtable|dynamo|kafka|cassandra|mapreduce|dremel|pregel|zuul|eureka|hystrix|kubernetes|thrift|grpc)\b/i,
    /\bfaang\b/i,
    /\bscale\s+at\b.*?\b(?:google|meta|netflix|amazon)\b/i,
  ],
  metaphor: [
    /\b(?:like|similar\s+to|analogous|think\s+of\s+(?:it\s+as|this\s+as)|imagine|picture|akin\s+to|reminiscent\s+of|just\s+as)\b/i,
    /\b(?:metaphor|analogy|parallel)\b/i,
    /\bthe\s+\w+\s+is\s+(?:a|an|the|like)\s+\w+\s+(?:of|for|in)\b/i,
  ],
  teachableMoment: [
    /\b(?:lesson|takeaway|broader\s+principle|beyond\s+this|in\s+general|worth\s+noting|important\s+because|the\s+deeper\s+issue)\b/i,
    /\b(?:teachable|learning|pattern\s+here|this\s+illustrates|worth\s+remembering)\b/i,
    /\bwhen(?:ever)?\s+you\s+(?:see|encounter|face|find)\b/i,
  ],
  techHistory: [
    /\b(?:historically|evolution|originated|evolved|invented|pioneered|legacy|traditional|introduced\s+in|dates?\s+back|since\s+\d{4})\b/i,
    /\b(?:first\s+proposed|originally\s+designed|classic|seminal|foundational)\b/i,
    /\bversion\s+\d+.*?(?:introduced|added|changed|deprecated)\b/i,
  ],
  businessImpact: [
    /\b(?:revenue|cost|roi|ttm|time\s+to\s+market|business\s+value|customer|user\s+experience|conversion|retention|churn|outage|downtime|sla|incident)\b/i,
    /\$\d+[kmbt]?\b/i,
    /\b(?:million|billion)\s+(?:users|requests|transactions|dollars)\b/i,
  ],
  socialDynamics: [
    /\b(?:team|cognitive\s+load|onboarding|knowledge\s+transfer|bus\s+factor|tribal\s+knowledge|code\s+ownership|collaboration|handoff|review\s+burden)\b/i,
    /\b(?:conway'?s?\s+law|organizational|cross-functional|silos?)\b/i,
    /\b(?:developer\s+experience|dx|ergonomic|friction)\b/i,
  ],
  crossRepoConnection: [
    /\b(?:cross-repo|cross-repository|related\s+(?:repo|repository)|upstream|downstream|dependency\s+graph)\b/i,
    /\b(?:this\s+pattern\s+(?:also|similarly)\s+(?:appears|exists)\s+in|seen\s+this\s+in|in\s+the\s+\w+\s+repo)\b/i,
    /\b(?:ecosystem|monorepo|shared\s+library|common\s+pattern\s+across)\b/i,
  ],
  frameQuestion: [
    /\b(?:but\s+should\s+we|is\s+this\s+the\s+right|worth\s+asking|stepping\s+back|the\s+real\s+question|reframe|reconsider)\b/i,
    /\b(?:permission\s+to\s+question|question\s+the\s+(?:question|premise|framing|assumption))\b/i,
    /\b(?:what\s+if\s+(?:instead|we|the)|alternative\s+framing|counterpoint)\b/i,
  ],
};

/**
 * Check structural depth of a review against the 8-element checklist.
 */
export function checkDepth(
  reviewContent: string,
  config?: DepthCheckerConfig,
): DepthResult {
  const minThreshold = config?.minElements ?? 5;

  const elements: DepthElements = {
    faangParallel: false,
    metaphor: false,
    teachableMoment: false,
    techHistory: false,
    businessImpact: false,
    socialDynamics: false,
    crossRepoConnection: false,
    frameQuestion: false,
  };

  for (const [key, patterns] of Object.entries(ELEMENT_PATTERNS)) {
    elements[key as keyof DepthElements] = patterns.some((p) => p.test(reviewContent));
  }

  const score = Object.values(elements).filter(Boolean).length;
  const total = 8;
  const passed = score >= minThreshold;

  return { elements, score, total, passed, minThreshold };
}

/**
 * Log a depth check result as a JSONL entry.
 */
export async function logDepthResult(
  result: DepthResult,
  meta: { runId: string; model: string; provider?: string },
  logPath?: string,
): Promise<void> {
  const path = logPath ?? "grimoires/loa/a2a/depth-checks.jsonl";
  const entry = {
    timestamp: new Date().toISOString(),
    runId: meta.runId,
    model: meta.model,
    provider: meta.provider,
    score: result.score,
    total: result.total,
    passed: result.passed,
    minThreshold: result.minThreshold,
    elements: result.elements,
  };

  try {
    await appendFile(path, JSON.stringify(entry) + "\n");
  } catch {
    // Log path may not exist yet — non-fatal
  }
}
