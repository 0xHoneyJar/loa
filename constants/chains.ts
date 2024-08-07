import { defineChain } from "viem";

export const berachainBartio = defineChain({
  id: 80084,
  name: "Berachain bArtio",
  network: "Berachain bArtio",
  nativeCurrency: {
    decimals: 18,
    name: "BERA",
    symbol: "BERA",
  },
  rpcUrls: {
    default: {
      http: ["https://bartio.rpc.berachain.com/"],
    },
    public: {
      http: ["https://bartio.rpc.berachain.com/"],
    },
  },
  blockExplorers: {
    default: { name: "Explorer", url: "https://bartio.beratrail.io/" },
  },
  contracts: {
    multicall3: {
      address: "0x09aA7d09Df3688BC4f2277428D49cCc87e632d35",
      blockCreated: 126199,
    },
  },
});
