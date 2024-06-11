import Blog from "@/components/board/blog";
import Development from "@/components/board/development";
import Feed from "@/components/board/feed";
import Guide from "@/components/board/guide";
import Incubated from "@/components/board/incubated";
import Mint from "@/components/board/mint";
import NFT from "@/components/board/nft";
import Partners from "@/components/board/partners";
import Quotes from "@/components/board/quotes";
import Spotlight from "@/components/board/spotlight";
import Tools from "@/components/board/tools";
import Updates from "@/components/board/updates";
import NewPartners from "@/components/board/new-partners";
import Quests from "@/components/board/quests";
import Delegate from "@/components/board/delegate";
import Artwork from "@/components/board/artwork";
import Data from "@/components/board/data";
import Honeycomb from "@/components/board/honeycomb";
import Validator from "@/components/board/validator";

export const DASHBOARD = [
  {
    key: "updates",
    dataGrid: {
      i: "updates",
      x: 0,
      y: 0,
      w: 2,
      h: 1,
    },
    ui: <Updates />,
  },
  {
    key: "quote",
    dataGrid: { i: "quote", x: 2, y: 0, w: 1, h: 1 },
    ui: <Quotes />,
  },
  {
    key: "newPartners",
    dataGrid: {
      i: "newPartners",
      x: 0,
      y: 1,
      w: 3,
      h: 1,
    },
    ui: <NewPartners />,
  },
  {
    key: "mint",
    dataGrid: {
      i: "mint",
      x: 0,
      y: 2,
      w: 3,
      h: 1.3,
    },
    ui: <Mint />,
  },
  {
    key: "blog",
    dataGrid: {
      i: "blog",
      x: 0,
      y: 4,
      w: 3,
      h: 1,
    },
    ui: <Blog />,
  },
  {
    key: "spotlight",
    dataGrid: {
      i: "spotlight",
      x: 0,
      y: 5,
      w: 2,
      h: 2,
    },
    ui: <Spotlight />,
  },
  {
    key: "development",
    dataGrid: { i: "development", x: 3, y: 5, w: 1, h: 3 },
    ui: <Development />,
  },
  {
    key: "quote2",
    dataGrid: { i: "quote2", x: 0, y: 6, w: 1, h: 1 },
    ui: <Quotes />,
  },
  {
    key: "feed",
    dataGrid: { i: "feed", x: 1, y: 6, w: 1, h: 1 },
    ui: <Feed />,
  },
  {
    key: "guide",
    dataGrid: { i: "guide", x: 0, y: 7, w: 3, h: 1 },
    ui: <Guide />,
  },
  {
    key: "incubated",
    dataGrid: { i: "incubated", x: 0, y: 8, w: 3, h: 1 },
    ui: <Incubated />,
  },
  {
    key: "tools",
    dataGrid: {
      i: "tools",
      x: 0,
      y: 9,
      w: 3,
      h: 1,
    },
    ui: <Tools />,
  },
  {
    key: "nft",
    dataGrid: { i: "nft", x: 0, y: 10, w: 3, h: 1 },
    ui: <NFT />,
  },
  {
    key: "quote3",
    dataGrid: { i: "quote3", x: 0, y: 11, w: 1, h: 1 },
    ui: <Quotes />,
  },
  {
    key: "quests",
    dataGrid: { i: "quests", x: 1, y: 11, w: 1, h: 3 },
    ui: <Quests />,
  },
  {
    key: "delegate",
    dataGrid: { i: "delegate", x: 2, y: 11, w: 1, h: 2 },
    ui: <Delegate />,
  },
  {
    key: "partners",
    dataGrid: { i: "partners", x: 0, y: 12, w: 1, h: 2 },
    ui: <Partners />,
  },
  {
    key: "quote4",
    dataGrid: { i: "quote4", x: 3, y: 12, w: 1, h: 1 },
    ui: <Quotes />,
  },
  {
    key: "artwork",
    dataGrid: { i: "artwork", x: 0, y: 13, w: 2, h: 1 },
    ui: <Artwork />,
  },
  {
    key: "data",
    dataGrid: { i: "data", x: 2, y: 13, w: 1, h: 4 },
    ui: <Data />,
  },
  {
    key: "honeycomb",
    dataGrid: { i: "honeycomb", x: 0, y: 14, w: 2, h: 3 },
    ui: <Honeycomb />,
  },
  {
    key: "validator",
    dataGrid: { i: "validator", x: 0, y: 17, w: 3, h: 1.5 },
    ui: <Validator />,
  },
];
