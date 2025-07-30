"use client";

import { ValidatorWidget } from "@0xhoneyjar/validator-widget";
import { trackEvent } from "@openpanel/nextjs";
import { ArrowUpRight, ChevronRight, Map } from "lucide-react";
import Image from "next/image";

export const GuideButton = () => {
  return (
    <a
      href={
        "https://0xhoneyjar.mirror.xyz/dHB3l29gAfLsPhPUPLGvg6_UAM1LxgxHMSJ054_QuDM"
      }
      onClick={() => {
        trackEvent(`explore_guide`);
      }}
      target="_blank"
      className="w-full whitespace-nowrap rounded-full bg-[#F4C10B] px-6 py-3 text-center text-sm font-medium text-black transition-all duration-500 ease-in-out hover:shadow-yellow md:w-auto md:px-8 md:text-left"
    >
      Explore
    </a>
  );
};

export const FollowButton = ({
  platform,
}: {
  platform: "twitter" | "discord" | "farcaster";
}) => {
  const platformConfig = {
    twitter: {
      href: "https://x.com/0xhoneyjar",
      height: "h-[26px] md:h-[32px]",
    },
    discord: {
      href: "https://discord.com/invite/thehoneyjar",
      height: "h-[38px] md:h-[46px]",
    },
    farcaster: {
      href: "https://warpcast.com/0xhoneyjar",
      height: "h-[38px] md:h-[46px]",
    },
  };

  const { href, height } = platformConfig[platform];

  return (
    <a
      href={href}
      target="_blank"
      onClick={() => {
        trackEvent(`follow_us_${platform}`);
      }}
      className={`relative aspect-square ${height} hover: opacity-70 transition-all duration-500 ease-in-out hover:opacity-100`}
    >
      <Image
        src={`/follow/${platform}.svg`}
        alt={platform}
        fill
        className="object-contain"
      />
    </a>
  );
};

export const SpotlightButton = ({ spotlight }: { spotlight: any }) => {
  return (
    <a
      className="flex w-full items-center justify-between rounded-lg bg-[#F4C10B]/10 px-4 py-3 text-[#F4C10B] transition-all duration-500 ease-in-out hover:bg-[#F4C10B] hover:font-semibold hover:text-[#121212]"
      href={spotlight.link}
      onClick={() => {
        trackEvent(`${spotlight._title}_spotlight`);
      }}
      target="_blank"
    >
      <p className="text-sm">Learn More</p>
      <ArrowUpRight className="aspect-square h-[16px] md:h-[24px]" />
    </a>
  );
};

export const NewMintButton = () => {
  return (
    <a
      className="flex h-12 w-full items-center justify-center gap-2 rounded-lg bg-[#F4C10B]/10 px-4 py-3 text-[#F4C10B] transition-all duration-500 ease-in-out hover:bg-[#F4C10B] hover:text-[#121212]"
      href={"/mint-collection"}
      onClick={() => {
        trackEvent(`mint-collection-button`);
      }}
      // target="_blank"
    >
      <p className="text-sm">View Collections Drop</p>
      <ArrowUpRight className="aspect-square h-[16px] md:h-[24px]" />
    </a>
  );
};

export const DevelopmentButton = ({ item, id }: { item: any; id: any }) => {
  const CommonContent = () => (
    <>
      <div className="relative aspect-square h-4 md:h-6">
        <Image
          src={"/development-arrow.svg"}
          alt="arrow"
          fill
          className="object-contain"
        />
      </div>
      <p className="text-xs md:text-sm">{item._title}</p>
    </>
  );

  return (
    <a
      className="z-10 flex items-center gap-1 underline transition-all duration-500 ease-in-out hover:text-white/75 md:gap-2"
      key={id}
      href={item.link}
      target="_blank"
      onClick={() => {
        trackEvent(`development_${item._title}`);
      }}
      rel="noopener noreferrer"
    >
      <CommonContent />
    </a>
  );
};

