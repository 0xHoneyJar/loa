import { supabase } from "@/lib/supabase";
import { NextRequest, NextResponse } from "next/server";
import { questQuerySchema } from "@/lib/zod/quests";

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

  const { count } = await supabase
    .from("quest_progress")
    .select("*", { count: "exact", head: true })
    .eq("quest_name", activeData.title);

  numParticipants = count ?? 0;

  return NextResponse.json({
    numParticipants,
  });
}
