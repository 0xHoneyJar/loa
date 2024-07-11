import Image from "next/image";
import { useState } from "react";
import DragHandle from "../drag-handle";

const Feed = () => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#121A12] bg-[#10120D] ${glow && "rotate-[1deg]"}`}
    >
      <div className="absolute -top-40 h-1 w-full" id="feed" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#43AA77]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#43AA77] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandle setGlow={setGlow} />
          <p className="text-lg text-white">Feed</p>
        </div>
        <a className="relative aspect-square h-[34px] cursor-pointer rounded-full border border-[#353535]">
          <Image
            src={"/twitter.svg"}
            alt="twitter"
            fill
            className="object-contain p-2"
          />
        </a>
      </div>
      <div className="flex grow items-center justify-center"></div>
    </div>
  );
};

export default Feed;
