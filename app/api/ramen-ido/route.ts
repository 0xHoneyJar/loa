import { NextRequest, NextResponse } from "next/server";

export async function GET(req: NextRequest) {
  try {
    const response = await fetch(
      "https://launchpad-staging-wor6ijn2wa-uc.a.run.app/v1/featured-projects",
    );

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
