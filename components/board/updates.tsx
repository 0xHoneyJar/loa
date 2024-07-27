import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import Image from "next/image";
import { ArrowUpRight, LockKeyhole } from "lucide-react";
import { useState } from "react";

const Updates = () => {
  const [hover, setHover] = useState(false);
  return (
    <div className="relative h-full overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]">
      <div className="absolute -top-40 h-1 w-full" id="updates" />
      <Carousel className="flex h-full flex-col">
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
        <div className="flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-20 md:px-6">
          <div className="flex items-center gap-2">
            <LockKeyhole className="aspect-square h-5 text-[#FFD7004D] md:h-[26px]" />
            <p className="text-sm font-medium text-[#FFD700] md:text-base xl:text-xl">
              Updates
            </p>
          </div>
          <div className="relative flex gap-1.5 md:gap-3">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-8 md:w-6" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-8 md:w-6" />
          </div>
        </div>
        <CarouselContent className="flex size-full py-4 pl-4 md:py-6 md:pl-6">
          <CarouselItem>
            <div className="relative flex h-full w-[200px] flex-col gap-2 overflow-hidden sm:w-[240px] md:w-[270px] md:gap-3">
              <div
                onMouseEnter={() => setHover(true)}
                onMouseLeave={() => setHover(false)}
                className={`relative h-2/3 w-full overflow-hidden rounded-xl border ${hover ? "cursor-blue border-[#F5D011D9]" : "border-[#2B2B2B]"}`}
              >
                <Image
                  src={"/update-placeholder.png"}
                  alt=""
                  fill
                  className="object-cover"
                />
              </div>
              <div className="flex h-1/3 flex-col gap-0.5 md:gap-1">
                <div className="flex items-center justify-between">
                  <p
                    className={`text-xs font-medium md:text-sm lg:text-base ${hover ? "text-[#F5D011]" : "text-white"}`}
                  >
                    Heading
                  </p>
                  <ArrowUpRight
                    className={`aspect-square h-4 md:h-5 ${hover ? "text-[#F5D011]" : "text-white/15"}`}
                  />
                </div>
                <p className="text-[10px] text-[#A9A9A9] md:text-xs lg:text-sm">
                  Description
                </p>
              </div>
            </div>
          </CarouselItem>
        </CarouselContent>
      </Carousel>
      {/* </div> */}
    </div>
  );
};

export default Updates;
