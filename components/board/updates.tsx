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
        <div className="h-2 w-full rounded-t-3xl bg-[#FFD700]" />
        <div className="flex h-16 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-6">
          <div className="flex items-center gap-2">
            <LockKeyhole className="aspect-square h-[26px] text-[#FFD7004D]" />
            <p className="text-lg text-[#FFD700]">Updates</p>
          </div>
          <div className="relative flex gap-3">
            <CarouselPrevious className="h-8 w-8 border-2 border-[#848484] bg-transparent" />
            <CarouselNext className="h-8 w-8 border-2 border-[#848484] bg-transparent" />
          </div>
        </div>
        <CarouselContent className="flex h-full w-full py-6 pl-6">
          <CarouselItem>
            <div className="relative flex h-full w-[270px] flex-col gap-3">
              <div
                onMouseEnter={() => setHover(true)}
                onMouseLeave={() => setHover(false)}
                className={`relative h-[140px] w-full overflow-hidden rounded-xl border ${hover ? "border-[#F5D011]/85 cursor-blue" : "border-[#2B2B2B]"}`}
              >
                <Image
                  src={"/update-placeholder.png"}
                  alt=""
                  fill
                  className="object-cover"
                />
              </div>
              <div className="flex flex-col gap-1">
                <div className="flex items-center justify-between">
                  <p
                    className={`font-medium ${hover ? "text-[#F5D011]" : "text-white"}`}
                  >
                    Heading
                  </p>
                  <ArrowUpRight
                    className={`aspect-square h-[20px] ${hover ? "text-[#F5D011]" : "text-white/15"}`}
                  />
                </div>
                <p className="text-sm text-[#A9A9A9]">Description</p>
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
