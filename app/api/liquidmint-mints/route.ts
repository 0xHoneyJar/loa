import { NextRequest, NextResponse } from "next/server";
import { unstable_noStore } from "next/cache";

export async function GET(req: NextRequest) {
  unstable_noStore();
  try {
    const response = await fetch(
      "https://indexer.dev.hyperindex.xyz/c719922/v1/graphql",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          query: `
              query {
                    Token(where:{collection: {launchpad_id:{_neq: ""}}}, order_by:{createdTimestamp: desc, tokenId: desc}) {
                        collection {
                            name
                        }
                        tokenId
                        createdTimestamp
                    }
                }
            `,
          //   variables: {
          //     address: address.toLowerCase(),
          //     questName: "Bitget",
          //   },
        }),
      },
    );

    if (response.status !== 200) {
      throw new Error("Error with response");
    }

    const data = await response.json();

    console.log(data);

    if (data.errors && data.errors.length) {
      throw new Error("Error with query");
    }

    return NextResponse.json({
      mints: data.data.Token,
    });
  } catch (error) {
    console.error("Error retrieving mints:", error);
    return NextResponse.json(
      { error: "Failed to retrieve mints" },
      { status: 500 },
    );
  }
}
