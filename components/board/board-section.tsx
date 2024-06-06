import Image from "next/image";

const BoardSection = () => {
  return (
    <div className="h-full w-full flex items-center flex-col">
      <div className="flex flex-col text-white items-center mb-20">
        <div className="h-[40px] aspect-square relative mb-4">
          <Image
            src={"/hand-move.svg"}
            alt="hand"
            fill
            className="object-contain"
          />
        </div>
        <p className="font-medium text-4xl mb-2">Control The THJ</p>
        <p className="text-[#FFFFFFB3] text-xl">
          Manage & Custom Your THJ Board
        </p>
      </div>
      <div className="w-3/4 h-full flex flex-col">
        <div className="w-full rounded-full py-3 px-4 border border-[#BCBCBC1A] mb-6">
          <div className="py-1.5 px-4 bg-gradient-to-r from-[#F2C8481F] to-[#F8A9291F] rounded-full w-fit">
            <p className="text-xs bg-gradient-to-r from-[#F2C848] to-[#F8A929] bg-clip-text text-transparent">
              ACTIVITY
            </p>
          </div>
        </div>
        <div className="w-full rounded-xl border border-[#BCBCBC1A] px-8 py-10">
        </div>
      </div>
    </div>
  );
}

export default BoardSection