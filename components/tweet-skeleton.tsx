import { Skeleton } from "@/components/ui/skeleton";
import Image from "next/image";

const TweetSkeleton = () => {
  return (
    <div
      className={`relative flex size-full flex-col divide-y divide-[#292929] rounded-lg bg-[#181818]`}
    >
      <div className="flex items-center gap-2 px-6 py-4">
        <div className="relative aspect-square h-[32px] md:h-[40px]">
          <Image src={"/thj-logo.png"} alt="logo" fill />
        </div>
        <div className="flex flex-col">
          <p className="whitespace-nowrap text-xs md:text-base">
            The Honey Jar
          </p>
          <p className="text-[10px] text-[#ABABAB] md:text-sm">@0xhoneyjar</p>
        </div>
      </div>
      <div className="flex size-full flex-col gap-2 overflow-hidden p-4 md:p-6">
        <Skeleton className="h-3 w-full rounded-full" />
        <Skeleton className="h-3 w-4/5 rounded-full" />
      </div>
    </div>
  );
};

export default TweetSkeleton;
