import Image from "next/image";
import Marquee from "react-fast-marquee";

const Footer = () => {
  return (
    <div className="relative flex h-full w-full flex-col items-center">
      <div className="absolute -top-72 z-[-1] flex aspect-square h-[1000px] items-center justify-center rounded-full border border-[#F5D01105] p-4">
        <div className="absolute -top-20 h-[100px] w-1/4 bg-[#43AA7780] blur-[100px]" />
        <div className="flex h-[95%] w-[95%] items-center justify-center rounded-full border border-[#F5D0110D]">
          <div className="flex h-[90%] w-[90%] items-center justify-center rounded-full border border-[#F5D0110D]">
            <div className="flex h-[90%] w-[90%] items-center justify-center rounded-full border border-[#F5D0110D]">
              <div className="flex h-[90%] w-[90%] items-center justify-center rounded-full border border-[#F5D0110D]">
                <div className="h-1/2 w-1/2 bg-[#F8A9291F] blur-[80px]" />
              </div>
            </div>
          </div>
        </div>
      </div>
      <Marquee
        autoFill
        // speed={50}
        className="relative top-8 z-[-1] overflow-hidden"
      >
        <p
          className="text-[14rem] font-bold leading-none text-[#F5D0110D]"
          style={{
            WebkitTextStroke: "1px #F5D01145",
          }}
        >
          Based Community Gateway on Berachain
        </p>
      </Marquee>
      <div className="flex h-[400px] w-full border-t border-dashed border-[#878787] bg-[#0B0701] text-white">
        <div className="flex h-full w-2/5 justify-end">
          <div className="flex h-full w-1/2 flex-col justify-center px-8 text-white">
            <p className="mb-2 font-clash text-2xl font-semibold">
              Partnership Guidelines
            </p>
            <p className="mb-4 w-[90%] text-base">
              Learn what you get from becoming a THJ Partner
            </p>
            <button className="flex w-fit rounded-xl border border-[#FEFEFE1A] px-6 py-1.5 text-[#DBDBDB]">
              Learn More
            </button>
          </div>
        </div>
        <div className="relative flex h-full w-1/5 flex-col justify-center border-x border-dashed border-[#DCE0E5] px-8 text-white">
          <div className="absolute inset-x-0 -top-16 mx-auto aspect-square h-[80px]">
            <Image
              src={"/jani-coin.png"}
              alt="jani-coin"
              fill
              className="object-contain"
            />
          </div>
          <p className="mb-2 font-clash text-2xl font-semibold">Brand Kit</p>
          <p className="mb-4 w-[90%] text-base">
            Find all assets and guidelines of THJ branding here
          </p>
          <button className="flex w-fit rounded-xl border border-[#FEFEFE1A] px-6 py-1.5 text-[#DBDBDB]">
            Learn More
          </button>
        </div>
        <div className="h-full w-2/5">
          <div className="flex h-full w-1/2 flex-col justify-center px-8 text-white">
            <p className="mb-2 font-clash text-2xl font-semibold">
              Beekeeper Kit
            </p>
            <p className="mb-4 w-[90%] text-base">
              Product suite, integrations and co-markerting guidelines
            </p>
            <button className="flex w-fit rounded-xl border border-[#FEFEFE1A] px-6 py-1.5 text-[#DBDBDB]">
              Learn More
            </button>
          </div>
        </div>
      </div>
      <div className="relative flex w-full flex-col items-center gap-8 overflow-hidden bg-[#F4C10B] pt-20 text-white">
        <Image
          src={"/thj-outline.svg"}
          alt="thj-outline"
          fill
          className="!top-10 z-[1] object-contain"
        />
        <div className="relative aspect-square h-[100px]">
          <Image
            src={"/thj-white.svg"}
            alt="thj-white"
            fill
            className="object-contain"
          />
        </div>
        <p className="font-clash text-7xl font-semibold">
          Be a Part of the Honey Jar
        </p>
        <p className="w-2/5 text-center text-lg">
          By delegating to the THJ Validator, you help us to grow and contribute
        </p>
        <div className="relative flex items-center gap-2">
          <button className="z-10 w-[240px] rounded-xl bg-black py-3">
            Join the Commmunity
          </button>
          <button className="z-10 w-[240px] rounded-xl bg-[#43AA77] py-3">
            Delegate Now
          </button>
          <div className="absolute -bottom-28 -right-40 z-10 aspect-square h-[172px]">
            <Image
              src={"/arrow-angled.svg"}
              alt="angled"
              fill
              className="object-contain"
            />
          </div>
        </div>
        <div className="relative z-10 aspect-[1/1.9] h-[165px]">
          <Image
            src={"/jani-sweep.gif"}
            alt="sweep"
            fill
            className="object-cover"
            unoptimized={true}
          />
        </div>
      </div>
    </div>
  );
};

export default Footer;
