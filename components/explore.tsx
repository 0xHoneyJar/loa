import { FLAGSHIP_ITEMS, ECOSYSTEM_ITEMS } from "@/constants/explore";
import Image from "next/image";
import { trackEvent } from "@openpanel/nextjs";
import * as NavigationMenu from "@radix-ui/react-navigation-menu";
import { ChevronDown } from "lucide-react";

const Explore = () => {
  return (
    <NavigationMenu.Root>
      <NavigationMenu.List>
        <NavigationMenu.Item className="">
          <NavigationMenu.Trigger className="group border-none outline-none">
            <div className="flex cursor-pointer flex-row items-center justify-center gap-[6px] rounded-full border border-[#F4C10B24] bg-gradient-to-b from-[#F4C10B12] to-[#F8A92912] px-4 py-2 text-sm text-white hover:border-[#F4C10B58] hover:from-[#F4C10B32] hover:to-[#F8A92932] md:px-5">
              <p className="">Explore</p>
              <p className="rounded-xl bg-gradient-to-b from-[#FFC500] to-[#FFD700] px-1 text-[10px] font-light uppercase leading-4 text-black">
                New
              </p>
              <ChevronDown
                className="duration-[250ms] relative top-px size-3 transition-transform ease-in group-data-[state=open]:-rotate-180"
                aria-hidden
              />
            </div>
          </NavigationMenu.Trigger>
          <div className="fixed left-1/2 top-[66px] mt-2 -translate-x-1/2">
            <NavigationMenu.Content className="relative flex size-auto w-[90vw] max-w-6xl origin-top flex-row items-stretch rounded-xl border border-[#66666632] bg-[#0D0D0D] data-[motion=from-end]:animate-enterFromRight data-[motion=from-start]:animate-enterFromLeft data-[motion=to-end]:animate-exitToRight data-[motion=to-start]:animate-exitToLeft data-[state=closed]:animate-scaleOut data-[state=open]:animate-scaleIn">
              <div className="grow p-5">
                <div className="mb-2 text-xs uppercase text-[#9B9B9B]">
                  Flagship
                </div>
                <div className="-mx-2 -mb-2 grid grid-cols-1 gap-0.5 lg:grid-cols-2">
                  {FLAGSHIP_ITEMS.map((item) => (
                    <ListItem key={item.title} {...item} />
                  ))}
                </div>
              </div>
              <div className="w-px self-stretch bg-[#66666632]" />
              <div className="grow p-5">
                <div className="mb-2 text-xs uppercase text-[#9B9B9B]">
                  Ecosystem
                </div>
                <div className="-mx-2 -mb-2 grid grid-cols-1 gap-0.5 lg:grid-cols-2">
                  {ECOSYSTEM_ITEMS.map((item) => (
                    <ListItem key={item.title} {...item} />
                  ))}
                </div>
              </div>
            </NavigationMenu.Content>
          </div>
        </NavigationMenu.Item>
      </NavigationMenu.List>
    </NavigationMenu.Root>
  );
};

export default Explore;

export const ListItem = ({
  title,
  description,
  icon,
  link,
  color,
  comingSoon,
  style,
}: {
  title: string;
  description: string;
  icon: string;
  link: string;
  color: string;
  comingSoon?: boolean;
  style?: React.CSSProperties;
}) => {
  const CommonContent = (
    <>
      <div
        className={`flex items-center justify-center rounded-lg p-3`}
        style={{ backgroundColor: color }}
      >
        <div className="relative aspect-square h-5">
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

  const className = `flex w-full md:w-full flex-row items-center justify-start gap-3 rounded-lg p-2 ${
    comingSoon
      ? "cursor-default opacity-50"
      : "cursor-pointer hover:bg-[#2B2B2B45]"
  }`;

  return comingSoon ? (
    <div className={className} style={style}>
      {CommonContent}
    </div>
  ) : (
    <a
      className={className}
      href={link}
      target="_blank"
      onClick={() => {
        trackEvent(`explore_item_${title.toLowerCase()}_navbar`);
      }}
      style={style}
    >
      {CommonContent}
    </a>
  );
};
