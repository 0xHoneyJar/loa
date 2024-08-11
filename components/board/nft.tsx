import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import Image from "next/image";
import { NFTItems } from "@/constants/nft";
import { NftItem } from "@/components/ui/buttons";

const NFT = () => {
  return (
    <div className="relative h-full overflow-hidden rounded-2xl border-2 border-[#121A12] bg-[#10120D]">
      <div className="absolute -top-40 h-1 w-full" id="nft" />
      <Carousel className="flex h-full flex-col" opts={{ dragFree: true }}>
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#43AA77]" />
        <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#1B271B] px-4 md:h-[72px] md:px-6">
          <div className="flex items-center gap-2">
            <p className="whitespace-nowrap text-base font-medium text-white md:text-lg">
              The Honey Jar NFTs
            </p>
          </div>
          <div className="relative flex gap-1.5 md:gap-2">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
          </div>
        </div>
        <CarouselContent className="mr-6 flex size-full grow items-center p-4 md:p-6">
          {NFTItems.map((nft, id) => (
            <CarouselItem key={id} className="h-full">
              <NftItem nft={nft} />
            </CarouselItem>
          ))}
        </CarouselContent>
      </Carousel>
    </div>
  );
};

export default NFT;
