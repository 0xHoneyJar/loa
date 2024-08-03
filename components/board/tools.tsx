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
import Image from "next/image";

const Tools = () => {
  const [glow, setGlow] = useState(false);

  const handleRedirect = (e: any, link: string) => {
    if (!link) {
      e.preventDefault(); // Prevent default navigation when disabled
    }
  };

  return (
    <div
      className={`${glow && "rotate-1"} relative h-full overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="tools" />
      <Carousel className="flex h-full flex-col" opts={{ dragFree: true }}>
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-white" />
        <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-[72px] md:px-6">
          <div
            className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#B8B8B8] blur-2xl ${glow ? "flex" : "hidden"}`}
          />
          <div className="flex items-center gap-2">
            <DragHandle setGlow={setGlow} />
            <p className="text-sm font-medium text-white md:text-base">
              Tools & Products
            </p>
          </div>
          <div className="relative flex gap-1.5 md:gap-2">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
          </div>
        </div>
        <CarouselContent className="mr-6 flex h-full w-full grow items-center py-4 pl-4 md:py-6 md:pl-6">
          {TOOLS.map((item, id) => (
            <CarouselItem key={id} className={`h-full`}>
              <a
                target="_blank"
                href={item.link}
                onClick={(e) => handleRedirect(e, item.link)}
                className={`flex h-full w-[178px] flex-col items-center justify-center rounded-lg border border-[#161616] bg-[#121212] px-4 text-[#C4C4C4] hover:cursor-blue hover:border-[#373737] hover:bg-[#1A1A1A] hover:font-medium hover:text-white md:w-[196px]`}
              >
                {item.image ? (
                  <div className="relative mb-4 mt-4 aspect-square h-16 overflow-hidden rounded-full md:mt-6 md:h-[80px]">
                    <Image
                      src={item.image}
                      alt={item.name}
                      fill
                      className="object-contain"
                    />
                  </div>
                ) : (
                  <div className="mb-4 mt-4 aspect-square h-16 rounded-full bg-[#FD4D01] md:mt-6 md:h-[80px]" />
                )}
                <p className="text-xs md:text-sm">{item.name}</p>
              </a>
            </CarouselItem>
          ))}
        </CarouselContent>
      </Carousel>
    </div>
  );
};

export default Tools;
