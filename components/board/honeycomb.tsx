import { ArrowUpRight } from "lucide-react";
import Image from "next/image";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import { PERKS } from "@/constants/perks";
import { useState } from "react";
import DragHandleY from "../drag-handle-y";

const Honeycomb = () => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-1"} relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="honeycomb" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-[72px] md:px-6 xl:h-20">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#FFC500] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandleY setGlow={setGlow} />
          <p className="text-sm font-medium text-[#FFD700] md:text-base xl:text-xl">
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
      <div className="flex h-full w-full grow flex-col">
        <div className="flex h-full w-full flex-col gap-4 p-4 md:p-6">
          <div className="relative flex h-[200px] w-full items-center justify-center overflow-hidden rounded-xl sm:h-[230px] md:h-[250px] md:justify-end">
            <Image
              src={"/honeycomb.png"}
              alt="honeycomb"
              fill
              className="object-cover"
            />
            <div className="z-10 flex w-4/5 flex-col gap-4 md:w-3/5 md:pr-12 xl:w-1/2">
              <p className="text-center text-xs text-[#D1D1D1] md:text-left md:text-sm xl:text-base">
                Honeycomb is an anti-hustle tech and a perk aggregator of the
                Berachain eco. It gives you whitelist to most projects in the
                ecosystem
              </p>
              <button className="flex items-center justify-center gap-2 whitespace-nowrap rounded-lg border border-[#1E1E1E] bg-[#0F0D08] py-2 md:py-3">
                <div className="relative aspect-square h-5 rounded-full md:h-[26px]">
                  <Image
                    src={"/opensea.svg"}
                    alt="opensea"
                    fill
                    className="object-contain p-1"
                  />
                </div>
                <p className="text-xs md:text-sm xl:text-base">
                  Buy a Honeycomb
                </p>
              </button>
            </div>
          </div>
          <Carousel className="flex h-[200px] w-full sm:h-[230px] md:h-[250px]">
            {/* <div className="flex h-full w-full"> */}
            <CarouselContent className="flex grow md:-ml-6 xl:-ml-0 xl:grid xl:!transform-none xl:grid-cols-4 xl:gap-4 2xl:gap-6">
              <CarouselItem className="basis-full sm:basis-1/2 md:pl-6 xl:pl-0">
                <div className="relative flex h-full w-full flex-col items-center rounded-lg border border-[#F5D0110A] bg-[#15120B] py-8">
                  <div className="absolute top-0 h-[2px] w-8 rounded-full bg-[#EE511E]" />
                  <p className="whitespace-nowrap text-sm text-[#6B6B6B] md:text-base xl:text-lg">
                    Total Perks
                  </p>
                  <div className="flex h-full w-full items-center justify-center">
                    <p className="bg-gradient-to-r from-[#F5D011] to-[#F8A929] bg-clip-text text-5xl font-medium text-transparent md:text-6xl xl:text-7xl">
                      94
                    </p>
                  </div>
                </div>
              </CarouselItem>
              <CarouselItem className="basis-full sm:basis-1/2 md:pl-6 xl:pl-0">
                <div className="relative flex h-full w-full flex-col items-center rounded-lg border border-[#F5D0110A] bg-[#15120B] py-8">
                  <div className="absolute top-0 h-[2px] w-8 rounded-full bg-[#EE511E]" />
                  <p className="whitespace-nowrap text-sm text-[#6B6B6B] md:text-base xl:text-lg">
                    Active Perks
                  </p>
                  <div className="flex h-full w-full items-center justify-center">
                    <p className="bg-gradient-to-r from-[#F5D011] to-[#F8A929] bg-clip-text text-5xl font-medium text-transparent md:text-6xl xl:text-7xl">
                      78
                    </p>
                  </div>
                </div>
              </CarouselItem>
              <CarouselItem className="basis-full sm:basis-1/2 md:pl-6 xl:pl-0">
                <div className="grid h-full w-full grid-rows-2 gap-3 md:gap-4 2xl:gap-6">
                  <div className="relative flex h-full w-full flex-col items-center justify-center overflow-hidden rounded-lg border border-[#F5D0110A] bg-[#15120B]">
                    <div className="absolute top-0 h-[2px] w-8 rounded-full bg-[#EE511E]" />
                    <p className="text-[10px] text-[#6B6B6B] md:text-xs xl:text-sm">
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
                      <p className="whitespace-nowrap text-xs md:text-sm xl:text-base">
                        333,286.24 ETH
                      </p>
                    </div>
                  </div>
                  <div className="relative flex h-full w-full flex-col items-center justify-center overflow-hidden rounded-lg border border-[#F5D0110A] bg-[#15120B]">
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
                      <p className="text-xs md:text-sm xl:text-base">
                        333,286.24
                      </p>
                    </div>
                  </div>
                </div>
              </CarouselItem>
              <CarouselItem className="basis-full sm:basis-1/2 md:pl-6 xl:pl-0">
                <div className="grid h-full w-full grid-rows-2 gap-3 md:gap-4 2xl:gap-6">
                  <div className="relative flex h-full w-full flex-col items-center justify-center overflow-hidden rounded-lg border border-[#F5D0110A] bg-[#15120B]">
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
                      <p className="text-xs md:text-sm xl:text-base">413,425</p>
                    </div>
                  </div>
                  <div className="relative flex h-full w-full flex-col items-center justify-center overflow-hidden rounded-lg border border-[#F5D0110A] bg-[#15120B]">
                    <div className="absolute top-0 h-[2px] w-8 rounded-full bg-[#EE511E]" />
                    <p className="text-[10px] text-[#6B6B6B] md:text-xs xl:text-sm">
                      Perks Value
                    </p>
                    <p className="flex items-center gap-2">
                      <span className="text-sm">$</span>
                      <p className="text-xs md:text-sm xl:text-base">
                        333,286.24
                      </p>
                    </p>
                  </div>
                </div>
              </CarouselItem>
            </CarouselContent>
            {/* </div> */}
          </Carousel>
          <button className="flex w-full items-center justify-between rounded-lg bg-[#F4C10B]/10 px-6 py-3 text-[#F4C10B] hover:cursor-blue hover:bg-[#F4C10B] hover:font-semibold hover:text-[#121212]">
            <p className="text-sm md:text-base xl:text-lg">
              Visit Honeycomb Dashboard
            </p>
            <ArrowUpRight className="aspect-square h-5 md:h-6 xl:h-[28px]" />
          </button>
        </div>
        <Carousel className="flex h-full flex-col" opts={{ dragFree: true }}>
          <div className="flex items-center justify-between border-y border-dashed border-[#FEFEFE14] px-6 py-4">
            <p className="text-sm text-white md:text-base xl:text-lg">
              Recent Perks
            </p>
            <div className="relative flex gap-1.5 md:gap-2 xl:gap-3">
              <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7 xl:h-8 xl:w-8" />
              <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7 xl:h-8 xl:w-8" />
            </div>
          </div>
          <CarouselContent className="flex h-full w-full py-6 pl-6">
            {PERKS.map((item, id) => (
              <CarouselItem key={id}>
                <div className="relative flex h-full w-[210px] flex-col items-center justify-around rounded-lg border border-[#F4C10B0F] bg-[#18140C] py-4 text-[#C4C4C4] hover:cursor-blue hover:border-[#F4C10B38] hover:bg-[#332200] hover:font-medium hover:text-white/90">
                  <div className="mt-2 flex flex-col items-center gap-2">
                    <div className="relative aspect-square h-[54px] rounded-full border border-[#F4C10B0F] bg-[#18140C05]">
                      <Image
                        src={item.image}
                        alt={item.name}
                        fill
                        className="object-contain p-2"
                      />
                    </div>
                    <p className="text-sm">{item.name}</p>
                    <div className="rounded-full bg-gradient-to-r from-[#F8A929]/5 to-[#F5D011]/5 px-4 py-1">
                      <p className="text-xs font-light text-[#F8A929]">
                        Perks Type
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-1">
                    <div className="relative aspect-square h-[14px] rounded-full bg-purple-500"></div>
                    <p className="text-[8px] text-[#A8A8A8]">The Lorem Ip</p>
                  </div>
                </div>
              </CarouselItem>
            ))}
          </CarouselContent>
        </Carousel>
      </div>
    </div>
  );
};

export default Honeycomb;
