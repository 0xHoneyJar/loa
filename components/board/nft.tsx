import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import Image from "next/image";
import { NFTItems } from "@/constants/nft";

const NFT = () => {
  return (
    <div className="border-2 bg-[#10120D] rounded-2xl border-[#121A12] overflow-hidden h-full">
      <Carousel className="flex flex-col h-full">
        <div className="w-full h-2 bg-[#43AA77] rounded-t-3xl" />
        <div className="flex justify-between items-center py-6 px-8 border-b border-dashed border-[#1B271B]">
          <div className="flex gap-2 items-center">
            <div className="h-[26px] aspect-square relative dragHandle">
              <Image
                src={"/drag-handle.svg"}
                alt="drag"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-white text-lg">The Honey Jar NFTs</p>
          </div>
          <div className="flex relative gap-3">
            <CarouselPrevious className="h-8 w-8 border-[#848484] bg-transparent border-2" />
            <CarouselNext className="h-8 w-8 border-[#848484] bg-transparent border-2" />
          </div>
        </div>
        <CarouselContent className="-ml-0 flex gap-2 items-center pl-10">
          {NFTItems.map((nft, id) => (
            <CarouselItem
              key={id}
            className=""
            >
              <div className="h-[196px] gap-3 aspect-square rounded-lg border bg-[#121212] border-[#161616] flex items-center justify-center flex-col hover:cursor-blue hover:bg-[#1A1A1A] hover:border-[#373737] text-[#C4C4C4] hover:text-white">
              <div className="h-[10%] w-full py-1 flex items-center justify-center">
                {nft.new && (
                  <div className="flex gap-2 items-center border border-[#F4C10B] bg-[#F5DA7F14] rounded-full px-2 py-1">
                    <div className="h-[12px] aspect-square rounded-full bg-[#F4C10B]">
                      <div className="h-full w-full rounded-full bg-[#F4C10B] animate-ping" />
                    </div>
                    <p className="text-xs text-[#F4C10B]">NEW</p>
                  </div>
                )}
              </div>
              <div className="h-[100px] aspect-square relative bg-[#FFFFFF03] rounded-full border border-[#1A1A1A]">
                <Image
                  src={nft.image}
                  alt={nft.name}
                  fill
                  className="object-contain p-5"
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
