import Article from "@/components/board/article";
import Development from "@/components/board/development";
import Feed from "@/components/board/feed";
import Guide from "@/components/board/guide";
import Portfolio from "@/components/board/portfolio";
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
import Ramen from "@/components/board/ramen";

export const DASHBOARD = [
  {
    name: "Guide",
    key: "guide",
    ui: <Guide />,
    hidden: false,
  },
  {
    name: "Updates",
    key: "updates",
    ui: <Updates />,
    hidden: false,
  },
  {
    name: "Follow Us",
    key: "follow",
    ui: <Follow />,
    hidden: false,
  },
  {
    name: "New Partners",
    key: "newPartners",
    ui: <NewPartners />,
    hidden: false,
  },
  {
    name: "Ramen IDO",
    key: "ramen",
    ui: <Ramen />,
    hidden: false,
  },
  {
    name: "New Mint",
    key: "mint",
    ui: <Mint />,
    hidden: false,
  },
  {
    name: "Articles",
    key: "articles",
    ui: <Article />,
    hidden: false,
  },
  {
    name: "Spotlight",
    key: "spotlight",
    ui: <Spotlight />,
    hidden: false,
  },
  {
    name: "Development Pipeline",
    key: "development",
    ui: <Development />,
    hidden: false,
  },
  {
    name: "OOGA BOOGA",
    key: "oogabooga",
    ui: <OogaBooga />,
    hidden: true,
  },
  {
    name: "Feed",
    key: "feed",
    ui: <Feed />,
    hidden: false,
  },
  {
    name: "Incubated Projects",
    key: "incubated",
    ui: <Portfolio />,
    hidden: false,
  },
  {
    name: "NFT",
    key: "nft",
    ui: <NFT />,
    hidden: false,
  },
  {
    name: "Quote",
    key: "quote",
    ui: <Quotes quoteNumber={1} />,
    hidden: true,
  },
  {
    name: "Quests",
    key: "quests",
    ui: <Quests />,
    hidden: false,
  },
  {
    name: "Delegate",
    key: "delegate",
    ui: <Delegate />,
    hidden: false,
  },
  {
    name: "Partners",
    key: "partners",
    ui: <Partners />,
    hidden: false,
  },
  {
    name: "Quote2",
    key: "quote2",
    ui: <Quotes quoteNumber={0} />,
    hidden: true,
  },
  {
    name: "Artwork / Meme",
    key: "artwork",
    ui: <Artwork />,
    hidden: false,
  },
  {
    name: "Data",
    key: "data",
    ui: <Data />,
    hidden: false,
  },
  {
    name: "Honeycomb",
    key: "honeycomb",
    ui: <Honeycomb />,
    hidden: false,
  },
  {
    name: "Raffles",
    key: "raffles",
    ui: <Raffles />,
    hidden: false,
  },
  {
    name: "Validator",
    key: "validator",
    ui: <Validator />,
    hidden: false,
  },
  {
    name: "Tools & Products",
    key: "tools",
    ui: <Tools />,
    hidden: false,
  },
  {
    name: "Beardrops",
    key: "beardrops",
    ui: <Beardrops />,
    hidden: false,
  },
];
