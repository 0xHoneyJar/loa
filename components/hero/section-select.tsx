import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectTrigger,
} from "@/components/ui/select";
import { SECTION } from "@/constants/section";

const SectionSelect = () => {
  return (
    <Select
      onValueChange={(value: any) => {
        const section = document.getElementById(value);
        section && section.scrollIntoView({ behavior: "smooth" });
      }}
    >
      <SelectTrigger className="md:px-6 px-4 py-3 h-full flex gap-1 items-center text-[#CCCCCC] rounded-full border border-[#FFFFFF]/15 md:text-sm text-xs bg-transparent">
        <p>Section</p>
      </SelectTrigger>
      <SelectContent
        align="center"
        sideOffset={30}
        className="items-center bg-[#0F0F0F] border border-[#171717] rounded-xl max-h-[490px] w-[220px] p-1 relative"
      >
        {/* <div className="h-1/6 w-full absolute bottom-0 bg-gradient-to-t from-[#0F0F0F] z-10" /> */}
        <SelectGroup className="gap-2 flex flex-col">
          {SECTION.map((section, id) => (
            <SelectItem
              key={id}
              value={section.value}
              className="text-[#E7E7E7] bg-[#121212] rounded-lg text-sm py-3 focus:bg-[#F8A9292E] focus:text-[#FFD700]"
            >
              {section.name}
            </SelectItem>
          ))}
        </SelectGroup>
      </SelectContent>
    </Select>
  );
};

export default SectionSelect;
