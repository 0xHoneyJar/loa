import Image from "next/image";

const Feed = () => {
  return (
    <div className="flex flex-col border-2 bg-[#43AA7703] rounded-2xl border-[#43AA7714] overflow-hidden h-full">
      <div className="w-full h-2 bg-[#43AA77] rounded-t-3xl" />
      <div className="flex justify-between items-center py-6 px-8 border-b border-dashed border-[#FFFFFF1F]">
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
      </div>
      <div className="flex items-center grow justify-center">
      </div>
    </div>
  );
};

export default Feed;
