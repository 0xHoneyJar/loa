import { IncubatedItem } from "@/components/ui/buttons";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import Image from "next/image";

const Portfolio = ({ partners }: { partners?: any }) => {
  const incubated = Array.isArray(partners)
    ? partners.filter((partner: any) => partner.partner === "Joint")
    : [];

  return (
    <div className="relative h-full overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]">
      <div className="absolute -top-40 h-1 w-full" id="incubated" />
      <Carousel className="flex h-full flex-col" opts={{ dragFree: true }}>
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
        <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-[72px] md:px-6">
          <div className="flex items-center gap-3">
            <p className="text-base font-medium text-[#FFD700] md:text-lg">
              THJ Portfolio
            </p>
            <div className="hidden items-center gap-2 rounded-full border border-[#F8A9291F] bg-gradient-to-r from-[#F5D0110D] to-[#F8A9290D] px-2 py-1 md:flex">
              <div className="relative aspect-square h-[16px]">
                <Image
                  src={"/rise.svg"}
                  alt="rise"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="whitespace-nowrap bg-gradient-to-r from-[#F5D011] to-[#F8A929] bg-clip-text text-xs text-transparent">
                Updated Recently
              </p>
            </div>
          </div>
          <div className="relative flex gap-1.5 md:gap-2">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
          </div>
        </div>
        <CarouselContent className="mr-6 flex size-full grow items-center py-4 pl-4 md:py-6 md:pl-6">
          {incubated.map((item, id) => (
            <CarouselItem key={id} className={`h-full`}>
              <IncubatedItem item={item} />
            </CarouselItem>
          ))}
        </CarouselContent>
      </Carousel>
    </div>
  );
};

export default Portfolio;
