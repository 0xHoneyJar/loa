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

const NewPartners = () => {
  return (
    <div className="rounded-2xl overflow-hidden bg-gradient-to-b from-[#F8A92917] to-[#14131017] h-full border-2 border-[#F8A92952]">
      <Carousel className="flex flex-col h-full">
        <div className="w-full h-2 bg-[#FFD700] rounded-t-3xl" />
        <div className="flex justify-between items-center py-6 px-8 border-b border-dashed border-[#F4C10B6B]">
          <div className="flex gap-2 items-center">
            <LockKeyhole className="h-[26px] aspect-square text-[#FFD7004D]" />
            <p className="text-[#FFD700] text-lg whitespace-nowrap">
              New Partners
            </p>
            <div className="flex gap-2 items-center rounded-full border py-1 px-2 border-[#F8A9291F] bg-gradient-to-r from-[#F5D0110D] to-[#F8A9290D]">
              <div className="h-[20px] aspect-square relative">
                <Image
                  src={"/rise.svg"}
                  alt="rise"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="font-medium whitespace-nowrap bg-gradient-to-r from-[#F5D011] to-[#F8A929] bg-clip-text text-transparent">
                On The Rise
              </p>
            </div>
          </div>
          <div className="flex relative gap-3">
            <CarouselPrevious className="h-8 w-8 border-[#848484] bg-transparent border-2" />
            <CarouselNext className="h-8 w-8 border-[#848484] bg-transparent border-2" />
          </div>
        </div>
        <CarouselContent className="flex items-center pl-8 h-full w-full">
          {PARTNERS.map((item, id) => (
            <CarouselItem className="" key={id}>
              <div className="h-[196px] aspect-square rounded-lg border bg-[#18140C] border-[#F4C10B0F] flex items-center justify-center flex-col relative hover:bg-[#332200] hover:border-[#F4C10B38] text-[#E0E0E0] hover:text-white/90 hover:cursor-blue">
                <div className="h-[2px] bg-[#EE511E] absolute top-0 w-8 rounded-full" />
                <div className="h-[100px] aspect-square mb-2 relative bg-[#18140C05] border border-[#F4C10B0F] rounded-full">
                  <Image
                    src={item.image}
                    alt={item.name}
                    fill
                    className="object-contain p-4"
                  />
                </div>
                <p className="mb-1">{item.name}</p>
                <StatusDisplay status={item.status} />
              </div>
            </CarouselItem>
          ))}
          <CarouselItem className="">
            <div className="h-[196px] aspect-square rounded-lg border bg-[#18140C] border-[#F4C10B0F] flex items-center justify-center relative hover:bg-[#533802] hover:border-[#F4C10B]/10 text-[#C4C4C4] hover:text-white/90 hover:cursor-blue">
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
      : "/partners/status/bronze.png";

  return (
    <div className="flex gap-1 items-center rounded-lg border border-[#1C1C1C] bg-gradient-to-b from-[#262626] to-[#141414] px-2 py-1">
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
