import {
  ArrowUpRight,
  Coins,
  Gamepad2,
  Hexagon,
  Landmark,
  Pyramid,
  Users,
} from "lucide-react";
import Image from "next/image";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import { useState, useMemo, useEffect } from "react";
import DragHandleY from "../drag-handle-y";
import S3Image from "@/components/s3-image";
import { formatEther } from "viem";

const Honeycomb = ({ perks }: { perks?: any }) => {
  const [glow, setGlow] = useState(false);
  const [honeycombData, setHoneycombData] = useState<any>(null);

  const activePerksCount = useMemo(() => {
    if (!perks) return 0;
    const currentDate = new Date();

    const perksWithDate = perks.filter((perk: any) => perk.startDate);

    const activePerks = perksWithDate.filter((perk: any) => {
      const startDate = new Date(perk.startDate);
      if (perk.endDate) {
        const endDate = new Date(perk.endDate);
        return startDate <= currentDate && currentDate <= endDate;
      } else {
        return startDate <= currentDate;
      }
    });

    return activePerks.length;
  }, [perks]);

  const options = {
    method: "GET",
    headers: {
      accept: "application/json",
      "X-API-KEY": process.env.NEXT_PUBLIC_SIMPLEHASH_API_KEY ?? "",
    },
  };

  useEffect(() => {
    async function fetchHoneycomb() {
      const res = await fetch(
        `https://api.simplehash.com/api/v0/nfts/collections/ids?collection_ids=5d0a382e24d6a4983ca7932e20f66cd3`,
        options,
      );

      const data = await res.json();
      setHoneycombData(data.collections[0]);
    }

    fetchHoneycomb();
  }, []);

  return (
    <div
      className={`${glow && "rotate-1"} relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="honeycomb" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-[72px] md:px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#FFC500] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandleY setGlow={setGlow} />
          <p className="text-sm font-medium text-[#FFD700] md:text-base">
            Honeycomb
          </p>
        </div>
        <div className="relative aspect-square h-[34px] rounded-full border border-[#353535]">
          <Image
            src={"/opensea.svg"}
            alt="opensea"
            fill
            className="object-contain p-1"
          />
        </div>
      </div>
      <div className="flex size-full grow flex-col">
        <div className="flex size-full flex-col gap-4 p-4 md:p-6">
          <div className="relative flex h-[200px] w-full items-center justify-center overflow-hidden rounded-xl sm:h-[230px] md:h-[250px] md:justify-end">
            <Image
              src={"/honeycomb.png"}
              alt="honeycomb"
              fill
              className="object-cover"
            />
            <div className="z-10 flex w-4/5 flex-col gap-4 md:w-3/5 md:pr-12">
              <p className="text-center text-xs text-[#D1D1D1] md:text-left md:text-sm">
                Honeycomb is an anti-hustle tech and a perk aggregator of the
                Berachain eco. It gives you whitelist to most projects in the
                ecosystem
              </p>
              <a
                target="_blank"
                href={"https://pro.opensea.io/collection/honey-comb-2"}
                rel="noopener noreferrer"
                className="flex cursor-blue items-center justify-center gap-2 whitespace-nowrap rounded-lg border border-[#1E1E1E] bg-[#0F0D08] py-2 hover:border-[#363636] hover:bg-[#14130f] md:py-3"
              >
                <div className="relative aspect-square h-5 rounded-full md:h-[26px]">
                  <Image
                    src={"/opensea.svg"}
                    alt="opensea"
                    fill
                    className="object-contain p-1"
                  />
                </div>
                <p className="text-xs md:text-sm">Buy a Honeycomb</p>
              </a>
            </div>
          </div>
          <Carousel className="flex h-[200px] w-full sm:h-[230px] md:h-[250px]">
            {/* <div className="flex h-full w-full"> */}
            <CarouselContent className="flex grow md:-ml-6 xl:-ml-0 xl:grid xl:!transform-none xl:grid-cols-4 xl:gap-4 2xl:gap-6">
              <CarouselItem className="basis-full sm:basis-1/2 md:pl-6 xl:pl-0">
                <div className="relative flex size-full flex-col items-center rounded-lg border border-[#F5D0110A] bg-[#15120B] py-8">
                  <div className="absolute top-0 h-[2px] w-8 rounded-full bg-[#EE511E]" />
                  <p className="whitespace-nowrap text-sm text-[#6B6B6B] md:text-base">
                    Total Perks
                  </p>
                  <div className="flex size-full items-center justify-center">
                    <p className="bg-gradient-to-r from-[#F5D011] to-[#F8A929] bg-clip-text text-5xl font-medium text-transparent md:text-6xl xl:text-7xl">
                      {perks.length}
                    </p>
                  </div>
                </div>
              </CarouselItem>
              <CarouselItem className="basis-full sm:basis-1/2 md:pl-6 xl:pl-0">
                <div className="relative flex size-full flex-col items-center rounded-lg border border-[#F5D0110A] bg-[#15120B] py-8">
                  <div className="absolute top-0 h-[2px] w-8 rounded-full bg-[#EE511E]" />
                  <p className="whitespace-nowrap text-sm text-[#6B6B6B] md:text-base">
                    Active Perks
                  </p>
                  <div className="flex size-full items-center justify-center">
                    <p className="bg-gradient-to-r from-[#F5D011] to-[#F8A929] bg-clip-text text-5xl font-medium text-transparent md:text-6xl xl:text-7xl">
                      {activePerksCount}
                    </p>
                  </div>
                </div>
              </CarouselItem>
              <CarouselItem className="basis-full sm:basis-1/2 md:pl-6 xl:pl-0">
                <div className="grid size-full gap-3 md:gap-4 2xl:gap-6">
                  <div className="relative flex size-full flex-col items-center justify-center overflow-hidden rounded-lg border border-[#F5D0110A] bg-[#15120B]">
                    <div className="absolute top-0 h-[2px] w-8 rounded-full bg-[#EE511E]" />
                    <p className="text-[10px] text-[#6B6B6B] md:text-xs">
                      Floor Price
                    </p>
                    <div className="flex items-center gap-2">
                      <div className="relative aspect-square h-[16px]">
                        <Image
                          src={"/floor-price.svg"}
                          alt="floor-price"
                          fill
                          className="object-contain"
                        />
                      </div>
                      <p className="whitespace-nowrap text-xs font-medium md:text-sm">
                        {honeycombData?.floor_prices?.[1]?.value
                          ? Number(
                              formatEther(honeycombData.floor_prices[1].value),
                            ).toFixed(3)
                          : "N/A"}
                        <span className="font-normal">&nbsp;ETH</span>
                      </p>
                    </div>
                  </div>
                  {/* <div className="relative flex h-full w-full flex-col items-center justify-center overflow-hidden rounded-lg border border-[#F5D0110A] bg-[#15120B]">
                    <div className="absolute top-0 h-[2px] w-8 rounded-full bg-[#EE511E]" />
                    <p className="text-[10px] text-[#6B6B6B] md:text-xs xl:text-sm">
                      Perk Value
                    </p>
                    <div className="flex items-center gap-2">
                      <div className="relative aspect-square h-[16px]">
                        <Image
                          src={"/gem.svg"}
                          alt="gem"
                          fill
                          className="object-contain"
                        />
                      </div>
                      <p className="text-xs font-medium md:text-sm xl:text-base">
                        333,286.24
                      </p>
                    </div>
                  </div> */}
                </div>
              </CarouselItem>
              <CarouselItem className="basis-full sm:basis-1/2 md:pl-6 xl:pl-0">
                <div className="grid size-full gap-3 md:gap-4 2xl:gap-6">
                  <div className="relative flex size-full flex-col items-center justify-center overflow-hidden rounded-lg border border-[#F5D0110A] bg-[#15120B]">
                    <div className="absolute top-0 h-[2px] w-8 rounded-full bg-[#EE511E]" />
                    <p className="text-[10px] text-[#6B6B6B] md:text-xs xl:text-sm">
                      Holders
                    </p>
                    <div className="flex items-center gap-2">
                      <div className="relative aspect-square h-[16px]">
                        <Image
                          src={"/holder.svg"}
                          alt="holder"
                          fill
                          className="object-contain"
                        />
                      </div>
                      <p className="text-xs font-medium md:text-sm xl:text-base">
                        {honeycombData?.distinct_owner_count ?? 0}
                      </p>
                    </div>
                  </div>
                  {/* <div className="relative flex h-full w-full flex-col items-center justify-center overflow-hidden rounded-lg border border-[#F5D0110A] bg-[#15120B]">
                    <div className="absolute top-0 h-[2px] w-8 rounded-full bg-[#EE511E]" />
                    <p className="text-[10px] text-[#6B6B6B] md:text-xs xl:text-sm">
                      Perks Value
                    </p>
                    <p className="flex items-center gap-2">
                      <span className="text-sm">$</span>
                      <p className="text-xs font-medium md:text-sm xl:text-base">
                        333,286.24
                      </p>
                    </p>
                  </div> */}
                </div>
              </CarouselItem>
            </CarouselContent>
            {/* </div> */}
          </Carousel>
          <a
            target="_blank"
            href={"https://honeycomb.0xhoneyjar.xyz/"}
            className="flex w-full items-center justify-between rounded-lg bg-[#F4C10B]/10 px-6 py-3 text-[#F4C10B] hover:cursor-blue hover:bg-[#F4C10B] hover:font-semibold hover:text-[#121212]"
          >
            <p className="text-sm md:text-base">Visit Honeycomb Dashboard</p>
            <ArrowUpRight className="aspect-square h-5 md:h-6" />
          </a>
        </div>
        <Carousel className="flex h-full flex-col" opts={{ dragFree: true }}>
          <div className="flex items-center justify-between border-y border-dashed border-[#FEFEFE14] px-6 py-4">
            <p className="text-sm text-white md:text-base">Recent Perks</p>
            <div className="relative flex gap-1.5 md:gap-2">
              <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
              <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
            </div>
          </div>
          <CarouselContent className="mr-6 flex size-full grow py-4 pl-4 md:py-6 md:pl-6">
            {perks.map((perk: any, id: any) => (
              <CarouselItem key={id}>
                <a
                  target="_blank"
                  href={perk.link}
                  className="relative flex h-full w-[210px] flex-col items-center justify-around overflow-hidden rounded-lg border border-[#F4C10B1F] bg-[#18140C] p-4 text-[#C4C4C4] hover:cursor-blue hover:border-[#F4C10B38] hover:bg-[#332200] hover:font-medium hover:text-white/90"
                >
                  <div className="mt-2 flex flex-col items-center justify-center gap-2">
                    <div className="relative aspect-square h-[54px] rounded-full border border-[#F4C10B1F] bg-[#18140C05] md:h-[64px]">
                      {perk.partner?.logo ? (
                        <S3Image
                          src={perk.partner.logo}
                          alt={perk._title}
                          fill
                          className="rounded-full object-cover p-1"
                        />
                      ) : (
                        <Image
                          src={"/partners/sleuth.png"}
                          alt={perk._title}
                          fill
                          className="object-contain p-2"
                        />
                      )}
                    </div>
                    <p className="text-center text-sm">{perk._title}</p>
                    <div className="rounded-full bg-gradient-to-r from-[#F8A929]/5 to-[#F5D011]/5 px-4 py-1">
                      <p className="text-xs font-light text-[#F8A929]">
                        {perk.perks}
                      </p>
                    </div>
                  </div>
                </a>
              </CarouselItem>
            ))}
          </CarouselContent>
        </Carousel>
      </div>
    </div>
  );
};

export default Honeycomb;
