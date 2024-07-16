"use server"

import { Raffle } from "@/constants/raffle";
import { getRaffles } from "@/queries/cached-queries";

export async function retrieveRaffles() {
  let raffles: Raffle[] = [];
  
  raffles = await getRaffles();
  raffles?.sort((a: any, b: any) => b.endTime - a.endTime);

  return raffles;
}
