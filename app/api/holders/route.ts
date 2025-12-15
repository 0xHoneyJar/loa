import { NextRequest, NextResponse } from "next/server";
import { GRAPHQL_HC_ENDPOINT } from "@/constants/api";

export async function GET(req: NextRequest) {
  // Add cache-control headers
  const headers = {
    "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
    Pragma: "no-cache",
    Expires: "0",
  };

  try {
    // Paginate through all UserBalance records with generation=0 (Honeycomb)
    // and balanceTotal > 0 to count unique holders
    let allIds: string[] = [];
    let offset = 0;
    const limit = 1000;
    let hasMore = true;

    while (hasMore) {
      const response = await fetch(GRAPHQL_HC_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          query: `
            query GetHoneycombHolders($limit: Int!, $offset: Int!) {
              UserBalance(
                where: { generation: { _eq: 0 }, balanceTotal: { _gt: 0 } }
                limit: $limit
                offset: $offset
              ) {
                id
              }
            }
          `,
          variables: { limit, offset },
        }),
      });

      const result = await response.json();
      const batch = result.data?.UserBalance ?? [];

      allIds = allIds.concat(batch.map((u: { id: string }) => u.id));

      if (batch.length < limit) {
        hasMore = false;
      } else {
        offset += limit;
      }
    }

    return NextResponse.json(
      {
        uniqueHolders: allIds.length,
      },
      { headers },
    );
  } catch (error) {
    console.error("GraphQL query error:", error);
    return new NextResponse(
      JSON.stringify({ error: "Failed to fetch holders data" }),
      { status: 500, headers },
    );
  }
}
