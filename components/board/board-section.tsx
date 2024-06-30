"use client";

import RGL, { WidthProvider } from "react-grid-layout";
import { DASHBOARD } from "@/constants/dashboard";
import Marquee from "react-fast-marquee";
import { motion } from "framer-motion";
import { useRef, useState, useEffect } from "react";
import { RotateCcw } from "lucide-react";
// import "react-grid-layout/css/styles.css";
// import "react-resizable/css/styles.css";

const ReactGridLayout = WidthProvider(RGL);
const ogLayout = DASHBOARD.map((dashboard) => dashboard.dataGrid);

const BoardSection = () => {
  const constraintsRef = useRef(null)

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

  return (
    <div className="h-full w-full flex items-center flex-col mb-60">
      <div ref={constraintsRef} className="overflow-hidden bg-[#FFFFFF14] mt-3 mb-20 py-2 px-3 rounded-full flex gap-3 items-center">
        <motion.div drag="x" dragSnapToOrigin className="h-[28px] aspect-square p-1 bg-white rounded-full">
          <RotateCcw className="h-full w-full text-black -rotate-90 scale-x-[-1]" />
        </motion.div>
        <p className="text-[#E7E7E7] text-sm">Swipe to reset to the default layout</p>
      </div>
      <div className="w-3/4 h-full flex flex-col relative items-center">
        <div className="h-[100px] w-full bg-[#F8A9291F] blur-[100px] absolute top-20" />
        <div className="w-full gap-2 rounded-full py-3 px-4 border border-[#BCBCBC1A] mb-6 flex">
          <div className="py-1.5 px-4 bg-gradient-to-r from-[#F2C8481F] to-[#F8A9291F] rounded-full w-fit">
            <p className="text-xs bg-gradient-to-r from-[#F2C848] to-[#F8A929] bg-clip-text text-transparent">
              ACTIVITY
            </p>
          </div>
          <Marquee
            autoFill
            speed={30}
          >
            <p className="text-white px-2 text-sm">
              Lorem ipsum dolor sit amet, consectetur adipiscing elit.
            </p>
          </Marquee>
        </div>
        <ReactGridLayout
          className="w-full rounded-2xl border border-[#BCBCBC1A] text-white bg-[#0A0A0A]"
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
