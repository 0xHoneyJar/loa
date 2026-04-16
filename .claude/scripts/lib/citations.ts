export interface CitationPair {
  filePath: string;
  lineNumber: number;
}

const CITATION_REGEX = /\[([^\]]+)\]\((~\/[^\s)]+:\d+)\)/g;

export function extractCitations(markdownContent: string): Set<string> {
  const result = new Set<string>();
  const regex = new RegExp(CITATION_REGEX.source, "g");
  let m: RegExpExecArray | null;
  while ((m = regex.exec(markdownContent)) !== null) {
    result.add(m[2]);
  }
  return result;
}

export function parseCitationKey(key: string): CitationPair {
  const lastColon = key.lastIndexOf(":");
  const filePath = key.slice(0, lastColon);
  const lineNumber = parseInt(key.slice(lastColon + 1), 10);
  return { filePath, lineNumber };
}
