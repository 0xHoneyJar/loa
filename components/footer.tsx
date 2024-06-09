import Image from "next/image";
import Marquee from "react-fast-marquee";

const Footer = () => {
  return (
    <div className="h-full w-full relative flex items-center flex-col">
      <div className="z-[-1] flex items-center justify-center aspect-square h-[1000px] absolute rounded-full border border-[#F5D01105] -top-72 p-4">
        <div className="h-[95%] w-[95%] rounded-full border border-[#F5D0110D] flex items-center justify-center">
          <div className="h-[90%] w-[90%] rounded-full border border-[#F5D0110D] flex items-center justify-center">
            <div className="h-[90%] w-[90%] rounded-full border border-[#F5D0110D] flex items-center justify-center">
              <div className="h-[90%] w-[90%] rounded-full border border-[#F5D0110D] flex items-center justify-center">
                <div className="h-1/2 w-1/2 bg-[#F8A9291F] blur-[80px]"/>
              </div>
            </div>
          </div>
        </div>
      </div>
      <Marquee
        autoFill
        // speed={50}
        className="z-[-1] overflow-hidden relative top-8"
      >
        <p
          className="font-bold text-[12rem] text-[#F5D0110D] leading-none"
          style={{
            WebkitTextStroke: "1px #F5D01145",
          }}
        >
          Lorem ipsum dolor sit amet, consectetur adipiscing elit.
        </p>
      </Marquee>
      <div className="h-[400px] w-full border-t border-dashed border-[#878787] flex text-white bg-[#121212]">
        <div className="w-2/5 h-full flex justify-end">
          <div className="h-full w-1/2 flex flex-col px-8 justify-center text-white">
            <p className="font-semibold text-2xl mb-2">Brand Kit</p>
            <p className="text-base w-3/4 mb-4">
              Lorem ipsum dolor sit amet, consectetur adipiscing elit.
            </p>
            <button className="rounded-xl border border-[#FEFEFE1A] flex px-3 py-1.5 w-fit text-[#DBDBDB]">
              Lorem ipsum
            </button>
          </div>
        </div>
        <div className="w-1/5 h-full border-x px-8 border-dashed border-[#DCE0E5] text-white flex justify-center flex-col relative">
          <div className="aspect-square h-[80px] absolute -top-16 inset-x-0 mx-auto">
            <Image
              src={"/jani-coin.png"}
              alt="jani-coin"
              fill
              className="object-contain"
            />
          </div>
          <p className="font-semibold text-2xl mb-2">Brand Kit</p>
          <p className="text-base w-3/4 mb-4">
            Lorem ipsum dolor sit amet, consectetur adipiscing elit.
          </p>
          <button className="rounded-xl border border-[#FEFEFE1A] flex px-3 py-1.5 w-fit text-[#DBDBDB]">
            Lorem ipsum
          </button>
        </div>
        <div className="w-2/5 h-full">
          <div className="h-full w-1/2 flex flex-col px-8 justify-center text-white">
            <p className="font-semibold text-2xl mb-2">Document</p>
            <p className="text-base w-3/4 mb-4">
              Lorem ipsum dolor sit amet, consectetur adipiscing elit.
            </p>
            <button className="rounded-xl border border-[#FEFEFE1A] flex px-3 py-1.5 w-fit text-[#DBDBDB]">
              Lorem ipsum
            </button>
          </div>
        </div>
      </div>
      <div className="h-[500px] text-white w-full bg-[#F4C10B] overflow-hidden flex items-center justify-center flex-col relative">
        <Image
          src={"/thj-outline.svg"}
          alt="thj-outline"
          fill
          className="object-contain !top-10 z-[1]"
        />
        <div className="aspect-square h-[100px] relative mb-8">
          <Image
            src={"/thj-white.svg"}
            alt="thj-white"
            fill
            className="object-contain"
          />
        </div>
        <p className="font-semibold text-7xl mb-4">Be a Part of the Honey Jar</p>
        <p className="text-lg mb-8 w-2/5 text-center">
          Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc
          vulputate libero et velit interdum, ac aliquet odio mattis.
        </p>
        <button className="rounded-xl px-6 py-2 bg-[#43AA77] z-10">
          Delegate Now
        </button>
        <div className="aspect-square h-[140px] absolute -bottom-6 inset-x-0 mx-auto left-80">
          <Image
            src={"/arrow-angled.svg"}
            alt="angled"
            fill
            className="object-contain"
          />
        </div>
      </div>
    </div>
  );
};

export default Footer;
