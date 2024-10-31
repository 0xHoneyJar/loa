"use client";

import fetcher from "@/lib/fetcher";
import { ChevronRight, Search } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import useSWR from "swr";
import PartnerImage from "./partner-image";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "./ui/select";
import { useState } from "react";
import { Input } from "./ui/input";

const ExploreMint = () => {
  const { data, error, isLoading } = useSWR<{
    mints: any;
  }>(`/api/kingdomly-mints`, fetcher);
  const [searchTerm, setSearchTerm] = useState("");
  const [selectedStatus, setSelectedStatus] = useState("all");
  const [selectedSort, setSelectedSort] = useState("");

  //   const filteredMints = data?.mints.filter((mints) =>
  //     product.name.toLowerCase().includes(searchTerm.toLowerCase()),
  //   );

  return (
    <div className="relative flex size-full flex-col px-20 pt-[65px] text-white md:pt-24">
      <div className="flex w-full items-center gap-2 py-10">
        <Link href="/" className="font-light text-[#FFFFFF]/70">
          Home
        </Link>
        <ChevronRight className="aspect-square h-[20px] text-[#FFC500]" />
        <p className="text-[#FFC500]">Partner Collections</p>
      </div>
      <p className="mb-1 text-3xl font-semibold">Explore Our Partners Mint</p>
      <p className="text-lg">Deets</p>
      <div className="relative my-6 flex items-center justify-between">
        <Search className="absolute left-4 aspect-square h-6 text-[#FFFFFF]/70" />
        <Input
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="relative h-12 w-1/2 rounded-xl border-none bg-[#FFFFFF]/10 pl-12 placeholder:text-[#FFFFFF]/70"
          placeholder="Search by mint name"
        />
        <div className="flex items-center gap-2">
          <StatusSelect
            setSelectedStatus={setSelectedStatus}
            selectedStatus={selectedStatus}
          />
          <SortSelect
            setSelectedSort={setSelectedSort}
            selectedSort={selectedSort}
          />
        </div>
      </div>
      {error ? (
        <div>Error retrieving partners mints</div>
      ) : isLoading ? (
        <div>Loading...</div>
      ) : (
        <div className="grid w-full grid-cols-[repeat(auto-fill,minmax(18rem,1fr))] gap-4">
          {data?.mints.live.map((mint: any, id: number) => (
            <MintDisplay key={id} mint={mint} status={"live"} />
          ))}
          {data?.mints.upcoming.map((mint: any, id: number) => (
            <MintDisplay key={id} mint={mint} status={"upcoming"} />
          ))}
          {data?.mints.sold_out.map((mint: any, id: number) => (
            <MintDisplay key={id} mint={mint} status={"soldOut"} />
          ))}
        </div>
      )}
    </div>
  );
};

export default ExploreMint;

const MintDisplay = ({
  mint,
  status,
}: {
  mint: any;
  status: "live" | "upcoming" | "soldOut";
}) => {
  return (
    <div className="flex h-[400px] w-full flex-col overflow-hidden rounded-xl border border-[#FFFFFF]/10 bg-[#FFFFFF]/5 p-2">
      <div className="relative h-full w-full overflow-hidden rounded-lg">
        <Image
          src={mint.header_image ? mint.header_image : mint.profile_image}
          alt=""
          fill
          className="z-0 object-cover"
        />
      </div>
      <div className="flex items-center justify-between py-3">
        <p className="font-medium">The Collection Name</p>
        <div className="relative aspect-square h-[20px]">
          <PartnerImage
            src={"faucet/quests/kingdomly.png"}
            alt="logo"
            fill
            className="rounded-full"
          />
        </div>
      </div>
      <div className="grid w-full grid-cols-2 gap-4 rounded-xl bg-[#FFFFFF]/10 px-4 py-2">
        <div className="flex h-full w-full flex-col justify-center">
          <p className="text-xs text-[#FFFFFF]/70">Status</p>
          <div className="flex items-center gap-2">
            {status === "live" ? (
              <div className="aspect-square h-2 rounded-full bg-[#22B642]" />
            ) : status === "upcoming" ? (
              <div className="aspect-square h-2 rounded-full bg-gradient-to-b from-[#F4C10B] to-[#FF4C12]" />
            ) : (
              <div className="aspect-square h-2 rounded-full bg-[#5B5B5B]" />
            )}
            <p className="text-sm font-medium">
              {status === "live"
                ? "Mint Now"
                : status === "upcoming"
                  ? "Upcoming"
                  : "Completed"}
            </p>
          </div>
        </div>
        <div className="flex h-full w-full flex-col justify-center">
          <p className="text-xs text-[#FFFFFF]/70">Price</p>
          <p className="text-sm">
            {mint.mint_group_data[0].price}&nbsp;{mint.chain.native_currency}
          </p>
        </div>
      </div>
    </div>
  );
};

