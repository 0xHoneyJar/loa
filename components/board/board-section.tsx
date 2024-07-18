"use client";

import RGL, { WidthProvider, Responsive } from "react-grid-layout";
import { DASHBOARD } from "@/constants/dashboard";
import Marquee from "react-fast-marquee";
import { motion } from "framer-motion";
import { useRef, useState, useEffect } from "react";
import { RotateCcw } from "lucide-react";
import "react-grid-layout/css/styles.css";
// import "react-resizable/css/styles.css";

// const ReactGridLayout = WidthProvider(RGL);
const ResponsiveGridLayout = WidthProvider(Responsive);

const BoardSection = () => {
  const constraintsRef = useRef<HTMLDivElement>(null);
  const resetRef = useRef<HTMLDivElement>(null);
  const ogLayout = DASHBOARD.map((dashboard) => dashboard.dataGrid);

  const getLayout = () => {
    if (typeof window !== "undefined") {
      const savedLayout = localStorage.getItem("grid-layout");

      return savedLayout ? JSON.parse(savedLayout) : ogLayout;
    }
  };

  const savedLayout = getLayout();

  const [layout, setLayout] = useState<any[]>(savedLayout);

  const resetLayout = () => {
    handleLayoutChange(ogLayout);
    setLayout(ogLayout);
  };

  const handleLayoutChange = (layouts: any) => {
    if (typeof window !== "undefined") {
      localStorage.setItem("grid-layout", JSON.stringify(layouts));
      setLayout(layouts);
    }
  };

  const handleDragEnd = () => {
    if (constraintsRef && resetRef) {
      const containerRect = constraintsRef.current?.getBoundingClientRect();
      const dragElementRect = resetRef.current?.getBoundingClientRect();
      if (containerRect?.right === dragElementRect?.right) {
        resetLayout();
      }
    }
  };

  return (
    <div className="md:mb-60 mb-40 flex h-full w-full flex-col items-center">
      <div className="md:mb-20 mb-10 mt-3 rounded-full bg-[#FFFFFF14] px-3 py-2">
        <div
          ref={constraintsRef}
          className="flex h-full w-full items-center gap-2"
        >
          <motion.div
            drag="x"
            dragSnapToOrigin
            dragConstraints={constraintsRef}
            dragElastic={{ right: 0, left: 0 }}
            onDragEnd={handleDragEnd}
            className="aspect-square h-[28px] touch-none rounded-full bg-white p-1"
            ref={resetRef}
          >
            <RotateCcw className="h-full w-full -rotate-90 scale-x-[-1] text-black" />
          </motion.div>
          <p className="text-xs text-[#E7E7E7] md:text-sm">
            Swipe to reset to the default layout
          </p>
        </div>
      </div>
      <div className="relative flex h-full w-[90%] flex-col items-center sm:w-4/5 lg:w-3/4">
        <div className="absolute top-20 h-[100px] w-full bg-[#F8A9291F] blur-[100px]" />
        <div className="mb-6 flex w-full gap-2 rounded-full border border-[#BCBCBC1A] px-2 py-1 md:px-4 md:py-3">
          <div className="w-fit rounded-full bg-gradient-to-r from-[#F2C8481F] to-[#F8A9291F] px-4 py-1.5">
            <p className="bg-gradient-to-r from-[#F2C848] to-[#F8A929] bg-clip-text text-[10px] text-transparent md:text-xs">
              ACTIVITY
            </p>
          </div>
          <Marquee autoFill speed={30}>
            <p className="px-2 text-xs text-white md:text-sm">
              Lorem ipsum dolor sit amet, consectetur adipiscing elit.
            </p>
          </Marquee>
        </div>
        <ResponsiveGridLayout
          className="w-full rounded-2xl border border-[#BCBCBC1A] bg-[#0A0A0A] text-white"
          breakpoints={{ lg: 1024, md: 768, sm: 640, xs: 450 }}
          cols={{ lg: 3, md: 3, sm: 2, xs: 1 }}
          rowHeight={340}
          draggableHandle=".dragHandle"
          layouts={{ lg: layout, md: layout, sm: layout, xs: layout }}
          isResizable={false}
          margin={{ lg: [30, 30], md: [30, 30] }}
          containerPadding={{ lg: [32, 48], md: [32, 48] }}
        >
          {DASHBOARD.map((dashboard) => {
            return <div key={dashboard.key}>{dashboard.ui}</div>;
          })}
        </ResponsiveGridLayout>
        {/* <ReactGridLayout
          className="w-full rounded-2xl border border-[#BCBCBC1A] bg-[#0A0A0A] text-white"
          cols={3}
          rowHeight={340}
          draggableHandle=".dragHandle"
          margin={[30, 30]}
          containerPadding={[32, 48]}
          layout={layout}
          isResizable={false}
          onLayoutChange={handleLayoutChange}
        >
          {DASHBOARD.map((dashboard) => {
            return <div key={dashboard.key}>{dashboard.ui}</div>;
          })}
        </ReactGridLayout> */}
        <div className="h-[1px] w-1/2 bg-gradient-to-r from-[#F5D01100] via-[#43AA77] via-50%" />
      </div>
    </div>
  );
};

export default BoardSection;
