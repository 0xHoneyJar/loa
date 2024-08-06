"use server";

import { Raffle } from "@/constants/raffle";
import { getRaffles } from "@/queries/cached-queries";

export async function retrieveRaffles() {
  let raffles: Raffle[] = [];

  raffles = await getRaffles();

  return raffles;
}
