"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import { ChevronRight } from "lucide-react";
import { retrieveQuests } from "@/actions/retrieve-quests";
import { Quest } from "@/constants/quest";
import useUserStore from "@/state/user/useUserStore";
import QuestDisplay from "../quest-display";
import { trackEvent } from "@openpanel/nextjs";
import SkeletonDisplay from "../skeleton-display";

const Quests = () => {
  const currentTime = useUserStore((state) => state.currentTime);
  const [quests, setQuests] = useState<Quest[]>([]);
  const [loadingQuest, setLoadingQuest] = useState(false);

  useEffect(() => {
    async function getQuests() {
      setLoadingQuest(true);
      const retrievedQuests = await retrieveQuests();
      retrievedQuests.sort((a, b) => {
        // Define a priority for each quest based on current time
        const getPriority = (quest: Quest) => {
          if (quest.startTime <= currentTime && quest.endTime >= currentTime)
            return 1; // Recent Active Quests
          if (quest.startTime > currentTime) return 2; // Coming Soon
          if (quest.endTime < currentTime) return 3; // Ended
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

      setQuests(retrievedQuests);
      setLoadingQuest(false);
    }

    getQuests();
  }, []);

  return (
    <div
      className={`relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="quests" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-[72px] md:px-6">
        <div className="flex items-center gap-3">
          <p className="text-base font-medium text-[#FFD700] md:text-lg">
            Quests
          </p>
          <div className="relative aspect-square h-2 rounded-full bg-[#FF0000]">
            <div className="absolute aspect-square size-full animate-ping rounded-full bg-[#FF0000]" />
          </div>
        </div>
      </div>
      <div className="flex grow flex-col justify-between p-4 md:p-6">
        <p className="mb-4 text-xs uppercase text-white md:text-sm">
          Take part in{" "}
          <span className="text-[#E1A94E]">THJ specials Quests</span> and{" "}
          <span className="text-[#E1A94E]">get rewarded! like seriously</span>
        </p>
        <div className="mb-4 grid size-full grid-rows-3 gap-4 overflow-hidden md:gap-6">
          {!loadingQuest
            ? quests
                .filter((q) => !q.paused && !q.disabled)
                .slice(0, 3)
                .map((quest, id) => <QuestDisplay quest={quest} key={id} />)
            : Array.from({ length: 3 }).map((_, id) => (
                <SkeletonDisplay key={id} />
              ))}
        </div>
        <a
          href={"https://www.cubquests.com/quests"}
          onClick={() => {
            trackEvent(`explore_quests`);
          }}
          target="_blank"
          className="flex w-full items-center justify-between rounded-lg border border-[#E8E8E80A] bg-[#FFFFFF0A] px-2 py-2 transition-all duration-500 ease-in-out hover:border-[#E8E8E80F] hover:bg-[#FFFFFF3D] md:px-3 md:py-3"
        >
          <div className="flex w-full flex-row items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="relative aspect-square h-5">
                <Image
                  src={"/question.svg"}
                  alt="question"
                  fill
                  className="object-contain"
                />
              </div>
              <p className="whitespace-nowrap text-sm">Explore All Quests</p>
            </div>
            <ChevronRight className="aspect-square h-3 text-[#FFFFFF40]" />
          </div>
        </a>
      </div>
    </div>
  );
};

export default Quests;
