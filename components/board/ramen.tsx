"use client";

import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import Image from "next/image";
import {
  AlertCircle,
  AlertTriangle,
  ArrowUpRight,
  Loader2,
} from "lucide-react";
import fetcher from "@/lib/fetcher";
import useSWR from "swr";
import { trackEvent } from "@openpanel/nextjs";
import PartnerImage from "../partner-image";

const Ramen = () => {
  const { data, error, isLoading } = useSWR<{
    projects: any;
  }>(`/api/ramen-ido`, fetcher);

  const ramenProjects = data?.projects;
  console.log(ramenProjects);
  return (
    <div className="relative h-full overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]">
      <div className="absolute -top-40 h-1 w-full" id="ramen" />
      <Carousel className="flex h-full flex-col" opts={{ dragFree: true }}>
        {/* eslint-disable-next-line tailwindcss/no-contradicting-classname */}
        <div className="flex h-2 w-full shrink-0 animate-gradient-x rounded-t-3xl bg-gradient-to-r from-white to-[#D8382B] bg-[length:200%_200%]" />
        <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-[72px] md:px-6 xl:h-20">
          <div className="flex items-center gap-3">
            <p className="whitespace-nowrap text-base font-medium text-white md:text-lg">
              Ramen IDOs
            </p>
            <div className="hidden items-center gap-2 rounded-full border border-[#272727] px-2 py-1 sm:flex">
              <p className="whitespace-nowrap text-xs font-medium uppercase text-[#BABABA]">
                Partnership
              </p>
            </div>
          </div>
          <div className="relative flex gap-1.5 md:gap-2">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
          </div>
        </div>
        {error ? (
          <div className="flex h-full w-full items-center justify-center gap-2">
            <AlertTriangle className="text-[#FFC500]" />
            Error retrieving Ramen IDOs
          </div>
        ) : isLoading ? (
          <div className="flex h-full w-full items-center justify-center gap-2">
            <Loader2 className="animate-spin text-white" />
            Loading...
          </div>
        ) : (
          <>
            {ramenProjects?.length ? (
              <CarouselContent className="mr-6 flex size-full grow p-4 md:p-6">
                {ramenProjects.map((item: any, id: number) => (
                  <CarouselItem className="" key={id}>
                    <RamenDisplay ido={item} />
                  </CarouselItem>
                ))}
                {ramenProjects.length >= 5 && (
                  <CarouselItem className="">
                    <a
                      target="_blank"
                      href={""}
                      className="relative flex h-full w-[300px] flex-col items-center justify-center overflow-hidden rounded-lg border border-[#F4C10B14] bg-[#221C11] p-4 hover:border-[#F4C10B47] hover:bg-[#423520] md:w-[400px]"
                    >
                      <p className="flex text-xs sm:text-sm md:text-base">
                        Explore All <ArrowUpRight />
                      </p>
                    </a>
                  </CarouselItem>
                )}
              </CarouselContent>
            ) : (
              <div className="flex h-full w-full items-center justify-center gap-2">
                <AlertCircle className="text-[#D8382B]" />
                No upcoming launches
              </div>
            )}
          </>
        )}
      </Carousel>
    </div>
  );
};

export default Ramen;

const RamenDisplay = ({ ido }: { ido: any }) => {
  function formatBera(wei: bigint, decimals: number = 4) {
    const bera: number = Number(wei) / 1_000_000_000_000_000_000;
    return bera.toFixed(decimals);
  }

  return (
    <a
      href={`https://app.ramen.finance/${ido.slug}`}
      target="_blank"
      onClick={() => {
        trackEvent(`ramen_${ido.slug}`);
      }}
      className="relative flex h-full w-[300px] flex-col justify-between overflow-hidden rounded-lg border border-[#F4C10B14] bg-[#221C11] p-4 hover:divide-[#F4C10B47] hover:border-[#F4C10B47] hover:bg-[#423520] md:w-[400px]"
    >
      <div className="absolute bottom-0 left-0 z-10 h-1/2 w-full bg-gradient-to-t from-[#000000]" />
      <div className="absolute left-0 top-0 size-full">
        <Image
          src={ido.token_icon_url}
          alt=""
          fill
          className="z-0 object-cover"
        />
      </div>
      <div className="z-10 flex items-center justify-start gap-2">
        {/* <div className="rounded-full bg-[#D8D8D8]/10 px-3 py-1">
          <p className="text-xs font-light text-[#E2E2E2]">
            <span className="font-normal text-white">{ido.total_supply}</span>{" "}
            total supply
          </p>
        </div> */}
      </div>
      <div className="z-10 flex w-full items-start justify-between">
        <div className="flex flex-col gap-1">
          <p className="text-sm text-[#FBFBFB] md:text-base">
            {ido?.name ?? "Unknown"}
          </p>
          <div className="flex items-center gap-2">
            <div className="relative aspect-square h-[20px]">
              <PartnerImage
                src={"faucet/quests/ramen_logo.svg"}
                alt="logo"
                fill
                className="rounded-full"
              />
            </div>
            <p className="whitespace-nowrap text-xs text-[#9E9E9E]">
              By Ramen Finance
            </p>
          </div>
        </div>
        <div className="flex items-center gap-1">
          <div className="relative aspect-square h-4">
            <Image src={"/BERA.svg"} alt="bera" fill />
          </div>
          <p className="text-sm font-semibold text-white md:text-lg">
            {formatBera(ido.token_price_in_bera)}
          </p>
        </div>
      </div>
    </a>
  );
};
