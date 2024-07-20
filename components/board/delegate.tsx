import Image from "next/image";

const Delegate = () => {
  return (
    <div className="relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFCA0C] bg-gradient-to-br from-[#FFC100] to-[#F8A929] p-2">
      <div className="absolute -top-40 h-1 w-full" id="delegate" />
      <div className="absolute inset-y-0 -bottom-12 left-0 my-auto aspect-square h-[52px]">
        <Image
          src={"/arrow-delegate.svg"}
          alt="arrow"
          fill
          className="scale-150 object-contain"
        />
      </div>
      <div className="absolute inset-y-0 -right-0 -top-20 my-auto aspect-square h-[52px]">
        <Image
          src={"/arrow-delegate-dashed.svg"}
          alt="arrow"
          fill
          className="scale-150 object-contain"
        />
      </div>
      <div className="relative flex h-full w-full flex-col gap-10 rounded-2xl border border-black/50 p-6">
        <div className="flex items-center gap-1">
          <div className="dragHandle relative aspect-square md:h-[26px] h-5">
            <Image
              src={"/drag-handle.svg"}
              alt="drag"
              fill
              className="object-contain"
            />
          </div>
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

        <p className="md:text-5xl text-3xl font-bold text-black">
          Delegate With The Honey Jar <span className="font-light">(THJ)</span>
        </p>
        <div className="rounded-full border border-dashed border-black/40 md:p-2 p-1">
          <button className="w-full rounded-full bg-black py-3 md:text-lg text-sm">
            Delegate Now
          </button>
        </div>
        <p className="md:text-2xl text-lg text-[#414141]">
          Help us make the Fat Bera Thesis come true! Delegate to THJ and get
          rewarded!
        </p>
      </div>
    </div>
  );
};

export default Delegate;
