import Image from "next/image";
import { Map, ChevronRight, ArrowRight, HelpCircle } from "lucide-react";
import { motion } from "framer-motion";
import { useState } from "react";
import DragHandle from "../drag-handle";

const Partners = () => {
  const [hover, setHover] = useState(false);
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-[1deg]"} relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#121A12] bg-[#10120D]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="partners" />
      <div className="h-2 w-full rounded-t-3xl bg-[#43AA77]" />
      <div className="relative flex h-16 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#43AA77] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandle setGlow={setGlow} />
          <p className="text-lg text-white">Partners</p>
        </div>
      </div>
      <div className="flex grow flex-col">
        <div className="flex w-full flex-col justify-center gap-5 p-6">
          <p className="text-[#A9A9A9]">
            THJ has a vast and constantly growing network of partners. Many of
            them are providing perks to Honeycomb holders.
          </p>
          <div className="relative w-full rounded-xl bg-[#43AA772E] px-4 py-6">
            <p className="text-5xl font-medium text-[#00AB55]">561</p>
            <p className="absolute bottom-4 right-4 flex items-center gap-1 text-sm text-[#A9A9A9]">
              / Total Partners <HelpCircle size={14} />
            </p>
          </div>
          <div className="relative w-full rounded-xl bg-[#43AA772E] px-4 py-6">
            <p className="text-5xl font-medium text-[#00AB55]">$9,000,000</p>
            <p className="absolute bottom-4 right-4 flex items-center gap-1 text-sm text-[#A9A9A9]">
              / Raised <HelpCircle size={14} />
            </p>
          </div>
          <button className="flex items-center justify-between rounded-lg border border-[#E8E8E80A] bg-[#FFFFFF0A] px-4 py-3 hover:cursor-blue hover:border-[#E8E8E81F] hover:bg-[#FFFFFF24]">
            <div className="flex gap-2">
              <Map />
              THJ Partner Map
            </div>
            <ChevronRight size={18} className="text-[#FFFFFF66]" />
          </button>
          <button className="flex items-center justify-between rounded-lg border border-[#E8E8E80A] bg-[#FFFFFF0A] px-4 py-3 hover:cursor-blue hover:border-[#E8E8E81F] hover:bg-[#FFFFFF24]">
            <div className="flex gap-2">
              <div className="relative aspect-square h-[28px]">
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
        <div className="relative flex w-full grow items-center justify-center border-t border-[#43AA771A] px-6">
          <div className="absolute -bottom-2 -left-0 aspect-square h-[40px]">
            <Image
              src={"/arrow-swirl-partner.svg"}
              alt="arrow-swirl"
              fill
              className="object-contain"
            />
          </div>
          <div className="absolute -right-0 -top-2 aspect-square h-[40px] rotate-180">
            <Image
              src={"/arrow-swirl-partner.svg"}
              alt="arrow-swirl"
              fill
              className="object-contain"
            />
          </div>
          <div className="w-full rounded-full border border-dashed border-[#9F9F9F63] p-2">
            <button
              onMouseEnter={() => setHover(true)}
              onMouseLeave={() => setHover(false)}
              style={{
                justifyContent: !hover ? "flex-start" : "flex-end",
              }}
              className="flex w-full items-center rounded-full bg-[#43AA77] px-2 py-1 text-lg font-semibold text-black hover:cursor-blue"
            >
              <motion.div
                layout
                className={`z-10 flex aspect-square h-[40px] items-center justify-center rounded-full ${
                  hover ? "bg-white" : "bg-[#171717]"
                }`}
                transition={{ duration: 0.3 }}
              >
                <ArrowRight className="text-[#43AA77]" />
              </motion.div>
              <p
                className={`absolute inset-x-0 mx-auto ${
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
