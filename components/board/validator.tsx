import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselNext,
  CarouselPrevious,
} from "@/components/ui/carousel";
import fetcher from "@/lib/fetcher";
import { formatToken } from "@/lib/utils";
import Image from "next/image";
import { useState } from "react";
import {
  CircularProgressbarWithChildren,
  buildStyles,
} from "react-circular-progressbar";
import useSWR from "swr";
import DragHandle from "../drag-handle";

const Validator = () => {
  const { data } = useSWR<{
    amountDelegated: string;
    boostedRewardRate: string;
  }>("/api/validator", fetcher);

  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-1"} relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#121A12] bg-[#10120D]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="validator" />
      <Carousel className="flex size-full flex-col">
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#43AA77]" />
        <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#1B271B] px-4 md:h-[72px] md:px-6 xl:h-20">
          <div
            className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#43AA77] blur-2xl ${glow ? "flex" : "hidden"}`}
          />
          <div className="flex items-center gap-2">
            <DragHandle setGlow={setGlow} />
            <p className="text-sm font-medium text-white md:text-base xl:text-xl">
              Validator
            </p>
          </div>
          <div className="relative flex gap-1.5 md:gap-2 lg:hidden">
            <CarouselPrevious className="size-6 border-2 border-[#848484] bg-transparent md:size-7 xl:size-8" />
            <CarouselNext className="size-6 border-2 border-[#848484] bg-transparent md:size-7 xl:size-8" />
          </div>
        </div>
        <div className="flex grow flex-col">
          <div className="flex h-[85%] w-full px-4 md:px-6">
            <CarouselContent className="flex grow py-4 md:py-6 xl:-ml-0 xl:grid xl:!transform-none xl:grid-cols-3 xl:gap-4">
              <CarouselItem className="basis-full sm:basis-1/2 xl:basis-full xl:pl-0">
                <div className="grid size-full grid-rows-3 gap-4">
                  <div className="flex size-full flex-col items-center justify-center gap-4 overflow-hidden rounded-xl border border-[#202020] bg-[#121212]">
                    <p className="whitespace-nowrap text-xs text-[#6B6B6B] md:text-sm xl:text-base">
                      Delegated to THJ (BGT)
                    </p>
                    <div className="flex items-center gap-2 text-lg md:text-xl xl:text-2xl">
                      <p className="font-semibold">
                        {formatToken(BigInt(data?.amountDelegated ?? "0"))}
                      </p>
                      <div className="relative aspect-square h-[28px]">
                        <Image
                          src={"/delegate-bee.png"}
                          alt="bee"
                          fill
                          className="object-contain"
                        />
                      </div>
                    </div>
                  </div>
                  <div className="flex size-full flex-col items-center justify-center gap-4 overflow-hidden rounded-xl border border-[#202020] bg-[#121212]">
                    <p className="whitespace-nowrap text-xs text-[#6B6B6B] md:text-sm xl:text-base">
                      Number of Delegators
                    </p>
                    <p className="text-lg font-semibold md:text-xl xl:text-2xl">
                      12,3245,213
                    </p>
                  </div>
                  <div className="flex size-full flex-col items-center justify-center gap-4 overflow-hidden rounded-xl border border-[#202020] bg-[#121212]">
                    <p className="text-xs text-[#6B6B6B] md:text-sm xl:text-base">
                      Return per BGT
                    </p>
                    <div className="flex items-center gap-2 text-2xl">
                      <p className="text-lg font-semibold md:text-xl xl:text-2xl">
                        $123.13
                      </p>
                      <div className="relative aspect-square h-[28px]">
                        <Image
                          src={"/bgt-honey.png"}
                          alt="honey"
                          fill
                          className="object-contain"
                        />
                      </div>
                    </div>
                  </div>
                </div>
              </CarouselItem>
              <CarouselItem className="basis-full sm:basis-1/2 xl:basis-full xl:pl-0">
                <div className="grid h-full grid-rows-3 gap-4">
                  <div className="flex size-full flex-col items-center justify-center gap-4 overflow-hidden rounded-xl border border-[#202020] bg-[#121212]">
                    <p className="text-xs text-[#6B6B6B] md:text-sm xl:text-base">
                      Validator&apos;s Rank
                    </p>
                    <p className="text-lg font-semibold md:text-xl xl:text-2xl">
                      1st
                    </p>
                  </div>
                  <div className="flex size-full flex-col items-center justify-center gap-4 overflow-hidden rounded-xl border border-[#202020] bg-[#121212]">
                    <p className="text-xs text-[#6B6B6B] md:text-sm xl:text-base">
                      Active Incentives
                    </p>
                    <p className="text-lg font-semibold md:text-xl xl:text-2xl">
                      $0{" "}
                      {/* <span className="text-xs font-normal text-[#989898]">
                  (The Value)
                </span> */}
                    </p>
                  </div>
                  <div className="flex size-full flex-col items-center justify-center gap-4 overflow-hidden rounded-xl border border-[#202020] bg-[#121212]">
                    <p className="text-xs text-[#6B6B6B] md:text-sm xl:text-base">
                      Reward Rate
                    </p>
                    <div className="flex items-center gap-2 text-lg md:text-xl xl:text-2xl">
                      <p className="font-semibold">
                        {formatToken(BigInt(data?.boostedRewardRate ?? "0"))}
                      </p>
                      <div className="relative aspect-square h-[28px]">
                        <Image
                          src={"/delegate-bee.png"}
                          alt="bee"
                          fill
                          className="object-contain"
                        />
                      </div>
                    </div>
                  </div>
                </div>
              </CarouselItem>
              <CarouselItem className="basis-full sm:basis-1/2 xl:pl-0">
                <div className="relative flex size-full flex-col items-center overflow-hidden rounded-2xl border border-[#202020] bg-[#121212] py-6">
                  <div className="relative flex size-full flex-col items-center justify-center">
                    <p className="absolute top-0 text-xs text-[#6B6B6B] md:text-sm xl:text-base">
                      Voting Power
                    </p>
                    <div className="mb-8 aspect-square h-[135px]">
                      <CircularProgressbarWithChildren
                        value={50}
                        strokeWidth={14}
                        styles={buildStyles({
                          rotation: 0.5,
                          strokeLinecap: "butt",
                          pathColor: "#43AA77",
                          trailColor: "#F4C10B",
                        })}
                      >
                        <p className="absolute -left-10 top-auto text-sm font-medium text-[#C1C1C1] sm:-left-4 sm:top-0 2xl:-left-10 2xl:top-auto">
                          50%
                        </p>
                        <p className="absolute -right-10 bottom-auto text-sm font-medium text-[#C1C1C1] sm:-right-4 sm:bottom-0 2xl:-right-10 2xl:bottom-auto">
                          50%
                        </p>
                      </CircularProgressbarWithChildren>
                    </div>
                    <div className="flex justify-center gap-2 text-[#C7C7C7]">
                      <div className="flex items-center justify-center gap-1">
                        <div className="aspect-square h-[14px] rounded-full bg-[#43AA77]" />
                        <p className="text-xs font-light md:text-sm">THJ</p>
                      </div>
                      <div className="flex items-center justify-center gap-1">
                        <div className="aspect-square h-[14px] rounded-full bg-[#F4C10B]" />
                        <p className="text-xs font-light md:text-sm">Other</p>
                      </div>
                    </div>
                  </div>
                </div>
              </CarouselItem>
            </CarouselContent>
          </div>
          <div className="flex h-[15%] w-full shrink-0 items-center justify-between border-t border-[#1B271B] p-4 md:p-6">
            <div className="flex items-center gap-2">
              <div className="relative aspect-square h-8 md:h-[38px]">
                <Image
                  src={"/jani-coin.png"}
                  alt="jani-coin"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="hidden whitespace-nowrap text-base font-light text-white sm:block md:text-lg xl:text-xl">
                Needs Your Support
              </p>
            </div>
            <div className="flex h-full items-center gap-2">
              <a
                target="_blank"
                href={
                  "https://bartio.station.berachain.com/validators/0x40495A781095932e2FC8dccA69F5e358711Fdd41"
                }
                className="flex h-full items-center justify-center whitespace-nowrap rounded-full border border-white/5 bg-white/5 px-6 text-xs font-medium text-white hover:cursor-blue hover:border-white/20 hover:bg-white/20 md:text-sm xl:text-base"
              >
                <span className="hidden xl:inline-flex">View</span> Validator
              </a>
              <a
                target="_blank"
                href={
                  "https://bartio.station.berachain.com/delegate?action=delegate&validator=0x40495A781095932e2FC8dccA69F5e358711Fdd41"
                }
                className="flex h-full items-center justify-center whitespace-nowrap rounded-full bg-[#43AA77] px-6 text-xs font-medium text-black hover:cursor-blue hover:shadow-evergreen md:text-sm xl:text-base"
              >
                Delegate <span className="hidden xl:inline-flex">Now</span>
              </a>
              {/* <div className="relative aspect-square h-[100px]">
              <Image
                src={"/arrow-wiggle.svg"}
                alt="arrow-wiggle"
                fill
                className="object-contain"
              />
            </div>
            <div className="rounded-full border border-dashed border-[#848484] p-1.5">
              <button className="rounded-full bg-[#43AA77] px-6 py-2 font-medium text-black hover:cursor-blue hover:shadow-evergreen">
                Delegate Now
              </button>
            </div> */}
            </div>
          </div>
        </div>
      </Carousel>
    </div>
  );
};

export default Validator;
