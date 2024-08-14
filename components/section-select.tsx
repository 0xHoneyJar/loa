import { DASHBOARD } from "@/constants/dashboard";
import {
  NavigationMenuItem,
  NavigationMenuTrigger,
  NavigationMenuContent,
  NavigationMenuLink,
} from "@/components/ui/navigation-menu";
import { ScrollArea } from "./ui/scroll-area";

const SectionSelect = () => {
  return (
    <NavigationMenuItem className="">
      <NavigationMenuTrigger className="hidden items-center gap-1 rounded-full bg-[#FFFFFF0F] px-6 py-2.5 text-xs text-white hover:bg-white/30 md:flex">
        Section
      </NavigationMenuTrigger>
      <NavigationMenuContent className="left-32 top-[48px] data-[motion=from-end]:animate-enterFromRight data-[motion=from-start]:animate-enterFromLeft data-[motion=to-end]:animate-exitToRight data-[motion=to-start]:animate-exitToLeft data-[state=closed]:animate-scaleOut data-[state=open]:animate-scaleIn">
        <ScrollArea className="relative h-[490px] w-[220px] items-center rounded-xl border border-[#171717] bg-[#0F0F0F] p-1">
          <div className="flex flex-col gap-1 p-2 pr-4">
            {DASHBOARD.map(
              (section, id) =>
                !section.hidden && (
                  <button
                    key={id}
                    // value={section.key}
                    onClick={() => {
                      const id = document?.getElementById(section.key);
                      id &&
                        id.scrollIntoView({
                          behavior: "smooth",
                        });
                    }}
                    className="rounded-lg px-3 py-3 text-left text-sm text-[#D4D4D4] hover:bg-[#2B2B2B45] hover:text-white"
                  >
                    {section.name}
                  </button>
                ),
            )}
          </div>
        </ScrollArea>
      </NavigationMenuContent>
    </NavigationMenuItem>
  );
};

export default SectionSelect;
