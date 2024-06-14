import Image from "next/image";

const Feed = () => {
  return (
    <div className="relative flex flex-col border-2 bg-[#10120D] rounded-2xl border-[#121A12] overflow-hidden h-full">
      <div className="absolute -top-40 w-full h-1" id="feed" />
      <div className="w-full h-2 bg-[#43AA77] rounded-t-3xl" />
      <div className="flex justify-between items-center px-6 h-16 border-b border-dashed border-[#FFFFFF1F]">
        <div className="flex gap-2 items-center">
          <div className="h-[26px] aspect-square relative dragHandle">
            <Image
              src={"/drag-handle.svg"}
              alt="drag"
              fill
              className="object-contain"
            />
          </div>
          <p className="text-white text-lg">Feed</p>
        </div>
        <a className="h-[34px] aspect-square rounded-full border border-[#353535] relative cursor-pointer">
          <Image
            src={"/twitter.svg"}
            alt="twitter"
            fill
            className="object-contain p-2"
          />
        </a>
      </div>
      <div className="flex items-center grow justify-center"></div>
    </div>
  );
};

export default Feed;
