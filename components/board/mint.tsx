"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import S3Image from "@/components/s3-image";
import { trackEvent } from "@openpanel/nextjs";
import PartnerImage from "../partner-image";
import useSWR from "swr";
import fetcher from "@/lib/fetcher";
import Marquee from "react-fast-marquee";
import { NewMintButton } from "../ui/buttons";
import { AlertTriangle, Loader2 } from "lucide-react";

const Mint = ({ mints }: { mints?: any }) => {
  const { data, error, isLoading } = useSWR<{
    mints: any;
  }>(`/api/kingdomly-mints`, fetcher);

  return (
    <div className="relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#EE511E]/10 from-[12%] via-[#F8A929]/10 via-[38%] to-[#141310]/10">
      <div className="absolute -top-40 h-1 w-full" id="mint" />
      {/* eslint-disable-next-line tailwindcss/no-contradicting-classname */}
      <div className="animate-gradient-x flex h-2 w-full shrink-0 rounded-t-3xl bg-gradient-to-r from-[#FFD700] via-[#FF7F0B] via-60% to-[#FF4C12] bg-[length:200%_200%]" />
      <div className="flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-[72px] md:px-6">
        <div className="flex items-center gap-2">
          <p className="whitespace-nowrap text-base font-medium text-[#FFD700] md:text-lg">
            New Mints
          </p>
          <div className="rounded-full border border-[#EBEBEB]/10 px-2 py-1">
            <p className="text-xs font-normal">Partners Collection</p>
          </div>
        </div>
      </div>
      <div className="relative flex h-full w-full flex-col">
        <div className="relative flex w-full grow flex-col gap-6 py-4">
          {error ? (
            <div className="flex h-full w-full items-center justify-center gap-2">
              <AlertTriangle className="text-[#FFC500]" />
              Error retrieving partners mints
            </div>
          ) : isLoading ? (
            <div className="flex h-full w-full items-center justify-center gap-2">
              <Loader2 className="animate-spin text-white" />
              Loading...
            </div>
          ) : (
            <>
              <div className="absolute left-0 top-0 z-10 h-full w-16 bg-gradient-to-r from-[#0D0803]" />
              <div className="absolute right-0 top-0 z-10 h-full w-16 bg-gradient-to-l from-[#0D0803]" />
              <Marquee autoFill speed={25} className="h-1/2">
                {mints.items.map((mint: any) => (
                  <div
                    key={mint._title}
                    className="mr-6 flex h-full w-[300px] grow md:w-[400px]"
                  >
                    <MintDisplay mint={mint} />
                  </div>
                ))}
              </Marquee>
              <Marquee autoFill speed={25} direction="right" className="h-1/2">
                {data?.mints.live.length > 0 ? (
                  data?.mints.live.map((mint: any) => (
                    <div
                      key={mint._title}
                      className="mr-6 flex h-full w-[300px] grow md:w-[400px]"
                    >
                      <KingdomlyMintDisplay mint={mint} />
                    </div>
                  ))
                ) : (
                  <div className="mr-6 flex h-full w-[300px] grow md:w-[400px]">
                    <div className="relative flex h-full w-full items-center justify-center overflow-hidden rounded-lg border border-[#F4C10B14] bg-[#221C11] p-4 hover:border-[#F4C10B47] hover:bg-[#423520]">
                      <p>No live mints found</p>
                    </div>
                  </div>
                )}
              </Marquee>
            </>
          )}
        </div>
        <div className="w-full border-t border-[#F4C10B]/10 p-6">
          <NewMintButton />
        </div>
      </div>
    </div>
  );
};

export default Mint;

// New component to handle time calculation
const TimeLeft = ({ endDate }: { endDate: number }) => {
  const [timeLeft, setTimeLeft] = useState<string>("");

  useEffect(() => {
    const timer = setInterval(() => {
      const now = Math.floor(Date.now() / 1000); // Current time in seconds
      const difference = endDate - now;

      if (difference <= 0) {
        setTimeLeft("Ended");
        clearInterval(timer);
      } else {
        const days = Math.floor(difference / (60 * 60 * 24));
        const hours = Math.floor((difference % (60 * 60 * 24)) / (60 * 60));
        const minutes = Math.floor((difference % (60 * 60)) / 60);

        setTimeLeft(`${days}d ${hours}h ${minutes}m`);
      }
    }, 1000);

    return () => clearInterval(timer);
  }, [endDate]);

  return (
    <div className="rounded-full bg-[#D8D8D8]/10 px-3 py-1">
      <p className="text-xs font-light text-[#E2E2E2]">
        <span className="font-normal text-white">{timeLeft}</span> left
      </p>
    </div>
  );
};

