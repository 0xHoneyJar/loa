"use client";

import Marquee from "react-fast-marquee";
import React, { useState, useEffect } from "react";
import Updates from "@/components/board/updates";
import Follow from "@/components/board/follow";
import NewPartners from "@/components/board/new-partners";
import Mint from "@/components/board/mint";
import Blog from "@/components/board/blog";
import Spotlight from "@/components/board/spotlight";
import Development from "@/components/board/development";
import Feed from "@/components/board/feed";
import Guide from "@/components/board/guide";
import Portfolio from "@/components/board/portfolio";
import NFT from "@/components/board/nft";
import Quests from "@/components/board/quests";
import Delegate from "@/components/board/delegate";
import Partners from "@/components/board/partners";
import Artwork from "@/components/board/artwork";
import Data from "@/components/board/data";
import Honeycomb from "@/components/board/honeycomb";
import Raffles from "@/components/board/raffles";
import Validator from "@/components/board/validator";
import Tools from "@/components/board/tools";
import Beardrops from "@/components/board/beardrops";
import OogaBooga from "@/components/board/ooga-booga";
import Quotes from "@/components/board/quotes";

const BoardSection = ({
  partners,
  community,
  perks,
}: {
  partners: any;
  community: any;
  perks: any;
}) => {
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const timer = setTimeout(() => {
      setIsLoading(false);
    }, 100);

    return () => clearTimeout(timer);
  }, []);

  return (
    <div className="mb-20 flex h-full w-full flex-col items-center md:mb-40 xl:mb-60">
      <div className="relative flex size-full flex-col items-center px-4 sm:w-[540px] md:w-[648px] lg:w-[864px] xl:w-[1080px] 2xl:w-[1296px]">
        <div className="absolute top-20 h-[100px] w-full bg-[#F8A9291F] blur-[100px]" />
        <div className="mb-6 flex w-full gap-2 rounded-full border border-[#BCBCBC1A] px-2 py-1 md:px-4 md:py-3">
          <div className="w-fit rounded-full bg-gradient-to-r from-[#F2C8481F] to-[#F8A9291F] px-4 py-1.5">
            <p className="bg-gradient-to-r from-[#F2C848] to-[#F8A929] bg-clip-text text-[10px] text-transparent md:text-xs">
              ACTIVITY
            </p>
          </div>
          <Marquee autoFill speed={30}>
            <p className="px-2 text-xs text-white md:text-sm">
              Henlo, and furthermore, ooga booga!
            </p>
          </Marquee>
        </div>
        <div className="md:grid-rows-22 xl:grid-rows-24 grid-rows-40 grid w-full grid-cols-1 gap-4 rounded-2xl border border-[#BCBCBC1A] bg-[#0A0A0A] p-2 text-white md:grid-cols-3 md:gap-6 md:p-6">
          <div className="row-span-1 md:col-span-3">
            <Guide />
          </div>
          <div className="row-span-1 md:col-span-2">
            <Updates updates={community.updates} />
          </div>
          <div className="row-span-1 md:col-span-1">
            <Follow />
          </div>
          <div className="row-span-1 md:col-span-full">
            <NewPartners partners={partners} />
          </div>
          <div className="row-span-1 md:col-span-full">
            <Mint mints={community.mints} />
          </div>
          <div className="row-span-1 md:col-span-full">
            <Blog />
          </div>
          <div className="row-span-2 md:col-span-2">
            <Spotlight spotlight={community.spotlight} />
          </div>
          <div className="row-span-3 md:col-span-1">
            <Development developments={community.developments} />
          </div>
          <div className="row-span-1 md:col-span-1">
            <OogaBooga />
          </div>
          <div className="row-span-1 md:col-span-1">
            <Feed />
          </div>
          <div className="row-span-1 md:col-span-full">
            <Portfolio partners={partners} />
          </div>
          <div className="row-span-1 md:col-span-full">
            <NFT />
          </div>
          <div className="row-span-1 md:col-span-1">
            <Quotes quoteNumber={1} />
          </div>
          <div className="row-span-3 md:col-span-1">
            <Quests />
          </div>
          <div className="row-span-2 md:col-span-1">
            <Delegate />
          </div>
          <div className="row-span-2 md:col-span-1">
            <Partners partners={partners} />
          </div>
          <div className="row-span-1 md:col-span-1">
            <Quotes quoteNumber={0} />
          </div>
          <div className="row-span-1 md:col-span-2">
            <Artwork />
          </div>
          <div className="row-span-4 md:col-span-1">
            <Data />
          </div>
          <div className="row-span-3 md:col-span-2">
            <Honeycomb perks={perks} />
          </div>
          <div className="row-span-3 md:col-span-1">
            <Raffles />
          </div>
          <div className="row-span-2 md:col-span-2">
            <Validator />
          </div>
          <div className="row-span-1 md:col-span-2">
            <Tools />
          </div>
          <div className="row-span-2 md:col-span-full">
            <Beardrops />
          </div>
        </div>
        <div className="h-px w-1/2 bg-gradient-to-r from-[#F5D01100] via-[#43AA77] via-50%" />
      </div>
    </div>
  );
};

export default BoardSection;
