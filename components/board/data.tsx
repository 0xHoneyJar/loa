import Image from "next/image";
import { useState } from "react";
import {
  CircularProgressbarWithChildren,
  buildStyles,
} from "react-circular-progressbar";
import DragHandleY from "../drag-handle-y";

const Data = () => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-1"} relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="data" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-20 md:px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#FFC500] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandleY setGlow={setGlow} />
          <p className="text-sm font-medium text-[#FFD700] md:text-base xl:text-xl">
            Data
          </p>
        </div>
      </div>
      <div className="flex grow flex-col">
        <div className="flex flex-col border-b border-[#F4C10B]/20 px-6 py-8">
          <div className="mb-2 flex items-center gap-2">
            <div className="relative aspect-square h-[20px]">
              <Image
                src={"/raised.svg"}
                alt="raised"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-lg font-medium">Total Raised</p>
          </div>
          <p className="mb-6 text-sm text-[#E4E4E4] xl:text-base">
            How much was raised by THJ and Berachain eco in general
          </p>
          <div className="relative mb-4 w-full rounded-xl border border-[#F8A9290F] bg-[#F8A9291F] px-4 py-6">
            <p className="text-3xl font-medium text-[#F8A929] md:text-4xl xl:text-5xl">
              $5,042,000
            </p>
            <p className="absolute bottom-2 right-2 flex items-center gap-1 text-sm text-[#A9A9A9]/50">
              / By Bera Eco
            </p>
          </div>
          <div className="relative w-full rounded-xl border border-[#F8A9290F] bg-[#F8A9291F] px-4 py-6">
            <p className="text-5xl font-medium text-[#F8A929]">$9,000,000</p>
            <p className="absolute bottom-2 right-2 flex items-center gap-1 text-sm text-[#A9A9A9]/50">
              / By THJ
            </p>
          </div>
        </div>
        <div className="flex flex-col border-b border-[#F4C10B]/20 px-6 py-8">
          <div className="mb-8 flex items-center gap-2">
            <div className="relative aspect-square h-[20px]">
              <Image
                src={"/faucet.svg"}
                alt="faucet"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-lg font-medium">THJ Faucet</p>
          </div>
          <div className="mb-10 flex grow-0 items-center justify-center">
            <CircularProgressbarWithChildren
              value={75}
              strokeWidth={14}
              styles={buildStyles({
                rotation: 0.7,
                strokeLinecap: "butt",
                pathColor: "#F5DA7F",
                trailColor: "#342911",
              })}
              className="size-full max-h-[240px]"
            >
              {/* <p className="text-xl font-medium">500,000</p>
              <p className="text-sm">Total Wallets</p> */}
              <div className="flex size-full flex-col items-center justify-center">
                <p className="text-xl font-medium">500,000</p>
                <p className="text-sm">Total Wallets</p>
              </div>
              <p className="absolute -left-0 bottom-0 text-sm font-medium text-[#7E6E4B]">
                25%
              </p>
              <p className="absolute -right-0 top-0 text-sm font-medium text-[#F5DA7F]">
                75%
              </p>
            </CircularProgressbarWithChildren>
          </div>
          <div className="flex justify-center gap-4 text-[#C7C7C7]">
            <div className="flex items-center justify-center gap-1">
              <div className="aspect-square h-[14px] rounded-full bg-[#F5DA7F]" />
              <p className="whitespace-nowrap text-xs font-light text-[#C7C7C7] md:text-sm">
                Don&apos;t Hold Honeycomb
              </p>
            </div>
            <div className="flex items-center justify-center gap-1">
              <div className="aspect-square h-[14px] rounded-full bg-[#342911]" />
              <p className="whitespace-nowrap text-xs font-light text-[#C7C7C7] md:text-sm">
                Hold Honeycomb
              </p>
            </div>
          </div>
        </div>
        <div className="flex grow flex-col p-6">
          <div className="mb-8 flex items-center gap-2">
            <div className="relative aspect-square h-[20px]">
              <Image
                src={"/faucet.svg"}
                alt="faucet"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-lg font-medium">Honeycomb Holders</p>
          </div>
          <div className="relative flex size-full flex-col items-center justify-between">
            <div className="flex w-full flex-col">
              <div className="mb-10 flex items-center justify-center">
                <CircularProgressbarWithChildren
                  value={75}
                  strokeWidth={14}
                  styles={buildStyles({
                    rotation: 0.7,
                    strokeLinecap: "butt",
                    pathColor: "#F5DA7F",
                    trailColor: "#342911",
                  })}
                  className="size-full max-h-[240px]"
                >
                  <p className="text-xl font-medium">50,000</p>
                  <p className="text-sm">Holders</p>
                  <p className="absolute -left-0 bottom-0 text-sm font-medium text-[#7E6E4B]">
                    25%
                  </p>
                  <p className="absolute -right-0 top-0 text-sm font-medium text-[#F5DA7F]">
                    75%
                  </p>
                </CircularProgressbarWithChildren>
              </div>
              <div className="flex justify-center gap-4 text-[#C7C7C7]">
                <div className="flex items-center justify-center gap-1">
                  <div className="aspect-square h-[14px] rounded-full bg-[#F5DA7F]" />
                  <p className="whitespace-nowrap text-xs font-light text-[#C7C7C7] md:text-sm">
                    Bera Holders
                  </p>
                </div>
                <div className="flex items-center justify-center gap-1">
                  <div className="aspect-square h-[14px] rounded-full bg-[#342911]" />
                  <p className="whitespace-nowrap text-xs font-light text-[#C7C7C7] md:text-sm">
                    Non-Bera Holders
                  </p>
                </div>
              </div>
            </div>
            <button className="flex w-full items-center justify-center gap-2 whitespace-nowrap rounded-lg bg-[#F4C10B] py-3 text-lg font-medium text-black hover:cursor-blue hover:shadow-yellow">
              <div className="relative aspect-square h-[18px]">
                <Image
                  src={"/dashboard.svg"}
                  alt="dashboard"
                  fill
                  className="object-contain"
                />
              </div>
              Honeycomb Dashboard
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Data;
