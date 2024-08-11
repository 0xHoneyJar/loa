import Image from "next/image";
import { ScrollArea } from "../ui/scroll-area";
import { DevelopmentButton } from "@/components/ui/buttons";

const Development = ({ developments }: { developments?: any }) => {
  return (
    <div className="relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#FFFFFF0A] bg-[#0F0F0F]">
      <div className="absolute -top-40 h-1 w-full" id="development" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-white" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-[72px] md:px-6">
        <div className="flex items-center gap-2">
          <p className="whitespace-nowrap text-base font-medium text-white md:text-lg">
            Development Updates
          </p>
        </div>
      </div>
      <ScrollArea className="relative flex grow py-4 md:py-6">
        <div className="absolute left-6 top-4 size-full border-l border-dashed border-[#4C4C4C] md:left-8 md:top-6" />
        <div className="absolute left-0 top-0 z-10 h-24 w-full bg-gradient-to-b from-[#0F0F0F]" />
        <div className="absolute bottom-0 left-0 z-10 h-24 w-full bg-gradient-to-t from-[#0F0F0F]" />
        <div className="relative size-full pl-6 md:pl-8">
          <div className="relative flex size-full grow flex-col gap-12 px-8 py-4 md:gap-16 md:py-6">
            {developments.items.map((development: any, id: any) => (
              <div className="relative flex flex-col gap-3" key={id}>
                <div className="absolute left-[-36px] top-2 aspect-[4/1] h-2 md:top-2.5">
                  <Image
                    src={"/development-pointer.svg"}
                    alt="pointer"
                    fill
                    className="object-contain"
                  />
                </div>
                <p className="text-sm text-[#F4C10B] md:text-base">
                  {development._title}
                </p>
                {development.milestones.items.map((item: any, id: any) => {
                  const CommonContent = () => (
                    <>
                      <div className="relative aspect-square h-4 md:h-6">
                        <Image
                          src={"/development-arrow.svg"}
                          alt="arrow"
                          fill
                          className="object-contain"
                        />
                      </div>
                      <p className="text-xs md:text-sm">{item._title}</p>
                    </>
                  );

                  return item.link ? (
                    <DevelopmentButton item={item} id={id} />
                  ) : (
                    <div className="flex items-center gap-1 md:gap-2" key={id}>
                      <CommonContent />
                    </div>
                  );
                })}
              </div>
            ))}
          </div>
        </div>
      </ScrollArea>
    </div>
  );
};

export default Development;
