import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import Image from "next/image";
import { ArrowUpRight, LockKeyhole } from "lucide-react";
import { useMemo } from "react";

const NewPartners = ({ partners }: { partners?: any }) => {
  const recentPartners = useMemo(() => {
    if (!partners || !Array.isArray(partners)) return [];

    return partners
      .filter((partner: any) => partner.partner && partner.logo)
      .reverse()
      .slice(0, 10);
  }, [partners]);

  return (
    <div className="relative h-full overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]">
      <div className="absolute -top-40 h-1 w-full" id="newPartners" />
      <Carousel className="flex h-full flex-col" opts={{ dragFree: true }}>
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
        <div className="flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-[72px] md:px-6">
          <div className="flex items-center gap-2">
            <LockKeyhole className="aspect-square h-5 text-[#FFD7004D] md:h-[26px]" />
            <p className="md:text-basel whitespace-nowrap text-base font-medium text-[#FFD700]">
              New Partners
            </p>
            <div className="hidden items-center gap-2 rounded-full border border-[#F8A9291F] bg-gradient-to-r from-[#F5D0110D] to-[#F8A9290D] px-2 py-1 sm:flex">
              <div className="relative aspect-square h-4 md:h-5">
                <Image
                  src={"/rise.svg"}
                  alt="rise"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="whitespace-nowrap bg-gradient-to-r from-[#F5D011] to-[#F8A929] bg-clip-text text-xs font-medium text-transparent md:text-sm">
                On The Rise
              </p>
            </div>
          </div>
          <div className="relative flex gap-1.5 md:gap-2">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
          </div>
        </div>
        <CarouselContent className="mr-6 flex size-full grow p-4 md:p-6">
          {recentPartners.map((item: any, id: any) => (
            <CarouselItem className="" key={id}>
              <a
                className="relative flex h-full w-[178px] flex-col items-center justify-center rounded-lg border border-[#F4C10B0F] bg-[#18140C] text-[#E0E0E0] hover:cursor-blue hover:border-[#F4C10B38] hover:bg-[#332200] hover:text-white/90 md:w-[196px]"
                href={item.twitter}
                target="_blank"
              >
                <div className="absolute top-0 h-[2px] w-8 rounded-full bg-[#EE511E]" />
                <div className="relative mb-2 aspect-square h-14 overflow-hidden rounded-full border border-[#F4C10B0F] bg-[#18140C05] md:mb-4 md:h-16">
                  <Image
                    src={
                      "https://d163aeqznbc6js.cloudfront.net/images" + item.logo
                    }
                    alt={item._title}
                    fill
                    className="object-cover"
                  />
                </div>
                <p className="mb-2 text-xs md:mb-4 md:text-sm">{item._title}</p>
                <StatusDisplay status={item.partner.toLowerCase()} />
              </a>
            </CarouselItem>
          ))}
          <CarouselItem className="">
            <a
              target="_blank"
              href={"https://ecosystem.0xhoneyjar.xyz/"}
              className="relative flex aspect-square h-full w-[178px] items-center justify-center rounded-lg border border-[#F4C10B0F] bg-[#18140C] text-[#C4C4C4] hover:cursor-blue hover:border-[#F4C10B]/10 hover:bg-[#533802] hover:text-white/90 md:w-[196px]"
            >
              <p className="flex text-xs sm:text-sm md:text-base">
                Explore All <ArrowUpRight />
              </p>
            </a>
          </CarouselItem>
        </CarouselContent>
      </Carousel>
      {/* </div> */}
    </div>
  );
};

export default NewPartners;

const StatusDisplay = ({ status }: { status: string }) => {
  const statusImage =
    status === "platinum"
      ? "/partners/status/plat.png"
      : status === "gold"
        ? "/partners/status/gold.png"
        : status === "silver"
          ? "/partners/status/silver.png"
          : status === "backed" || status === "joint"
            ? "/partners/status/incubated.png"
            : "/partners/status/bronze.png";

  return (
    <div className="flex items-center gap-1 rounded-lg border border-[#1C1C1C] bg-gradient-to-b from-[#262626] to-[#141414] px-2 py-1">
      <div className="relative aspect-square h-[16px]">
        <Image src={statusImage} alt="status" fill />
      </div>
      <p
        className={`bg-gradient-to-b bg-clip-text font-switzer text-xs text-transparent ${
          status === "platinum"
            ? "from-white to-[#B9B9B9]"
            : status === "gold"
              ? "from-[#F5CF13] to-[#766511]"
              : status === "silver"
                ? "from-white to-[#6C6C6C]"
                : status === "backed" || status === "joint"
                  ? "from-[#7FA255] to-[#22B642]"
                  : "from-[#EC7634] to-[#592C13]"
        }`}
        style={{
          filter:
            status === "platinum" ? "drop-shadow(#FFFFFF80 0 0 10px)" : "none",
        }}
      >
        {status.toUpperCase()}
      </p>
    </div>
  );
};
