"use client";

import fetcher from "@/lib/fetcher";
import { AlertTriangle, ChevronRight, Loader2, Search } from "lucide-react";
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
import S3Image from "./s3-image";

type Mint = {
  image: string;
  price: string;
  currency: string;
  status: "live" | "upcoming" | "completed";
  title: string;
  link: string;
  source: string;
  logo: string;
};

const ExploreMint = ({ mints }: { mints: any }) => {
  const { data, error, isLoading } = useSWR<{
    mints: any;
  }>(`/api/kingdomly-mints`, fetcher);

  const kingdomlyMints = data?.mints;

  function processKindomlyMint(
    mint: any,
    status: "live" | "upcoming" | "completed",
  ) {
    return {
      image: mint.profile_image ? mint.profile_image : mint.header_image,
      price: mint.mint_group_data[0].price,
      currency: mint.chain.native_currency,
      status: status,
      logo: "faucet/quests/kingdomly.png",
      title: mint.collection_name || "Unknown",
      link: `https://www.kingdomly.app/${mint.slug}` || "",
      source: "kingdomly",
    };
  }

  function processMint(mint: any) {
    return {
      image: mint.image,
      price: mint.price,
      currency: "ETH",
      status: "live",
      logo: mint.partner.logo,
      title: mint._title,
      link: mint.link,
      source: "basehub",
    };
  }

  const allMints: Mint[] = [
    ...mints.items.map(processMint),
    ...(kingdomlyMints?.live.map((mint: any) =>
      processKindomlyMint(mint, "live"),
    ) ?? []),
    ...(kingdomlyMints?.upcoming.map((mint: any) =>
      processKindomlyMint(mint, "upcoming"),
    ) ?? []),
    ...(kingdomlyMints?.sold_out.map((mint: any) =>
      processKindomlyMint(mint, "completed"),
    ) ?? []),
  ];

  const [searchTerm, setSearchTerm] = useState("");
  const [selectedStatus, setSelectedStatus] = useState("all");
  const [selectedSort, setSelectedSort] = useState("");

  const filteredMints = allMints.filter(
    (mint: Mint) =>
      (selectedStatus === "all" || mint.status === selectedStatus) &&
      mint.title.toLowerCase().includes(searchTerm.toLowerCase()),
  );

  // const filteredMints = allMints;

  // console.log(filteredMints);

  const partnerMintsNum =
    data?.mints.live.length +
    data?.mints.upcoming.length +
    data?.mints.sold_out.length;

  const allMintsNum = mints.items.length + partnerMintsNum;

  return (
    <div className="relative flex size-full flex-col px-10 pb-20 pt-[65px] text-white md:px-20 md:pt-24">
      <div className="flex w-full items-center gap-2 py-10">
        <Link
          href="/"
          className="text-sm font-light text-[#FFFFFF]/70 md:text-base"
        >
          Home
        </Link>
        <ChevronRight className="aspect-square h-[20px] text-[#FFC500]" />
        <p className="text-[#FFC500]">Partner Collections</p>
      </div>
      <p className="mb-1 text-2xl font-semibold md:text-3xl">
        Explore Our Partners Mint
      </p>
      {/* <p className="text-lg">Deets</p> */}
      <div className="relative my-6 flex flex-col-reverse items-start justify-between gap-4 md:flex-row md:items-center">
        <div className="relative w-full">
          <Search className="absolute inset-y-0 left-4 my-auto aspect-square h-6 text-[#FFFFFF]/70" />
          <Input
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="relative h-12 w-full rounded-xl border-none bg-[#FFFFFF]/10 pl-12 placeholder:text-[#FFFFFF]/70 md:w-3/4"
            placeholder="Search by mint name"
          />
        </div>

        <div className="flex items-center gap-2">
          <StatusSelect
            setSelectedStatus={setSelectedStatus}
            selectedStatus={selectedStatus}
          />
          {/* <SortSelect
            setSelectedSort={setSelectedSort}
            selectedSort={selectedSort}
            allMintsNum={allMintsNum}
            partnerMintsNum={partnerMintsNum}
          /> */}
        </div>
      </div>
      {error ? (
        <div className="flex items-center gap-2">
          <AlertTriangle className="text-[#FFC500]" />
          Error retrieving partners mints
        </div>
      ) : isLoading ? (
        <div className="flex items-center gap-2">
          <Loader2 className="animate-spin text-white" />
          Loading...
        </div>
      ) : filteredMints.length === 0 ? (
        <p>No Mints Found</p>
      ) : (
        <div className="grid w-full grid-cols-[repeat(auto-fill,minmax(18rem,1fr))] gap-4">
          {filteredMints.map((mint: Mint, id: number) => (
            <MintDisplay key={id} mint={mint} status={mint.status} />
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
  status: "live" | "upcoming" | "completed";
}) => {
  const [hover, setHover] = useState(false);
  return (
    <div
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      className={`flex h-[300px] w-full rounded-xl bg-gradient-to-b md:h-[400px] ${!hover ? "from-[#F4C10B]/80 via-[#F8A929]/50 via-20% to-[#F2C8481F] p-px" : "from-[#FFC500]/75 via-[#F8A929]/75 via-40% to-[#FF4C12]/75 p-[2px]"} `}
    >
      <div className="h-full w-full rounded-xl bg-[#0A0601]">
        <div
          className={`bg-gradient-to-r ${!hover ? "from-[#F2C848]/5 to-[#F8A929]/5" : "from-[#F2C848]/10 to-[#F8A929]/10 shadow-partner"} flex h-full w-full flex-col overflow-hidden rounded-xl p-2`}
        >
          <div className="relative flex h-full w-full items-end overflow-hidden rounded-xl p-2">
            {mint.source === "kingdomly" ? (
              mint.image.toLowerCase().includes(".mp4") ? (
                <video
                  src={mint.image}
                  autoPlay
                  loop
                  muted
                  playsInline
                  className="absolute left-0 z-0 overflow-hidden object-cover"
                />
              ) : (
                <Image
                  src={mint.image}
                  alt=""
                  fill
                  className="z-0 object-cover"
                />
              )
            ) : (
              <S3Image
                src={mint.image}
                alt=""
                fill
                className="z-0 object-cover"
              />
            )}
            {hover && (
              <a href={mint.link} className="z-10 w-full" target="_blank">
                <button className="w-full rounded-xl bg-[#F4C10B] py-2 font-semibold text-[#121212]">
                  Explore Now
                </button>
              </a>
            )}
          </div>
          <div className="flex items-center justify-between py-3">
            <p className="font-medium">{mint.title}</p>
            <div className="relative aspect-square h-[20px]">
              <PartnerImage
                src={mint.logo}
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
                {mint.price}&nbsp;{mint.currency}
              </p>
            </div>
          </div>
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
    { title: "Live", value: "live" },
    { title: "Upcoming", value: "upcoming" },
    { title: "Completed", value: "completed" },
  ];
  return (
    <Select
      defaultValue={selectedStatus}
      onValueChange={(value) => setSelectedStatus(value)}
    >
      <SelectTrigger className="h-12 gap-4 whitespace-nowrap rounded-xl border border-[#FFFFFF]/10 bg-transparent">
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
                  <div className="aspect-square h-2 rounded-full bg-[#F4C10B]" />
                ) : item.value === "live" ? (
                  <div className="aspect-square h-2 rounded-full bg-[#22B642]" />
                ) : item.value === "upcoming" ? (
                  <div className="aspect-square h-2 rounded-full bg-gradient-to-b from-[#F4C10B] to-[#FF4C12]" />
                ) : (
                  <div className="aspect-square h-2 rounded-full bg-[#5B5B5B]" />
                )}
                <p className="text-xs md:text-sm">{item.title}</p>
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
  partnerMintsNum,
  allMintsNum,
}: {
  selectedSort: string;
  setSelectedSort: React.Dispatch<React.SetStateAction<string>>;
  partnerMintsNum: number;
  allMintsNum: number;
}) => {
  const ITEMS = [
    { title: "Partners mint only", value: "partners", num: partnerMintsNum },
    { title: "All Mints", value: "all", num: allMintsNum },
  ];
  return (
    <Select
      defaultValue={selectedSort}
      onValueChange={(value) => setSelectedSort(value)}
    >
      <SelectTrigger className="h-12 min-w-[180px] rounded-xl border border-[#FFFFFF]/10 bg-transparent">
        <SelectValue placeholder="Sort by" />
      </SelectTrigger>
      <SelectContent className="rounded-xl border border-[#666666]/30 bg-[#0D0D0D]/90 p-1">
        <SelectGroup>
          {ITEMS.map((item, id) => (
            <SelectItem
              key={id}
              value={item.value}
              className="rounded-xl p-3 text-[#FFFFFF]/70 focus:bg-[#FFFFFF]/20 focus:font-medium focus:text-white"
            >
              <p>
                {item.title}&nbsp;
                <span className="text-[#FFFFFF]/30">({item.num})</span>
              </p>
            </SelectItem>
          ))}
        </SelectGroup>
      </SelectContent>
    </Select>
  );
};
