"use client";

import useUserStore from "@/state/user/useUserStore";
import { useEffect } from "react";

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
      {children}
    </div>
  );
};

export default MainWrapper;
