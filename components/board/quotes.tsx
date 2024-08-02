import Image from "next/image";
import { QUOTES } from "@/constants/quotes";
import { useState } from "react";
import DragHandle from "../drag-handle";

const Quotes = ({ quoteNumber }: { quoteNumber: number }) => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-1"} flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]`}
    >
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-white" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-[72px] md:px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#B8B8B8] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandle setGlow={setGlow} />
          <p className="text-sm font-medium text-white md:text-base">
            Our Quotes 001
          </p>
        </div>
      </div>
      <div className="flex grow px-4 py-6 md:px-6 md:py-10">
        <p className="text-2xl font-semibold uppercase text-white md:text-3xl xl:text-4xl">
          {QUOTES[quoteNumber].quote}
        </p>
      </div>
    </div>
  );
};

export default Quotes;
