"use client";

import Image from "next/image";
import RGL, { WidthProvider } from "react-grid-layout";
import Tools from "./tools";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";

const ReactGridLayout = WidthProvider(RGL);

const BoardSection = () => {
  return (
    <div className="h-full w-full flex items-center flex-col">
      <div className="flex flex-col text-white items-center mb-20">
        <div className="h-[40px] aspect-square relative mb-4">
          <Image
            src={"/hand-move.svg"}
            alt="hand"
            fill
            className="object-contain"
          />
        </div>
        <p className="font-medium text-4xl mb-2">Control The THJ</p>
        <p className="text-[#FFFFFFB3] text-xl">
          Manage & Custom Your THJ Board
        </p>
      </div>
      <div className="w-3/4 h-full flex flex-col">
        <div className="w-full rounded-full py-3 px-4 border border-[#BCBCBC1A] mb-6">
          <div className="py-1.5 px-4 bg-gradient-to-r from-[#F2C8481F] to-[#F8A9291F] rounded-full w-fit">
            <p className="text-xs bg-gradient-to-r from-[#F2C848] to-[#F8A929] bg-clip-text text-transparent">
              ACTIVITY
            </p>
          </div>
        </div>
        <ReactGridLayout
          className="w-full rounded-2xl border border-[#BCBCBC1A] text-white bg-[#0A0A0A] overflow-hidden"
          cols={3}
          rowHeight={340}
          draggableHandle=".dragHandle"
          margin={[20, 20]}
          containerPadding={[32,48]}
        >
          <div
            className="border-2 bg-[#0F0F0F] rounded-2xl border-[#FFFFFF0A] overflow-hidden"
            key="1"
            data-grid={{
              x: 0,
              y: 0,
              w: 3,
              h: 1,
            }}
          >
            <Carousel className="flex flex-col h-full">
              <div className="w-full h-2 bg-white rounded-t-3xl" />
              <div className="flex justify-between items-center py-6 px-10 border-b border-dashed border-[#FFFFFF1F]">
                <div className="flex gap-2 items-center">
                  <div className="h-[26px] aspect-square relative dragHandle">
                    <Image
                      src={"/drag-handle.svg"}
                      alt="drag"
                      fill
                      className="object-contain"
                    />
                  </div>
                  <p className="text-white text-lg">Tools & Products</p>
                </div>
                <div className="flex relative gap-3">
                  <CarouselPrevious className="h-8 w-8 border-[#848484] bg-transparent border-2" />
                  <CarouselNext className="h-8 w-8 border-[#848484] bg-transparent border-2" />
                </div>
              </div>
              <CarouselContent className="-ml-0 flex gap-4 items-center pl-10 h-full">
                <CarouselItem>
                  <div className="h-[180px] aspect-square rounded-lg border bg-[#121212] border-[#161616] flex items-center justify-center flex-col">
                    <div className="h-[90px] aspect-square bg-[#FD4D01] rounded-full mb-4" />
                    <p className="text-[#C4C4C4]">Faucet</p>
                  </div>
                </CarouselItem>
              </CarouselContent>
            </Carousel>
          </div>
          <div
            className="rounded-2xl overflow-hidden bg-gradient-to-b from-[#F8A92917] to-[#14131017] h-full border-2 border-[#F8A92952]"
            key="2"
            data-grid={{
              x: 0,
              y: 1,
              w: 3,
              h: 1,
            }}
          >
            <Carousel className="flex flex-col">
              <div className="w-full h-2 bg-[#FFD700] rounded-t-3xl" />
              <div className="flex justify-between items-center py-6 px-10 border-b border-dashed border-[#F4C10B6B]">
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
              <CarouselContent className="-ml-0 flex gap-4 py-10 pl-10">
                <CarouselItem>
                  <div className="h-[180px] aspect-square rounded-lg border bg-[#18140C] border-[#F4C10B0F] flex items-center justify-center flex-col relative">
                    <div className="h-[2px] bg-[#EE511E] absolute top-0 w-8 rounded-full" />
                    <div className="h-[90px] aspect-square bg-[#18140C05] border border-[#F4C10B0F] rounded-full mb-4" />
                    <p className="text-[#C4C4C4]">Standard & Paws</p>
                  </div>
                </CarouselItem>
              </CarouselContent>
            </Carousel>
            {/* </div> */}
          </div>
          <div
            className="border-2 bg-[#43AA7703] rounded-2xl border-[#43AA7714] overflow-hidden"
            key="3"
            data-grid={{
              x: 0,
              y: 3,
              w: 3,
              h: 1,
            }}
          >
            <Carousel className="flex flex-col">
              <div className="w-full h-2 bg-[#43AA77] rounded-t-3xl" />
              <div className="flex justify-between items-center py-6 px-10 border-b border-dashed border-[#FFFFFF1F]">
                <div className="flex gap-2 items-center">
                  <div className="h-[26px] aspect-square relative dragHandle">
                    <Image
                      src={"/drag-handle.svg"}
                      alt="drag"
                      fill
                      className="object-contain"
                    />
                  </div>
                  <p className="text-white text-lg">The Honey Jar NFTs</p>
                </div>
                <div className="flex relative gap-3">
                  <CarouselPrevious className="h-8 w-8 border-[#848484] bg-transparent border-2" />
                  <CarouselNext className="h-8 w-8 border-[#848484] bg-transparent border-2" />
                </div>
              </div>
              <CarouselContent className="-ml-0 flex gap-4 py-10 pl-10">
                <CarouselItem>
                  <div className="h-[180px] aspect-square rounded-lg border bg-[#121212] border-[#161616] flex items-center justify-center flex-col">
                    <div className="h-[90px] aspect-square bg-[#FD4D01] rounded-full mb-4" />
                    <p className="text-[#C4C4C4]">Faucet</p>
                  </div>
                </CarouselItem>
              </CarouselContent>
            </Carousel>
          </div>
          <div
            className="border-2 bg-[#43AA7703] rounded-2xl border-[#43AA7714] overflow-hidden"
            key="4"
            data-grid={{
              x: 0,
              y: 4,
              w: 1,
              h: 1,
            }}
          >
            <Carousel className="flex flex-col">
              <div className="w-full h-2 bg-[#43AA77] rounded-t-3xl" />
              <div className="flex justify-between items-center py-6 px-10 border-b border-dashed border-[#FFFFFF1F]">
                <div className="flex gap-2 items-center">
                  <div className="h-[26px] aspect-square relative dragHandle">
                    <Image
                      src={"/drag-handle.svg"}
                      alt="drag"
                      fill
                      className="object-contain"
                    />
                  </div>
                  <p className="text-white text-lg">Feed</p>
                </div>
              </div>
              <CarouselContent className="-ml-0 flex gap-4 py-10 pl-10">
                <CarouselItem>
                  <div className="h-[180px] aspect-square rounded-lg border bg-[#121212] border-[#161616] flex items-center justify-center flex-col">
                    <div className="h-[90px] aspect-square bg-[#FD4D01] rounded-full mb-4" />
                    <p className="text-[#C4C4C4]">Faucet</p>
                  </div>
                </CarouselItem>
              </CarouselContent>
            </Carousel>
          </div>
          <div
            className="border-2 bg-[#0F0F0F] rounded-2xl border-[#FFFFFF0A] overflow-hidden"
            key="5"
            data-grid={{
              x: 1,
              y: 4,
              w: 1,
              h: 1,
            }}
          >
            <Carousel className="flex flex-col">
              <div className="w-full h-2 bg-white rounded-t-3xl" />
              <div className="flex justify-between items-center py-6 px-10 border-b border-dashed border-[#FFFFFF1F]">
                <div className="flex gap-2 items-center">
                  <div className="h-[26px] aspect-square relative dragHandle">
                    <Image
                      src={"/drag-handle.svg"}
                      alt="drag"
                      fill
                      className="object-contain"
                    />
                  </div>
                  <p className="text-white text-lg">Tools & Products</p>
                </div>
              </div>
              <CarouselContent className="-ml-0 flex gap-4 py-10 pl-10">
                <CarouselItem>
                  <div className="h-[180px] aspect-square rounded-lg border bg-[#121212] border-[#161616] flex items-center justify-center flex-col">
                    <div className="h-[90px] aspect-square bg-[#FD4D01] rounded-full mb-4" />
                    <p className="text-[#C4C4C4]">Faucet</p>
                  </div>
                </CarouselItem>
              </CarouselContent>
            </Carousel>
          </div>
          <div
            className="border-2 bg-[#0F0F0F] rounded-2xl border-[#FFFFFF0A] overflow-hidden"
            key="6"
            data-grid={{
              x: 3,
              y: 4,
              w: 1,
              h: 3,
            }}
          >
            <Carousel className="flex flex-col">
              <div className="w-full h-2 bg-white rounded-t-3xl" />
              <div className="flex justify-between items-center py-6 px-10 border-b border-dashed border-[#FFFFFF1F]">
                <div className="flex gap-2 items-center">
                  <div className="h-[26px] aspect-square relative dragHandle">
                    <Image
                      src={"/drag-handle.svg"}
                      alt="drag"
                      fill
                      className="object-contain"
                    />
                  </div>
                  <p className="text-white text-lg">Tools & Products</p>
                </div>
              </div>
              <CarouselContent className="-ml-0 flex gap-4 py-10 pl-10">
                <CarouselItem>
                  <div className="h-[180px] aspect-square rounded-lg border bg-[#121212] border-[#161616] flex items-center justify-center flex-col">
                    <div className="h-[90px] aspect-square bg-[#FD4D01] rounded-full mb-4" />
                    <p className="text-[#C4C4C4]">Faucet</p>
                  </div>
                </CarouselItem>
              </CarouselContent>
            </Carousel>
          </div>
        </ReactGridLayout>
      </div>
    </div>
  );
};

export default BoardSection;
