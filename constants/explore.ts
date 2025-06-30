export interface ListItemData {
  title: string;
  description: string;
  icon: string;
  link: string;
  color: string;
  comingSoon?: boolean;
}

export const FLAGSHIP_ITEMS: ListItemData[] = [
  {
    title: "The Honey Jar",
    description: "The front page of The Honey Jar",
    icon: "/navbar/community.png",
    link: "https://0xhoneyjar.xyz/",
    color: "#2C2610",
  },
  {
    title: "Henlo",
    description: "Memecoin built by The Honey Jar",
    icon: "/navbar/henlo.png",
    link: "https://www.henlo.com/",
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
    title: "Set & Forgetti",
    description: "Easiest way to Farm Berachain PoL",
    icon: "/navbar/set&forgetti.svg",
    link: "https://www.setandforgetti.io/",
    color: "#2A1F26",
  },
  {
    title: "Moneycomb",
    description: "All about Honeycomb and its perks",
    icon: "/navbar/moneycomb.png",
    link: "https://honeycomb.0xhoneyjar.xyz/",
    color: "#151429",
  },
  {
    title: "Apiology DAO",
    description: "Honeycomb on steroids",
    icon: "/navbar/apiology.png",
    link: "https://www.apiologydao.xyz/",
    color: "#1E1E1E",
  },
  {
    title: "THJ Validator",
    description: "Validating Berachain 24/7",
    icon: "/navbar/validator.png",
    link: "https://hub.berachain.com/validators/0xa0c673180d97213c1c35fe3bf4e684dd3534baab235a106d1f71b9c8a37e4d37a056d47546964fd075501dff7f76aeaf/",
    color: "#17231D",
  },
  {
    title: "Interpol",
    description: "Get the most out of your locked liquidity",
    icon: "/navbar/interpol.png",
    link: "https://www.notinterpol.com/",
    color: "#0A1A2E",
  },
  {
    title: "fatBERA",
    description: "Innovative Bera LST",
    icon: "/navbar/fatbera.png",
    link: "https://www.fatbera.xyz/",
    color: "#12242A",
  },
];

export const ECOSYSTEM_ITEMS: ListItemData[] = [
  // {
  //   title: "Faucet",
  //   description: "Official bArtio v2 testnet faucet",
  //   icon: "/navbar/faucet.png",
  //   link: "https://www.cubquests.com/",
  //   color: "#12242A",
  // },
  {
    title: "Mint Mania",
    description: "Old, but gold",
    icon: "/navbar/thj.png",
    link: "https://app.0xhoneyjar.xyz/",
    color: "#122618",
  },
  {
    title: "Beraflip",
    description: "Your bera mememaker",
    icon: "/navbar/beraflip.svg",
    link: "https://www.beraflip.com/",
    color: "#1A2A2E",
  },
  {
    title: "Beardrops",
    description: "The best tool for snapshots",
    icon: "/navbar/beardrops.png",
    link: "https://beardrops.0xhoneyjar.xyz/",
    color: "#2B3234",
  },
  {
    title: "For Partners",
    description: "Learn more about the THJ org",
    icon: "/navbar/partner.png",
    link: "http://partners.0xhoneyjar.xyz/",
    color: "#2D2313",
  },
  {
    title: "Ecosystem Explorer",
    description: "THJ Ecosystem Explorer",
    icon: "/navbar/explorer.png",
    link: "http://ecosystem.0xhoneyjar.xyz/",
    color: "#2E1811",
  },
  {
    title: "Mibera",
    description: "Mibera Maker",
    icon: "/navbar/mibera.png",
    link: "https://www.honeyroad.xyz/",
    color: "#2B150E",
    // comingSoon: true,
  },
  {
    title: "OBB",
    description: "Cutest Beras on Berachain",
    icon: "/navbar/obb.png",
    link: "",
    color: "#20242C",
    comingSoon: true,
  },
];
