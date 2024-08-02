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
      className={`${glow && "rotate-1"} relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#121A12] bg-[#10120D]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="partners" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#43AA77]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-[72px] md:px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#43AA77] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandle setGlow={setGlow} />
          <p className="text-sm font-medium text-white md:text-base">
            Partners
          </p>
        </div>
      </div>
      <div className="flex grow flex-col">
        <div className="flex w-full flex-col justify-center gap-4 p-4 md:gap-6 md:p-6">
          <p className="text-xs text-[#A9A9A9] md:text-sm">
            THJ has a vast and constantly growing network of partners. Many of
            them are providing perks to Honeycomb holders.
          </p>
          <div className="relative w-full rounded-xl bg-[#43AA772E] px-4 py-6">
            <p className="text-2xl font-medium text-[#00AB55] md:text-3xl xl:text-4xl">
              561
            </p>
            <p className="absolute bottom-2 right-2 flex items-center text-[10px] text-[#A9A9A9] md:text-xs">
              / Total Partners
              {/* <HelpCircle className="aspect-square h-3 md:h-[14px]" /> */}
            </p>
          </div>
          <div className="relative w-full rounded-xl bg-[#43AA772E] px-4 py-6">
            <p className="text-2xl font-medium text-[#00AB55] md:text-3xl xl:text-4xl">
              $9,000,000
            </p>
            <p className="absolute bottom-2 right-2 flex items-center text-[10px] text-[#A9A9A9] md:text-xs">
              / Raised
              {/* <HelpCircle className="aspect-square h-3 md:h-[14px]" /> */}
            </p>
          </div>
          <button className="flex items-center justify-between rounded-lg border border-[#E8E8E80A] bg-[#FFFFFF0A] px-4 py-3 hover:cursor-blue hover:border-[#E8E8E81F] hover:bg-[#FFFFFF24]">
            <div className="flex items-center gap-2 whitespace-nowrap">
              <Map className="aspect-square h-4 md:h-[22px]" />
              <p className="text-xs md:text-sm">THJ Partner Map</p>
            </div>
            <ChevronRight className="aspect-square h-3 text-[#FFFFFF66] md:h-[14px]" />
          </button>
          <button className="flex items-center justify-between rounded-lg border border-[#E8E8E80A] bg-[#FFFFFF0A] px-4 py-3 hover:cursor-blue hover:border-[#E8E8E81F] hover:bg-[#FFFFFF24]">
            <div className="flex items-center gap-2 whitespace-nowrap">
              <div className="relative aspect-square h-4 md:h-[22px]">
                <Image
                  src={"/partners.svg"}
                  alt="partners"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="text-xs md:text-sm">Explore Partners</p>
            </div>
            <ChevronRight className="aspect-square h-3 text-[#FFFFFF66] md:h-[14px]" />
          </button>
        </div>
        <div className="relative flex w-full grow items-center justify-center border-t border-[#43AA771A] px-4 md:px-6">
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
              className="flex w-full items-center rounded-full bg-[#43AA77] px-2 py-1 text-sm font-semibold text-black hover:cursor-blue md:text-base xl:text-lg"
            >
              <motion.div
                layout
                className={`z-10 flex aspect-square h-6 items-center justify-center rounded-full md:h-8 ${
                  hover ? "bg-white" : "bg-[#171717]"
                }`}
                transition={{ duration: 0.3 }}
              >
                <ArrowRight className="text-[#43AA77]" />
              </motion.div>
              <p
                className={`absolute inset-x-0 mx-auto text-xs md:text-sm lg:left-6 xl:left-0 ${
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