export const IncubatedItem = ({ item }: { item: any }) => {
  return (
    <a
      className="hover: relative flex h-full w-[178px] flex-col items-center justify-center rounded-lg border border-[#F4C10B0F] bg-[#18140C] text-[#C4C4C4] hover:border-[#F4C10B38] hover:bg-[#332200] hover:font-medium hover:text-white/90 md:w-[196px]"
      href={
        item._title === "The Honey Jar"
          ? "https://magiceden.us/collections/berachain/0x886d2176d899796cd1affa07eff07b9b2b80f1be "
          : item.twitter
      }
      onClick={() => {
        trackEvent(
          item._title === "The Honey Jar"
            ? "Honeycomb_portfolio"
            : `${item._title}_portfolio`,
        );
      }}
      target="_blank"
    >
      <div className="absolute top-0 h-[2px] w-8 rounded-full bg-[#EE511E]" />
      <div className="relative my-4 aspect-square h-16 overflow-hidden rounded-full border border-[#F4C10B0F] bg-[#18140C05] md:mt-6 md:h-[80px]">
        <Image
          src={
            item._title === "The Honey Jar"
              ? "/honeycomb-icon.png"
              : "https://d163aeqznbc6js.cloudfront.net/images" + item.logo
          }
          alt={item._title}
          fill
          className={`${item._title === "The Honey Jar" && "p-1 md:p-2"} object-cover`}
        />
      </div>
      <p className="text-sm md:text-base">
        {item._title === "The Honey Jar" ? "Honeycomb" : item._title}
      </p>
    </a>
  );
};

export const NftItem = ({ nft }: { nft: any }) => {
  return (
    <a
      target="_blank"
      href={nft.link}
      onClick={() => {
        trackEvent(`${nft.name}_nft`);
      }}
      className="hover: flex h-full w-[178px] flex-col items-center justify-center gap-3 rounded-lg border border-[#161616] bg-[#121212] px-4 text-[#C4C4C4] hover:border-[#373737] hover:bg-[#1A1A1A] hover:font-medium hover:text-white md:w-[196px]"
    >
      <div className="flex h-[10%] w-full items-center justify-center gap-1 py-1">
        {nft.new && (
          <div className="flex items-center gap-2 rounded-full border border-[#F4C10B] bg-[#F5DA7F14] px-1.5 py-0.5">
            <div className="aspect-square h-[8px] rounded-full bg-[#F4C10B]">
              <div className="h-full w-full animate-ping rounded-full bg-[#F4C10B]" />
            </div>
            <p className="text-[10px] text-[#F4C10B]">NEW</p>
          </div>
        )}
        {nft.soon && (
          <div className="flex items-center gap-2 rounded-full border border-white bg-[#F5DA7F14] px-1.5 py-0.5">
            <div className="aspect-square h-[8px] rounded-full bg-white">
              <div className="h-full w-full animate-ping rounded-full bg-white" />
            </div>
            <p className="text-[10px] text-white">Coming Soon</p>
          </div>
        )}
      </div>
      <div className="relative aspect-square h-16 rounded-full border border-[#1A1A1A] bg-[#FFFFFF03] md:h-20">
        <Image
          src={nft.image}
          alt={nft.name}
          fill
          className="object-contain p-3 md:p-4"
        />
      </div>
      <p className="">{nft.name}</p>
    </a>
  );
};

export const DelegateButton = () => {
  return (
    // <ValidatorWidget apiUrl="/api/delegate" referrer="thj">
    <a
      href={
        "https://hub.berachain.com/validators/0xa0c673180d97213c1c35fe3bf4e684dd3534baab235a106d1f71b9c8a37e4d37a056d47546964fd075501dff7f76aeaf/"
      }
      onClick={() => {
        trackEvent(`boost_validator`);
      }}
      target="_blank"
    >
      <div className="flex w-full cursor-pointer items-center justify-center rounded-full bg-black py-3 text-sm font-medium transition-all duration-500 ease-in-out hover:bg-white hover:text-black md:text-base">
        Boost Now
      </div>
    </a>

    // </ValidatorWidget>
  );
};

