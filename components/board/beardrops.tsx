import Image from "next/image";

const Beardrops = () => {
  return (
    <div className="relative flex h-full flex-col justify-end overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]">
      <div className="absolute -top-40 h-1 w-full" id="guide" />
      <Image src={"/beardrops.png"} alt="" fill className="object-cover" />
      <div className="absolute bottom-0 h-1/2 w-full bg-gradient-to-t from-[#0E0D09]" />
      <div className="z-10 flex w-full items-center justify-between p-6">
        <div className="flex items-center gap-2">
          <div className="dragHandle relative aspect-square h-[26px]">
            <Image
              src={"/drag-handle.svg"}
              alt="drag"
              fill
              className="object-contain"
            />
          </div>
          <p className="text-xl font-medium text-white sm:text-2xl md:text-3xl">
            Beardrops
          </p>
        </div>
        <button className="rounded-full bg-[#F4C10B] px-6 py-1 text-sm font-medium text-black hover:shadow-yellow md:px-8 md:py-2 md:text-lg">
          Explore
        </button>
      </div>
    </div>
  );
};

export default Beardrops;
