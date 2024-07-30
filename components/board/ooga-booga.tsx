import DragHandle from "../drag-handle";
import { useState } from "react";

const OogaBooga = () => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-1"} flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]`}
    >
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-white" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-[72px] md:px-6 xl:h-20">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#B8B8B8] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandle setGlow={setGlow} />
          <p className="text-sm font-medium text-white md:text-base xl:text-xl">
            OOGA BOOGA
          </p>
        </div>
      </div>
      <div className="flex grow flex-col justify-center px-4 text-3xl font-semibold tracking-wide md:px-6 md:text-4xl xl:text-5xl">
        <p>A CULT</p>
        <p>A PONZI</p>
        <p>A SCAM</p>
      </div>
    </div>
  );
};

export default OogaBooga;
