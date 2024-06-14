import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import Image from "next/image";
import { LockKeyhole } from "lucide-react";

const Updates = () => {
  return (
    <div className="relative rounded-2xl overflow-hidden bg-gradient-to-b from-[#F8A92917] to-[#14131017] h-full border-2 border-[#F8A92952]">
      <div className="absolute -top-40 w-full h-1" id="updates" />
      <Carousel className="flex flex-col h-full">
        <div className="w-full h-2 bg-[#FFD700] rounded-t-3xl" />
        <div className="flex justify-between items-center h-16 px-6 border-b border-dashed border-[#F4C10B6B]">
          <div className="flex gap-2 items-center">
            {/* <div className="h-[26px] aspect-square relative dragHandle">
              <Image
                src={"/drag-handle-y.svg"}
                alt="drag"
                fill
                className="object-contain"
              />
            </div> */}
            <LockKeyhole className="h-[26px] aspect-square text-[#FFD7004D]" />
            <p className="text-[#FFD700] text-lg">Updates</p>
          </div>
          <div className="flex relative gap-3">
            <CarouselPrevious className="h-8 w-8 border-[#848484] bg-transparent border-2" />
            <CarouselNext className="h-8 w-8 border-[#848484] bg-transparent border-2" />
          </div>
        </div>
        <CarouselContent className="flex pl-6 py-6 h-full w-full">
          <CarouselItem>
            <div className="w-[270px] h-full rounded-lg border bg-[#18140C] border-[#F4C10B0F] flex items-center justify-center flex-col relative"></div>
          </CarouselItem>
        </CarouselContent>
      </Carousel>
      {/* </div> */}
    </div>
  );
};

export default Updates;
