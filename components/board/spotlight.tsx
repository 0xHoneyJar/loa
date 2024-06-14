import { ArrowUpRight } from "lucide-react";
import Image from "next/image";

const Spotlight = () => {
  return (
    <div className="relative flex flex-col rounded-2xl overflow-hidden bg-gradient-to-b from-[#F8A92917] to-[#14131017] h-full border-2 border-[#F8A92952]">
      <div className="absolute -top-40 w-full h-1" id="spotlight" />
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
          <p className="text-[#FFD700] text-lg mr-2">Spotlight</p>
          <div className="flex items-center rounded-full py-1 px-2 bg-[#F5D01124]">
            <p className="text-[#F5D011] uppercase text-xs">Don't miss it</p>
          </div>
        </div>
      </div>
      <div className="flex grow p-6 flex-col items-center gap-4">
        <div className="h-3/5 w-full relative rounded-lg overflow-hidden border border-[#1C1C1C]">
          <Image
            src={"/spotlight.png"}
            alt="spotlight"
            fill
            className="object-cover"
          />
        </div>
        <div className="h-2/5 w-full relative flex flex-col gap-3 justify-between">
          <div className="flex flex-col">
            <p className="text-[#FBFBFB] font-medium text-lg">Text</p>
            <p className="text-[#A9A9A9]">Details</p>
          </div>
          <button className="flex items-center py-3 px-4 bg-[#F4C10B]/10 rounded-lg justify-between text-[#F4C10B] hover:bg-[#F4C10B] hover:text-[#121212] hover:font-semibold hover:cursor-blue">
            Read Now <ArrowUpRight size={24} />
          </button>
        </div>
      </div>
    </div>
  );
};

export default Spotlight;
