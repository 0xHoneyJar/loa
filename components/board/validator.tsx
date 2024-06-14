import Image from "next/image";
import {
  CircularProgressbarWithChildren,
  buildStyles,
} from "react-circular-progressbar";

const Validator = () => {
  return (
    <div className="relative flex flex-col border-2 bg-[#10120D] rounded-2xl border-[#121A12] overflow-hidden h-full">
      <div className="absolute -top-40 w-full h-1" id="validator" />
      <div className="w-full h-2 bg-[#43AA77] rounded-t-3xl" />
      <div className="flex justify-between items-center px-6 h-16 border-b border-dashed border-[#1B271B]">
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
          <div className="h-full w-full bg-[#121212] border relative border-[#161616] rounded-2xl flex flex-col py-6 items-center">
            <div className="h-full w-full items-center justify-center flex relative">
              <p className="text-[#6B6B6B] absolute top-0">Voting Rank</p>
              <div className="h-[135px] aspect-square">
                <CircularProgressbarWithChildren
                  value={50}
                  strokeWidth={14}
                  styles={buildStyles({
                    rotation: 0.5,
                    strokeLinecap: "butt",
                    pathColor: "#43AA77",
                    trailColor: "#F4C10B",
                  })}
                >
                  <p className="font-medium text-sm text-[#C1C1C1] absolute -left-10">
                    50%
                  </p>
                  <p className="font-medium text-sm text-[#C1C1C1] absolute -right-10">
                    50%
                  </p>
                </CircularProgressbarWithChildren>
              </div>
              <div className="flex gap-2 text-[#C7C7C7] justify-center absolute bottom-0">
                <div className="flex gap-1 items-center justify-center">
                  <div className="h-[14px] aspect-square rounded-full bg-[#43AA77]" />
                  <p className="font-light md:text-sm text-xs">Lorem</p>
                </div>
                <div className="flex gap-1 items-center justify-center">
                  <div className="h-[14px] aspect-square rounded-full bg-[#F4C10B]" />
                  <p className="font-light md:text-sm text-xs">Lorem</p>
                </div>
              </div>
            </div>
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
              <button className="px-6 py-2 bg-[#43AA77] rounded-full text-black font-medium hover:shadow-evergreen hover:cursor-blue">
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
