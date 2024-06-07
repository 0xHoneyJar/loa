import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";

const Tools = () => {
  return (
    <Carousel
      className="flex flex-col"
      key="1"
      data-grid={{
        x: 0,
        y: 0,
        w: 3,
        h: 1,
      }}
    >
      <div className="relative mb-4 flex flex-col justify-center gap-2 md:flex-row md:items-end md:justify-between">
        <p className="font-switzer text-3xl font-medium md:text-5xl">
          NFTS/Gaming
        </p>
        <p className="whitespace-nowrap font-switzer text-xl font-light text-[#9A9A9A] md:text-3xl">
          Partners
        </p>
        <div className="flex gap-2 sm:absolute sm:right-0 md:hidden">
          <CarouselPrevious className="h-10 w-10 border-[#303033] bg-[#171717] text-white hover:border-[#969696] hover:bg-[#292929] md:h-14 md:w-14" />
          <CarouselNext className="h-10 w-10 border-[#303033] bg-[#171717] text-white hover:border-[#969696] hover:bg-[#292929] md:h-14 md:w-14" />
        </div>
      </div>
      <hr className="mb-10 w-full border border-[#2A2A2A]" />
      <CarouselContent className="-ml-0 flex flex-row gap-6 md:!transform-none md:flex-wrap md:justify-center">
        <CarouselItem
          className={`relative flex aspect-[1/1.12] w-[245px] flex-col items-center rounded-lg border border-[#232323B3] bg-[#111111] pl-0 sm:w-[284px] md:w-[314px] lg:w-[356px]`}
        ></CarouselItem>
      </CarouselContent>
    </Carousel>
  );
};

export default Tools;
