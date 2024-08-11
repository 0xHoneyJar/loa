"use server";

import {
  getQuestsQuery,
  getRafflesQuery,
} from "@/queries/queries";
import { unstable_cache } from "next/cache";

export async function getRaffles() {
  return unstable_cache(
    async () => {
      return getRafflesQuery();
    },
    ["raffles"],
    {
      tags: ["raffles"],
      revalidate: 3600,
    },
  )();
}

export async function getQuests() {
  return unstable_cache(
    async () => {
      return getQuestsQuery();
    },
    ["quests"],
    {
      tags: ["quests"],
      revalidate: 3600,
    },
  )();
}

// export async function getQuest(slug: string) {
//   return unstable_cache(
//     async () => {
//       return getQuestQuery(slug);
//     },
//     ["quest", slug],
//     {
//       tags: ["quest", `quest_${slug}`],
//       revalidate: 180,
//     },
//   )();
// }

// export async function getCompletedQuests(address: string) {
//   return unstable_cache(
//     async () => {
//       return getCompletedQuestsQuery(address);
//     },
//     ["completedQuests", address],
//     {
//       tags: [`completed_quests_${address}`],
//       revalidate: 180,
//     },
//   )();
// }

// export async function getDripClaimData(address: string) {
//   return unstable_cache(
//     async () => {
//       return getDripClaimDataQuery(address);
//     },
//     ["dripClaimData", address],
//     {
//       tags: [`drip_claim_data_${address}`],
//       revalidate: 180,
//     },
//   )();
// }

// export async function getBadgesMigrationClaims(address: string) {
//   return unstable_cache(
//     async () => {
//       return getBadgesMigrationClaimsQuery(address);
//     },
//     ["badgesMigrationClaims", address],
//     {
//       tags: [`badges_migration_claims_${address}`],
//       revalidate: 3600,
//     },
//   )();
// }

// export async function getBadgesClaims(address: string) {
//   return unstable_cache(
//     async () => {
//       return getBadgesClaimsQuery(address);
//     },
//     ["badgesClaimData", address],
//     {
//       tags: [`badges_claim_data_${address}`],
//       revalidate: 180,
//     },
//   )();
// }
