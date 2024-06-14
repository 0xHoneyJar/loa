import Image from "next/image";

const Delegate = () => {
  return (
    <div className="flex flex-col relative border-2 bg-gradient-to-br from-[#FFC100] to-[#F8A929] rounded-2xl border-[#FFCA0C] overflow-hidden h-full p-2">
      <div className="absolute -top-40 w-full h-1" id="delegate" />
      <div className="aspect-square h-[52px] absolute inset-y-0 my-auto left-0 -bottom-12">
        <Image
          src={"/arrow-delegate.svg"}
          alt="arrow"
          fill
          className="object-contain scale-150"
        />
      </div>
      <div className="aspect-square h-[52px] absolute inset-y-0 my-auto -right-0 -top-20">
        <Image
          src={"/arrow-delegate-dashed.svg"}
          alt="arrow"
          fill
          className="object-contain scale-150"
        />
      </div>
      <div className="h-full w-full border border-black/50 rounded-2xl flex flex-col relative gap-10 p-6">
        <div className="flex gap-3 items-center">
          <div className="aspect-square h-[44px] relative">
            <Image
              src={"/thj-logo.png"}
              alt="thj-logo"
              fill
              className="object-contain"
            />
          </div>
          <div className="aspect-square h-[44px] relative">
            <Image
              src={"/jani-coin.png"}
              alt="jani-coin"
              fill
              className="object-contain"
            />
          </div>
        </div>
        <p className="font-bold text-5xl text-black">
          Delegate With The Honey Jar <span className="font-light">(THJ)</span>
        </p>
        <div className="border rounded-full border-dashed border-black/40 p-2">
          <button className="py-3 bg-black w-full rounded-full text-lg">
            Delegate Now
          </button>
        </div>
        <p className="text-2xl text-[#414141]">
          Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc
          vulputate libero et velit interdum, ac aliquet odio mattis. Class
          aptent taciti sociosqu.
        </p>
      </div>
    </div>
  );
};

export default Delegate;
