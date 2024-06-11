import { ArrowUpRight } from "lucide-react";
import Image from "next/image";

const Blog = () => {
  return (
    <div className="flex flex-col rounded-2xl overflow-hidden bg-gradient-to-b from-[#F8A92917] to-[#14131017] h-full border-2 border-[#F8A92952]">
      <div className="w-full h-2 bg-[#FFD700] rounded-t-3xl" />
      <div className="flex justify-between items-center py-6 px-8 border-b border-dashed border-[#F4C10B6B]">
        <div className="flex gap-2 items-center">
          <div className="h-[26px] aspect-square relative dragHandle">
            <Image
              src={"/drag-handle-y.svg"}
              alt="drag"
              fill
              className="object-contain"
            />
          </div>
          <p className="text-[#FFD700] text-lg">Our Blog</p>
        </div>
      </div>
      <div className="flex grow px-8 py-6">
        <div className="grid grid-cols-4 w-full gap-8">
          <div className="h-full w-full relative rounded-xl overflow-hidden border border-[#2B2B2B] flex items-center justify-center">
            <Image src={"/blog.png"} alt="blog" fill className="object-cover" />
            <button className="hover:cursor-blue px-4 py-2 flex rounded-full gap-1 border border-[#3B3B3B] backdrop-blur-lg bg-[#5A5A5A]/30 z-10">
              Read Now <ArrowUpRight />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Blog;
