import S3Image from "@/components/s3-image";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselPrevious,
  CarouselNext,
} from "@/components/ui/carousel";
import { ArrowUpRight, LockKeyhole } from "lucide-react";
import { useState } from "react";

const Updates = ({ updates }: { updates?: any }) => {
  return (
    <div className="relative h-full overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]">
      <div className="absolute -top-40 h-1 w-full" id="updates" />
      <Carousel className="flex h-full flex-col" opts={{ dragFree: true }}>
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
        <div className="flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-[72px] md:px-6">
          <div className="flex items-center gap-2">
            <LockKeyhole className="aspect-square h-5 text-[#FFD7004D] md:h-[26px]" />
            <p className="text-sm font-medium text-[#FFD700] md:text-base">
              Updates
            </p>
          </div>
          <div className="relative flex gap-1.5 md:gap-2">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
          </div>
        </div>
        <CarouselContent className="mr-4 flex size-full grow p-4 md:mr-6 md:p-6">
          {updates?.items?.map((update: any, id: any) => (
            <UpdateDisplay
              key={id}
              title={update._title}
              image={update.image}
              link={update.link}
              desc={update.description}
            />
          ))}
        </CarouselContent>
      </Carousel>
      {/* </div> */}
    </div>
  );
};

export default Updates;

const UpdateDisplay = ({
  image,
  link,
  title,
  desc,
}: {
  image: string;
  link: string;
  title: string;
  desc: string;
}) => {
  const [hover, setHover] = useState(false);
  return (
    <CarouselItem>
      <div className="relative flex h-full w-[200px] flex-col gap-2 overflow-hidden sm:w-[240px] md:w-[270px] md:gap-3">
        <a
          target="_blank"
          href={link}
          onMouseEnter={() => setHover(true)}
          onMouseLeave={() => setHover(false)}
          className={`relative h-2/3 w-full overflow-hidden rounded-xl border ${hover ? "cursor-blue border-[#F5D011D9]" : "border-[#2B2B2B]"}`}
        >
          <S3Image src={image} alt="" fill className="object-cover" />
        </a>
        <div className="flex h-1/3 flex-col gap-0.5 md:gap-1">
          <div className="flex items-center justify-between">
            <p
              className={`truncate text-xs font-medium md:text-sm ${hover ? "text-[#F5D011]" : "text-white"}`}
            >
              {title}
            </p>
            <ArrowUpRight
              className={`aspect-square h-4 md:h-5 ${hover ? "text-[#F5D011]" : "text-white/15"}`}
            />
          </div>
          <p className="text-[10px] text-[#A9A9A9] md:text-xs">{desc}</p>
        </div>
      </div>
    </CarouselItem>
  );
};
