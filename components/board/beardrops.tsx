import { trackEvent } from "@openpanel/nextjs";
import Image from "next/image";

const Validator = () => {
  return (
    <div
      className={`relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#121A12] bg-[#10120D]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="beardrops" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#43AA77]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#1B271B] px-4 md:h-[72px] md:px-6">
        <div className="flex items-center gap-2">
          <p className="text-base font-medium text-white md:text-lg">
            Beardrops
          </p>
        </div>
      </div>
      <div className="relative flex grow flex-col">
        <div className="h-[85%] w-full p-4 md:p-6">
          <div className="relative flex h-full w-full items-end overflow-hidden rounded-lg border border-[#1C1C1C] p-6">
            <Image
              src={"/beardrops.png"}
              alt="beardrops"
              fill
              className="object-cover"
            />
            <p className="z-10 text-sm md:text-base">
              Want to target one of the strongest cults on Berachain?
            </p>
            <div className="absolute bottom-0 left-0 h-1/2 w-full bg-gradient-to-t from-[#0E0D09]" />
          </div>
        </div>
        <div className="flex w-full items-center justify-between gap-4 border-t border-[#1B271B] p-4 md:p-6">
          <div className="hidden items-center gap-3 md:flex">
            <div className="relative aspect-square h-5">
              <Image
                src={"/parachute.svg"}
                alt="parachute"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-base">Snapshot Honeycomb in a single click</p>
          </div>
          <a
            target="_blank"
            href={"https://beardrops.0xhoneyjar.xyz/"}
            onClick={() => {
              trackEvent(`beardrops_snapshot`);
            }}
            className="flex size-full items-center justify-center rounded-full bg-[#43AA77] px-6 py-3 text-sm font-medium text-black hover:cursor-blue hover:shadow-evergreen md:w-auto md:px-8"
          >
            Snapshot
          </a>
        </div>
      </div>
    </div>
  );
};

export default Validator;
