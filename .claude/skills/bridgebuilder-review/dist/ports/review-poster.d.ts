export type ReviewEvent = "COMMENT" | "REQUEST_CHANGES";
/** bug-1004: which dedup marker the posted body is stamped with.
 * "review" (default) is the genuine reviewed-marker; "skip" stamps a
 * distinct marker so a skip notice never claims the sha as reviewed. */
export type ReviewMarkerKind = "review" | "skip";
export interface PostReviewInput {
    owner: string;
    repo: string;
    prNumber: number;
    headSha: string;
    body: string;
    event: ReviewEvent;
    markerKind?: ReviewMarkerKind;
}
export interface PostCommentInput {
    owner: string;
    repo: string;
    prNumber: number;
    body: string;
}
export interface IReviewPoster {
    postReview(input: PostReviewInput): Promise<boolean>;
    hasExistingReview(owner: string, repo: string, prNumber: number, headSha: string, markerKind?: ReviewMarkerKind): Promise<boolean>;
    /** Post an issue comment (not a review). Used for multi-model per-model comments and consensus summary. */
    postComment?(input: PostCommentInput): Promise<boolean>;
}
//# sourceMappingURL=review-poster.d.ts.map