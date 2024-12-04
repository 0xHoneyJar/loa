import { NextRequest, NextResponse } from "next/server";
import { unstable_noStore } from "next/cache";

export async function GET(req: NextRequest) {
  unstable_noStore();
  try {
    const response = await fetch(
      "https://kingdomly.app/api/fetchPartnerMints",
      {
        method: "GET",
        headers: {
          "API-Key": `${process.env.KINGDOMLY_MINT_API_KEY}`,
          "Content-Type": "application/json",
        },
      },
    );
    if (response.status !== 200) {
      throw new Error("Error status");
    }
    const data = await response.json();

    return NextResponse.json({
      mints: data.partnerCollections,
    });
  } catch (error) {
    console.error("Error retrieving mints:", error);
    return NextResponse.json(
      { error: "Failed to retrieve mints" },
      { status: 500 },
    );
  }
}
