import { useState } from "react";
import DragHandleY from "../drag-handle-y";
import { ChevronRight } from "lucide-react";
import Image from "next/image";

const Raffles = () => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-[1deg]"} relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="quests" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#FFC500] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandleY setGlow={setGlow} />
          <p className="text-lg text-[#FFD700]">Raffles</p>
        </div>
      </div>
      <div className="flex grow flex-col justify-between p-6">
        <p className="uppercase text-white">
          TAKE PART IN RAFFLES TO WIN PRIZES FROM AROUND THE&nbsp;
          <span className="text-[#E1A94E]">BERACHAIN ECOSYSTEM!</span>
        </p>
        <div className="grid w-full grid-rows-3 gap-6">
          <div className="h-[250px] w-full bg-white"></div>
          <div className="h-[250px] w-full bg-white"></div>
          <div className="h-[250px] w-full bg-white"></div>
        </div>
        <button className="flex w-full cursor-blue items-center justify-between rounded-lg border border-[#E8E8E8]/5 bg-[#FFFFFF]/5 px-4 py-3">
          <div className="flex items-center gap-2">
            <div className="relative aspect-square h-[32px]">
              <Image
                src={"/question.svg"}
                alt="question"
                fill
                className="object-contain"
              />
            </div>
            <p>Explore All Raffles</p>
          </div>
          <ChevronRight className="aspect-square h-[18px] text-[#FFFFFF]/40" />
        </button>
      </div>
    </div>
  );
};

export default Raffles;
