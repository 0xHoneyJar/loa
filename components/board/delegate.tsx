import { DelegateButton } from "@/components/ui/buttons";
import Image from "next/image";

const Delegate = () => {
  return (
    <div className="relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFCA0C] bg-gradient-to-br from-[#FFC100] to-[#F8A929] p-2">
      <div className="absolute -top-40 h-1 w-full" id="delegate" />
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
          Boost The Honey Jar <span className="font-light">(THJ)</span>
        </p>
        <div className="relative rounded-full border border-dashed border-black/40 p-1 md:p-2">
          <DelegateButton />
          <div className="absolute -bottom-6 -left-8 my-auto aspect-square h-12 lg:h-[52px]">
            <Image
              src={"/arrow-delegate.svg"}
              alt="arrow"
              fill
              className="scale-150 object-contain"
            />
          </div>
          <div className="absolute -right-8 -top-6 my-auto aspect-square h-12 lg:h-[52px]">
            <Image
              src={"/arrow-delegate-dashed.svg"}
              alt="arrow"
              fill
              className="scale-150 object-contain"
            />
          </div>
        </div>
        <p className="text-base text-[#414141]">
          Help us make the Fat Bera Thesis come true! Boost THJ and get
          rewarded!
        </p>
      </div>
    </div>
  );
};

export default Delegate;
