import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import Image from "next/image";
import { NFTItems } from "@/constants/nft";
import { useState } from "react";
import DragHandle from "../drag-handle";

const NFT = () => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-1"} relative h-full overflow-hidden rounded-2xl border-2 border-[#121A12] bg-[#10120D]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="nft" />
      <Carousel className="flex h-full flex-col" opts={{ dragFree: true }}>
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#43AA77]" />
        <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#1B271B] px-4 md:h-[72px] md:px-6 xl:h-20">
          <div
            className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#43AA77] blur-2xl ${glow ? "flex" : "hidden"}`}
          />
          <div className="flex items-center gap-2">
            <DragHandle setGlow={setGlow} />
            <p className="whitespace-nowrap text-sm font-medium text-white md:text-base xl:text-xl">
              The Honey Jar NFTs
            </p>
          </div>
          <div className="relative flex gap-1.5 md:gap-2 xl:gap-3">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7 xl:h-8 xl:w-8" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7 xl:h-8 xl:w-8" />
          </div>
        </div>
        <CarouselContent className="flex size-full items-center py-4 pl-4 md:py-6 md:pl-6">
          {NFTItems.map((nft, id) => (
            <CarouselItem key={id} className="h-full">
              <div className="flex h-full w-[178px] flex-col items-center justify-center gap-3 rounded-lg border border-[#161616] bg-[#121212] text-[#C4C4C4] hover:cursor-blue hover:border-[#373737] hover:bg-[#1A1A1A] hover:font-medium hover:text-white md:w-[196px]">
                <div className="flex h-[10%] w-full items-center justify-center py-1">
                  {nft.new && (
                    <div className="flex items-center gap-2 rounded-full border border-[#F4C10B] bg-[#F5DA7F14] px-1.5 py-0.5">
                      <div className="aspect-square h-[8px] rounded-full bg-[#F4C10B]">
                        <div className="size-full animate-ping rounded-full bg-[#F4C10B]" />
                      </div>
                      <p className="text-[10px] text-[#F4C10B]">NEW</p>
                    </div>
                  )}
                </div>
                <div className="relative aspect-square h-16 rounded-full border border-[#1A1A1A] bg-[#FFFFFF03] md:h-20 xl:h-[100px]">
                  <Image
                    src={nft.image}
                    alt={nft.name}
                    fill
                    className="object-contain p-3 md:p-4 xl:p-5"
                  />
                </div>
                <p className="">{nft.name}</p>
              </div>
            </CarouselItem>
          ))}
        </CarouselContent>
      </Carousel>
    </div>
  );
};

export default NFT;
