export interface Quest {
  title: string;
  startTime: number;
  endTime: number;
  image: string;
  disabled?: boolean | null;
  logo?: string[] | null;
  paused?: boolean;
  slug: string;
  reward: number[];
}
