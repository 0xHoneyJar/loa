import { PartnerButton, PartnersButton } from "@/components/ui/buttons";
import Image from "next/image";

const Partners = ({ partners }: { partners?: any }) => {
  const filteredPartners = partners?.filter(
    (partner: any) =>
      partner.partner &&
      partner.status &&
      partner.category &&
      partner.partner !== "Unknown",
  );

  return (
    <div
      className={`relative col-span-full row-span-1 flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#121A12] bg-[#10120D]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="partners" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#43AA77]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-[72px] md:px-6">
        <div className="flex items-center gap-2">
          <p className="text-base font-medium text-white md:text-lg">
            Partners
          </p>
        </div>
      </div>
      <div className="flex grow flex-col">
        <div className="flex w-full flex-col justify-center gap-4 p-4 md:gap-6 md:p-6">
          <p className="text-xs text-[#A9A9A9] md:text-sm">
            THJ has a vast and constantly growing network of partners. Many of
            them are providing perks to Honeycomb holders.
          </p>
          <div className="relative w-full rounded-xl bg-[#43AA772E] px-4 py-6">
            <p className="text-3xl font-medium text-[#00AB55]">
              {filteredPartners?.length}
            </p>
            <p className="absolute bottom-2 right-2 flex items-center text-[10px] text-[#A9A9A9] md:text-xs">
              / Total Partners
              {/* <HelpCircle className="aspect-square h-3 md:h-[14px]" /> */}
            </p>
          </div>
          <div className="relative w-full rounded-xl bg-[#43AA772E] px-4 py-6">
            <p className="w-full truncate text-3xl font-medium text-[#00AB55]">
              $11,000,000+
            </p>
            <p className="absolute bottom-2 right-2 flex items-center text-[10px] text-[#A9A9A9] md:text-xs">
              / Raised
              {/* <HelpCircle className="aspect-square h-3 md:h-[14px]" /> */}
            </p>
          </div>
          <PartnersButton />
        </div>
        <div className="relative flex w-full grow items-center justify-center border-t border-[#43AA771A] px-4 md:px-6">
          <div className="absolute -bottom-2 -left-0 aspect-square h-[40px]">
            <Image
              src={"/arrow-swirl-partner.svg"}
              alt="arrow-swirl"
              fill
              className="object-contain"
            />
          </div>
          <div className="absolute -right-0 -top-2 aspect-square h-[40px] rotate-180">
            <Image
              src={"/arrow-swirl-partner.svg"}
              alt="arrow-swirl"
              fill
              className="object-contain"
            />
          </div>
          <div className="w-full rounded-full border border-dashed border-[#9F9F9F63] p-2">
            <PartnerButton />
          </div>
        </div>
      </div>
    </div>
  );
};

export default Partners;
