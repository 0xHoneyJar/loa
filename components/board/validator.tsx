import Image from "next/image";
import {
  CircularProgressbarWithChildren,
  buildStyles,
} from "react-circular-progressbar";
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
      <div className="relative flex h-20 shrink-0 items-center justify-between border-b border-dashed border-[#1B271B] px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#43AA77] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandle setGlow={setGlow} />
          <p className="text-xl text-white font-medium">Validator</p>
        </div>
      </div>
      <div className="flex grow flex-col">
        <div className="grid h-full w-full grid-cols-3 gap-4 p-6">
          <div className="grid h-full w-full grid-rows-3 gap-4">
            <div className="flex h-full w-full flex-col items-center justify-center gap-4 rounded-xl border border-[#202020] bg-[#121212]">
              <p className="text-[#6B6B6B]">Delegated to THJ (BGT)</p>
              <div className="flex items-center gap-2 text-2xl">
                <p className="font-semibold">12,324</p>
                <div className="relative aspect-square h-[28px]">
                  <Image
                    src={"/delegate-bee.png"}
                    alt="bee"
                    fill
                    className="object-contain"
                  />
                </div>
              </div>
            </div>
            <div className="flex h-full w-full flex-col items-center justify-center gap-4 rounded-xl border border-[#202020] bg-[#121212]">
              <p className="text-[#6B6B6B]">Number of Delegators</p>
              <p className="text-2xl font-semibold">12,3245,213</p>
            </div>
            <div className="flex h-full w-full flex-col items-center justify-center gap-4 rounded-xl border border-[#202020] bg-[#121212]">
              <p className="text-[#6B6B6B]">Return per BGT</p>
              <div className="flex items-center gap-2 text-2xl">
                <p className="text-2xl font-semibold">$123.13</p>
                <div className="relative aspect-square h-[28px]">
                  <Image
                    src={"/bgt-honey.png"}
                    alt="honey"
                    fill
                    className="object-contain"
                  />
                </div>
              </div>
            </div>
          </div>
          <div className="grid h-full w-full grid-rows-3 gap-4">
            <div className="flex h-full w-full flex-col items-center justify-center gap-4 rounded-xl border border-[#202020] bg-[#121212]">
              <p className="text-[#6B6B6B]">Validator&apos;s Rank</p>
              <p className="text-2xl font-semibold">1st</p>
            </div>
            <div className="flex h-full w-full flex-col items-center justify-center gap-4 rounded-xl border border-[#202020] bg-[#121212]">
              <p className="text-[#6B6B6B]">Active Incentives</p>
              <p className="text-2xl font-semibold">
                $0{" "}
                {/* <span className="text-xs font-normal text-[#989898]">
                  (The Value)
                </span> */}
              </p>
            </div>
            <div className="flex h-full w-full flex-col items-center justify-center gap-4 rounded-xl border border-[#202020] bg-[#121212]">
              <p className="text-[#6B6B6B]">Reward Rate</p>
              <div className="flex items-center gap-2 text-2xl">
                <p className="font-semibold">12,324</p>
                <div className="relative aspect-square h-[28px]">
                  <Image
                    src={"/delegate-bee.png"}
                    alt="bee"
                    fill
                    className="object-contain"
                  />
                </div>
              </div>
            </div>
          </div>
          <div className="relative flex h-full w-full flex-col items-center rounded-2xl border border-[#202020] bg-[#121212] py-6">
            <div className="relative flex h-full w-full items-center justify-center flex-col">
              <p className="absolute top-0 text-[#6B6B6B]">Voting Power</p>
              <div className="aspect-square h-[135px] mb-8">
                <CircularProgressbarWithChildren
                  value={50}
                  strokeWidth={14}
                  styles={buildStyles({
                    rotation: 0.5,
                    strokeLinecap: "butt",
                    pathColor: "#43AA77",
                    trailColor: "#F4C10B",
                  })}
                >
                  <p className="absolute -left-10 text-sm font-medium text-[#C1C1C1]">
                    50%
                  </p>
                  <p className="absolute -right-10 text-sm font-medium text-[#C1C1C1]">
                    50%
                  </p>
                </CircularProgressbarWithChildren>
              </div>
              <div className=" flex justify-center gap-2 text-[#C7C7C7]">
                <div className="flex items-center justify-center gap-1">
                  <div className="aspect-square h-[14px] rounded-full bg-[#43AA77]" />
                  <p className="text-xs font-light md:text-sm">THJ</p>
                </div>
                <div className="flex items-center justify-center gap-1">
                  <div className="aspect-square h-[14px] rounded-full bg-[#F4C10B]" />
                  <p className="text-xs font-light md:text-sm">Other</p>
                </div>
              </div>
            </div>
          </div>
        </div>
        <div className="flex h-[112px] w-full shrink-0 items-center justify-between border-t border-[#1B271B] px-6">
          <div className="flex items-center gap-2">
            <div className="relative aspect-square h-[38px]">
              <Image
                src={"/jani-coin.png"}
                alt="jani-coin"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-xl font-light text-white">Needs Your Support</p>
          </div>
          <div className="flex items-center gap-2">
            <div className="relative aspect-square h-[100px]">
              <Image
                src={"/arrow-wiggle.svg"}
                alt="arrow-wiggle"
                fill
                className="object-contain"
              />
            </div>
            <div className="rounded-full border border-dashed border-[#848484] p-1.5">
              <button className="rounded-full bg-[#43AA77] px-6 py-2 font-medium text-black hover:cursor-blue hover:shadow-evergreen">
                Delegate Now
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Validator;
