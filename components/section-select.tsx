import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectTrigger,
} from "@/components/ui/select";
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
    // <Select
    //   onValueChange={(value: any) => {
    //     const section = document.getElementById(value);
    //     section && section.scrollIntoView({ behavior: "smooth" });
    //   }}
    // >
    //   <SelectTrigger className="flex h-[36px] items-center gap-1 rounded-full bg-[#FFFFFF0F] px-4 text-xs text-white md:px-6 md:text-sm">
    //     <p>Section</p>
    //   </SelectTrigger>
    //   <SelectContent
    //     align="center"
    //     sideOffset={30}
    //     className="relative max-h-[490px] w-[220px] items-center rounded-xl border border-[#171717] bg-[#0F0F0F] p-1"
    //   >
    //     {/* <div className="h-1/6 w-full absolute bottom-0 bg-gradient-to-t from-[#0F0F0F] z-10" /> */}
    //     <SelectGroup className="flex flex-col gap-2">
    //       {DASHBOARD.map(
    //         (section, id) =>
    //           !section.hidden && (
    //             <SelectItem
    //               key={id}
    //               value={section.key}
    //               className="rounded-lg py-3 text-sm text-[#E7E7E7] focus:bg-[#FFFFFF2E] focus:font-medium focus:text-white"
    //             >
    //               {section.name}
    //             </SelectItem>
    //           ),
    //       )}
    //     </SelectGroup>
    //   </SelectContent>
    // </Select>
    <NavigationMenuItem value="section">
      <NavigationMenuTrigger className="flex items-center gap-1 rounded-full bg-[#FFFFFF0F] px-6 py-2.5 text-xs text-white lg:text-sm">
        Section
      </NavigationMenuTrigger>
      <NavigationMenuContent className="data-[state=open]:animate-scaleIn data-[state=closed]:animate-scaleOut data-[motion=from-start]:animate-enterFromLeft data-[motion=from-end]:animate-enterFromRight data-[motion=to-start]:animate-exitToLeft data-[motion=to-end]:animate-exitToRight left-32 top-[60px]">
        <ScrollArea className="relative h-[490px] w-[220px] items-center rounded-xl border border-[#171717] bg-[#0F0F0F] p-1">
          {/* <div className="h-1/6 w-full absolute bottom-0 bg-gradient-to-t from-[#0F0F0F] z-10" /> */}
          <div className="flex flex-col gap-2">
            {DASHBOARD.map(
              (section, id) =>
                !section.hidden && (
                  <button
                    key={id}
                    // value={section.key}
                    className="rounded-lg px-8 py-3 text-left text-sm text-[#E7E7E7] hover:bg-[#FFFFFF2E] hover:font-medium hover:text-white"
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