const StatusSelect = ({
  selectedStatus,
  setSelectedStatus,
}: {
  selectedStatus: string;
  setSelectedStatus: React.Dispatch<React.SetStateAction<string>>;
}) => {
  const ITEMS = [
    { title: "All Status", value: "all" },
    { title: "Upcoming", value: "upcoming" },
    { title: "Completed", value: "completed" },
  ];
  return (
    <Select
      defaultValue={selectedStatus}
      onValueChange={(value) => setSelectedStatus(value)}
    >
      <SelectTrigger className="h-12 gap-4 whitespace-nowrap rounded-lg border border-[#FFFFFF]/10 bg-transparent">
        <SelectValue />
      </SelectTrigger>
      <SelectContent className="rounded-xl border border-[#666666]/30 bg-[#0D0D0D]/90 p-1">
        <SelectGroup>
          {ITEMS.map((item, id) => (
            <SelectItem
              key={id}
              value={item.value}
              className="rounded-xl p-3 text-[#FFFFFF]/70 focus:bg-[#FFFFFF]/20 focus:font-medium focus:text-white"
            >
              <div className="flex items-center gap-2">
                {item.value === "all" ? (
                  <div className="aspect-square h-2 rounded-full bg-[#22B642]" />
                ) : item.value === "upcoming" ? (
                  <div className="aspect-square h-2 rounded-full bg-gradient-to-b from-[#F4C10B] to-[#FF4C12]" />
                ) : (
                  <div className="aspect-square h-2 rounded-full bg-[#5B5B5B]" />
                )}
                <p>{item.title}</p>
              </div>
            </SelectItem>
          ))}
        </SelectGroup>
      </SelectContent>
    </Select>
  );
};

const SortSelect = ({
  selectedSort,
  setSelectedSort,
}: {
  selectedSort: string;
  setSelectedSort: React.Dispatch<React.SetStateAction<string>>;
}) => {
  const ITEMS = [
    { title: "Partners mint only", value: "partners" },
    { title: "All Mints", value: "all" },
  ];
  return (
    <Select
      defaultValue={selectedSort}
      onValueChange={(value) => setSelectedSort(value)}
    >
      <SelectTrigger className="h-12 min-w-[180px] rounded-xl border border-[#FFFFFF]/10 bg-transparent">
        <SelectValue placeholder="Sort by" />
      </SelectTrigger>
      <SelectContent className="border border-[#666666]/30 bg-[#0D0D0D]/90 p-1">
        <SelectGroup>
          {ITEMS.map((item, id) => (
            <SelectItem
              key={id}
              value={item.value}
              className="rounded-xl p-3 text-[#FFFFFF]/70 focus:bg-[#FFFFFF]/20 focus:font-medium focus:text-white"
            >
              <p>{item.title}</p>
            </SelectItem>
          ))}
        </SelectGroup>
      </SelectContent>
    </Select>
  );
};
