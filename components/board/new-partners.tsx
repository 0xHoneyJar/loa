import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import Image from "next/image";
import { ArrowUpRight, LockKeyhole } from "lucide-react";
import { PARTNERS } from "@/constants/partners";

const NewPartners = ({ partners }: { partners?: any }) => {
  const recentPartners = partners
    .sort((a: any, b: any) => b.startDate?.getTime() - a.startDate?.getTime())
    .filter((partner: any) => partner.partner !== "Incubated")
    .slice(0, 10);

  return (
    <div className="relative h-full overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]">
      <div className="absolute -top-40 h-1 w-full" id="newPartners" />
      <Carousel className="flex h-full flex-col">
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
        <div className="flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-20 md:px-6">
          <div className="flex items-center gap-2">
            <LockKeyhole className="aspect-square h-5 text-[#FFD7004D] md:h-[26px]" />
            <p className="whitespace-nowrap font-medium text-[#FFD700] md:text-xl">
              New Partners
            </p>
            <div className="hidden items-center gap-2 rounded-full border border-[#F8A9291F] bg-gradient-to-r from-[#F5D0110D] to-[#F8A9290D] px-2 py-1 md:flex">
              <div className="relative aspect-square h-[20px]">
                <Image
                  src={"/rise.svg"}
                  alt="rise"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="whitespace-nowrap bg-gradient-to-r from-[#F5D011] to-[#F8A929] bg-clip-text font-medium text-transparent">
                On The Rise
              </p>
            </div>
          </div>
          <div className="relative flex gap-1.5 md:gap-3">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-8 md:w-8" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-8 md:w-8" />
          </div>
        </div>
        <CarouselContent className="flex h-full w-full py-6 pl-6">
          {recentPartners.map((item: any, id: any) => (
            <CarouselItem className="" key={id}>
              <div className="relative flex h-full w-[196px] flex-col items-center justify-center rounded-lg border border-[#F4C10B0F] bg-[#18140C] text-[#E0E0E0] hover:cursor-blue hover:border-[#F4C10B38] hover:bg-[#332200] hover:text-white/90">
                <div className="absolute top-0 h-[2px] w-8 rounded-full bg-[#EE511E]" />
                <div className="relative mb-2 aspect-square h-[100px] rounded-full border border-[#F4C10B0F] bg-[#18140C05]">
                  <Image
                    src={
                      "https://d163aeqznbc6js.cloudfront.net/images" + item.logo
                    }
                    alt={item._title}
                    fill
                    className="rounded-full object-cover p-4"
                  />
                </div>
                <p className="mb-1">{item._title}</p>
                <StatusDisplay status={item.partner.toLowerCase()} />
              </div>
            </CarouselItem>
          ))}
          <CarouselItem className="">
            <div className="relative flex aspect-square h-[196px] items-center justify-center rounded-lg border border-[#F4C10B0F] bg-[#18140C] text-[#C4C4C4] hover:cursor-blue hover:border-[#F4C10B]/10 hover:bg-[#533802] hover:text-white/90">
              <p className="flex">
                Explore All <ArrowUpRight />
              </p>
            </div>
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
          : status === "incubated"
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
                : status === "incubated"
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
