import Image from "next/image";
import DragHandle from "../drag-handle";
import { useState } from "react";

const Follow = () => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F] ${glow && "rotate-[1deg]"}`}
    >
      <div className="h-2 w-full rounded-t-3xl bg-white" />
      <div className="relative flex h-16 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#B8B8B8] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandle setGlow={setGlow} />
          <p className="text-lg text-white">Follow Us</p>
        </div>
      </div>
      <div className="relative flex grow items-center justify-center px-6">
        <div className="flex flex-row items-center gap-3 rounded-full border border-dashed border-[#747474]/40 px-4 py-3">
          <a className="relative aspect-square h-[40px] opacity-70 hover:cursor-blue hover:opacity-100">
            <Image
              src={"/follow/twitter.svg"}
              alt="twitter"
              fill
              className="object-contain"
            />
          </a>
          <a className="relative aspect-square h-[58px] opacity-70 hover:cursor-blue hover:opacity-100">
            <Image
              src={"/follow/discord.svg"}
              alt="discord"
              fill
              className="object-contain"
            />
          </a>
          <a className="relative aspect-square h-[58px] opacity-70 hover:cursor-blue hover:opacity-100">
            <Image
              src={"/follow/farcaster.svg"}
              alt="farcaster"
              fill
              className="object-contain"
            />
          </a>
        </div>
        <div className="absolute bottom-8 right-6 flex items-end gap-2">
          <div className="relative aspect-square h-[50px]">
            <Image
              src={"/follow/arrow-swirl.svg"}
              alt="arrow-swirl"
              fill
              className="scale-x-110 object-contain"
            />
          </div>
          <p className="text-xs text-[#747474]/65">Follow Us For More</p>
        </div>
      </div>
    </div>
  );
};

export default Follow;
