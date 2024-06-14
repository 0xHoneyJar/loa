import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import Image from "next/image";
import { INCUBATED } from "@/constants/incubated";

const Incubated = () => {
  return (
    <div className="relative rounded-2xl overflow-hidden bg-gradient-to-b from-[#F8A92917] to-[#14131017] h-full border-2 border-[#F8A92952]">
      <div className="absolute -top-40 w-full h-1" id="incubated" />
      <Carousel className="flex flex-col h-full">
        <div className="w-full h-2 bg-[#FFD700] rounded-t-3xl" />
        <div className="flex justify-between items-center px-6 h-16 border-b border-dashed border-[#F4C10B6B]">
          <div className="flex gap-2 items-center">
            <div className="h-[26px] aspect-square relative dragHandle">
              <Image
                src={"/drag-handle-y.svg"}
                alt="drag"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-[#FFD700] text-lg">Incubated Projects</p>
            <div className="flex gap-2 items-center rounded-full border py-1 px-2 border-[#F8A9291F] bg-gradient-to-r from-[#F5D0110D] to-[#F8A9290D]">
              <div className="h-[20px] aspect-square relative">
                <Image
                  src={"/rise.svg"}
                  alt="rise"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="bg-gradient-to-r from-[#F5D011] to-[#F8A929] bg-clip-text text-transparent">
                On The Rise
              </p>
            </div>
          </div>
          <div className="flex relative gap-3">
            <CarouselPrevious className="h-8 w-8 border-[#848484] bg-transparent border-2" />
            <CarouselNext className="h-8 w-8 border-[#848484] bg-transparent border-2" />
          </div>
        </div>
        <CarouselContent className="flex items-center pl-6 h-full w-full py-6">
          {INCUBATED.map((item, id) => (
            <CarouselItem key={id} className="pl-5 h-full">
              <div className="w-[196px] h-full rounded-lg border bg-[#18140C] border-[#F4C10B0F] flex items-center justify-center flex-col relative hover:bg-[#332200] hover:border-[#F4C10B38] text-[#C4C4C4] hover:text-white/90 hover:cursor-blue hover:font-medium">
                <div className="h-[2px] bg-[#EE511E] absolute top-0 w-8 rounded-full" />
                <div className="h-[100px] mt-6 relative aspect-square bg-[#18140C05] border border-[#F4C10B0F] rounded-full mb-4">
                  <Image
                    src={item.image}
                    alt={item.name}
                    fill
                    className="object-contain p-4"
                  />
                </div>
                <p className="text-lg">{item.name}</p>
              </div>
            </CarouselItem>
          ))}
        </CarouselContent>
      </Carousel>
      {/* </div> */}
    </div>
  );
};

export default Incubated;
