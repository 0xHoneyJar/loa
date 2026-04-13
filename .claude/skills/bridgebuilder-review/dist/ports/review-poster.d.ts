export type ReviewEvent = "COMMENT" | "REQUEST_CHANGES";
export interface PostReviewInput {
    owner: string;
    repo: string;
    prNumber: number;
    headSha: string;
    body: string;
    event: ReviewEvent;
}
export interface PostCommentInput {
    owner: string;
    repo: string;
    prNumber: number;
    body: string;
}
export interface IReviewPoster {
    postReview(input: PostReviewInput): Promise<boolean>;
    hasExistingReview(owner: string, repo: string, prNumber: number, headSha: string): Promise<boolean>;
    /** Post an issue comment (not a review). Used for multi-model per-model comments and consensus summary. */
    postComment?(input: PostCommentInput): Promise<boolean>;
}
//# sourceMappingURL=review-poster.d.ts.map