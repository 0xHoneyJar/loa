"use client";

import Image from "next/image";
import RGL, { WidthProvider } from "react-grid-layout";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import { DASHBOARD } from "@/constants/dashboard";

const ReactGridLayout = WidthProvider(RGL);

const BoardSection = () => {
  return (
    <div className="h-full w-full flex items-center flex-col">
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
          containerPadding={[32, 48]}
        >
          {DASHBOARD.map((dashboard) => {
            return (
              <div key={dashboard.key} data-grid={{ ...dashboard.dataGrid }}>
                {dashboard.ui}
              </div>
            );
          })}
        </ReactGridLayout>
      </div>
    </div>
  );
};

export default BoardSection;
