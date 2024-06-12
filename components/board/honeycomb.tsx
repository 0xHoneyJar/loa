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
      <div className="flex grow px-8">
        <div className="flex flex-col py-6 w-full">
          <div className="h-[220px] w-full relative rounded-xl overflow-hidden px-12 flex justify-end items-center">
            <Image
              src={"/honeycomb.png"}
              alt="honeycomb"
              fill
              className="object-cover"
            />
            <div className="flex flex-col gap-4 z-10 w-1/2">
              <p className="text-[#D1D1D1]">
                Honeycomb is an anti-hustle tech and a perk aggregator of the
                Berachain eco. It gives you whitelist to most projects in the
                ecosystem
              </p>
              <button className="flex gap-2 items-center border border-[#1E1E1E] bg-[#0F0D08] py-3 justify-center rounded-lg">
                <div className="h-[26px] aspect-square rounded-full relative">
                  <Image
                    src={"/opensea.svg"}
                    alt="opensea"
                    fill
                    className="object-contain p-1"
                  />
                </div>
                Buy a Honeycomb
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default Honeycomb