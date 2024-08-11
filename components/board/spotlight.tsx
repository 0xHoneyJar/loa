import { ScrollArea } from "../ui/scroll-area";
import S3Image from "../s3-image";
import { SpotlightButton } from "@/components/ui/buttons";

const Spotlight = ({ spotlight }: { spotlight?: any }) => {
  return (
    <div
      className={`relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="spotlight" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-6 md:h-[72px]">
        <div className="flex items-center gap-3">
          <p className="text-base font-medium text-[#FFD700] md:text-lg">
            Spotlight
          </p>
          <div className="flex items-center rounded-full bg-[#F5D01124] px-2 py-1">
            <p className="text-xs uppercase text-[#F5D011]">
              Don&apos;t miss it
            </p>
          </div>
        </div>
      </div>
      <div className="flex grow flex-col items-center gap-4 p-4 md:p-6">
        <div className="relative flex h-3/5 w-full shrink-0 overflow-hidden rounded-lg border border-[#1C1C1C]">
          <S3Image
            src={spotlight.image}
            fill
            alt="spotlight"
            className="object-cover"
          />
        </div>
        <div className="relative flex size-full flex-col overflow-hidden">
          <p className="mb-1 text-sm font-medium text-[#FBFBFB] md:text-base">
            {spotlight.title}
          </p>
          <ScrollArea>
            <p className="text-xs text-[#A9A9A9] md:text-sm">
              {spotlight.description}
            </p>
          </ScrollArea>
        </div>
        <SpotlightButton spotlight={spotlight} />
      </div>
    </div>
  );
};

export default Spotlight;
