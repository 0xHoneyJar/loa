"use client";

import { useState } from "react";
import { ChevronRight } from "lucide-react";
import Image from "next/image";
import useUserStore from "@/state/user/useUserStore";
import { Raffle } from "@/constants/raffle";
import { useEffect } from "react";
import { retrieveRaffles } from "@/actions/retrieve-raffles";
import RaffleDisplay from "../raffle-display";
import { trackEvent } from "@openpanel/nextjs";
import SkeletonDisplay from "../skeleton-display";

const Raffles = () => {
  const currentTime = useUserStore((state) => state.currentTime);
  const [raffles, setRaffles] = useState<Raffle[]>([]);
  const [loadingRaffle, setLoadingRaffle] = useState(false);

  useEffect(() => {
    async function getRaffles() {
      setLoadingRaffle(true);
      const retrievedRaffles = await retrieveRaffles();
      retrievedRaffles.sort((a, b) => {
        // Define a priority for each quest based on current time
        const getPriority = (raffle: Raffle) => {
          if (raffle.startTime <= currentTime && raffle.endTime >= currentTime)
            return 1; // Recent Active Quests
          if (raffle.startTime > currentTime) return 2; // Coming Soon
          if (raffle.endTime < currentTime) return 3; // Ended
          return 4; // Default priority for undefined statuses
        };

        // Compare based on priority first
        const priorityA = getPriority(a);
        const priorityB = getPriority(b);

        if (priorityA !== priorityB) {
          return priorityA - priorityB;
        }

        // If priorities are the same, sort by endTime descending
        return b.endTime - a.endTime;
      });
      setRaffles(retrievedRaffles);
      setLoadingRaffle(false);
    }

    getRaffles();
  }, []);

  return (
    <div className="relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]">
      <div className="absolute -top-40 h-1 w-full" id="raffles" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-[72px] md:px-6">
        <div className="flex items-center gap-2">
          <p className="text-base font-medium text-[#FFD700] md:text-lg">
            Raffles
          </p>
        </div>
      </div>
      <div className="flex grow flex-col justify-between p-4 md:p-6">
        <p className="mb-4 text-xs uppercase text-white md:text-sm">
          TAKE PART IN RAFFLES TO WIN PRIZES FROM AROUND THE&nbsp;
          <span className="text-[#E1A94E]">BERACHAIN ECOSYSTEM!</span>
        </p>
        <div className="mb-4 grid size-full grid-rows-3 gap-4 overflow-hidden md:gap-6">
          {!loadingRaffle
            ? raffles
                .slice(0, 3)
                .map((raffle, id) => <RaffleDisplay raffle={raffle} key={id} />)
            : Array.from({ length: 3 }).map((_, id) => (
                <SkeletonDisplay key={id} />
              ))}
        </div>
        <a
          href={"https://faucet.0xhoneyjar.xyz/raffles"}
          target="_blank"
          onClick={() => {
            trackEvent(`explore_raffles`);
          }}
          className="flex w-full cursor-blue items-center justify-between rounded-lg border border-[#E8E8E80A] bg-[#FFFFFF0A] p-2 transition-all duration-500 ease-in-out hover:border-[#E8E8E80F] hover:bg-[#FFFFFF3D] md:px-4 md:py-3"
        >
          <div className="flex items-center gap-1 md:gap-2">
            <div className="relative aspect-square h-6 md:h-[26px]">
              <Image
                src={"/question.svg"}
                alt="question"
                fill
                className="object-contain"
              />
            </div>
            <p className="whitespace-nowrap text-xs md:text-sm">
              Explore All Raffles
            </p>
          </div>
          <ChevronRight className="aspect-square h-3 text-[#FFFFFF]/40 md:hidden md:h-[14px] xl:block" />
        </a>
      </div>
    </div>
  );
};

export default Raffles;
