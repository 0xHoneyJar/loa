"use client";

import useUserStore from "@/state/user/useUserStore";
import { useEffect } from "react";
import Snowfall from "react-snowfall";

const MainWrapper = ({ children }: { children: React.ReactNode }) => {
  const setCurrentTime = useUserStore((state) => state.setCurrentTime);

  useEffect(() => {
    const interval = setInterval(() => {
      setCurrentTime(Math.floor(Date.now() / 1000));
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="relative mx-auto min-w-[24rem] max-w-[112rem] overflow-hidden">
      {/* <Snowfall
        style={{
          position: "fixed",
          width: "100vw",
          height: "100vh",
          zIndex: 20,
        }}
        // radius={[1, 2]}
        speed={[0.1, 0.5]}
        snowflakeCount={100}
        wind={[-1, 0.5]}
      /> */}
      {children}
    </div>
  );
};

export default MainWrapper;
