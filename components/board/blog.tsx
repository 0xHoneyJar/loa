import { ArrowUpRight } from "lucide-react";
import Image from "next/image";
import DragHandleY from "../drag-handle-y";
import { useState } from "react";

const Blog = () => {
  const [hover, setHover] = useState(false);
  const [glow, setGlow] = useState(false);
  return (
    <div
      className={`relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017] ${glow && "rotate-[1deg]"}`}
    >
      <div className="absolute -top-40 h-1 w-full" id="blog" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#FFC500] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandleY setGlow={setGlow} />
          <p className="text-lg text-[#FFD700]">Our Blog</p>
        </div>
      </div>
      <div className="flex grow p-6">
        <div className="grid w-full grid-cols-4 gap-6">
          <div className="relative flex h-full w-full flex-col gap-3">
            <div
              onMouseEnter={() => setHover(true)}
              onMouseLeave={() => setHover(false)}
              className={`relative h-[140px] w-full overflow-hidden rounded-xl border ${hover ? "cursor-blue border-[#F5D011D9]" : "border-[#2B2B2B]"}`}
            >
              <Image
                src={"/update-placeholder.png"}
                alt=""
                fill
                className="object-cover"
              />
            </div>
            <div className="flex flex-col gap-1">
              <div className="flex items-center justify-between">
                <p
                  className={`font-medium ${hover ? "text-[#F5D011]" : "text-white"}`}
                >
                  Heading
                </p>
                <ArrowUpRight
                  className={`aspect-square h-[20px] ${hover ? "text-[#F5D011]" : "text-white/15"} `}
                />
              </div>
              <p className="text-sm text-[#A9A9A9]">Description</p>
            </div>
          </div>
          <div className="relative flex h-full w-full items-center justify-center overflow-hidden rounded-xl border border-[#2B2B2B]">
            <Image src={"/blog.png"} alt="blog" fill className="object-cover" />
            <button className="z-10 flex gap-1 rounded-full border border-[#3B3B3B] bg-[#5A5A5A]/30 px-4 py-2 backdrop-blur-lg hover:cursor-blue">
              Read Now <ArrowUpRight />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Blog;
