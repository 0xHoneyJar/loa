import DragHandle from "../drag-handle";
import { useState } from "react";

const OogaBooga = () => {
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-[1deg]"} flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]`}
    >
      <div className="h-2 w-full rounded-t-3xl bg-white" />
      <div className="relative flex h-16 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#B8B8B8] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandle setGlow={setGlow} />
          <p className="text-lg text-white">OOGA BOOGA</p>
        </div>
      </div>
      <div className="flex grow flex-col justify-center px-6 text-5xl font-semibold tracking-wide">
        <p>A CULT</p>
        <p>A PONZI</p>
        <p>A SCAM</p>
      </div>
    </div>
  );
};

export default OogaBooga;
