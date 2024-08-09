import Image from "next/image";
import { trackEvent } from "@openpanel/nextjs";

const Delegate = () => {
  return (
    <div className="relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFCA0C] bg-gradient-to-br from-[#FFC100] to-[#F8A929] p-2">
      <div className="absolute -top-40 h-1 w-full" id="delegate" />
      <div className="absolute inset-y-0 -bottom-0 left-0 my-auto aspect-square h-12 sm:-bottom-20 md:-bottom-0 lg:-bottom-16 lg:h-[52px] xl:-bottom-32 2xl:-bottom-12">
        <Image
          src={"/arrow-delegate.svg"}
          alt="arrow"
          fill
          className="scale-150 object-contain"
        />
      </div>
      <div className="absolute inset-y-0 -right-0 -top-28 my-auto aspect-square h-12 sm:-top-12 md:-top-32 lg:-top-16 lg:h-[52px] xl:-top-6 2xl:-top-24">
        <Image
          src={"/arrow-delegate-dashed.svg"}
          alt="arrow"
          fill
          className="scale-150 object-contain"
        />
      </div>
      <div className="relative flex size-full flex-col gap-10 rounded-2xl border border-black/50 p-6">
        <div className="flex items-center gap-1">
          <div className="relative aspect-square h-[36px] md:h-[44px]">
            <Image
              src={"/thj-logo.png"}
              alt="thj-logo"
              fill
              className="object-contain"
            />
          </div>
          <div className="relative aspect-square h-[36px] md:h-[44px]">
            <Image
              src={"/jani-coin.png"}
              alt="jani-coin"
              fill
              className="object-contain"
            />
          </div>
        </div>
        <p className="text-3xl font-bold text-black md:text-4xl xl:text-5xl">
          Delegate to The Honey Jar <span className="font-light">(THJ)</span>
        </p>
        <div className="rounded-full border border-dashed border-black/40 p-1 md:p-2">
          <a
            href={
              "https://bartio.station.berachain.com/delegate?action=delegate&validator=0x40495A781095932e2FC8dccA69F5e358711Fdd41"
            }
            onClick={() => {
              trackEvent(`delegate_thj`);
            }}
            target="_blank"
            className="flex w-full cursor-blue items-center justify-center rounded-full bg-black py-3 text-sm font-medium hover:bg-white hover:text-black md:text-base"
          >
            Delegate Now
          </a>
        </div>
        <p className="text-base text-[#414141]">
          Help us make the Fat Bera Thesis come true! Delegate to THJ and get
          rewarded!
        </p>
      </div>
    </div>
  );
};

export default Delegate;
