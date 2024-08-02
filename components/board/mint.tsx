import Image from "next/image";
import { LockKeyhole, ArrowUpRight } from "lucide-react";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import { useEffect, useState } from "react";
import S3Image from "@/components/s3-image";

const Mint = ({ mints }: { mints?: any }) => {
  return (
    <div className="relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]">
      <div className="absolute -top-40 h-1 w-full" id="mint" />
      <Carousel className="flex h-full flex-col" opts={{ dragFree: true }}>
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
        <div className="flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-[72px] md:px-6">
          <div className="flex items-center gap-2">
            <LockKeyhole className="aspect-square h-5 text-[#FFD7004D] md:h-[26px]" />
            <p className="whitespace-nowrap text-sm font-medium text-[#FFD700] md:text-base">
              New Mints
            </p>
          </div>
          <div className="relative flex gap-1.5 md:gap-2 xl:gap-3">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
          </div>
          {/* <button className="flex items-center gap-1 text-lg font-medium text-[#848484] hover:text-white">
            Explore <ArrowUpRight size={24} />
          </button> */}
        </div>
        <CarouselContent className="flex size-full grow p-4 md:p-6">
          {mints.items.map((mint: any) => (
            <CarouselItem
              key={mint._title}
              className="basis-full sm:basis-1/2 xl:basis-1/3"
            >
              <MintDisplay mint={mint} />
            </CarouselItem>
          ))}
        </CarouselContent>
      </Carousel>
    </div>
  );
};

export default Mint;

// New component to handle time calculation
const TimeLeft = ({ endDate }: { endDate: number }) => {
  const [timeLeft, setTimeLeft] = useState<string>("");

  useEffect(() => {
    const timer = setInterval(() => {
      const now = Math.floor(Date.now() / 1000); // Current time in seconds
      const difference = endDate - now;

      if (difference <= 0) {
        setTimeLeft("Ended");
        clearInterval(timer);
      } else {
        const days = Math.floor(difference / (60 * 60 * 24));
        const hours = Math.floor((difference % (60 * 60 * 24)) / (60 * 60));
        const minutes = Math.floor((difference % (60 * 60)) / 60);

        setTimeLeft(`${days}d ${hours}h ${minutes}m`);
      }
    }, 1000);

    return () => clearInterval(timer);
  }, [endDate]);

  return (
    <div className="rounded-full bg-[#D8D8D8]/10 px-3 py-1">
      <p className="text-xs font-light text-[#E2E2E2]">
        <span className="font-normal text-white">{timeLeft}</span> left
      </p>
    </div>
  );
};

const MintDisplay = ({ mint }: { mint: any }) => (
  <a
    href={mint.link}
    target="_blank"
    className="relative flex h-full w-full flex-col justify-between overflow-hidden rounded-lg border border-[#F4C10B14] bg-[#221C11] p-4 hover:cursor-blue hover:divide-[#F4C10B47] hover:border-[#F4C10B47] hover:bg-[#423520]"
  >
    <div className="absolute left-0 top-0 size-full bg-[#0a0500]">
      <S3Image
        src={mint.image}
        alt=""
        fill
        className="z-0 object-cover opacity-25"
      />
    </div>
    <div className="z-10 flex items-center justify-start gap-2">
      {mint.endDate && <TimeLeft endDate={mint.endDate} />}
      <div className="rounded-full bg-[#D8D8D8]/10 px-3 py-1">
        <p className="text-xs font-light text-[#E2E2E2]">
          <span className="font-normal text-white">{mint.supply}</span> total
          supply
        </p>
      </div>
    </div>
    <div className="z-10 flex w-full items-start justify-between">
      <div className="flex flex-col gap-1">
        <p className="text-sm text-[#FBFBFB] md:text-base">{mint._title}</p>
        <div className="flex items-center gap-2">
          <div className="relative aspect-square h-[20px]">
            <Image src={"/thj-logo.png"} alt="logo" fill />
          </div>
          <p className="whitespace-nowrap text-xs text-[#9E9E9E]">
            By The Honey jar
          </p>
        </div>
      </div>
      {/* <div className="flex flex-col items-end"> */}
      <div className="flex items-center gap-1">
        <div className="relative aspect-square h-4">
          <Image src={"/eth.svg"} alt="eth" fill />
        </div>
        <p className="text-sm font-semibold text-white md:text-lg">
          {mint.price}
        </p>
      </div>
      {/* <p className="text-[8px] text-[#BABABA]">$123,145.00</p> */}
      {/* </div> */}
    </div>
  </a>
);
