import { ArrowUpRight } from "lucide-react";
import Image from "next/image";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import { PERKS } from "@/constants/perks";

const Honeycomb = () => {
  return (
    <div className="relative flex flex-col rounded-2xl overflow-hidden bg-gradient-to-b from-[#F8A92917] to-[#14131017] h-full border-2 border-[#F8A92952]">
      <div className="absolute -top-40 w-full h-1" id="honeycomb" />
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
          <p className="text-[#FFD700] text-lg">Honeycomb</p>
        </div>
        <div className="h-[34px] aspect-square rounded-full border border-[#353535] relative">
          <Image
            src={"/opensea.svg"}
            alt="opensea"
            fill
            className="object-contain p-1"
          />
        </div>
      </div>
      <div className="flex grow flex-col w-full">
        <div className="flex flex-col p-6 w-full gap-4">
          <div className="h-[220px] w-full relative rounded-xl overflow-hidden flex items-center justify-end">
            <Image
              src={"/honeycomb.png"}
              alt="honeycomb"
              fill
              className="object-cover"
            />
            <div className="flex flex-col gap-4 z-10 w-1/2 pr-12">
              <p className="text-[#D1D1D1]">
                Honeycomb is an anti-hustle tech and a perk aggregator of the
                Berachain eco. It gives you whitelist to most projects in the
                ecosystem
              </p>
              <button className="flex gap-2 items-center border border-[#1E1E1E] bg-[#0F0D08] py-3 justify-center rounded-lg">
                <div className="h-[26px] aspect-square rounded-full relative">
                  <Image
                    src={"/opensea.svg"}
                    alt="opensea"
                    fill
                    className="object-contain p-1"
                  />
                </div>
                Buy a Honeycomb
              </button>
            </div>
          </div>
          <div className="h-[214px] w-full relative">
            <div className="grid grid-cols-4 w-full h-full gap-4">
              <div className="h-full w-full rounded-lg py-8 border bg-[#15120B] border-[#F5D0110A] flex items-center flex-col relative">
                <div className="h-[2px] bg-[#EE511E] absolute top-0 w-8 rounded-full" />
                <p className="text-lg text-[#6B6B6B]">Total Perks</p>
                <div className="h-full w-full flex items-center justify-center">
                  <p className="bg-gradient-to-r from-[#F5D011] to-[#F8A929] bg-clip-text text-transparent font-medium text-7xl">
                    94
                  </p>
                </div>
              </div>
              <div className="h-full w-full rounded-lg py-8 border bg-[#15120B] border-[#F5D0110A] flex items-center flex-col relative">
                <div className="h-[2px] bg-[#EE511E] absolute top-0 w-8 rounded-full" />
                <p className="text-lg text-[#6B6B6B]">Active Perks</p>
                <div className="h-full w-full flex items-center justify-center">
                  <p className="bg-gradient-to-r from-[#F5D011] to-[#F8A929] bg-clip-text text-transparent font-medium text-7xl">
                    78
                  </p>
                </div>
              </div>
              <div className="grid h-full w-full grid-rows-2 gap-6">
                <div className="h-full w-full rounded-lg border bg-[#15120B] border-[#F5D0110A] flex items-center flex-col justify-center relative">
                  <div className="h-[2px] bg-[#EE511E] absolute top-0 w-8 rounded-full" />
                  <p className="text-sm text-[#6B6B6B]">Floor Price</p>
                  <p className="flex gap-2 items-center">
                    <div className="h-[16px] aspect-square relative">
                      <Image
                        src={"/floor-price.svg"}
                        alt="floor-price"
                        fill
                        className="object-contain"
                      />
                    </div>
                    333,286.24 ETH
                  </p>
                </div>
                <div className="h-full w-full rounded-lg border bg-[#15120B] border-[#F5D0110A] flex items-center flex-col justify-center relative">
                  <div className="h-[2px] bg-[#EE511E] absolute top-0 w-8 rounded-full" />
                  <p className="text-sm text-[#6B6B6B]">Perk Value</p>
                  <p className="flex gap-2 items-center">
                    <div className="h-[16px] aspect-square relative">
                      <Image
                        src={"/gem.svg"}
                        alt="gem"
                        fill
                        className="object-contain"
                      />
                    </div>
                    333,286.24
                  </p>
                </div>
              </div>
              <div className="grid h-full w-full grid-rows-2 gap-6">
                <div className="h-full w-full rounded-lg border bg-[#15120B] border-[#F5D0110A] flex items-center flex-col justify-center relative">
                  <div className="h-[2px] bg-[#EE511E] absolute top-0 w-8 rounded-full" />
                  <p className="text-sm text-[#6B6B6B]">Holders</p>
                  <p className="flex gap-2 items-center">
                    <div className="h-[16px] aspect-square relative">
                      <Image
                        src={"/holder.svg"}
                        alt="holder"
                        fill
                        className="object-contain"
                      />
                    </div>
                    413,425
                  </p>
                </div>
                <div className="h-full w-full rounded-lg border bg-[#15120B] border-[#F5D0110A] flex items-center flex-col justify-center relative">
                  <div className="h-[2px] bg-[#EE511E] absolute top-0 w-8 rounded-full" />
                  <p className="text-sm text-[#6B6B6B]">Perks Value</p>
                  <p className="flex gap-2 items-center">
                    <span className="text-sm">$</span>
                    333,286.24
                  </p>
                </div>
              </div>
            </div>
          </div>
          <button className="w-full items-center text-[#F4C10B] bg-[#F4C10B]/10 px-6 py-3 rounded-lg flex justify-between text-lg hover:bg-[#F4C10B] hover:text-[#121212] hover:font-semibold hover:cursor-blue">
            Visit Honeycomb Dashboard
            <ArrowUpRight size={28} />
          </button>
        </div>
        <Carousel className="flex flex-col h-full">
          <div className="flex justify-between items-center py-4 px-6 border-y border-dashed border-[#FEFEFE14]">
            <p className="text-white text-lg">Recent Perks</p>
            <div className="flex relative gap-3">
              <CarouselPrevious className="h-8 w-8 border-[#848484] bg-transparent border-2" />
              <CarouselNext className="h-8 w-8 border-[#848484] bg-transparent border-2" />
            </div>
          </div>
          <CarouselContent className="flex items-center pl-6 h-full w-full">
            {PERKS.map((item, id) => (
              <CarouselItem key={id} className="pl-5">
                <div className="h-[196px] aspect-square rounded-lg border bg-[#18140C] border-[#F4C10B0F] flex items-center justify-center flex-col relative hover:bg-[#332200] hover:border-[#F4C10B38] text-[#C4C4C4] hover:text-white/90 hover:cursor-blue hover:font-medium">
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
      </div>
    </div>
  );
};

export default Honeycomb;
