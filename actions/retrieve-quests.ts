"use server";

import { Quest } from "@/constants/quest";
import { getQuests } from "@/queries/cached-queries";

export async function retrieveQuests() {
  let quests: Quest[] = [];
  quests = (await getQuests()) ?? [];

  quests?.sort((a: any, b: any) => b.endTime - a.endTime);
  return quests
}
