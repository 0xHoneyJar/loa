import { NextRequest, NextResponse } from "next/server";
import { gql } from "@apollo/client";
import { createApolloClientHC } from "@/lib/apollo";

const client = createApolloClientHC();

export async function GET(req: NextRequest) {
  // Add cache-control headers
  const headers = {
    "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
    Pragma: "no-cache",
    Expires: "0",
  };

  // Query unique Honeycomb holders from envio indexer
  // UserBalance with generation=0 represents Honeycomb holders
  // balanceTotal > 0 ensures we only count current holders
  const query = gql`
    query GetUniqueHoneycombHolders {
      UserBalance_aggregate(
        where: { generation: { _eq: 0 }, balanceTotal: { _gt: 0 } }
      ) {
        aggregate {
          count
        }
      }
    }
  `;

  try {
    const { data } = await client.query({
      query,
      fetchPolicy: "network-only",
      context: {
        fetchOptions: {
          next: { revalidate: 0 },
        },
      },
    });

    const uniqueHolders = data.UserBalance_aggregate?.aggregate?.count ?? 0;

    return NextResponse.json(
      {
        uniqueHolders,
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
