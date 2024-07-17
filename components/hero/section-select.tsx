import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectTrigger,
} from "@/components/ui/select";
import { DASHBOARD } from "@/constants/dashboard";

const SectionSelect = () => {
  return (
    <Select
      onValueChange={(value: any) => {
        const section = document.getElementById(value);
        section && section.scrollIntoView({ behavior: "smooth" });
      }}
    >
      <SelectTrigger className="flex h-[36px] items-center gap-1 rounded-full bg-[#FFFFFF0F] px-4 text-xs text-white md:px-6 md:text-sm">
        <p>Section</p>
      </SelectTrigger>
      <SelectContent
        align="center"
        sideOffset={30}
        className="relative max-h-[490px] w-[220px] items-center rounded-xl border border-[#171717] bg-[#0F0F0F] p-1"
      >
        {/* <div className="h-1/6 w-full absolute bottom-0 bg-gradient-to-t from-[#0F0F0F] z-10" /> */}
        <SelectGroup className="flex flex-col gap-2">
          {DASHBOARD.map(
            (section, id) =>
              !section.hidden && (
                <SelectItem
                  key={id}
                  value={section.key}
                  className="rounded-lg bg-[#121212] py-3 text-sm text-[#E7E7E7] focus:bg-[#F8A9292E] focus:text-[#FFD700]"
                >
                  {section.name}
                </SelectItem>
              ),
          )}
        </SelectGroup>
      </SelectContent>
    </Select>
  );
};

export default SectionSelect;
