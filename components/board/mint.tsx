import Image from "next/image";
import { LockKeyhole, ArrowUpRight } from "lucide-react";

const Mint = () => {
  return (
    <div className="flex flex-col h-full rounded-2xl overflow-hidden bg-gradient-to-b from-[#F8A92917] to-[#14131017] border-2 border-[#F8A92952]">
      <div className="w-full h-2 bg-[#FFD700] rounded-t-3xl" />
      <div className="flex justify-between items-center py-6 px-8 border-b border-dashed border-[#F4C10B6B]">
        <div className="flex gap-2 items-center">
          <LockKeyhole className="h-[26px] aspect-square text-[#FFD7004D]" />
          <p className="text-[#FFD700] text-lg whitespace-nowrap">New Mint</p>
        </div>
        <button className="flex gap-1 items-center font-medium text-lg text-[#848484] hover:text-white">
          Explore <ArrowUpRight size={24}/>
        </button>
      </div>
      <div className="flex grow px-6 items-center justify-center"></div>
    </div>
  );
};

export default Mint;
