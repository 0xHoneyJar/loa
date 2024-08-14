"use client";

import { trackEvent } from "@openpanel/nextjs";
import Image from "next/image";
import Marquee from "react-fast-marquee";

const Footer = () => {
  return (
    <div className="relative flex size-full flex-col items-center">
      <div className="absolute -top-72 z-[-1] flex aspect-square h-[1000px] items-center justify-center rounded-full border border-[#F5D01105] p-4">
        <div className="absolute -top-20 h-[100px] w-1/4 bg-[#43AA7780] blur-[100px]" />
        <div className="flex size-[95%] items-center justify-center rounded-full border border-[#F5D0110D]">
          <div className="flex size-[90%] items-center justify-center rounded-full border border-[#F5D0110D]">
            <div className="flex size-[90%] items-center justify-center rounded-full border border-[#F5D0110D]">
              <div className="flex size-[90%] items-center justify-center rounded-full border border-[#F5D0110D]">
                <div className="size-1/2 bg-[#F8A9291F] blur-[80px]" />
              </div>
            </div>
          </div>
        </div>
      </div>
      <div className="relative top-0 z-[-1] hidden h-[198px] w-full overflow-hidden border-b border-dashed border-[#878787] md:flex">
        <Marquee autoFill className="relative overflow-hidden">
          <p
            className="text-[12rem] font-bold leading-none text-[#F5D0110D] lg:text-[17rem]"
            style={{
              WebkitTextStroke: "1px #F5D01145",
            }}
          >
            Based Community Gateway on Berachain
          </p>
        </Marquee>
      </div>
      <div className="relative mt-24 grid size-full h-auto grid-cols-1 gap-2 bg-[#0B0701] text-white sm:h-[300px] md:mt-0 md:h-[400px] md:grid-cols-3 xl:mx-auto xl:max-w-7xl">
        <div className="absolute inset-x-0 -top-12 mx-auto aspect-square h-[60px] md:-top-16 md:h-[80px]">
          <Image
            src={"/jani-coin.png"}
            alt="jani-coin"
            fill
            className="object-contain"
          />
        </div>
        <div className="flex size-full flex-col items-center justify-center border-t border-dashed border-[#DCE0E5] px-4 py-10 text-white sm:items-start md:border-t-0 md:px-8 md:py-0">
          <p className="mb-2 font-clash text-lg font-semibold md:text-xl">
            Partnership Guidelines
          </p>
          <p className="mb-4 w-full text-center text-xs text-white/75 sm:text-left md:w-[90%] md:text-sm">
            Learn what you get from becoming a THJ Partner
          </p>
          <a
            target="_blank"
            onClick={() => {
              trackEvent(`learn_more_partners_footer`);
            }}
            href={"https://partners.0xhoneyjar.xyz/"}
            className="flex w-fit whitespace-nowrap rounded-xl border border-[#FEFEFE1A] px-6 py-1.5 text-sm text-[#DBDBDB] transition-all duration-500 ease-in-out hover:border-[#E8E8E80F] hover:bg-[#FFFFFF3D]"
          >
            Learn More
          </a>
        </div>
        <div className="relative flex size-full flex-col items-center justify-center border-y border-dashed border-[#DCE0E5] px-4 py-10 text-white sm:items-start sm:border-x sm:border-y-0 md:px-8 md:py-0">
          <p className="mb-2 whitespace-nowrap font-clash text-lg font-semibold md:text-xl">
            Branding Kit
          </p>
          <p className="mb-4 w-full text-center text-xs text-white/75 sm:text-left md:w-[90%] md:text-sm">
            Find all assets and guidelines of THJ branding here
          </p>
          <a
            href={"https://docs.0xhoneyjar.xyz/docs/branding"}
            target="_blank"
            onClick={() => {
              trackEvent(`learn_more_branding_footer`);
            }}
            className="flex w-fit whitespace-nowrap rounded-xl border border-[#FEFEFE1A] px-6 py-1.5 text-sm text-[#DBDBDB] transition-all duration-500 ease-in-out hover:border-[#E8E8E80F] hover:bg-[#FFFFFF3D]"
          >
            Learn More
          </a>
        </div>
        <div className="flex size-full flex-col items-center justify-center px-4 py-10 text-white sm:items-start md:px-8 md:py-0">
          <p className="mb-2 whitespace-nowrap font-clash text-lg font-semibold md:text-xl">
            Beekeeper Kit
          </p>
          <p className="mb-4 w-full text-center text-xs text-white/75 sm:text-left md:w-[90%] md:text-sm">
            Product suite, integrations and co-markerting guidelines
          </p>
          <a
            target="_blank"
            href={"https://docs.cubquests.com/"}
            onClick={() => {
              trackEvent(`learn_more_beekeeper_footer`);
            }}
            className="flex w-fit whitespace-nowrap rounded-xl border border-[#FEFEFE1A] px-6 py-1.5 text-sm text-[#DBDBDB] transition-all duration-500 ease-in-out hover:border-[#E8E8E80F] hover:bg-[#FFFFFF3D]"
          >
            Learn More
          </a>
        </div>
      </div>
      <div className="relative flex h-auto w-full flex-col items-center gap-4 overflow-hidden bg-[#F4C10B] pt-10 text-white md:gap-6 md:pt-20">
        <Image
          src={"/thj-outline.svg"}
          alt="thj-outline"
          fill
          className="!top-10 z-[1] object-cover md:object-contain"
        />
        <div className="relative aspect-square h-[60px] sm:h-[80px] md:h-[100px]">
          <Image
            src={"/thj-white.svg"}
            alt="thj-white"
            fill
            className="object-contain"
          />
        </div>
        <p className="text-center font-clash text-3xl font-semibold md:text-5xl">
          Be a Part of the Honey Jar
        </p>
        <p className="w-4/5 text-center text-sm sm:w-3/5 md:w-2/5 md:text-lg">
          By delegating to the THJ Validator, you help us to grow and contribute
        </p>
        <div className="relative flex flex-col items-center gap-2 sm:flex-row">
          <a
            href={"https://discord.com/invite/thehoneyjar"}
            target="_blank"
            onClick={() => {
              trackEvent(`join_discord_footer`);
            }}
            className="z-10 flex w-[180px] justify-center rounded-xl bg-black py-3 text-xs font-medium transition-all duration-500 ease-in-out hover:bg-white hover:text-black md:w-[240px] md:text-base"
          >
            Join the Commmunity
          </a>
          <a
            href={
              "https://bartio.station.berachain.com/delegate?action=delegate&validator=0x40495A781095932e2FC8dccA69F5e358711Fdd41"
            }
            target="_blank"
            onClick={() => {
              trackEvent(`delegate_footer`);
            }}
            className="z-10 flex w-[180px] justify-center rounded-xl bg-[#43AA77] py-3 text-xs font-medium transition-all duration-500 ease-in-out hover:bg-[#086134] md:w-[240px] md:text-base"
          >
            <p>Delegate Now</p>
          </a>
          <div className="absolute -bottom-24 -right-32 z-10 aspect-square h-[140px] md:-bottom-28 md:-right-40 md:h-[172px]">
            <Image
              src={"/arrow-angled.svg"}
              alt="angled"
              fill
              className="object-contain"
            />
          </div>
        </div>
        <div className="relative z-10 aspect-[1/1.9] h-[165px]">
          <Image
            src={"/jani-sweep.gif"}
            alt="sweep"
            fill
            className="object-cover"
            unoptimized={true}
          />
        </div>
      </div>
    </div>
  );
};

export default Footer;
