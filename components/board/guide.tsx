import Image from "next/image";
import DragHandle from "../drag-handle";
import { useState } from "react";

const Guide = () => {
  const [glow, setGlow] = useState(false);
  return (
    <div className="relative flex h-full flex-col justify-end overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]">
      <div className="absolute -top-40 h-1 w-full" id="guide" />
      <Image src={"/guide.png"} alt="guide" fill className="object-cover" />
      <div className="absolute bottom-0 h-1/2 w-full bg-gradient-to-t from-[#0E0D09]" />
      <div className="z-10 flex w-full items-center justify-between p-6">
        <div className="flex items-center gap-2">
          {/* <div className="dragHandle relative aspect-square h-[26px]">
            <Image
              src={"/drag-handle.svg"}
              alt="drag"
              fill
              className="object-contain"
            />
          </div> */}
          <DragHandle setGlow={setGlow} />
          <p className="text-lg font-medium text-white md:text-2xl">
            New to THJ? Start with THJ 101 Guide!
          </p>
        </div>
        <a
          href={
            "https://0xhoneyjar.mirror.xyz/dHB3l29gAfLsPhPUPLGvg6_UAM1LxgxHMSJ054_QuDM"
          }
          target="_blank"
          className="whitespace-nowrap rounded-full bg-[#F4C10B] px-6 py-1 text-sm font-medium text-black hover:shadow-yellow md:px-8 md:py-2 md:text-base"
        >
          Explore
        </a>
      </div>
    </div>
  );
};

export default Guide;
