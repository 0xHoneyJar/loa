import Image from "next/image";

const Quests = () => {
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
          <p className="text-[#FFD700] text-lg">Quests</p>
          <div className="h-[12px] aspect-square bg-[#FF0000] rounded-full relative">
            <div className="h-full w-full aspect-square absolute bg-[#FF0000] rounded-full animate-ping" />
          </div>
        </div>
      </div>
      <div className="flex grow px-8 items-center">
        <p className="text-white uppercase">
          Take part in{" "}
          <span className="text-[#E1A94E]">THJ specials Quests</span> and{" "}
          <span className="text-[#E1A94E]">get rewarded!like seriously</span>
        </p>
      </div>
    </div>
  );
};

export default Quests;
