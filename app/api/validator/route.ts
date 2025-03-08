import { BGTMainnetABI } from "@/abis/BGT_Mainnet";
import { BlockRewardControllerMainnetAbi } from "@/abis/BlockRewardController_Mainnet";
import {
  BGT_MAINNET_ADDRESS,
  BLOCK_REWARD_CONTROLLER_MAINNET_ADDRESS,
  THJ_MAINNET_VALIDATOR_ADDRESS,
} from "@/constants/contracts";
import { NextRequest, NextResponse } from "next/server";
import {
  createPublicClient,
  createWalletClient,
  getContract,
  http,
} from "viem";
import { berachain } from "viem/chains";

const beraMainnetClient = createWalletClient({
  chain: berachain,
  transport: http(process.env.RPC_URL_80094),
});

const beraMainnetPublicClient = createPublicClient({
  chain: berachain,
  transport: http(process.env.RPC_URL_80094),
});

export async function GET(req: NextRequest) {
  const BGTContract = getContract({
    abi: BGTMainnetABI,
    address: BGT_MAINNET_ADDRESS,
    client: {
      public: beraMainnetPublicClient,
      wallet: beraMainnetClient,
    },
  });

  const blockRewardController = getContract({
    abi: BlockRewardControllerMainnetAbi,
    address: BLOCK_REWARD_CONTROLLER_MAINNET_ADDRESS,
    client: {
      public: beraMainnetPublicClient,
      wallet: beraMainnetClient,
    },
  });

  const rewardRate = await blockRewardController.read.rewardRate();

  const amountDelegated = await BGTContract.read.boostees([
    THJ_MAINNET_VALIDATOR_ADDRESS,
  ]);

  // console.log(amountDelegated.toString());
  // const boostedRewardRate = await BGTContract.read.boostedRewardRate([
  //   THJ_MAINNET_VALIDATOR_ADDRESS,
  //   rewardRate,
  // ]);

  // console.log(rewardRate.toString());

  return NextResponse.json({
    amountDelegated: amountDelegated.toString(),
    boostedRewardRate: "",
    // boostedRewardRate.toString(),
  });
}
