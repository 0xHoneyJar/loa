import Image from "next/image";
import { DEVELOPMENT } from "@/constants/development";
import DragHandle from "../drag-handle";
import { useState } from "react";

const Development = () => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-[1deg]"} relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="development" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-white" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#B8B8B8] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandle setGlow={setGlow} />
          <p className="whitespace-nowrap text-lg text-white">
            Development Pipeline
          </p>
        </div>
      </div>
      <div className="relative flex grow overflow-y-auto">
        <div className="h-full w-full overflow-y-auto overflow-x-hidden py-6 pl-8">
          <div className="absolute left-0 top-0 z-10 h-1/6 w-full bg-gradient-to-b from-[#0F0F0F]" />
          <div className="absolute bottom-0 left-0 z-10 h-1/6 w-full bg-gradient-to-t from-[#0F0F0F]" />
          <div className="relative flex w-full flex-col gap-20 border-l border-dashed border-[#4C4C4C] pl-12 pt-6">
            <div className="relative flex flex-col gap-3">
              <div className="absolute -left-[54px] top-2 aspect-[4/1] h-[12px]">
                <Image
                  src={"/development-pointer.svg"}
                  alt="pointer"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="text-lg text-[#F4C10B]">1st Quarter, 2024</p>
              {DEVELOPMENT.filter((item) => item.quarter === 1).map(
                (item, id) => (
                  <div className="flex gap-2" key={id}>
                    <div className="relative aspect-square h-[24px]">
                      <Image
                        src={"/development-arrow.svg"}
                        alt="arrow"
                        fill
                        className="object-contain"
                      />
                    </div>
                    <p className="whitespace-nowrap">{item.name}</p>
                    <p className="font-light text-[#424242]/90">{item.date}</p>
                  </div>
                ),
              )}
            </div>
            <div className="relative flex flex-col gap-3">
              <div className="absolute -left-[54px] top-2 aspect-[4/1] h-[12px]">
                <Image
                  src={"/development-pointer.svg"}
                  alt="pointer"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="text-lg text-[#F4C10B]">2nd Quarter, 2024</p>
              {DEVELOPMENT.filter((item) => item.quarter === 2).map(
                (item, id) => (
                  <div className="flex gap-2" key={id}>
                    <div className="relative aspect-square h-[24px]">
                      <Image
                        src={"/development-arrow.svg"}
                        alt="arrow"
                        fill
                        className="object-contain"
                      />
                    </div>
                    <p className="whitespace-nowrap">{item.name}</p>
                    <p className="font-light text-[#424242]/90">{item.date}</p>
                  </div>
                ),
              )}
            </div>
            <div className="relative flex flex-col gap-3">
              <div className="absolute -left-[54px] top-2 aspect-[4/1] h-[12px]">
                <Image
                  src={"/development-pointer.svg"}
                  alt="pointer"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="text-lg text-[#F4C10B]">4th Quarter, 2024</p>
              {DEVELOPMENT.filter((item) => item.quarter === 4).map(
                (item, id) => (
                  <div className="flex gap-2" key={id}>
                    <div className="relative aspect-square h-[24px]">
                      <Image
                        src={"/development-arrow.svg"}
                        alt="arrow"
                        fill
                        className="object-contain"
                      />
                    </div>
                    <p className="whitespace-nowrap">{item.name}</p>
                    <p className="font-light text-[#424242]/90">{item.date}</p>
                  </div>
                ),
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Development;
