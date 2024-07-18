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
      className={`${glow && "rotate-[1deg]"} relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="quests" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
      <div className="relative flex h-20 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-6">
        <div
          className={`absolute inset-x-0 -top-6 mx-auto h-4 w-[90%] animate-pulse bg-[#FFC500] blur-2xl ${glow ? "flex" : "hidden"}`}
        />
        <div className="flex items-center gap-2">
          <DragHandleY setGlow={setGlow} />
          <p className="text-xl font-medium text-[#FFD700]">Quests</p>
          <div className="relative aspect-square h-[12px] rounded-full bg-[#FF0000]">
            <div className="absolute aspect-square h-full w-full animate-ping rounded-full bg-[#FF0000]" />
          </div>
        </div>
      </div>
      <div className="flex grow flex-col justify-between p-6">
        <p className="uppercase text-white">
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
          className="flex w-full cursor-blue items-center justify-between rounded-lg border border-[#E8E8E80A] bg-[#FFFFFF0A] px-4 py-3 hover:border-[#E8E8E80F] hover:bg-[#FFFFFF3D]"
        >
          <div className="flex items-center gap-2">
            <div className="relative aspect-square h-[32px]">
              <Image
                src={"/question.svg"}
                alt="question"
                fill
                className="object-contain"
              />
            </div>
            <p>Explore All Quests</p>
          </div>
          <ChevronRight className="aspect-square h-[18px] text-[#FFFFFF]/40" />
        </a>
      </div>
    </div>
  );
};

export default Quests;
