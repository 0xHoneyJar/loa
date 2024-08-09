import { ArrowUpRight } from "lucide-react";
import Image from "next/image";
import DragHandleY from "../drag-handle-y";
import { useState } from "react";
import { ScrollArea } from "../ui/scroll-area";
import S3Image from "../s3-image";
import { trackEvent } from "@openpanel/nextjs";

const Spotlight = ({ spotlight }: { spotlight?: any }) => {
  const [glow, setGlow] = useState(false);

  return (
    <div
      className={`${glow && "rotate-1"} relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="spotlight" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-6 md:h-[72px]">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#FFC500] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandleY setGlow={setGlow} />
          <p className="text-sm font-medium text-[#FFD700] md:text-base">
            Spotlight
          </p>
          <div className="ml-2 flex items-center rounded-full bg-[#F5D01124] px-2 py-1">
            <p className="text-[10px] uppercase text-[#F5D011] md:text-xs">
              Don&apos;t miss it
            </p>
          </div>
        </div>
      </div>
      <div className="flex grow flex-col items-center gap-4 p-4 md:p-6">
        <div className="relative flex h-3/5 w-full shrink-0 overflow-hidden rounded-lg border border-[#1C1C1C]">
          <S3Image
            src={spotlight.image}
            width={1000}
            fill
            alt="spotlight"
            className="z-[-1] object-cover"
          />
        </div>
        <div className="relative flex size-full flex-col overflow-hidden">
          {/* <div className="flex w-full flex-col"> */}
          <p className="mb-1 text-sm font-medium text-[#FBFBFB] md:text-base">
            {spotlight.title}
          </p>
          <ScrollArea>
            <p className="text-xs text-[#A9A9A9] md:text-sm">
              {spotlight.description}
            </p>
          </ScrollArea>
          {/* </div> */}
        </div>
        <a
          className="flex w-full items-center justify-between rounded-lg bg-[#F4C10B]/10 px-4 py-3 text-[#F4C10B] hover:cursor-blue hover:bg-[#F4C10B] hover:font-semibold hover:text-[#121212]"
          href={spotlight.link}
          onClick={() => {
            trackEvent(`${spotlight._title}_spotlight`);
          }}
          target="_blank"
        >
          <p className="text-xs md:text-sm">Learn More</p>
          <ArrowUpRight className="aspect-square h-[16px] md:h-[24px]" />
        </a>
      </div>
    </div>
  );
};

export default Spotlight;
