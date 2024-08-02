export interface ListItemData {
  title: string;
  description: string;
  icon: string;
  link: string;
  color: string;
  comingSoon?: boolean;
}

export const EXPLOREITEMS: ListItemData[] = [
  {
    title: "For Community",
    description: "The front page of The Honey Jar",
    icon: "/navbar/community.png",
    link: "https://community-interface.vercel.app/",
    color: "#2C2610",
  },
  {
    title: "For Partners",
    description: "Learn more about the THJ org",
    icon: "/navbar/partner.png",
    link: "https://partners-interface.vercel.app/",
    color: "#2D2313",
  },
  {
    title: "Cub Quests",
    description: "Explore Berachain and get rewarded",
    icon: "/navbar/cub.png",
    link: "https://www.cubquests.com/",
    color: "#241A0F",
  },
  {
    title: "THJ Validator",
    description: "Validating Berachain 24/7",
    icon: "/navbar/validator.png",
    link: "",
    color: "#17231D",
  },
  {
    title: "Moneycomb",
    description: "All about Honeycomb and its perks",
    icon: "/navbar/moneycomb.png",
    link: "https://moneycomb-interface.vercel.app/",
    color: "#151429",
    comingSoon: true,
  },
  {
    title: "Partners Explorer",
    description: "THJ Ecosystem Explorer",
    icon: "/navbar/explorer.png",
    link: "https://explorer-interface.vercel.app/",
    color: "#2E1811",
    comingSoon: true,
  },
  {
    title: "THJ Old",
    description: "Old, but gold",
    icon: "/navbar/thj.png",
    link: "https://www.0xhoneyjar.xyz/",
    color: "#122618",
  },
  {
    title: "Faucet",
    description: "Official bArtio v2 testnet faucet",
    icon: "/navbar/faucet.png",
    link: "https://www.cubquests.com/",
    color: "#12242A",
  },
  {
    title: "Apiology DAO",
    description: "Honeycomb on steroids",
    icon: "/navbar/apiology.png",
    link: "https://www.apiologydao.xyz/",
    color: "#1E1E1E",
  },
  {
    title: "Beardrops",
    description: "The best tool for snapshots",
    icon: "/navbar/beardrops.png",
    link: "https://beardrops-interface.vercel.app/",
    color: "#2B3234",
    comingSoon: true,
  },
];
