export function processKindomlyMint(
  mint: any,
  status: "live" | "upcoming" | "completed",
) {
  return {
    image: mint.profile_image ? mint.profile_image : mint.header_image,
    price: mint.mint_group_data[0]?.price || 0,
    currency: mint.chain.native_currency,
    status: status,
    logo: "faucet/quests/kingdomly.png",
    title: mint.collection_name || "Unknown",
    link: `https://www.kingdomly.app/${mint.slug}` || "",
    source: "kingdomly",
    supply: mint.total_supply,
    partnerName: "Kingdomly",
  };
}

export function processMint(mint: any) {
  return {
    image: mint.image,
    price: mint.price,
    currency: "ETH",
    status: "live",
    logo: mint.partner.logo,
    title: mint._title,
    link: mint.link,
    source: "basehub",
    supply: mint.supply,
    partnerName: mint.partner._title,
    endDate: mint.endDate,
  };
}

export type MintType = {
  image: string;
  price: string;
  currency: string;
  status: "live" | "upcoming" | "completed";
  title: string;
  link: string;
  source: string;
  logo: string;
  supply: number;
  partnerName: string;
  endDate?: number;
};
