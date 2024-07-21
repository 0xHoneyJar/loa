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
import Follow from "@/components/board/follow";
import OogaBooga from "@/components/board/ooga-booga";
import Raffles from "@/components/board/raffles";
import Beardrops from "@/components/board/beardrops";
import JaniSweeping from "@/components/board/jani-sweeping";

export const DASHBOARD = [
  {
    name: "Updates",
    key: "updates",
    dataGrid: {
      i: "updates",
      x: 0,
      y: 0,
      w: 2,
      h: 1,
      static: true,
    },
    ui: <Updates />,
    hidden: false,
  },
  {
    name: "Follow Us",
    key: "follow",
    dataGrid: { i: "follow", x: 2, y: 0, w: 1, h: 1 },
    dataGrid_md: { i: "follow", x: 0, y: 7, w: 1, h: 1 },
    dataGrid_sm: { i: "follow", x: 0, y: 7, w: 1, h: 1 },
    ui: <Follow />,
    hidden: false,
  },
  {
    name: "New Partners",
    key: "newPartners",
    dataGrid: {
      i: "newPartners",
      x: 0,
      y: 1,
      w: 3,
      h: 1,
      static: true,
    },
    ui: <NewPartners />,
    hidden: false,
  },
  {
    name: "New Mint",
    key: "mint",
    dataGrid: {
      i: "mint",
      x: 0,
      y: 2,
      w: 3,
      h: 1,
      static: true,
    },
    ui: <Mint />,
    hidden: false,
  },
  {
    name: "Blog",
    key: "blog",
    dataGrid: {
      i: "blog",
      x: 0,
      y: 4,
      w: 3,
      h: 1,
    },
    ui: <Blog />,
    hidden: false,
  },
  {
    name: "Spotlight",
    key: "spotlight",
    dataGrid: {
      i: "spotlight",
      x: 0,
      y: 5,
      w: 2,
      h: 2,
    },
    ui: <Spotlight />,
    hidden: false,
  },
  {
    name: "Development Pipeline",
    key: "development",
    dataGrid: { i: "development", x: 2, y: 5, w: 1, h: 3 },
    ui: <Development />,
    hidden: false,
  },
  {
    name: "OOGA BOOGA",
    key: "oogabooga",
    dataGrid: { i: "oogabooga", x: 0, y: 6, w: 1, h: 1 },
    ui: <OogaBooga />,
    hidden: true,
  },
  {
    name: "Feed",
    key: "feed",
    dataGrid: { i: "feed", x: 1, y: 6, w: 1, h: 1 },
    dataGrid_md: { i: "sweep", x: 0, y: 8, w: 1, h: 1 },
    dataGrid_sm: { i: "sweep", x: 0, y: 8, w: 1, h: 1 },
    ui: <Feed />,
    hidden: false,
  },
  // {
  //   name: "Sweep",
  //   key: "sweep",
  //   dataGrid: { i: "sweep", x: 1, y: 6, w: 1, h: 1 },
  //   dataGrid_md: { i: "sweep", x: 0, y: 8, w: 1, h: 1 },
  //   dataGrid_sm: { i: "sweep", x: 0, y: 8, w: 1, h: 1 },
  //   ui: <JaniSweeping />,
  //   hidden: true,
  // },
  {
    name: "Guide",
    key: "guide",
    dataGrid: { i: "guide", x: 0, y: 7, w: 3, h: 1 },
    ui: <Guide />,
    hidden: false,
  },
  {
    name: "Incubated Projects",
    key: "incubated",
    dataGrid: { i: "incubated", x: 0, y: 8, w: 3, h: 1 },
    ui: <Incubated />,
    hidden: false,
  },
  // {
  //   name: "Tools & Products",
  //   key: "tools",
  //   dataGrid: {
  //     i: "tools",
  //     x: 0,
  //     y: 9,
  //     w: 3,
  //     h: 1,
  //   },
  //   ui: <Tools />,
  // },
  {
    name: "NFT",
    key: "nft",
    dataGrid: { i: "nft", x: 0, y: 10, w: 3, h: 1 },
    ui: <NFT />,
    hidden: false,
  },
  {
    name: "Quote",
    key: "quote",
    dataGrid: { i: "quote", x: 0, y: 11, w: 1, h: 1 },
    ui: <Quotes quoteNumber={1} />,
    hidden: true,
  },
  {
    name: "Quests",
    key: "quests",
    dataGrid: { i: "quests", x: 1, y: 11, w: 1, h: 3 },
    ui: <Quests />,
    hidden: false,
  },
  {
    name: "Delegate",
    key: "delegate",
    dataGrid: { i: "delegate", x: 2, y: 11, w: 1, h: 2 },
    ui: <Delegate />,
    hidden: false,
  },
  {
    name: "Partners",
    key: "partners",
    dataGrid: { i: "partners", x: 0, y: 12, w: 1, h: 2 },
    ui: <Partners />,
    hidden: false,
  },
  {
    name: "Quote2",
    key: "quote2",
    dataGrid: { i: "quote2", x: 2, y: 12, w: 1, h: 1 },
    ui: <Quotes quoteNumber={0} />,
    hidden: true,
  },
  {
    name: "Artwork / Meme",
    key: "artwork",
    dataGrid: { i: "artwork", x: 0, y: 13, w: 2, h: 1 },
    ui: <Artwork />,
    hidden: false,
  },
  {
    name: "Data",
    key: "data",
    dataGrid: { i: "data", x: 2, y: 13, w: 1, h: 4 },
    ui: <Data />,
    hidden: false,
  },
  {
    name: "Honeycomb",
    key: "honeycomb",
    dataGrid: { i: "honeycomb", x: 0, y: 14, w: 2, h: 3 },
    ui: <Honeycomb />,
    hidden: false,
  },
  {
    name: "Raffles",
    key: "raffles",
    dataGrid: { i: "raffles", x: 0, y: 19, w: 1, h: 3 },
    ui: <Raffles />,
    hidden: false,
  },
  {
    name: "Validator",
    key: "validator",
    dataGrid: { i: "validator", x: 1, y: 19, w: 2, h: 2 },
    ui: <Validator />,
    hidden: false,
  },
  {
    name: "Tools & Products",
    key: "tools",
    dataGrid: {
      i: "tools",
      x: 1,
      y: 21,
      w: 2,
      h: 1,
    },
    ui: <Tools />,
    hidden: false,
  },
  {
    name: "Beardrops",
    key: "beardrops",
    dataGrid: {
      i: "beardrops",
      x: 1,
      y: 22,
      w: 3,
      h: 1,
    },
    ui: <Beardrops />,
    hidden: false,
  },
];
