import Image from "next/image";
import { LockKeyhole, ArrowUpRight } from "lucide-react";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";

const Mint = () => {
  return (
    <div className="relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]">
      <div className="absolute -top-40 h-1 w-full" id="mint" />
      <Carousel className="flex h-full flex-col" opts={{ dragFree: true }}>
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
        <div className="flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-20 md:px-6">
          <div className="flex items-center gap-2">
            <LockKeyhole className="aspect-square h-5 text-[#FFD7004D] md:h-[26px]" />
            <p className="whitespace-nowrap text-sm font-medium text-[#FFD700] md:text-base xl:text-xl">
              New Mint
            </p>
          </div>
          <div className="relative flex gap-1.5 md:gap-2 xl:gap-3">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7 xl:h-8 xl:w-8" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7 xl:h-8 xl:w-8" />
          </div>
          {/* <button className="flex items-center gap-1 text-lg font-medium text-[#848484] hover:text-white">
            Explore <ArrowUpRight size={24} />
          </button> */}
        </div>
        {/* <div className="flex grow p-6">
          <div className="grid h-full w-full grid-cols-4 gap-6">
            <div className="relative flex h-full w-full flex-col justify-between overflow-hidden rounded-lg border border-[#F4C10B14] bg-[#221C11] px-4 py-2 hover:cursor-blue hover:divide-[#F4C10B47] hover:border-[#F4C10B47] hover:bg-[#423520]">
              <Image
                src={"/mint-placeholder.png"}
                alt=""
                fill
                className="object-cover"
              />
              <div className="z-10 flex gap-2">
                <div className="rounded-full bg-[#D8D8D8]/10 px-3 py-1">
                  <p className="text-xs font-light text-white">
                    24:10:59 <span className="text-[#E2E2E2]">left</span>
                  </p>
                </div>
                <div className="rounded-full bg-[#D8D8D8]/10 px-3 py-1">
                  <p className="text-xs font-light text-white">NFT Supply</p>
                </div>
              </div>
              <div className="z-10 flex w-full items-center justify-between py-2">
                <div className="flex flex-col gap-0.5">
                  <p className="text-sm text-[#FBFBFB]">Title</p>
                  <div className="flex items-center gap-2">
                    <div className="relative aspect-square h-[20px]">
                      <Image src={"/thj-logo.png"} alt="logo" fill />
                    </div>
                    <p className="whitespace-nowrap text-xs text-[#6B6B6B]">
                      By The Honey jar
                    </p>
                  </div>
                </div>

                <div className="flex flex-col items-end">
                  <div className="flex items-center gap-1">
                    <div className="relative aspect-square h-[12px]">
                      <Image src={"/eth.svg"} alt="eth" fill />
                    </div>
                    <p className="text-sm font-semibold text-white">12.00</p>
                  </div>
                  <p className="text-[8px] text-[#BABABA]">$123,145.00</p>
                </div>
              </div>
            </div>
          </div>
        </div> */}
        <CarouselContent className="flex h-full w-full py-6 pl-6">
          <CarouselItem className="">
            <div className="relative flex h-full w-[196px] flex-col justify-between overflow-hidden rounded-lg border border-[#F4C10B14] bg-[#221C11] px-4 py-2 hover:cursor-blue hover:divide-[#F4C10B47] hover:border-[#F4C10B47] hover:bg-[#423520]">
              <Image
                src={"/mint-placeholder.png"}
                alt=""
                fill
                className="object-cover"
              />
              <div className="z-10 flex gap-2">
                <div className="rounded-full bg-[#D8D8D8]/10 px-3 py-1">
                  <p className="whitespace-nowrap text-[10px] font-light text-white">
                    24:10:59 <span className="text-[#E2E2E2]">left</span>
                  </p>
                </div>
                <div className="rounded-full bg-[#D8D8D8]/10 px-3 py-1">
                  <p className="whitespace-nowrap text-[10px] font-light text-white">
                    NFT Supply
                  </p>
                </div>
              </div>
              <div className="z-10 flex w-full items-center justify-between py-2">
                <div className="flex flex-col gap-0.5">
                  <p className="text-sm text-[#FBFBFB]">Title</p>
                  <div className="flex items-center gap-2">
                    <div className="relative aspect-square h-[20px]">
                      <Image src={"/thj-logo.png"} alt="logo" fill />
                    </div>
                    <p className="whitespace-nowrap text-xs text-[#6B6B6B]">
                      By The Honey jar
                    </p>
                  </div>
                </div>

                <div className="flex flex-col items-end">
                  <div className="flex items-center gap-1">
                    <div className="relative aspect-square h-[12px]">
                      <Image src={"/eth.svg"} alt="eth" fill />
                    </div>
                    <p className="text-sm font-semibold text-white">12.00</p>
                  </div>
                  <p className="text-[8px] text-[#BABABA]">$123,145.00</p>
                </div>
              </div>
            </div>
          </CarouselItem>
        </CarouselContent>
      </Carousel>
    </div>
  );
};

export default Mint;
