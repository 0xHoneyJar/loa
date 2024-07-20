import Image from "next/image";
import { QUOTES } from "@/constants/quotes";
import { useState } from "react";
import DragHandle from "../drag-handle";

const Quotes = ({ quoteNumber }: { quoteNumber: number }) => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-[1deg]"} flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]`}
    >
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-white" />
      <div className="relative flex md:h-20 h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] md:px-6 px-4">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#B8B8B8] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandle setGlow={setGlow} />
          <p className="md:text-xl font-medium text-white">Our Quotes 001</p>
        </div>
      </div>
      <div className="flex grow md:px-6 px-4 md:py-10 py-6">
        <p className="md:text-4xl text-3xl font-semibold uppercase text-white">
          {QUOTES[quoteNumber].quote}
        </p>
      </div>
    </div>
  );
};

export default Quotes;
