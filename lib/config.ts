// config/index.tsx

import { http, createConfig } from "wagmi";
import { berachainTestnetbArtio } from "wagmi/chains";
import { metaMask } from "wagmi/connectors";

export const projectId = "fb297a4ca0bff468a184d944ed22510a";

export const config = createConfig({
  chains: [berachainTestnetbArtio] as const,
  connectors: [metaMask()],
  transports: {
    [berachainTestnetbArtio.id]: http(),
  },
});
