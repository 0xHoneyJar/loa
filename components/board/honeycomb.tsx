import Image from "next/image";

const Honeycomb = () => {
  return (
    <div className="flex flex-col rounded-2xl overflow-hidden bg-gradient-to-b from-[#F8A92917] to-[#14131017] h-full border-2 border-[#F8A92952]">
      <div className="w-full h-2 bg-[#FFD700] rounded-t-3xl" />
      <div className="flex justify-between items-center py-6 px-8 border-b border-dashed border-[#F4C10B6B]">
        <div className="flex gap-2 items-center">
          <div className="h-[26px] aspect-square relative dragHandle">
            <Image
              src={"/drag-handle-y.svg"}
              alt="drag"
              fill
              className="object-contain"
            />
          </div>
          <p className="text-[#FFD700] text-lg">Honeycomb</p>
        </div>
        <div className="h-[34px] aspect-square rounded-full border border-[#353535] relative">
          <Image
            src={"/opensea.svg"}
            alt="opensea"
            fill
            className="object-contain p-1"
          />
        </div>
      </div>
      <div className="flex grow px-6 items-center justify-center"></div>
    </div>
  );
}

export default Honeycomb