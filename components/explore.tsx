import {
  NavigationMenuItem,
  NavigationMenuTrigger,
  NavigationMenuContent,
} from "@/components/ui/navigation-menu";
import { EXPLOREITEMS } from "@/constants/explore";
import Image from "next/image";

const Explore = () => {
  return (
    <NavigationMenuItem className="" value="explore">
      <NavigationMenuTrigger className="flex items-center rounded-full border border-[#F4C10B24] bg-gradient-to-b from-[#F4C10B1F] to-[#F8A9291F] px-6 py-2.5 text-xs text-white hover:border-[#F4C10B58] hover:from-[#F4C10B32] hover:to-[#F8A92932] lg:text-sm">
        <p>Explore</p>
        <p className="ml-2 mr-1 rounded-full border bg-[#FFFFFF14] px-2 text-[7px]">
          NEW
        </p>
      </NavigationMenuTrigger>
      <NavigationMenuContent className="-left-20 top-[60px] flex flex-col rounded-xl border border-[#66666632] bg-[#0D0D0D] data-[motion=from-end]:animate-enterFromRight data-[motion=from-start]:animate-enterFromLeft data-[motion=to-end]:animate-exitToRight data-[motion=to-start]:animate-exitToLeft data-[state=closed]:animate-scaleOut data-[state=open]:animate-scaleIn lg:-left-52 lg:flex-row">
        <div className="flex flex-col gap-1 p-2 pb-0 md:pb-2">
          {EXPLOREITEMS.slice(0, 5).map((item) => (
            <ListItem key={item.title} {...item} />
          ))}
        </div>
        <div className="w-px self-stretch bg-[#66666632]" />
        <div className="flex flex-col gap-1 p-2 pt-0 md:pt-2">
          {EXPLOREITEMS.slice(5, 10).map((item: any) => (
            <ListItem key={item.title} {...item} />
          ))}
        </div>
      </NavigationMenuContent>
    </NavigationMenuItem>
  );
};

export default Explore;

const ListItem = ({
  title,
  description,
  icon,
  link,
  color,
  comingSoon,
}: {
  title: string;
  description: string;
  icon: string;
  link: string;
  color: string;
  comingSoon?: boolean;
}) => {
  const CommonContent = (
    <>
      <div
        className={`flex items-center justify-center rounded-lg p-3`}
        style={{ backgroundColor: color }}
      >
        <div className="relative h-5 aspect-square">
          <Image
            src={icon}
            alt=""
            fill
            className="object-contain object-center"
          />
        </div>
      </div>
      <div className="flex flex-col">
        <div className="flex flex-row items-center justify-start gap-2">
          <p className="text-sm text-[#D4D4D4]">{title}</p>
          {comingSoon && (
            <p className="mb-[2px] rounded-lg border border-[#FFFFFF12] bg-[#FFFFFF10] px-1 text-[10px] text-[#FFFFFF75]">
              Coming Soon
            </p>
          )}
        </div>
        <p className="text-xs text-[#9B9B9B]">{description}</p>
      </div>
    </>
  );

  const className = `flex w-72 flex-row items-center justify-start gap-3 rounded-lg p-2 ${
    comingSoon
      ? "cursor-default opacity-50"
      : "cursor-pointer hover:bg-[#2B2B2B45]"
  }`;

  return comingSoon ? (
    <div className={className}>{CommonContent}</div>
  ) : (
    <a className={className} href={link} target="_blank">
      {CommonContent}
    </a>
  );
};
