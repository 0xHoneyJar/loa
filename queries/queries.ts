import { supabase } from "@/lib/supabase";

export const getRafflesQuery = async () => {
  const { data, error } = await supabase
    .from("raffles")
    .select("*")
    .throwOnError();

  if (!data || error) {
    return [];
  }

  return data;
};

export const getQuestsQuery = async () => {
  const { data, error } = await supabase
    .from("quests")
    .select(
      "title,startTime,endTime,image,logo,disabled,paused,slug,reward,campaignName",
    )
    .throwOnError();

  if (!data || error) {
    return [];
  }

  const quests = data;

  const finalQuest = quests?.map((quest) => ({
    ...quest,
    logo: quest.logo ? quest.logo.split(",") : null,
    reward: quest.reward.split(",").map(Number),
  }));

  return finalQuest;
};

// export const getRaffleQuery = async (slug: string) => {
//   const { data } = await supabase
//     .from("raffles")
//     .select("*")
//     .eq("slug", slug)
//     .single();

//   return data ? convertRaffleFromDatabase(data) : null;
// };

// export const getQuestQuery = async (slug: string) => {
//   const { data } = await supabase
//     .from("quests")
//     .select("*")
//     .eq("slug", slug)
//     .single();

//   const activeData = data;

//   return {
//     quest: activeData ? convertQuestFromDatabase(activeData) : null,
//   };
// };
