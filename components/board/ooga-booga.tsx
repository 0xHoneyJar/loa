import Image from "next/image";

const OogaBooga = () => {
  return (
    <div className="flex flex-col border-2 bg-[#0F0F0F] rounded-2xl border-[#FFFFFF0A] overflow-hidden h-full">
      <div className="w-full h-2 bg-white rounded-t-3xl" />
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
          <p className="text-white text-lg">OOGA BOOGA</p>
        </div>
      </div>
      <div className="flex grow px-6 justify-center text-5xl flex-col font-semibold tracking-wide">
        <p>A CULT</p>
        <p>A PONZI</p>
        <p>A SCAM</p>
      </div>
    </div>
  );
};

export default OogaBooga;
