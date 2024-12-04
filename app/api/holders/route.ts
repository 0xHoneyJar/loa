import { NextRequest, NextResponse } from "next/server";
import { gql } from "@apollo/client";
import { createApolloClientHC } from "@/lib/apollo";

const client = createApolloClientHC();

export async function GET(req: NextRequest) {
  const query = gql`
    query MyQuery {
      snapshots(
        limit: 1
        orderBy: blockNumber_DESC
        where: { contractType_eq: "HoneyComb" }
      ) {
        uniqueHolders
      }
    }
  `;

  try {
    // Use Apollo Client to execute the query
    const { data } = await client.query({
      query,
    });

    return NextResponse.json({
      uniqueHolders: data.snapshots[0].uniqueHolders,
    });
  } catch (error) {
    console.error("GraphQL query error:", error);
    return new NextResponse(
      JSON.stringify({ error: "Failed to fetch holders data" }),
      { status: 500 },
    );
  }
}
