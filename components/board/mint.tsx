import Image from "next/image";
import { LockKeyhole, ArrowUpRight } from "lucide-react";

const Mint = () => {
  return (
    <div className="relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]">
      <div className="absolute -top-40 h-1 w-full" id="mint" />
      <div className="h-2 w-full rounded-t-3xl bg-[#FFD700]" />
      <div className="flex h-16 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-6">
        <div className="flex items-center gap-2">
          <LockKeyhole className="aspect-square h-[26px] text-[#FFD7004D]" />
          <p className="whitespace-nowrap text-lg text-[#FFD700]">New Mint</p>
        </div>
        <button className="flex items-center gap-1 text-lg font-medium text-[#848484] hover:text-white">
          Explore <ArrowUpRight size={24} />
        </button>
      </div>
      <div className="flex grow p-6">
        <div className="grid h-full w-full grid-cols-5 gap-6">
          <div className="flex h-full w-full flex-col divide-y divide-[#F4C10B14] rounded-lg border border-[#F4C10B14] bg-[#221C11] hover:cursor-blue hover:divide-[#F4C10B47] hover:border-[#F4C10B47] hover:bg-[#423520]">
            <div className="h-4/5 w-full p-2">
              <div className="relative flex h-full w-full flex-col justify-between overflow-hidden rounded-t-lg p-2">
                <Image
                  src={"/mint.png"}
                  alt="mint"
                  fill
                  className="object-cover"
                />
                <div className="bg-[#D8D8D8]/10 px-4 py-1 z-10 rounded-full w-fit">
                  <p className="text-xs font-light text-[#AFAFAF]">
                    24:10:59 <span className="text-[#525252]">left</span>
                  </p>
                </div>
                <div className="z-10 flex flex-col">
                  <p className="text-sm text-[#FBFBFB]">The Title For Sure</p>
                  <p className="text-xs text-[#A9A9A9]">Placeholder</p>
                </div>
              </div>
            </div>
            <div className="flex h-1/5 w-full items-center justify-between px-2">
              <div className="flex items-center gap-2">
                <div className="relative aspect-square h-[20px]">
                  <Image src={"/thj-logo.png"} alt="logo" fill />
                </div>
                <p className="whitespace-nowrap text-xs text-[#6B6B6B]">
                  By the Honey
                </p>
              </div>
              <div className="flex flex-col items-end">
                <div className="flex items-center gap-1">
                  <div className="relative aspect-square h-[12px]">
                    <Image src={"/eth.svg"} alt="eth" fill />
                  </div>
                  <p className="text-sm font-semibold text-white">12.00</p>
                </div>
                <p className="text-[8px] text-[#9E9E9E]">$123,145.00</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Mint;
