import Development from "@/components/board/development";
import Feed from "@/components/board/feed";
import Incubated from "@/components/board/incubated";
import NFT from "@/components/board/nft";
import Quotes from "@/components/board/quotes";
import Tools from "@/components/board/tools";

export const DASHBOARD = [
  {
    key: "tools",
    dataGrid: {
      x: 0,
      y: 0,
      w: 3,
      h: 1,
    },
    ui: <Tools />,
  },
  {
    key: "incubated",
    dataGrid: {
      x: 0,
      y: 1,
      w: 3,
      h: 1,
    },
    ui: <Incubated />,
  },
  {
    key: "nft",
    dataGrid: {
      x: 0,
      y: 3,
      w: 3,
      h: 1,
    },
    ui: <NFT />,
  },
  {
    key: "feed",
    dataGrid: {
      x: 0,
      y: 4,
      w: 1,
      h: 1,
    },
    ui: <Feed />,
  },
  {
    key: "quote",
    dataGrid: {
      x: 1,
      y: 4,
      w: 1,
      h: 1,
    },
    ui: <Quotes />,
  },
  {
    key: "development",
    dataGrid: {
      x: 3,
      y: 4,
      w: 1,
      h: 3,
    },
    ui: <Development />,
  },
];