const MintDisplay = ({ mint }: { mint: any }) => (
  <a
    href={mint.link}
    target="_blank"
    onClick={() => {
      trackEvent(`${mint._title}_mint`);
    }}
    className="relative flex h-full w-full flex-col justify-between overflow-hidden rounded-lg border border-[#F4C10B14] bg-[#221C11] p-4 hover:border-[#F4C10B47] hover:bg-[#423520]"
  >
    <div className="absolute left-0 top-0 size-full bg-[#0a0500]">
      <S3Image
        src={mint.image}
        alt=""
        fill
        className="z-0 object-cover opacity-25"
      />
    </div>
    <div className="z-10 flex items-center justify-start gap-2">
      {mint.endDate && <TimeLeft endDate={mint.endDate} />}
      <div className="rounded-full bg-[#D8D8D8]/10 px-3 py-1">
        <p className="text-xs font-light text-[#E2E2E2]">
          <span className="font-normal text-white">{mint.supply}</span> total
          supply
        </p>
      </div>
    </div>
    <div className="z-10 flex w-full items-start justify-between">
      <div className="flex flex-col gap-1">
        <p className="text-sm text-[#FBFBFB] md:text-base">{mint._title}</p>
        <div className="flex items-center gap-2">
          <div className="relative aspect-square h-[20px]">
            <PartnerImage
              src={mint.partner.logo}
              alt="logo"
              fill
              className="rounded-full"
            />
          </div>
          <p className="whitespace-nowrap text-xs text-[#9E9E9E]">
            By {mint.partner._title}
          </p>
        </div>
      </div>
      {/* <div className="flex flex-col items-end"> */}
      <div className="flex items-center gap-1">
        <div className="relative aspect-square h-4">
          <Image src={"/eth.svg"} alt="eth" fill />
        </div>
        <p className="text-sm font-semibold text-white md:text-lg">
          {mint.price}
        </p>
      </div>
      {/* <p className="text-[8px] text-[#BABABA]">$123,145.00</p> */}
      {/* </div> */}
    </div>
  </a>
);

const KingdomlyMintDisplay = ({ mint }: { mint: any }) => (
  <a
    href={`https://www.kingdomly.app/${mint.slug}`}
    target="_blank"
    onClick={() => {
      trackEvent(`kingdomly_${mint.slug}_mint`);
    }}
    className="relative flex h-full w-full flex-col justify-between overflow-hidden rounded-lg border border-[#F4C10B14] bg-[#221C11] p-4 hover:divide-[#F4C10B47] hover:border-[#F4C10B47] hover:bg-[#423520]"
  >
    <div className="absolute left-0 top-0 size-full bg-[#0a0500]">
      <Image
        src={mint.profile_image}
        alt=""
        fill
        className="z-0 object-cover opacity-25"
      />
    </div>
    <div className="z-10 flex items-center justify-start gap-2">
      <div className="rounded-full bg-[#D8D8D8]/10 px-3 py-1">
        <p className="text-xs font-light text-[#E2E2E2]">
          <span className="font-normal text-white">{mint.total_supply}</span>{" "}
          total supply
        </p>
      </div>
    </div>
    <div className="z-10 flex w-full items-start justify-between">
      <div className="flex flex-col gap-1">
        <p className="text-sm text-[#FBFBFB] md:text-base">
          {mint?.title ?? "Unknown"}
        </p>
        <div className="flex items-center gap-2">
          <div className="relative aspect-square h-[20px]">
            <PartnerImage
              src={"faucet/quests/kingdomly.png"}
              alt="logo"
              fill
              className="rounded-full"
            />
          </div>
          <p className="whitespace-nowrap text-xs text-[#9E9E9E]">
            By Kingdomly
          </p>
        </div>
      </div>
      {/* <div className="flex flex-col items-end"> */}
      <div className="flex items-center gap-1">
        <div className="relative aspect-square h-4">
          <Image src={"/eth.svg"} alt="eth" fill />
        </div>
        <p className="text-sm font-semibold text-white md:text-lg">
          {mint.mint_group_data[0].price}
        </p>
      </div>
      {/* <p className="text-[8px] text-[#BABABA]">$123,145.00</p> */}
      {/* </div> */}
    </div>
  </a>
);
