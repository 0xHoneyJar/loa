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

  // Query to fetch data from both HoneyComb and HoneyCombBerachain contracts
  // Including contractBalances to get the actual wallet addresses
  const query = gql`
    query CombinedHoldersQuery {
      honeycombSnapshots: snapshots(
        limit: 1
        orderBy: blockNumber_DESC
        where: { contractType_eq: "HoneyComb" }
      ) {
        contractBalances
      }
      berachainSnapshots: snapshots(
        limit: 1
        orderBy: blockNumber_DESC
        where: { contractType_eq: "HoneyCombBerachain" }
      ) {
        contractBalances
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

    // Sets to store addresses for intersection calculation
    const ethAddresses = new Set<string>();
    const beraAddresses = new Set<string>();

    try {
      const balancesHoneycomb =
        typeof data.honeycombSnapshots[0].contractBalances === "string"
          ? JSON.parse(data.honeycombSnapshots[0].contractBalances)
          : data.honeycombSnapshots[0].contractBalances;

      if (balancesHoneycomb && typeof balancesHoneycomb === "object") {
        const addresses = Object.keys(balancesHoneycomb).map((addr) =>
          addr.toLowerCase(),
        );

        addresses.forEach((address: string) => {
          ethAddresses.add(address);
        });
      }
    } catch (e) {
      console.error(`Error parsing ETH contractBalances`, e);
    }

    try {
      const balancesBeraHoneycomb =
        typeof data.berachainSnapshots[0].contractBalances === "string"
          ? JSON.parse(data.berachainSnapshots[0].contractBalances)
          : data.berachainSnapshots[0].contractBalances;

      if (balancesBeraHoneycomb && typeof balancesBeraHoneycomb === "object") {
        const addresses = Object.keys(balancesBeraHoneycomb).map((addr) =>
          addr.toLowerCase(),
        );

        addresses.forEach((address: string) => {
          beraAddresses.add(address);
        });
      }
    } catch (e) {
      console.error(`Error parsing Bera contractBalances`, e);
    }

    // Combine all addresses into one set to count unique holders
    const allUniqueAddresses = new Set([
      ...Array.from(ethAddresses),
      ...Array.from(beraAddresses),
    ]);

    return NextResponse.json(
      {
        uniqueHolders: allUniqueAddresses.size,
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
