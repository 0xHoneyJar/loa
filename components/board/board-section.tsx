"use client";

import RGL, { WidthProvider, Responsive } from "react-grid-layout";
import { DASHBOARD } from "@/constants/dashboard";
import Marquee from "react-fast-marquee";
import { motion } from "framer-motion";
import React, { useRef, useState, useEffect } from "react";
import { RotateCcw } from "lucide-react";
import "react-grid-layout/css/styles.css";
// import "react-resizable/css/styles.css";

// const ReactGridLayout = WidthProvider(RGL);
const ResponsiveGridLayout = WidthProvider(Responsive);

const BoardSection = ({
  partners,
  spotlight,
}: {
  partners: any;
  spotlight: any;
}) => {
  const constraintsRef = useRef<HTMLDivElement>(null);
  const resetRef = useRef<HTMLDivElement>(null);
  const ogLayout = DASHBOARD.map((dashboard) => dashboard.dataGrid);

  const breakpoints = ["lg", "md", "sm", "xs"];
  const ogLayouts = breakpoints.reduce((acc: any, breakpoint: any) => {
    acc[breakpoint] = DASHBOARD.map(
      (dashboard: any) =>
        dashboard[`dataGrid_${breakpoint}`] || dashboard.dataGrid,
    );
    return acc;
  }, {});

  const [drag, setDrag] = useState(false);

  const mouseDownHandler = () => {
    setDrag(true);
  };

  useEffect(() => {
    const handleMouseUp = () => {
      setDrag(false);
    };

    window.addEventListener("mouseup", handleMouseUp);

    return () => {
      window.removeEventListener("mouseup", handleMouseUp);
    };
  }, []);

  const [rowHeight, setRowHeight] = useState(0);

  // reactgridlayout
  const getLayout = () => {
    if (typeof window !== "undefined") {
      const savedLayout = localStorage.getItem("grid-layout");

      return savedLayout ? JSON.parse(savedLayout) : ogLayout;
    }
  };

  // responsivegridlayout
  const getLayouts = () => {
    if (typeof window !== "undefined") {
      const savedLayout = localStorage.getItem("grid-layout");

      return savedLayout ? JSON.parse(savedLayout)["layouts"] : ogLayouts;
    }
  };

  const savedLayout = getLayout();

  const savedLayouts = getLayouts();

  const [layout, setLayout] = useState(savedLayout);
  const [layouts, setLayouts] = useState(savedLayouts);

  // reactgridlayout
  const resetLayout = () => {
    handleLayoutChange(ogLayout);
    setLayout(ogLayout);
  };

  const resetLayouts = () => {
    handleLayoutsChange(null, ogLayouts);
    setLayouts(ogLayouts);
  };

  // reactgridlayout
  const handleLayoutChange = (layouts: any) => {
    if (typeof window !== "undefined") {
      localStorage.setItem("grid-layout", JSON.stringify(layouts));
      setLayout(layouts);
    }
  };

  const handleLayoutsChange = (layout: any, layouts: any) => {
    if (typeof window !== "undefined") {
      localStorage.setItem(
        "grid-layout",
        JSON.stringify({
          layouts: layouts,
        }),
      );
      setLayouts(layouts);
    }
  };

  const convertedTailwindBreakpoints = {
    xs: 0,
    sm: 380,
    md: 540,
    lg: 648,
  };

  const handleBreakpointChange = (width: any) => {
    // if (breakpoint === "md") setRowHeight(340);
    // else if (breakpoint === "sm") setRowHeight(300);
    // else setRowHeight(240);

    // console.log(width);

    if (width >= convertedTailwindBreakpoints.md) {
      setRowHeight(340);
    } else if (
      width >= convertedTailwindBreakpoints.sm &&
      width < convertedTailwindBreakpoints.md
    ) {
      setRowHeight(300);
    } else {
      setRowHeight(280);
    }
  };

  // determines if the swipe has hit the end
  const handleDragEnd = () => {
    if (constraintsRef && resetRef) {
      const containerRect = constraintsRef.current?.getBoundingClientRect();
      const dragElementRect = resetRef.current?.getBoundingClientRect();
      if (containerRect?.right === dragElementRect?.right) {
        // resetLayout();
        resetLayouts();
      }
    }
  };

  return (
    <div className="mb-20 flex h-full w-full flex-col items-center md:mb-40 xl:mb-60">
      <div className="mb-10 mt-3 rounded-full bg-[#FFFFFF14] px-3 py-2 md:mb-20">
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
            className={`aspect-square h-[28px] touch-none rounded-full bg-white p-1 ${drag ? "cursor-grabbing" : "cursor-grab"}`}
            ref={resetRef}
            onMouseDown={mouseDownHandler}
          >
            <RotateCcw className="h-full w-full -rotate-90 scale-x-[-1] text-black" />
          </motion.div>
          <p className="text-xs text-[#E7E7E7] md:text-sm">
            Swipe to reset to the default layout
          </p>
        </div>
      </div>
      <div className="relative flex h-full w-[380px] flex-col items-center sm:w-[540px] md:w-[648px] lg:w-[864px] xl:w-[1080px] 2xl:w-[1296px]">
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
          breakpoints={{
            lg: convertedTailwindBreakpoints.lg,
            md: convertedTailwindBreakpoints.md,
            sm: convertedTailwindBreakpoints.sm,
            xs: convertedTailwindBreakpoints.xs,
          }}
          cols={{ lg: 3, md: 2, sm: 2, xs: 1 }}
          rowHeight={rowHeight}
          draggableHandle=".dragHandle"
          layouts={layouts}
          // isResizable={false}
          margin={{
            lg: [30, 30],
            md: [28, 28],
            sm: [24, 24],
            xs: [16, 16],
          }}
          containerPadding={{
            lg: [32, 48],
            md: [30, 45],
            sm: [28, 42],
            xs: [20, 30],
          }}
          onLayoutChange={handleLayoutsChange}
          onWidthChange={handleBreakpointChange}
        >
          {DASHBOARD.map((dashboard) => {
            if (
              dashboard.key === "incubated" ||
              dashboard.key === "newPartners"
            ) {
              return (
                <div key={dashboard.key}>
                  {React.cloneElement(dashboard.ui, { partners })}
                </div>
              );
            } else if (dashboard.key === "spotlight") {
              return (
                <div key={dashboard.key}>
                  {React.cloneElement(dashboard.ui, { spotlight })}
                </div>
              );
            }
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
