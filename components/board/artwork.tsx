import Image from "next/image";
import Marquee from "react-fast-marquee";
import DragHandle from "../drag-handle";
import { useState } from "react";

const Artwork = () => {
  const ARTWORK = [
    "/artwork/artwork-0.png",
    "/artwork/artwork-1.png",
    "/artwork/artwork-2.png",
    "/artwork/artwork-3.png",
  ];
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`${glow && "rotate-1"} relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="artwork" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-white" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-[72px] md:px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#B8B8B8] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandle setGlow={setGlow} />
          <p className="text-sm font-medium text-white md:text-base">
            Apiculture Exhibition
          </p>
        </div>
      </div>
      <Marquee
        autoFill
        speed={25}
        gradient
        gradientColor="#0F0F0F"
        gradientWidth={50}
        className="flex grow items-center"
      >
        {ARTWORK.map((item, id) => (
          <div
            className="relative mx-2 aspect-square h-[172px] overflow-hidden rounded-lg sm:h-[192px] md:h-[200px]"
            key={id}
          >
            <Image
              src={item}
              alt={"artwork-" + id}
              fill
              className="object-cover"
            />
          </div>
        ))}
      </Marquee>
    </div>
  );
};

export default Artwork;
