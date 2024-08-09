import { QUOTES } from "@/constants/quotes";

const Quotes = ({ quoteNumber }: { quoteNumber: number }) => {
  return (
    <div className="flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]">
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-white" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-[72px] md:px-6">
        <div className="flex items-center gap-2">
          <p className="text-base font-medium text-white md:text-lg">
            Our Quotes 001
          </p>
        </div>
      </div>
      <div className="flex grow px-4 py-6 md:px-6 md:py-10">
        <p className="text-2xl font-semibold uppercase text-white md:text-3xl xl:text-4xl">
          {QUOTES[quoteNumber].quote}
        </p>
      </div>
    </div>
  );
};

export default Quotes;
