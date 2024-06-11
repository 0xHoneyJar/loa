import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import Image from "next/image";
import { TOOLS } from "@/constants/tools";

const Tools = () => {
  return (
    <div className="border-2 bg-[#0F0F0F] rounded-2xl border-[#FFFFFF0A] overflow-hidden h-full">
      <Carousel className="flex flex-col h-full">
        <div className="w-full h-2 bg-white rounded-t-3xl" />
        <div className="flex justify-between items-center py-6 px-8 border-b border-dashed border-[#FFFFFF1F]">
          <div className="flex gap-2 items-center">
            <div className="h-[26px] aspect-square relative dragHandle">
              <Image
                src={"/drag-handle.svg"}
                alt="drag"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-white text-lg">Tools & Products</p>
          </div>
          <div className="flex relative gap-3">
            <CarouselPrevious className="h-8 w-8 border-[#848484] bg-transparent border-2" />
            <CarouselNext className="h-8 w-8 border-[#848484] bg-transparent border-2" />
          </div>
        </div>
        <CarouselContent className="flex items-center pl-8 h-full w-full">
          {TOOLS.map((item, id) => (
            <CarouselItem key={id} className="pl-5">
              <div className="h-[196px] aspect-square rounded-lg border bg-[#121212] border-[#161616] flex items-center justify-center flex-col hover:cursor-blue hover:bg-[#1A1A1A] hover:border-[#373737] text-[#C4C4C4] hover:text-white hover:font-medium">
                <div className="h-[100px] aspect-square bg-[#FD4D01] rounded-full mb-4 mt-6" />
                <p className="">{item.name}</p>
              </div>
            </CarouselItem>
          ))}
        </CarouselContent>
      </Carousel>
    </div>
  );
};

export default Tools;
