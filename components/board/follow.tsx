import Image from "next/image";
import DragHandle from "../drag-handle";
import { useState } from "react";

const Follow = () => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F] ${glow && "rotate-[1deg]"}`}
    >
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-white" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-20 md:px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#B8B8B8] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandle setGlow={setGlow} />
          <p className="font-medium text-white md:text-xl">Follow Us</p>
        </div>
      </div>
      <div className="relative flex grow items-center justify-center px-6">
        <div className="flex flex-row items-center gap-3 rounded-full border border-dashed border-[#747474]/40 px-4 py-3">
          <a
            href={"https://x.com/0xhoneyjar"}
            target="_blank"
            className="relative aspect-square h-[32px] opacity-70 hover:cursor-blue hover:opacity-100 md:h-[40px]"
          >
            <Image
              src={"/follow/twitter.svg"}
              alt="twitter"
              fill
              className="object-contain"
            />
          </a>
          <a
            href={"https://discord.com/invite/thehoneyjar"}
            target="_blank"
            className="relative aspect-square h-[46px] opacity-70 hover:cursor-blue hover:opacity-100 md:h-[58px]"
          >
            <Image
              src={"/follow/discord.svg"}
              alt="discord"
              fill
              className="object-contain"
            />
          </a>
          <a
            href={"https://warpcast.com/0xhoneyjar"}
            target="_blank"
            className="relative aspect-square h-[46px] opacity-70 hover:cursor-blue hover:opacity-100 md:h-[58px]"
          >
            <Image
              src={"/follow/farcaster.svg"}
              alt="farcaster"
              fill
              className="object-contain"
            />
          </a>
        </div>
        <div className="absolute flex items-end gap-2 md:bottom-8 bottom-6 left-32 justify-center inset-x-0 mx-auto">
          <div className="relative aspect-square h-[42px] md:h-[50px]">
            <Image
              src={"/follow/arrow-swirl.svg"}
              alt="arrow-swirl"
              fill
              className="scale-x-110 object-contain"
            />
          </div>
          <p className="text-[10px] text-[#747474]/65 md:text-xs whitespace-nowrap">
            Follow Us <span className="md:inline-flex hidden">For More</span>
          </p>
        </div>
      </div>
    </div>
  );
};

export default Follow;
