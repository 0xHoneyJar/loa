import Image from "next/image";
import { LockKeyhole, ArrowUpRight } from "lucide-react";

const Mint = () => {
  return (
    <div className="relative flex flex-col h-full rounded-2xl overflow-hidden bg-gradient-to-b from-[#F8A92917] to-[#14131017] border-2 border-[#F8A92952]">
      <div className="absolute -top-40 w-full h-1" id="mint" />
      <div className="w-full h-2 bg-[#FFD700] rounded-t-3xl" />
      <div className="flex justify-between items-center px-6 h-16 border-b border-dashed border-[#F4C10B6B]">
        <div className="flex gap-2 items-center">
          <LockKeyhole className="h-[26px] aspect-square text-[#FFD7004D]" />
          <p className="text-[#FFD700] text-lg whitespace-nowrap">New Mint</p>
        </div>
        <button className="flex gap-1 items-center font-medium text-lg text-[#848484] hover:text-white">
          Explore <ArrowUpRight size={24} />
        </button>
      </div>
      <div className="flex grow p-6">
        <div className="grid grid-cols-5 w-full h-full gap-6">
          <div className="h-full w-full bg-[#221C11] rounded-lg border border-[#F4C10B14] flex flex-col divide-y divide-[#F4C10B14] hover:bg-[#423520] hover:border-[#F4C10B47] hover:divide-[#F4C10B47] hover:cursor-blue">
            <div className="h-4/5 w-full p-2">
              <div className="h-full w-full rounded-t-lg relative overflow-hidden flex items-end">
                <Image
                  src={"/mint.png"}
                  alt="mint"
                  fill
                  className="object-cover"
                />
                <div className="flex flex-col z-10 p-2">
                  <p className="text-[#FBFBFB] text-sm">The Title For Sure</p>
                  <p className="text-[#A9A9A9] text-xs">Placeholder</p>
                </div>
              </div>
            </div>
            <div className="h-1/5 w-full flex justify-between items-center px-2">
              <div className="flex items-center gap-2">
                <div className="relative h-[20px] aspect-square">
                  <Image src={"/thj-logo.png"} alt="logo" fill />
                </div>
                <p className="text-[#6B6B6B] text-xs whitespace-nowrap">
                  By the Honey
                </p>
              </div>
              <div className="flex flex-col items-end">
                <div className="flex items-center gap-1">
                  <div className="relative h-[12px] aspect-square">
                    <Image src={"/eth.svg"} alt="eth" fill />
                  </div>
                  <p className="text-sm text-white font-semibold">12.00</p>
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
