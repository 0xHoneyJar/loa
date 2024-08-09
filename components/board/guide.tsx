import Image from "next/image";
import { trackEvent } from "@openpanel/nextjs";
const Guide = () => {
  return (
    <div className="relative flex h-full flex-col justify-end overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]">
      <div className="absolute -top-40 h-1 w-full" id="guide" />
      <Image src={"/guide.png"} alt="guide" fill className="object-cover" />
      <div className="absolute bottom-0 h-1/2 w-full bg-gradient-to-t from-[#0E0D09]" />
      <div className="z-10 flex h-full w-full flex-col items-center justify-between gap-4 p-6 md:h-auto md:flex-row">
        <div className="flex items-center gap-2">
          <p className="text-center text-lg font-medium text-white md:text-left md:text-xl">
            New to THJ? Start with THJ 101 Guide!
          </p>
        </div>
        <a
          href={
            "https://0xhoneyjar.mirror.xyz/dHB3l29gAfLsPhPUPLGvg6_UAM1LxgxHMSJ054_QuDM"
          }
          onClick={() => {
            trackEvent(`explore_guide`);
          }}
          target="_blank"
          className="w-full cursor-blue whitespace-nowrap rounded-full bg-[#F4C10B] px-6 py-3 text-center text-sm font-medium text-black hover:shadow-yellow md:w-auto md:px-8 md:text-left"
        >
          Explore
        </a>
      </div>
    </div>
  );
};

export default Guide;
