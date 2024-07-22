import Image from "next/image";

const SecondaryTweetDisplay = ({ text }: { text: string }) => {
  return (
    <div
      className={`absolute -top-6 flex h-full w-full scale-90 flex-col divide-y divide-[#292929] rounded-lg bg-[#1E1E1E]/30`}
    >
      <div className="flex items-center gap-2 px-6 py-4">
        <div className="relative aspect-square h-[40px]">
          <Image src={"/thj-logo.png"} alt="logo" fill />
        </div>
        <div className="flex flex-col">
          <p className="text-xs text-white/30 md:text-base">The Honey Jar</p>
          <p className="text-[10px] text-[#ABABAB]/30 md:text-sm">
            @0xhoneyjar
          </p>
        </div>
      </div>
      <div className="flex h-full w-full overflow-hidden p-4 md:p-6">
        <p className="overflow-y-auto overflow-x-hidden text-xs font-light md:text-base">
          {text}
        </p>
      </div>
    </div>
  );
};

export default SecondaryTweetDisplay;
