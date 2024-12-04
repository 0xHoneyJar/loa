import { supabase } from "@/lib/supabase";
import { NextRequest, NextResponse } from "next/server";
import { questQuerySchema } from "@/lib/zod/quests";
import { createApolloClient } from "@/lib/apollo";
import { gql } from "@apollo/client";

// Number of participants for a quest
export async function GET(req: NextRequest) {
  const { questName } = questQuerySchema.parse({
    questName: req.nextUrl.searchParams.get("questName"),
  });

  const { data: activeData } = await supabase
    .from("quests")
    .select("*")
    .eq("title", questName)
    .single();

  let numParticipants = 0;

  if (!activeData) {
    return NextResponse.json({
      numParticipants,
    });
  }

  const client = createApolloClient();

  const COUNT_QUERY = gql`
    query CountByQuestName($questName: String!) {
      countByQuestName(questName: $questName)
    }
  `;

  if (activeData.steps?.every((step: any) => step.type === "OnchainAction")) {
    try {
      const { data } = await client.query({
        query: COUNT_QUERY,
        variables: { questName: activeData.title },
      });

      numParticipants = data.countByQuestName;
    } catch (error) {
      console.error("Error fetching onchain quest count:", error);
    }
  } else {
    const { count } = await supabase
      .from("quest_progress")
      .select("*", { count: "exact", head: true })
      .eq("quest_name", activeData.title);
    numParticipants = count ?? 0;
  }

  return NextResponse.json({
    numParticipants,
  });
}
