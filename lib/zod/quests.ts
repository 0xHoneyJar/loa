import { z } from "zod";

export const questQuerySchema = z.object({
  questName: z.string(),
});
