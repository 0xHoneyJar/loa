"use client";

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
import {
  CircularProgressbarWithChildren,
  buildStyles,
} from "react-circular-progressbar";
import useSWR from "swr";
import { trackEvent } from "@openpanel/nextjs";
import { ValidatorWidget } from "@0xhoneyjar/validator-widget";

const Validator = () => {
  const { data } = useSWR<{
    amountDelegated: string;
    // boostedRewardRate: string;
    rewardRate: string;
    rank: string;
    boosters: string;
  }>("/api/validator", fetcher);

  const formatOrdinal = (num: string) => {
    const n = parseInt(num);
    if (isNaN(n)) return "1st";

    const j = n % 10;
    const k = n % 100;

    if (j === 1 && k !== 11) return `${n}st`;
    if (j === 2 && k !== 12) return `${n}nd`;
    if (j === 3 && k !== 13) return `${n}rd`;
    return `${n}th`;
  };

  const formatNumberWithK = (num: string) => {
    const n = parseInt(num);
    if (isNaN(n)) return "0";

    if (n >= 1000) {
      return (n / 1000).toFixed(2) + "k";
    }
    return n.toString();
  };

  return (
    <div
      className={`relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#121A12] bg-[#10120D]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="validator" />
      <Carousel className="flex size-full flex-col">
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#43AA77]" />
        <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#1B271B] px-4 md:h-[72px] md:px-6">
          <div className="flex items-center gap-2">
            <p className="text-base font-medium text-white md:text-lg">
              Validator
            </p>
          </div>
          <div className="relative flex gap-1.5 md:gap-2 lg:hidden">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
          </div>
        </div>
        <div className="flex grow flex-col">
          <div className="flex h-[85%] w-full px-4 md:px-6">
            <CarouselContent className="flex grow py-4 md:py-6 xl:-ml-0 xl:grid xl:!transform-none xl:grid-cols-3 xl:gap-4">
              <CarouselItem className="basis-full sm:basis-1/2 xl:basis-full xl:pl-0">
                <div className="grid size-full grid-rows-3 gap-4">
                  <div className="flex size-full flex-col items-center justify-center gap-4 overflow-hidden rounded-xl border border-[#202020] bg-[#121212]">
                    <p className="whitespace-nowrap text-xs text-[#6B6B6B] md:text-sm">
                      Boosts (BGT)
                    </p>
                    <div className="flex items-center gap-2 text-2xl md:text-xl">
                      <p className="font-semibold">
                        {/* {formatToken(BigInt(data?.amountDelegated ?? "0"))} */}
                        {formatNumberWithK(data?.amountDelegated ?? "0")}
                      </p>
                      <div className="relative aspect-square h-5">
                        <Image
                          src={"/delegate-bee-v2.png"}
                          alt="bee"
                          fill
                          className="object-contain"
                        />
                      </div>
                    </div>
                  </div>
                  <div className="flex size-full flex-col items-center justify-center gap-4 overflow-hidden rounded-xl border border-[#202020] bg-[#121212]">
                    <p className="whitespace-nowrap text-xs text-[#6B6B6B] md:text-sm">
                      Number of Boosters
                    </p>
                    <p className="text-2xl font-semibold md:text-xl">
                      {formatNumberWithK(data?.boosters ?? "0")}
                    </p>
                  </div>
                  <div className="flex size-full flex-col items-center justify-center gap-4 overflow-hidden rounded-xl border border-[#202020] bg-[#121212]">
                    <p className="text-xs text-[#6B6B6B] md:text-sm">
                      Return per BGT
                    </p>
                    <div className="flex items-center gap-2 text-2xl">
                      <p className="text-2xl font-semibold md:text-xl">6.90</p>
                      <div className="relative aspect-square h-5">
                        <Image
                          src={"/bgt-honey-v2.png"}
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
                    <p className="text-xs text-[#6B6B6B] md:text-sm">
                      Validator&apos;s Rank
                    </p>
                    <p className="text-lg font-semibold md:text-xl">
                      {formatOrdinal(data?.rank ?? "1")}
                    </p>
                  </div>
                  <div className="flex size-full flex-col items-center justify-center gap-4 overflow-hidden rounded-xl border border-[#202020] bg-[#121212]">
                    <p className="text-xs text-[#6B6B6B] md:text-sm">
                      Active Incentives
                    </p>
                    <p className="text-lg font-semibold md:text-xl">
                      $9.24M
                      {/* <span className="text-xs font-normal text-[#989898]">
                  (The Value)
                </span> */}
                    </p>
                  </div>
                  <div className="flex size-full flex-col items-center justify-center gap-4 overflow-hidden rounded-xl border border-[#202020] bg-[#121212]">
                    <p className="text-xs text-[#6B6B6B] md:text-sm">
                      Reward Rate
                    </p>
                    <div className="flex items-center gap-2 text-lg md:text-xl">
                      <p className="font-semibold">
                        {/* {formatToken(BigInt(data?.boostedRewardRate ?? "0"))} */}
                        {Number(data?.rewardRate ?? "0").toFixed(2)}
                      </p>
                      <div className="relative aspect-square h-5">
                        <Image
                          src={"/delegate-bee-v2.png"}
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
                    <p className="absolute top-0 text-xs text-[#6B6B6B] md:text-sm">
                      Voting Power
                    </p>
                    <div className="aspect-square h-[135px]">
                      <CircularProgressbarWithChildren
                        value={90.42}
                        strokeWidth={14}
                        styles={buildStyles({
                          rotation: 0.43,
                          strokeLinecap: "butt",
                          pathColor: "#43AA77",
                          trailColor: "#F4C10B",
                        })}
                      >
                        <p className="absolute -left-4 -top-4 text-sm font-medium text-[#C1C1C1]">
                          90.42%
                        </p>
                        <p className="absolute -bottom-4 -right-4 text-sm font-medium text-[#C1C1C1]">
                          9.58%
                        </p>
                        <div className="absolute -bottom-16 flex justify-center gap-3 text-[#C7C7C7]">
                          <div className="flex items-center justify-center gap-2">
                            <div className="aspect-square h-3 rounded-full bg-[#43AA77]" />
                            <p className="text-xs font-light md:text-sm">THJ</p>
                          </div>
                          <div className="flex items-center justify-center gap-2">
                            <div className="aspect-square h-3 rounded-full bg-[#F4C10B]" />
                            <p className="text-xs font-light md:text-sm">
                              Other
                            </p>
                          </div>
                        </div>
                      </CircularProgressbarWithChildren>
                    </div>
                  </div>
                </div>
              </CarouselItem>
            </CarouselContent>
          </div>
          <div className="flex h-[15%] w-full shrink-0 items-center justify-between border-t border-[#1B271B] p-4 md:p-6">
            <div className="flex items-center gap-3">
              <div className="relative aspect-square h-8 md:h-[38px]">
                <Image
                  src={"/jani-coin.png"}
                  alt="jani-coin"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="hidden whitespace-nowrap text-sm font-light text-white sm:block">
                Needs Your Support
              </p>
            </div>
            <div className="flex h-full items-center gap-2">
              <a
                target="_blank"
                href={
                  "https://hub.berachain.com/validators/0xa0c673180d97213c1c35fe3bf4e684dd3534baab235a106d1f71b9c8a37e4d37a056d47546964fd075501dff7f76aeaf/"
                }
                onClick={() => {
                  trackEvent(`view_validator`);
                }}
                className="flex h-full items-center justify-center whitespace-nowrap rounded-full border border-white/5 bg-white/5 px-6 text-xs font-medium text-white transition-all duration-500 ease-in-out hover:border-white/20 hover:bg-white/20 md:text-sm"
              >
                <span className="hidden xl:inline-flex">View</span>
                &nbsp;Validator
              </a>
              <div className="relative z-10 flex h-full items-center justify-center">
                {/* <ValidatorWidget apiUrl="/api/delegate" referrer="thj"> */}
                <a
                  href={
                    "https://hub.berachain.com/validators/0xa0c673180d97213c1c35fe3bf4e684dd3534baab235a106d1f71b9c8a37e4d37a056d47546964fd075501dff7f76aeaf/"
                  }
                  onClick={() => {
                    trackEvent(`boost_validator`);
                  }}
                  target="_blank"
                >
                  <div className="flex h-[46px] cursor-pointer items-center justify-center whitespace-nowrap rounded-full bg-[#43AA77] px-6 text-xs font-medium text-black transition-all duration-500 ease-in-out hover:shadow-evergreen md:text-sm">
                    Boost&nbsp;
                    <span className="hidden xl:inline-flex">Now</span>
                  </div>
                </a>
                {/* </ValidatorWidget> */}
              </div>
              {/* <div className="relative aspect-square h-[100px]">
              <Image
                src={"/arrow-wiggle.svg"}
                alt="arrow-wiggle"
                fill
                className="object-contain"
              />
            </div>
            <div className="rounded-full border border-dashed border-[#848484] p-1.5">
              <button className="rounded-full bg-[#43AA77] px-6 py-2 font-medium text-black  hover:shadow-evergreen">
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
