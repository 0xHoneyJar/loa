import { BGTMainnetABI } from "@/abis/BGT_Mainnet";
import { BlockRewardControllerMainnetAbi } from "@/abis/BlockRewardController_Mainnet";
import {
  BGT_MAINNET_ADDRESS,
  BLOCK_REWARD_CONTROLLER_MAINNET_ADDRESS,
  THJ_MAINNET_VALIDATOR_ADDRESS,
  THJ_MAINNET_VALIDATOR_PUBKEY,
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
  // const BGTContract = getContract({
  //   abi: BGTMainnetABI,
  //   address: BGT_MAINNET_ADDRESS,
  //   client: {
  //     public: beraMainnetPublicClient,
  //     wallet: beraMainnetClient,
  //   },
  // });

  // const blockRewardController = getContract({
  //   abi: BlockRewardControllerMainnetAbi,
  //   address: BLOCK_REWARD_CONTROLLER_MAINNET_ADDRESS,
  //   client: {
  //     public: beraMainnetPublicClient,
  //     wallet: beraMainnetClient,
  //   },
  // });

  // const boostPower = await BGTContract.read.normalizedBoost([
  //   THJ_MAINNET_VALIDATOR_PUBKEY,
  // ]);
  // const rewardRate = await blockRewardController.read.rewardRate();
  // const boostMultiplier = await blockRewardController.read.boostMultiplier();
  // const rewardConvexity = await blockRewardController.read.rewardConvexity();

  // const amountDelegated = await BGTContract.read.boostees([
  //   THJ_MAINNET_VALIDATOR_PUBKEY,
  // ]);

  // const computedRewardRate = await blockRewardController.read.computeReward([
  //   boostPower,
  //   rewardRate,
  //   boostMultiplier,
  //   rewardConvexity,
  // ]);

  // console.log(computedRewardRate.toString());

  const res = await fetch("https://api.berachain.com/", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query: `
       query GetValidator($id: String!, $chain: GqlChain!) {
          validator: polGetValidator(validatorId: $id, chain: $chain) {
            ...ApiValidator
            __typename
          }
        }

        fragment ApiValidator on GqlValidator {
          ...ApiValidatorMinimal
          operator
          __typename
        }

        fragment ApiValidatorMinimal on GqlValidator {
          id
          pubkey
          operator
          dynamicData {
            activeBoostAmount
            usersActiveBoostCount
            queuedBoostAmount
            usersQueuedBoostCount
            allTimeDistributedBGTAmount
            rewardRate
            stakedBeraAmount
            lastDayDistributedBGTAmount
            activeBoostAmountRank
            boostApr
            commissionOnIncentives
          }
        }
      `,
      variables: {
        chain: "BERACHAIN",
        id: "0x68b58f24be0e7c16df3852402e8475e8b3cc53a64cfaf45da3dbc148cdc05d30",
      },
    }),
  });

  const data = await res.json();

  console.log(data);

  const amountDelegated = data.data.validator.dynamicData.activeBoostAmount;
  const rewardRate = data.data.validator.dynamicData.rewardRate;
  const rank = data.data.validator.dynamicData.activeBoostAmountRank;
  const boosters = data.data.validator.dynamicData.usersActiveBoostCount;

  return NextResponse.json({
    amountDelegated: amountDelegated.toString(),
    rewardRate: rewardRate.toString(),
    rank: rank.toString(),
    boosters: boosters.toString(),
  });
}
