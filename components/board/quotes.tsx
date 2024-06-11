import Image from "next/image";

const Quotes = () => {
  return (
    <div className="flex flex-col border-2 bg-[#0F0F0F] rounded-2xl border-[#FFFFFF0A] overflow-hidden h-full">
      <div className="w-full h-2 bg-white rounded-t-3xl" />
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
          <p className="text-white text-lg">Our Quotes 001</p>
        </div>
      </div>
      <div className="flex grow px-8 items-center justify-center">
        <p className="uppercase text-white font-semibold text-4xl">
          <span className="text-[#F5D011]">Honey Jar</span> is the best in da west for sure
        </p>
      </div>
    </div>
  );
};

export default Quotes;
