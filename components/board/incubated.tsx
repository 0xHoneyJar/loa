import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import Image from "next/image";
import { INCUBATED } from "@/constants/incubated";
import DragHandleY from "../drag-handle-y";
import { useState } from "react";

const Incubated = () => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-[1deg]"} relative h-full overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="incubated" />
      <Carousel className="flex h-full flex-col">
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
        <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-20 md:px-6">
          <div
            className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#FFC500] blur-2xl ${glow ? "flex" : "hidden"}`}
          />
          <div className="flex items-center gap-2">
            <DragHandleY setGlow={setGlow} />
            <p className="font-medium text-[#FFD700] md:text-xl">
              Incubated Projects
            </p>
            <div className="hidden items-center gap-2 rounded-full border border-[#F8A9291F] bg-gradient-to-r from-[#F5D0110D] to-[#F8A9290D] px-2 py-1 md:flex">
              <div className="relative aspect-square h-[20px]">
                <Image
                  src={"/rise.svg"}
                  alt="rise"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="whitespace-nowrap bg-gradient-to-r from-[#F5D011] to-[#F8A929] bg-clip-text text-transparent">
                Updated Recently
              </p>
            </div>
          </div>
          <div className="relative flex gap-1.5 md:gap-3">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-8 md:w-8" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-8 md:w-8" />
          </div>
        </div>
        <CarouselContent className="flex h-full w-full items-center py-6 pl-6">
          {INCUBATED.map((item, id) => (
            <CarouselItem key={id} className="h-full pl-5">
              <div className="relative flex h-full w-[196px] flex-col items-center justify-center rounded-lg border border-[#F4C10B0F] bg-[#18140C] text-[#C4C4C4] hover:cursor-blue hover:border-[#F4C10B38] hover:bg-[#332200] hover:font-medium hover:text-white/90">
                <div className="absolute top-0 h-[2px] w-8 rounded-full bg-[#EE511E]" />
                <div className="relative mb-4 mt-6 aspect-square h-[100px] rounded-full border border-[#F4C10B0F] bg-[#18140C05]">
                  <Image
                    src={item.image}
                    alt={item.name}
                    fill
                    className="object-contain p-4"
                  />
                </div>
                <p className="text-lg">{item.name}</p>
              </div>
            </CarouselItem>
          ))}
        </CarouselContent>
      </Carousel>
      {/* </div> */}
    </div>
  );
};

export default Incubated;
