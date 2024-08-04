import Image from "next/image";
import { DEVELOPMENT } from "@/constants/development";
import DragHandle from "../drag-handle";
import { useState } from "react";
import { ScrollArea } from "../ui/scroll-area";

const Development = ({ developments }: { developments?: any }) => {
  const [glow, setGlow] = useState(false);
  console.log(developments);
  return (
    <div
      className={`${glow && "rotate-1"} relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="development" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-white" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-[72px] md:px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#B8B8B8] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandle setGlow={setGlow} />
          <p className="whitespace-nowrap text-sm font-medium text-white md:text-base">
            Development Updates
          </p>
        </div>
      </div>
      <ScrollArea className="relative flex grow py-4 md:py-6">
        <div className="absolute left-6 top-4 size-full border-l border-dashed border-[#4C4C4C] md:left-8 md:top-6" />
        <div className="absolute left-0 top-0 z-10 h-1/6 w-full bg-gradient-to-b from-[#0F0F0F]" />
        <div className="absolute bottom-0 left-0 z-10 h-1/6 w-full bg-gradient-to-t from-[#0F0F0F]" />
        <div className="relative size-full pl-6 md:pl-8">
          <div className="relative flex size-full grow flex-col gap-12 px-8 pt-4 md:gap-16 md:pt-6">
            {developments.items.map((development: any, id: any) => (
              <div className="relative flex flex-col gap-3" key={id}>
                <div className="absolute left-[-36px] top-2 aspect-[4/1] h-2 md:top-2.5">
                  <Image
                    src={"/development-pointer.svg"}
                    alt="pointer"
                    fill
                    className="object-contain"
                  />
                </div>
                <p className="text-sm text-[#F4C10B] md:text-base">
                  {development._title}
                </p>
                {development.milestones.items.map((item: any, id: any) => (
                  <div className="flex items-center gap-1 md:gap-2" key={id}>
                    <div className="relative aspect-square h-4 md:h-6">
                      <Image
                        src={"/development-arrow.svg"}
                        alt="arrow"
                        fill
                        className="object-contain"
                      />
                    </div>
                    <p className="text-xs md:text-sm">{item._title}</p>
                    <p className="text-xs font-light text-[#424242]/90 md:text-sm">
                      {item.date}
                    </p>
                  </div>
                ))}
              </div>
            ))}
          </div>
        </div>
      </ScrollArea>
    </div>
  );
};

export default Development;
