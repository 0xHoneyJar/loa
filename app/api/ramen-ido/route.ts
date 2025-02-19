import { NextRequest, NextResponse } from "next/server";
import { unstable_noStore } from "next/cache";

export async function GET(req: NextRequest) {
  unstable_noStore();
  try {
    const response = await fetch(
      "https://api.ramen.finance/v1/featured-projects",
    );

    if (!response.ok) {
      throw new Error("Error status");
    }

    const data = await response.json();

    if (data.status !== "OK") {
      throw new Error("Error status");
    }
    return NextResponse.json({
      projects: data.data.projects ?? [],
    });
  } catch (error) {
    console.error("Error retrieving projects:", error);
    return NextResponse.json(
      { error: "Failed to retrieve projects" },
      { status: 500 },
    );
  }
}
