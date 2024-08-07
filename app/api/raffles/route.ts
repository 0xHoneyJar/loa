import { supabase } from "@/lib/supabase";
import { raffleQuerySchema } from "@/lib/zod/quests";
import { NextRequest, NextResponse } from "next/server";

export async function GET(req: NextRequest) {
  const { raffleName } = raffleQuerySchema.parse({
    raffleName: req.nextUrl.searchParams.get("raffleName"),
  });

  const { data: raffleData, error } = await supabase.rpc("get_total_tickets", {
    arg: raffleName,
  });

  if (error) {
    return NextResponse.json(
      {
        error: error.message,
      },
      { status: 500 },
    );
  }

  return NextResponse.json({
    numEntries: raffleData,
  });
}
