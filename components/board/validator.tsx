import Image from "next/image";

const Validator = () => {
  return (
    <div className="flex flex-col border-2 bg-[#10120D] rounded-2xl border-[#121A12] overflow-hidden h-full">
      <div className="w-full h-2 bg-[#43AA77] rounded-t-3xl" />
      <div className="flex justify-between items-center py-6 px-8 border-b border-dashed border-[#1B271B]">
        <div className="flex gap-2 items-center">
          <div className="h-[26px] aspect-square relative dragHandle">
            <Image
              src={"/drag-handle.svg"}
              alt="drag"
              fill
              className="object-contain"
            />
          </div>
          <p className="text-white text-lg">Validator</p>
        </div>
      </div>
      <div className="flex grow flex-col">
        <div className="h-4/5 w-full grid grid-cols-4 p-6 gap-8">
          <div className="h-full w-full bg-[#121212] border border-[#161616] rounded-2xl flex flex-col py-6 items-center">
            <p className="text-[#6B6B6B]">Delegated to THJ (BGT)</p>
            <div className="h-full w-full items-center justify-center flex">
              <p className="font-semibold text-white text-6xl">12,324</p>
            </div>
          </div>
          <div className="h-full w-full bg-[#121212] border border-[#161616] rounded-2xl flex flex-col py-6 items-center">
            <p className="text-[#6B6B6B]">Amount of Delegators</p>
            <div className="h-full w-full items-center justify-center flex">
              <p className="font-semibold text-white text-6xl">12,324</p>
            </div>
          </div>
          <div className="h-full w-full bg-[#121212] border border-[#161616] rounded-2xl flex flex-col py-6 items-center">
            <p className="text-[#6B6B6B]">Amount of Delegators</p>
            <div className="h-full w-full items-center justify-center flex">
              <p className="font-semibold text-white text-6xl">21st</p>
            </div>
          </div>
          <div className="h-full w-full bg-[#121212] border border-[#161616] rounded-2xl flex flex-col py-6 items-center">
            <p className="text-[#6B6B6B]">Voting Rank</p>
            <div className="h-full w-full items-center justify-center flex"></div>
          </div>
        </div>
        <div className="h-1/5 w-full flex justify-between items-center border-t border-[#1B271B] px-6">
          <div className="flex gap-2 items-center">
            <div className="aspect-square h-[38px] relative">
              <Image
                src={"/jani-coin.png"}
                alt="jani-coin"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-white text-xl font-light">
              <span className="font-medium">THJ</span> Needs Your Vote! Delegate
              to THJ Now
            </p>
          </div>
          <div className="flex gap-2 items-center">
            <div className="aspect-square h-[100px] relative">
              <Image
                src={"/arrow-wiggle.svg"}
                alt="arrow-wiggle"
                fill
                className="object-contain"
              />
            </div>
            <div className="p-1.5 border border-dashed rounded-full border-[#848484]">
              <button className="px-6 py-2 bg-[#43AA77] rounded-full text-black">
                Delegate Now
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Validator;
