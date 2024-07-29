import Image from "next/image";
import DragHandle from "../drag-handle";
import { useState } from "react";

const Validator = () => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-[1deg]"} relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#121A12] bg-[#10120D]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="validator" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#43AA77]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#1B271B] px-4 md:h-20 md:px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#43AA77] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandle setGlow={setGlow} />
          <p className="text-sm font-medium text-white md:text-base xl:text-xl">
            Beardrops
          </p>
        </div>
      </div>
      <div className="relative flex grow flex-col">
        <div className="h-[85%] w-full p-4 md:p-6">
          <div className="relative flex h-full w-full items-end overflow-hidden rounded-lg border border-[#1C1C1C] p-6">
            <Image
              src={"/beardrops.png"}
              alt="beardrops"
              fill
              className="object-cover"
            />
            <p className="z-10 text-sm md:text-base xl:text-lg">
              Want to target one of the strongest cults on Berachain?
            </p>
            <div className="absolute bottom-0 left-0 h-1/2 w-full bg-gradient-to-t from-[#0E0D09]" />
          </div>
        </div>
        <div className="flex h-[15%] w-full items-center justify-between border-t border-[#1B271B] p-4 md:p-6">
          <div className="flex items-center gap-2">
            <div className="relative aspect-square h-5 md:h-6 xl:h-[28px]">
              <Image
                src={"/parachute.svg"}
                alt="parachute"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-sm md:text-base xl:text-lg">
              Snapshot Honeycomb in a single click
            </p>
          </div>
          <button className="h-full rounded-full bg-[#43AA77] px-6 text-sm font-medium text-black hover:cursor-blue hover:shadow-evergreen md:text-base xl:text-lg">
            Snapshot
          </button>
        </div>
      </div>
    </div>
  );
};

export default Validator;
