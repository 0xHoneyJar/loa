import { z } from "zod";

export const questQuerySchema = z.object({
  questName: z.string(),
});

export const raffleQuerySchema = z.object({
  raffleName: z.string(),
});