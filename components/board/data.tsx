import Image from "next/image";
import {
  CircularProgressbarWithChildren,
  buildStyles,
} from "react-circular-progressbar";

const Data = () => {
  return (
    <div className="relative flex flex-col rounded-2xl overflow-hidden bg-gradient-to-b from-[#F8A92917] to-[#14131017] h-full border-2 border-[#F8A92952]">
      <div className="absolute -top-40 w-full h-1" id="data" />
      <div className="w-full h-2 bg-[#FFD700] rounded-t-3xl" />
      <div className="flex justify-between items-center px-6 h-16 border-b border-dashed border-[#F4C10B6B]">
        <div className="flex gap-2 items-center">
          <div className="h-[26px] aspect-square relative dragHandle">
            <Image
              src={"/drag-handle-y.svg"}
              alt="drag"
              fill
              className="object-contain"
            />
          </div>
          <p className="text-[#FFD700] text-lg">Data</p>
        </div>
      </div>
      <div className="flex grow flex-col">
        <div className="flex flex-col p-6 border-b border-[#F4C10B]/20">
          <div className="flex gap-2 items-center mb-2">
            <div className="h-[20px] aspect-square relative">
              <Image
                src={"/raised.svg"}
                alt="raised"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-lg font-medium">Total Raised</p>
          </div>
          <p className="text-[#E4E4E4] mb-6">
            How much was raised by THJ and Berachain eco in general
          </p>
          <div className="w-full p-6 bg-[#F8A9291F] rounded-xl relative mb-4 border border-[#F8A9290F]">
            <p className="font-medium text-5xl text-[#F8A929]">5,042,000</p>
            <p className="text-sm text-[#A9A9A9]/50 flex items-center gap-1 absolute right-2 bottom-2">
              / By Bera Eco
            </p>
          </div>
          <div className="w-full p-6 bg-[#F8A9291F] rounded-xl relative mb-4 border border-[#F8A9290F]">
            <p className="font-medium text-5xl text-[#F8A929]">9,000,000</p>
            <p className="text-sm text-[#A9A9A9]/50 flex items-center gap-1 absolute right-2 bottom-2">
              / By THJ
            </p>
          </div>
        </div>
        <div className="flex flex-col p-6 border-b border-[#F4C10B]/20">
          <div className="flex gap-2 items-center mb-8">
            <div className="h-[20px] aspect-square relative">
              <Image
                src={"/faucet.svg"}
                alt="faucet"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-lg font-medium">THJ Faucet</p>
          </div>
          <div className="h-[240px] aspect-square mb-10 flex justify-center">
            <CircularProgressbarWithChildren
              value={75}
              strokeWidth={14}
              styles={buildStyles({
                rotation: 0.7,
                strokeLinecap: "butt",
                pathColor: "#F5DA7F",
                trailColor: "#342911",
              })}
              className="h-full w-full"
            >
              <p className="font-medium text-xl">500,000</p>
              <p className="text-sm">Total Wallets</p>
              <p className="font-medium text-sm text-[#7E6E4B] absolute -left-0 bottom-0">
                25%
              </p>
              <p className="font-medium text-sm text-[#F5DA7F] absolute -right-0 top-0">
                75%
              </p>
            </CircularProgressbarWithChildren>
          </div>
          <div className="flex gap-4 text-[#C7C7C7] justify-center">
            <div className="flex gap-1 items-center justify-center">
              <div className="h-[14px] aspect-square rounded-full bg-[#F5DA7F]" />
              <p className="font-light md:text-sm text-xs text-[#C7C7C7] whitespace-nowrap">
                Don&apos;t Hold Honeycomb
              </p>
            </div>
            <div className="flex gap-1 items-center justify-center">
              <div className="h-[14px] aspect-square rounded-full bg-[#342911]" />
              <p className="font-light md:text-sm text-xs text-[#C7C7C7] whitespace-nowrap">
                Hold Honeycomb
              </p>
            </div>
          </div>
        </div>
        <div className="flex flex-col p-6 grow">
          <div className="flex gap-2 items-center mb-8">
            <div className="h-[20px] aspect-square relative">
              <Image
                src={"/faucet.svg"}
                alt="faucet"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-lg font-medium">Honeycomb Holders</p>
          </div>
          <div className="h-full w-full items-center flex relative flex-col justify-between">
            <div className="flex flex-col w-full">
              <div className="h-[240px] aspect-square mb-10 flex justify-center">
                <CircularProgressbarWithChildren
                  value={75}
                  strokeWidth={14}
                  styles={buildStyles({
                    rotation: 0.7,
                    strokeLinecap: "butt",
                    pathColor: "#F5DA7F",
                    trailColor: "#342911",
                  })}
                  className="h-full w-full"
                >
                  <p className="font-medium text-xl">50,000</p>
                  <p className="text-sm">Holders</p>
                  <p className="font-medium text-sm text-[#7E6E4B] absolute -left-0 bottom-0">
                    25%
                  </p>
                  <p className="font-medium text-sm text-[#F5DA7F] absolute -right-0 top-0">
                    75%
                  </p>
                </CircularProgressbarWithChildren>
              </div>
              <div className="flex gap-4 text-[#C7C7C7] justify-center">
                <div className="flex gap-1 items-center justify-center">
                  <div className="h-[14px] aspect-square rounded-full bg-[#F5DA7F]" />
                  <p className="font-light md:text-sm text-xs text-[#C7C7C7] whitespace-nowrap">
                    Bera Holders
                  </p>
                </div>
                <div className="flex gap-1 items-center justify-center">
                  <div className="h-[14px] aspect-square rounded-full bg-[#342911]" />
                  <p className="font-light md:text-sm text-xs text-[#C7C7C7] whitespace-nowrap">
                    Non-Bera Holders
                  </p>
                </div>
              </div>
            </div>
            <button className="hover:cursor-blue whitespace-nowrap w-full py-3 flex items-center gap-2 justify-center hover:shadow-yellow text-black bg-[#F4C10B] rounded-lg font-medium text-lg">
              <div className="h-[18px] aspect-square relative">
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
}

export default Data