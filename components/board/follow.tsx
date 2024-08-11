import { FollowButton } from "@/components/ui/buttons";
import Image from "next/image";

const Follow = () => {
  return (
    <div
      className={`col-span-1 row-span-1 flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="follow" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-white" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-[72px] md:px-6 xl:h-20">
        <div className="flex items-center gap-2">
          <p className="text-base font-medium text-white md:text-lg">
            Follow Us
          </p>
        </div>
      </div>
      <div className="relative flex grow items-center justify-center px-6">
        <div className="flex flex-row items-center gap-2 rounded-full border border-dashed border-[#747474]/40 px-4 py-3 md:gap-3">
          <FollowButton platform="twitter" />
          <FollowButton platform="discord" />
          <FollowButton platform="farcaster" />
        </div>
        <div className="absolute inset-x-0 bottom-6 left-24 mx-auto flex items-end justify-center gap-2 sm:bottom-8 xl:left-36">
          <div className="relative aspect-square h-[42px] md:h-[50px]">
            <Image
              src={"/follow/arrow-swirl.svg"}
              alt="arrow-swirl"
              fill
              className="scale-x-110 object-contain"
            />
          </div>
          <p className="whitespace-nowrap text-[10px] text-[#747474]/65 md:text-xs">
            Follow Us <span className="hidden xl:inline-flex">For More</span>
          </p>
        </div>
      </div>
    </div>
  );
};

export default Follow;
