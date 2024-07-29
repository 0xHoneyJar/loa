import { useEffect, useState } from "react";
import DragHandleY from "../drag-handle-y";
import Image from "next/image";
import { ChevronRight } from "lucide-react";
import { retrieveQuests } from "@/actions/retrieve-quests";
import { Quest } from "@/constants/quest";
import useUserStore from "@/state/user/useUserStore";
import QuestDisplay from "../quest-display";

const Quests = () => {
  const [glow, setGlow] = useState(false);
  const currentTime = useUserStore((state) => state.currentTime);
  const [quests, setQuests] = useState<Quest[]>([]);
  useEffect(() => {
    async function getQuests() {
      const retrievedQuests = await retrieveQuests();

      // const liveAndUpcomingQuests = retrievedQuests.filter(
      //   (quest) =>
      //     !quest.disabled &&
      //     !quest.paused &&
      //     ((quest.startTime <= currentTime && currentTime < quest.endTime) ||
      //       quest.startTime > currentTime),
      // );
      setQuests(retrievedQuests);
    }

    // getQuests();
  }, []);

  return (
    <div
      className={`${glow && "rotate-1"} relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="quests" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-20 md:px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#FFC500] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandleY setGlow={setGlow} />
          <p className="text-sm font-medium text-[#FFD700] md:text-base xl:text-xl">
            Quests
          </p>
          <div className="relative aspect-square h-[12px] rounded-full bg-[#FF0000]">
            <div className="absolute aspect-square size-full animate-ping rounded-full bg-[#FF0000]" />
          </div>
        </div>
      </div>
      <div className="flex grow flex-col justify-between p-4 md:p-6">
        <p className="text-xs uppercase text-white md:text-sm xl:text-base">
          Take part in{" "}
          <span className="text-[#E1A94E]">THJ specials Quests</span> and{" "}
          <span className="text-[#E1A94E]">get rewarded! like seriously</span>
        </p>
        <div className="grid w-full grid-rows-3 gap-6">
          {quests.slice(0, 3).map((quest, id) => (
            <QuestDisplay quest={quest} key={id} />
          ))}
        </div>
        <a
          href={"https://faucet.0xhoneyjar.xyz/quests"}
          target="_blank"
          className="flex w-full cursor-blue items-center justify-between rounded-lg border border-[#E8E8E80A] bg-[#FFFFFF0A] px-2 py-2 hover:border-[#E8E8E80F] hover:bg-[#FFFFFF3D] md:px-3 md:py-3 xl:px-4"
        >
          <div className="flex items-center gap-2">
            <div className="relative aspect-square h-6 md:h-[26px] xl:h-[32px]">
              <Image
                src={"/question.svg"}
                alt="question"
                fill
                className="object-contain"
              />
            </div>
            <p className="whitespace-nowrap text-xs md:text-sm xl:text-base">
              Explore All Quests
            </p>
          </div>
          <ChevronRight className="aspect-square h-3 text-[#FFFFFF]/40 md:h-[14px] xl:h-[18px]" />
        </a>
      </div>
    </div>
  );
};

export default Quests;
