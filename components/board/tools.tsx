import { ToolsButton } from "@/components/ui/buttons";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import { TOOLS } from "@/constants/tools";

const Tools = () => {
  return (
    <div
      className={`relative h-full overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="tools" />
      <Carousel className="flex h-full flex-col" opts={{ dragFree: true }}>
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-white" />
        <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-[72px] md:px-6">
          <div className="flex items-center gap-2">
            <p className="text-base font-medium text-white md:text-lg">
              Tools & Products
            </p>
          </div>
          <div className="relative flex gap-1.5 md:gap-2">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
          </div>
        </div>
        <CarouselContent className="mr-6 flex h-full w-full grow items-center py-4 pl-4 md:py-6 md:pl-6">
          {TOOLS.map((item, id) => (
            <CarouselItem key={id} className={`h-full`}>
              <ToolsButton item={item} />
            </CarouselItem>
          ))}
        </CarouselContent>
      </Carousel>
    </div>
  );
};

export default Tools;
