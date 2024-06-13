import Image from "next/image";
import { DEVELOPMENT } from "@/constants/development";
import { Play } from "lucide-react";

const Development = () => {
  return (
    <div className="flex flex-col border-2 bg-[#0F0F0F] rounded-2xl border-[#FFFFFF0A] overflow-hidden h-full">
      <div className="w-full h-2 bg-white rounded-t-3xl" />
      <div className="flex justify-between items-center px-6 h-16 border-b border-dashed border-[#FFFFFF1F]">
        <div className="flex gap-2 items-center">
          <div className="h-[26px] aspect-square relative dragHandle">
            <Image
              src={"/drag-handle.svg"}
              alt="drag"
              fill
              className="object-contain"
            />
          </div>
          <p className="text-white text-lg whitespace-nowrap">
            Development Pipeline
          </p>
        </div>
      </div>
      <div className="flex grow justify-center py-6 pl-8 relative">
        <div className="h-1/6 w-full absolute top-0 bg-gradient-to-b from-[#0F0F0F] z-10" />
        <div className="h-1/6 w-full absolute bottom-0 bg-gradient-to-t from-[#0F0F0F] z-10" />
        <div className="h-full w-full border-l border-dashed border-[#4C4C4C] pl-12 flex flex-col pt-6 relative gap-20">
          <div className="flex gap-3 flex-col relative">
            <div className="h-[12px] aspect-[4/1] absolute top-2 -left-[54px]">
              <Image
                src={"/development-pointer.svg"}
                alt="pointer"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-[#F4C10B] text-lg">1st Quarter, 2024</p>
            {DEVELOPMENT.filter((item) => item.quarter === 1).map(
              (item, id) => (
                <div className="flex gap-2" key={id}>
                  <div className="h-[24px] aspect-square relative">
                    <Image
                      src={"/development-arrow.svg"}
                      alt="arrow"
                      fill
                      className="object-contain"
                    />
                  </div>
                  <p className="whitespace-nowrap">{item.name}</p>
                  <p className="text-[#424242]/90 font-light">{item.date}</p>
                </div>
              )
            )}
          </div>
          <div className="flex gap-3 flex-col relative">
            <div className="h-[12px] aspect-[4/1] absolute top-2 -left-[54px]">
              <Image
                src={"/development-pointer.svg"}
                alt="pointer"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-[#F4C10B] text-lg">2nd Quarter, 2024</p>
            {DEVELOPMENT.filter((item) => item.quarter === 2).map(
              (item, id) => (
                <div className="flex gap-2" key={id}>
                  <div className="h-[24px] aspect-square relative">
                    <Image
                      src={"/development-arrow.svg"}
                      alt="arrow"
                      fill
                      className="object-contain"
                    />
                  </div>
                  <p className="whitespace-nowrap">{item.name}</p>
                  <p className="text-[#424242]/90 font-light">{item.date}</p>
                </div>
              )
            )}
          </div>
          <div className="flex gap-3 flex-col relative">
            <div className="h-[12px] aspect-[4/1] absolute top-2 -left-[54px]">
              <Image
                src={"/development-pointer.svg"}
                alt="pointer"
                fill
                className="object-contain"
              />
            </div>
            <p className="text-[#F4C10B] text-lg">4th Quarter, 2024</p>
            {DEVELOPMENT.filter((item) => item.quarter === 4).map(
              (item, id) => (
                <div className="flex gap-2" key={id}>
                  <div className="h-[24px] aspect-square relative">
                    <Image
                      src={"/development-arrow.svg"}
                      alt="arrow"
                      fill
                      className="object-contain"
                    />
                  </div>
                  <p className="whitespace-nowrap">{item.name}</p>
                  <p className="text-[#424242]/90 font-light">{item.date}</p>
                </div>
              )
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default Development;
