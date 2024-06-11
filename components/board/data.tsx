import Image from "next/image";

const Data = () => {
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
          <p className="text-[#FFD700] text-lg">Data</p>
        </div>
      </div>
      <div className="flex grow flex-col">
        <div className="flex flex-col p-6 border-b border-[#F4C10B]/20">
          <div className="flex gap-2 items-center mb-2">
            <div className="h-[20px] aspect-square relative">
              <Image
                src={"/raised.svg"}
                alt="raised"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-lg font-medium">Total Raised</p>
          </div>
          <p className="text-[#E4E4E4] mb-6">
            How much was raised by THJ and Berachain eco in general
          </p>
          <div className="w-full p-6 bg-[#F8A9291F] rounded-xl relative mb-4 border border-[#F8A9290F]">
            <p className="font-medium text-5xl text-[#F8A929]">5,042,000</p>
            <p className="text-sm text-[#A9A9A9]/50 flex items-center gap-1 absolute right-2 bottom-2">
              / By Bera Eco
            </p>
          </div>
          <div className="w-full p-6 bg-[#F8A9291F] rounded-xl relative mb-4 border border-[#F8A9290F]">
            <p className="font-medium text-5xl text-[#F8A929]">9,000,000</p>
            <p className="text-sm text-[#A9A9A9]/50 flex items-center gap-1 absolute right-2 bottom-2">
              / By THJ
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}

export default Data