export const PartnersButton = () => {
  return (
    <>
      <a
        href="https://ecosystem.0xhoneyjar.xyz/"
        target="_blank"
        onClick={() => {
          trackEvent(`partner_map_partners`);
        }}
      >
        <button className="hover: flex w-full items-center justify-between rounded-lg border border-[#E8E8E80A] bg-[#FFFFFF0A] px-4 py-3 transition-all duration-500 ease-in-out hover:border-[#E8E8E81F] hover:bg-[#FFFFFF24]">
          <div className="flex items-center gap-2 whitespace-nowrap">
            <Map className="aspect-square h-4 md:h-[22px]" />
            <p className="text-xs md:text-sm">THJ Partner Map</p>
          </div>
          <ChevronRight className="aspect-square h-3 text-[#FFFFFF66] md:h-[14px]" />
        </button>
      </a>
      <a
        href="https://ecosystem.0xhoneyjar.xyz/"
        target="_blank"
        onClick={() => {
          trackEvent(`explore_partners_partners`);
        }}
      >
        <button className="hover: flex w-full items-center justify-between rounded-lg border border-[#E8E8E80A] bg-[#FFFFFF0A] px-4 py-3 transition-all duration-500 ease-in-out hover:border-[#E8E8E81F] hover:bg-[#FFFFFF24]">
          <div className="flex items-center gap-2 whitespace-nowrap">
            <div className="relative aspect-square h-4 md:h-[22px]">
              <Image
                src={"/partners.svg"}
                alt="partners"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-xs md:text-sm">Explore Partners</p>
          </div>
          <ChevronRight className="aspect-square h-3 text-[#FFFFFF66] md:h-[14px]" />
        </button>
      </a>
    </>
  );
};

export const PartnerButton = () => {
  return (
    <a
      href="https://partners.0xhoneyjar.xyz/"
      target="_blank"
      onClick={() => {
        trackEvent(`become_partner_partners`);
      }}
    >
      <button className="hover: flex w-full items-center justify-center rounded-full bg-[#43AA77] p-3 text-sm font-medium text-black transition-all duration-500 ease-in-out hover:shadow-evergreen md:text-base xl:text-lg">
        <p className="text-sm">Become a Partner</p>
      </button>
    </a>
  );
};

export const ToolsButton = ({ item }: { item: any }) => {
  return (
    <a
      target="_blank"
      href={item.link}
      onClick={() => {
        trackEvent(`${item.name}_tools_product`);
      }}
      className={`hover: flex h-full w-[178px] flex-col items-center justify-center rounded-lg border border-[#161616] bg-[#121212] px-4 text-[#C4C4C4] hover:border-[#373737] hover:bg-[#1A1A1A] hover:font-medium hover:text-white md:w-[196px]`}
    >
      {item.image ? (
        <div className="relative mb-4 mt-4 aspect-square h-16 overflow-hidden rounded-full md:mt-6 md:h-[80px]">
          <Image
            src={item.image}
            alt={item.name}
            fill
            className="object-contain"
          />
        </div>
      ) : (
        <div className="mb-4 mt-4 aspect-square h-16 rounded-full bg-[#FD4D01] md:mt-6 md:h-[80px]" />
      )}
      <p className="text-xs md:text-sm">{item.name}</p>
    </a>
  );
};

export const SnapshotButton = () => {
  return (
    <a
      target="_blank"
      href={"https://beardrops.0xhoneyjar.xyz/"}
      onClick={() => {
        trackEvent(`beardrops_snapshot`);
      }}
      className="hover: flex size-full items-center justify-center rounded-full bg-[#43AA77] px-6 py-3 text-sm font-medium text-black transition-all duration-500 ease-in-out hover:shadow-evergreen md:w-auto md:px-8"
    >
      Snapshot
    </a>
  );
};
