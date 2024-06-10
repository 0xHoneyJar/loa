import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import Image from "next/image";

const Quests = () => {
  return (
    <div className="rounded-2xl overflow-hidden bg-gradient-to-b from-[#F8A92917] to-[#14131017] h-full border-2 border-[#F8A92952]">
      <Carousel className="flex flex-col h-full">
        <div className="w-full h-2 bg-[#FFD700] rounded-t-3xl" />
        <div className="flex justify-between items-center py-6 px-8 border-b border-dashed border-[#F4C10B6B]">
          <div className="flex gap-2 items-center">
            <div className="h-[26px] aspect-square relative dragHandle">
              <Image
                src={"/drag-handle-y.svg"}
                alt="drag"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-[#FFD700] text-lg">Our Blog</p>
            <div className="flex gap-2 items-center rounded-full border py-1 px-2 border-[#F8A9291F] bg-gradient-to-r from-[#F5D0110D] to-[#F8A9290D]">
              <div className="h-[20px] aspect-square relative">
                <Image
                  src={"/rise.svg"}
                  alt="rise"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="bg-gradient-to-r from-[#F5D011] to-[#F8A929] bg-clip-text text-transparent">
                On The Rise
              </p>
            </div>
          </div>
          <div className="flex relative gap-3">
            <CarouselPrevious className="h-8 w-8 border-[#848484] bg-transparent border-2" />
            <CarouselNext className="h-8 w-8 border-[#848484] bg-transparent border-2" />
          </div>
        </div>
        <CarouselContent className="-ml-0 flex gap-4 pl-10 items-center">
          <CarouselItem>
            <div className="h-[180px] aspect-square rounded-lg border bg-[#18140C] border-[#F4C10B0F] flex items-center justify-center flex-col relative">
              <div className="h-[2px] bg-[#EE511E] absolute top-0 w-8 rounded-full" />
              <div className="h-[90px] aspect-square bg-[#18140C05] border border-[#F4C10B0F] rounded-full mb-4" />
              <p className="text-[#C4C4C4]">Standard & Paws</p>
            </div>
          </CarouselItem>
        </CarouselContent>
      </Carousel>
      {/* </div> */}
    </div>
  );
};

export default Quests;
