import Image from "next/image";
import { Map, ChevronRight, ArrowRight, HelpCircle } from "lucide-react";
import { motion } from "framer-motion";
import { useState } from "react";

const Partners = () => {
  const [hover, setHover] = useState(false);
  return (
    <div className="flex flex-col border-2 bg-[#10120D] rounded-2xl border-[#121A12] overflow-hidden h-full">
      <div className="w-full h-2 bg-[#43AA77] rounded-t-3xl" />
      <div className="flex justify-between items-center py-6 px-8 border-b border-dashed border-[#FFFFFF1F]">
        <div className="flex gap-2 items-center">
          <div className="h-[26px] aspect-square relative dragHandle">
            <Image
              src={"/drag-handle.svg"}
              alt="drag"
              fill
              className="object-contain"
            />
          </div>
          <p className="text-white text-lg">Partners</p>
        </div>
      </div>
      <div className="flex grow flex-col">
        <div className="h-4/5 w-full flex flex-col px-8 justify-center gap-5">
          <p className="text-[#A9A9A9]">
            THJ has a vast and constantly growing network of partners. Many of
            them are providing perks to Honeycomb holders.
          </p>
          <div className="w-full p-6 bg-[#43AA772E] rounded-xl relative">
            <p className="font-medium text-5xl text-[#00AB55]">561</p>
            <p className="text-sm text-[#A9A9A9] flex items-center gap-1 absolute right-6 bottom-4">
              / Total Partners <HelpCircle size={14} />
            </p>
          </div>
          <div className="w-full p-6 bg-[#43AA772E] rounded-xl relative">
            <p className="font-medium text-5xl text-[#00AB55]">9,000,000</p>
            <p className="text-sm text-[#A9A9A9] flex items-center gap-1 absolute right-6 bottom-4">
              / Raised <HelpCircle size={14} />
            </p>
          </div>
          <button className="flex items-center justify-between rounded-lg bg-[#FFFFFF0A] border border-[#E8E8E80A] py-3 px-4 hover:cursor-blue hover:bg-[#FFFFFF24] hover:border-[#E8E8E81F]">
            <div className="flex gap-2">
              <Map />
              THJ Partner Map
            </div>
            <ChevronRight size={18} className="text-[#FFFFFF66]" />
          </button>
          <button className="flex items-center justify-between rounded-lg bg-[#FFFFFF0A] border border-[#E8E8E80A] py-3 px-4 hover:cursor-blue hover:bg-[#FFFFFF24] hover:border-[#E8E8E81F]">
            <div className="flex gap-2">
              <div className="aspect-square h-[28px] relative">
                <Image
                  src={"/partners.svg"}
                  alt="partners"
                  fill
                  className="object-contain"
                />
              </div>
              Explore Partners
            </div>
            <ChevronRight size={18} className="text-[#FFFFFF66]" />
          </button>
        </div>
        <div className="h-1/5 w-full flex items-center justify-center px-8 border-t border-[#43AA771A] relative">
          <div className="aspect-square h-[40px] absolute -left-0 -bottom-2">
            <Image
              src={"/arrow-swirl-partner.svg"}
              alt="arrow-swirl"
              fill
              className="object-contain"
            />
          </div>
          <div className="aspect-square h-[40px] absolute -right-0 -top-2 rotate-180">
            <Image
              src={"/arrow-swirl-partner.svg"}
              alt="arrow-swirl"
              fill
              className="object-contain"
            />
          </div>
          <div className="p-2 border border-dashed border-[#9F9F9F63] rounded-full w-full">
            <button
              onMouseEnter={() => setHover(true)}
              onMouseLeave={() => setHover(false)}
              style={{
                justifyContent: !hover ? "flex-start" : "flex-end",
              }}
              className="flex rounded-full bg-[#43AA77] px-2 py-1 items-center text-black font-semibold w-full hover:cursor-blue text-lg"
            >
              <motion.div
                layout
                className={`h-[40px] z-10 aspect-square rounded-full flex items-center justify-center ${
                  hover ? "bg-white" : "bg-[#171717]"
                }`}
                transition={{ duration: 0.3 }}
              >
                <ArrowRight className="text-[#43AA77]" />
              </motion.div>
              <p
                className={`absolute mx-auto inset-x-0 ${
                  hover && "text-white"
                }`}
              >
                Become a Partner
              </p>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Partners;
