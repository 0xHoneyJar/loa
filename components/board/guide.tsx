import Image from "next/image";

const Guide = () => {
  return (
    <div className="flex flex-col justify-end border-2 bg-[#0F0F0F] rounded-2xl border-[#FFFFFF0A] overflow-hidden h-full relative">
      <div className="absolute -top-40 w-full h-1" id="guide" />
      <Image src={"/guide.png"} alt="guide" fill className="object-cover" />
      <div className="h-1/2 w-full absolute bottom-0 bg-gradient-to-t from-[#0E0D09]" />
      <div className="flex w-full justify-between p-6 items-center z-10">
        <div className="flex gap-2 items-center">
          <div className="h-[26px] aspect-square relative dragHandle">
            <Image
              src={"/drag-handle.svg"}
              alt="drag"
              fill
              className="object-contain"
            />
          </div>
          <p className="text-3xl font-medium text-white">
            New to THJ? Start with THJ 101 Guide!
          </p>
        </div>
        <button className="py-2 px-8 bg-[#F4C10B] text-black text-lg font-medium rounded-full hover:shadow-yellow">
          Visit Us
        </button>
      </div>
    </div>
  );
};

export default Guide;
