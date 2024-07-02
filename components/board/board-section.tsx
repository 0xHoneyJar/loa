"use client";

import RGL, { WidthProvider } from "react-grid-layout";
import { DASHBOARD } from "@/constants/dashboard";
import Marquee from "react-fast-marquee";
import { motion } from "framer-motion";
import { useRef, useState, useEffect } from "react";
import { RotateCcw } from "lucide-react";
import "react-grid-layout/css/styles.css";
// import "react-resizable/css/styles.css";

const ReactGridLayout = WidthProvider(RGL);
const ogLayout = DASHBOARD.map((dashboard) => dashboard.dataGrid);

const BoardSection = () => {
  const constraintsRef = useRef<HTMLDivElement>(null);

  const [layout, setLayout] = useState<any[]>([]);

  useEffect(() => {
    // Load layout from localStorage on component mount
    const savedLayout = getLayout();
    setLayout(savedLayout);
  }, []);

  const resetLayout = () => {
    setLayout(ogLayout);
  };

  const handleLayoutChange = (layouts: any) => {
    if (typeof window !== "undefined") {
      localStorage.setItem("grid-layout", JSON.stringify(layouts));
    }
  };

  const getLayout = () => {
    if (typeof window === "undefined") {
      return true; // Default to true on server-side
    }
    const savedLayout = localStorage.getItem("grid-layout");

    return savedLayout ? JSON.parse(savedLayout) : ogLayout;
  };

  const handleDragEnd = (info: any) => {
    console.log(info);
  };

  return (
    <div className="mb-60 flex h-full w-full flex-col items-center">
      <div className="mb-20 mt-3 rounded-full bg-[#FFFFFF14] px-3 py-2">
        <motion.div
          ref={constraintsRef}
          className="flex h-full w-full items-center gap-2"
        >
          <motion.div
            drag="x"
            dragSnapToOrigin
            dragConstraints={constraintsRef}
            dragElastic={{ right: 0, left: 0 }}
            onDragEnd={(event, info) => handleDragEnd(info)}
            className="aspect-square h-[28px] touch-none rounded-full bg-white p-1"
          >
            <RotateCcw className="h-full w-full -rotate-90 scale-x-[-1] text-black" />
          </motion.div>
          <p className="text-sm text-[#E7E7E7]">
            Swipe to reset to the default layout
          </p>
        </motion.div>
      </div>
      <div className="relative flex h-full w-3/4 flex-col items-center">
        <div className="absolute top-20 h-[100px] w-full bg-[#F8A9291F] blur-[100px]" />
        <div className="mb-6 flex w-full gap-2 rounded-full border border-[#BCBCBC1A] px-4 py-3">
          <div className="w-fit rounded-full bg-gradient-to-r from-[#F2C8481F] to-[#F8A9291F] px-4 py-1.5">
            <p className="bg-gradient-to-r from-[#F2C848] to-[#F8A929] bg-clip-text text-xs text-transparent">
              ACTIVITY
            </p>
          </div>
          <Marquee autoFill speed={30}>
            <p className="px-2 text-sm text-white">
              Lorem ipsum dolor sit amet, consectetur adipiscing elit.
            </p>
          </Marquee>
        </div>
        <ReactGridLayout
          className="w-full rounded-2xl border border-[#BCBCBC1A] bg-[#0A0A0A] text-white"
          cols={3}
          rowHeight={340}
          draggableHandle=".dragHandle"
          margin={[30, 30]}
          containerPadding={[32, 48]}
          layout={layout}
          isResizable={false}
          // onLayoutChange={handleLayoutChange as any}
        >
          {DASHBOARD.map((dashboard) => {
            return <div key={dashboard.key}>{dashboard.ui}</div>;
          })}
        </ReactGridLayout>
        <div className="h-[1px] w-1/2 bg-gradient-to-r from-[#F5D01100] via-[#43AA77] via-50%" />
      </div>
    </div>
  );
};

export default BoardSection;
