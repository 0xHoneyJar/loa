import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import { TOOLS } from "@/constants/tools";
import DragHandle from "../drag-handle";
import { useState } from "react";

const Tools = () => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-[1deg]"} relative h-full overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="tools" />
      <Carousel className="flex h-full flex-col">
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-white" />
        <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-20 md:px-6">
          <div
            className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#B8B8B8] blur-2xl ${glow ? "flex" : "hidden"}`}
          />
          <div className="flex items-center gap-2">
            <DragHandle setGlow={setGlow} />
            <p className="font-medium text-white md:text-xl">
              Tools & Products
            </p>
          </div>
          <div className="relative flex gap-1.5 md:gap-3">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-8 md:w-8" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-8 md:w-8" />
          </div>
        </div>
        <CarouselContent className="flex h-full w-full items-center md:py-6 py-4 md:pl-6 pl-4">
          {TOOLS.map((item, id) => (
            <CarouselItem key={id} className="h-full pl-5">
              <div className="flex h-full w-[196px] flex-col items-center justify-center rounded-lg border border-[#161616] bg-[#121212] text-[#C4C4C4] hover:cursor-blue hover:border-[#373737] hover:bg-[#1A1A1A] hover:font-medium hover:text-white">
                <div className="mb-4 mt-6 aspect-square md:h-[100px] h-[80px] rounded-full bg-[#FD4D01]" />
                <p className="md:text-base text-xs">{item.name}</p>
              </div>
            </CarouselItem>
          ))}
        </CarouselContent>
      </Carousel>
    </div>
  );
};

export default Tools;
