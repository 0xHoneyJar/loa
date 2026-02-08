export type ReviewEvent = "COMMENT" | "REQUEST_CHANGES";

export interface PostReviewInput {
  owner: string;
  repo: string;
  prNumber: number;
  headSha: string;
  body: string;
  event: ReviewEvent;
}

export interface IReviewPoster {
  postReview(input: PostReviewInput): Promise<boolean>;
  hasExistingReview(
    owner: string,
    repo: string,
    prNumber: number,
    headSha: string,
  ): Promise<boolean>;
}
