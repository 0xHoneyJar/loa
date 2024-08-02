import { BGTABI } from "@/abis/BGT";
import { berachainBartio } from "@/constants/chains";
import { BGT_ADDRESS, THJ_VALIDATOR_ADDRESS } from "@/constants/contracts";
import { NextRequest, NextResponse } from "next/server";
import {
  createPublicClient,
  createWalletClient,
  getContract,
  http,
} from "viem";

export const bartioPublicClient = createPublicClient({
  chain: berachainBartio,
  transport: http(process.env.RPC_URL_80084),
});

export const bartioClient = createWalletClient({
  chain: berachainBartio,
  transport: http(process.env.RPC_URL_80084),
});

export async function GET(req: NextRequest) {
  const BGTContract = getContract({
    abi: BGTABI,
    address: BGT_ADDRESS,
    client: {
      public: bartioPublicClient,
      wallet: bartioClient,
    },
  });

  const amountDelegated = await BGTContract.read.boostees([
    THJ_VALIDATOR_ADDRESS,
  ]);
  const commission = await BGTContract.read.commissions([
    THJ_VALIDATOR_ADDRESS,
  ]);
  return NextResponse.json({
    amountDelegated: amountDelegated.toString(),
    commission: commission.toString(),
  });
}
