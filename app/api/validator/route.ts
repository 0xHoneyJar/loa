import { BGTABI } from "@/abis/BGT";
import { BlockRewardControllerAbi } from "@/abis/BlockRewardController";
import { berachainBartio } from "@/constants/chains";
import {
  BGT_ADDRESS,
  BLOCK_REWARD_CONTROLLER_ADDRESS,
  THJ_VALIDATOR_ADDRESS,
} from "@/constants/contracts";
import { NextRequest, NextResponse } from "next/server";
import {
  createPublicClient,
  createWalletClient,
  getContract,
  http,
} from "viem";

const bartioPublicClient = createPublicClient({
  chain: berachainBartio,
  transport: http(process.env.RPC_URL_80084),
});

const bartioClient = createWalletClient({
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

  const blockRewardController = getContract({
    abi: BlockRewardControllerAbi,
    address: BLOCK_REWARD_CONTROLLER_ADDRESS,
    client: {
      public: bartioPublicClient,
      wallet: bartioClient,
    },
  });

  const rewardRate = await blockRewardController.read.rewardRate();

  const amountDelegated = await BGTContract.read.boostees([
    THJ_VALIDATOR_ADDRESS,
  ]);

  const boostedRewardRate = await BGTContract.read.boostedRewardRate([
    THJ_VALIDATOR_ADDRESS,
    rewardRate,
  ]);

  return NextResponse.json({
    amountDelegated: amountDelegated.toString(),
    boostedRewardRate: boostedRewardRate.toString(),
  });
}
