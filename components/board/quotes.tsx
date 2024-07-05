import Image from "next/image";
import { QUOTES } from "@/constants/quotes";

const Quotes = ({quoteNumber}: {quoteNumber: number}) => {
  return (
    <div className="flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]">
      <div className="h-2 w-full rounded-t-3xl bg-white" />
      <div className="flex h-16 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-6">
        <div className="flex items-center gap-2">
          <div className="dragHandle relative aspect-square h-[26px]">
            <Image
              src={"/drag-handle.svg"}
              alt="drag"
              fill
              className="object-contain"
            />
          </div>
          <p className="text-lg text-white">Our Quotes 001</p>
        </div>
      </div>
      <div className="flex grow px-6 py-10">
        <p className="text-4xl font-semibold uppercase text-white">
          {QUOTES[quoteNumber].quote}
        </p>
      </div>
    </div>
  );
};

export default Quotes;
