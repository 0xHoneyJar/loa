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
          className="text-[12rem] font-bold leading-none text-[#F5D0110D] lg:text-[14rem]"
          style={{
            WebkitTextStroke: "1px #F5D01145",
          }}
        >
          Based Community Gateway on Berachain
        </p>
      </Marquee>
      <div className="relative grid h-full w-full grid-cols-1 gap-2 border-t border-dashed border-[#878787] bg-[#0B0701] text-white sm:h-[300px] sm:grid-cols-3 sm:gap-0 md:h-[400px] xl:grid-cols-5">
        <div className="absolute inset-x-0 -top-12 mx-auto aspect-square h-[60px] md:-top-16 md:h-[80px]">
          <Image
            src={"/jani-coin.png"}
            alt="jani-coin"
            fill
            className="object-contain"
          />
        </div>
        <div className="hidden xl:flex" />
        {/* <div className="flex h-full w-full"> */}
        <div className="flex h-full w-full flex-col items-center justify-center px-4 py-3 text-white sm:items-start sm:py-0 md:px-8">
          <p className="mb-2 font-clash text-lg font-semibold md:text-xl xl:text-2xl">
            Partnership Guidelines
          </p>
          <p className="mb-4 w-full text-center text-xs sm:text-left md:w-[90%] md:text-sm xl:text-base">
            Learn what you get from becoming a THJ Partner
          </p>
          <button className="flex w-fit whitespace-nowrap rounded-xl border border-[#FEFEFE1A] px-6 py-1.5 text-xs text-[#DBDBDB] md:text-sm xl:text-base">
            Learn More
          </button>
        </div>
        {/* </div> */}
        <div className="relative flex h-full w-full flex-col items-center justify-center border-y border-dashed border-[#DCE0E5] px-4 py-3 text-white sm:items-start sm:border-x sm:border-y-0 sm:py-0 md:px-8">
          <p className="mb-2 whitespace-nowrap font-clash text-lg font-semibold md:text-xl xl:text-2xl">
            Brand Kit
          </p>
          <p className="mb-4 w-full text-center text-xs sm:text-left md:w-[90%] md:text-sm xl:text-base">
            Find all assets and guidelines of THJ branding here
          </p>
          <button className="flex w-fit whitespace-nowrap rounded-xl border border-[#FEFEFE1A] px-6 py-1.5 text-xs text-[#DBDBDB] md:text-sm xl:text-base">
            Learn More
          </button>
        </div>
        {/* <div className="h-full w-1/3 lg:w-full"> */}
        <div className="flex h-full w-full flex-col items-center justify-center px-4 py-3 text-white sm:items-start sm:py-0 md:px-8">
          <p className="mb-2 whitespace-nowrap font-clash text-lg font-semibold md:text-xl xl:text-2xl">
            Beekeeper Kit
          </p>
          <p className="mb-4 w-full text-center text-xs sm:text-left md:w-[90%] md:text-sm xl:text-base">
            Product suite, integrations and co-markerting guidelines
          </p>
          <button className="flex w-fit whitespace-nowrap rounded-xl border border-[#FEFEFE1A] px-6 py-1.5 text-xs text-[#DBDBDB] md:text-sm xl:text-base">
            Learn More
          </button>
        </div>
        {/* </div> */}
      </div>
      <div className="relative flex w-full flex-col items-center gap-4 overflow-hidden bg-[#F4C10B] pt-10 text-white md:gap-6 md:pt-20 lg:gap-8">
        <Image
          src={"/thj-outline.svg"}
          alt="thj-outline"
          fill
          className="!top-10 z-[1] object-cover md:object-contain"
        />
        <div className="relative aspect-square h-[60px] sm:h-[80px] md:h-[100px]">
          <Image
            src={"/thj-white.svg"}
            alt="thj-white"
            fill
            className="object-contain"
          />
        </div>
        <p className="text-center font-clash text-3xl font-semibold md:text-5xl xl:text-7xl">
          Be a Part of the Honey Jar
        </p>
        <p className="w-4/5 text-center text-sm sm:w-3/5 md:w-2/5 md:text-lg">
          By delegating to the THJ Validator, you help us to grow and contribute
        </p>
        <div className="relative flex flex-col items-center gap-2 sm:flex-row">
          <button className="z-10 w-[180px] rounded-xl bg-black py-3 text-xs font-medium md:w-[240px] md:text-base">
            Join the Commmunity
          </button>
          <button className="z-10 w-[180px] rounded-xl bg-[#43AA77] py-3 text-xs font-medium md:w-[240px] md:text-base">
            Delegate Now
          </button>
          <div className="absolute -bottom-24 -right-32 z-10 aspect-square h-[140px] md:-bottom-28 md:-right-40 md:h-[172px]">
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
