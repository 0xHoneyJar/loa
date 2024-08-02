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
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-[72px] md:px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#FFC500] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandleY setGlow={setGlow} />
          <p className="text-sm font-medium text-[#FFD700] md:text-base">
            Data
          </p>
        </div>
      </div>
      <div className="flex grow flex-col">
        <div className="flex flex-col border-b border-[#F4C10B]/20 p-4 md:p-6">
          <div className="mb-2 flex items-center gap-2">
            <div className="relative aspect-square h-4 md:h-5">
              <Image
                src={"/raised.svg"}
                alt="raised"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-sm font-medium md:text-base">Total Raised</p>
          </div>
          <p className="mb-4 text-xs text-[#E4E4E4] md:mb-6 md:text-sm">
            How much was raised by THJ and Berachain eco in general
          </p>
          <div className="relative mb-4 w-full rounded-xl border border-[#F8A9290F] bg-[#F8A9291F] px-2 py-4 md:px-4 md:py-6">
            <p className="text-2xl font-medium text-[#F8A929] md:text-3xl xl:text-4xl">
              $5,042,000
            </p>
            <p className="absolute bottom-2 right-2 flex items-center text-[10px] text-[#A9A9A9]/50 md:text-xs">
              / By Bera Eco
            </p>
          </div>
          <div className="relative w-full rounded-xl border border-[#F8A9290F] bg-[#F8A9291F] px-2 py-4 md:px-4 md:py-6">
            <p className="text-2xl font-medium text-[#F8A929] md:text-3xl xl:text-4xl">
              $9,000,000
            </p>
            <p className="absolute bottom-2 right-2 flex items-center text-[10px] text-[#A9A9A9]/50 md:text-xs">
              / By THJ
            </p>
          </div>
        </div>
        <div className="flex flex-col border-b border-[#F4C10B]/20 p-4 md:p-6">
          <div className="mb-10 flex items-center gap-2">
            <div className="relative aspect-square h-4 md:h-5">
              <Image
                src={"/faucet.svg"}
                alt="faucet"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-sm font-medium md:text-base">THJ Faucet</p>
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
              className="h-[180px] md:h-[200px]"
            >
              {/* <p className="text-xl font-medium">500,000</p>
              <p className="text-sm">Total Wallets</p> */}
              <div className="flex h-full w-full flex-col items-center justify-center">
                <p className="font-medium md:text-xl">500,000</p>
                <p className="text-xs md:text-sm">Total Wallets</p>
              </div>
              <p className="absolute -left-0 bottom-0 text-xs font-medium text-[#7E6E4B] md:text-sm">
                25%
              </p>
              <p className="absolute -right-0 top-0 text-xs font-medium text-[#F5DA7F] md:text-sm">
                75%
              </p>
            </CircularProgressbarWithChildren>
          </div>
          <div className="flex flex-row justify-center gap-4 text-[#C7C7C7] sm:flex-col 2xl:flex-row">
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
        <div className="flex grow flex-col p-4 md:p-6">
          <div className="mb-10 flex items-center gap-2">
            <div className="relative aspect-square h-4 md:h-5">
              <Image
                src={"/faucet.svg"}
                alt="faucet"
                fill
                className="object-contain"
              />
            </div>
            <p className="whitespace-nowrap text-sm font-medium md:text-base">
              Honeycomb Holders
            </p>
          </div>
          <div className="relative flex h-full w-full flex-col items-center justify-between">
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
                  className="h-[180px] md:h-[200px]"
                >
                  <p className="font-medium md:text-xl">50,000</p>
                  <p className="text-xs md:text-sm">Holders</p>
                  <p className="absolute -left-0 bottom-0 text-xs font-medium text-[#7E6E4B] md:text-sm">
                    25%
                  </p>
                  <p className="absolute -right-0 top-0 text-xs font-medium text-[#F5DA7F] md:text-sm">
                    75%
                  </p>
                </CircularProgressbarWithChildren>
              </div>
              <div className="flex flex-row justify-center gap-4 text-[#C7C7C7] sm:flex-col 2xl:flex-row">
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
            <a
              href={"https://dune.com/thj"}
              target="_blank"
              className="flex w-full items-center justify-center gap-2 whitespace-nowrap rounded-full bg-[#F4C10B] py-3 font-medium text-black hover:cursor-blue hover:shadow-yellow"
            >
              <div className="relative aspect-square h-3 md:h-4">
                <Image
                  src={"/dashboard.svg"}
                  alt="dashboard"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="text-xs md:text-base">Data Dashboards</p>
            </a>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Data;
