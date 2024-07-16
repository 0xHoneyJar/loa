import { Quest } from "@/constants/quest";
import useSWR from "swr";
import fetcher from "@/lib/fetcher";
import S3Image from "./s3-image";
import Image from "next/image";
import { motion } from "framer-motion";
import { useState, useEffect } from "react";
import useUserStore from "@/state/user/useUserStore";
import { calculateTimeRemaining, convertUnixToLocalTime } from "@/lib/utils";
import { ArrowUpRight } from "lucide-react";

const QuestDisplay = ({ quest }: { quest: Quest }) => {
  const { data: questData, error } = useSWR<{
    numParticipants: number;
  }>(`/api/quests?${new URLSearchParams({ questName: quest.title })}`, fetcher);

  const [timeRemaining, setTimeRemaining] = useState("");
  const [width, setWidth] = useState(0);
  const currentTime = useUserStore((state) => state.currentTime);
  const [newQuest, setNewQuest] = useState(true);
  const [hover, setHover] = useState(false);

  const upcomingQuest = quest.startTime - currentTime > 0;
  const endedQuest = quest.endTime - currentTime < 0;

  const calculateWidth = (
    startTime: number,
    endTime: number,
    currentTime: number,
  ) => {
    // Calculate total duration and elapsed time
    const totalDuration = endTime - startTime;
    const elapsedTime = currentTime - startTime;

    // Calculate percentage completed
    const completedPercentage = (elapsedTime / totalDuration) * 100;

    if (completedPercentage > 10) {
      setNewQuest(false);
    }

    return completedPercentage;
  };

  useEffect(() => {
    const endTimeRemaining = calculateTimeRemaining(quest.endTime, currentTime);

    if (upcomingQuest) {
      setTimeRemaining("Coming Soon");
    } else if (quest.endTime - currentTime > 0) {
      if (endTimeRemaining == "") setTimeRemaining("Ends Soon");
      else setTimeRemaining("Ending in " + endTimeRemaining);
    }

    setWidth(calculateWidth(quest.startTime, quest.endTime, currentTime));
  }, [currentTime]);

  return (
    <div className="h-[250px] w-full">
      <div
        onMouseEnter={() => !upcomingQuest && !endedQuest && setHover(true)}
        onMouseLeave={() => !upcomingQuest && !endedQuest && setHover(false)}
        className={`relative flex h-[85%] w-full flex-col justify-between overflow-hidden rounded-lg border border-[#3A3A3A] px-2 py-4`}
      >
        {hover && (
          <div className="absolute left-0 top-0 z-10 flex h-full w-full cursor-blue items-center justify-center bg-black/75">
            <a
              href={`https://faucet.0xhoneyjar.xyz/quests/${quest.slug}`}
              target="_blank"
              className="cursor-blue rounded-full bg-white/25 px-4 py-2 backdrop-blur-md"
            >
              <div className="flex items-center gap-1 font-medium">
                Join Now <ArrowUpRight size={20} />
              </div>
            </a>
            <div className="absolute bottom-0 h-1/2 w-full bg-gradient-to-t from-black" />
          </div>
        )}
        <S3Image
          src={quest.image}
          width={1000}
          fill
          alt="Quest Background"
          className="z-[-1] object-cover"
        />
        {upcomingQuest ? (
          <div className="flex h-full w-full flex-col items-center justify-center">
            <p className="text-2xl font-medium">{timeRemaining}</p>
            <p className="text-[#E0E0E0]">
              {convertUnixToLocalTime(quest.startTime)}
            </p>
          </div>
        ) : (
          <>
            <div className="flex items-center gap-2">
              {quest.reward.map((reward) => (
                <div className="relative aspect-square h-[45px]">
                  <S3Image
                    src={`/faucet/badges/${reward}.png`}
                    fill
                    width={128}
                    className="object-cover"
                    alt=""
                  />
                </div>
              ))}
              {newQuest && (
                <div className="flex w-fit items-center gap-2 rounded-full border border-[#F4C10B] bg-[#F4C10B]/10 px-2 py-1 backdrop-blur-sm">
                  <div className="relative aspect-square h-[12px] rounded-full bg-[#F4C10B]">
                    <div className="absolute aspect-square h-full w-full animate-ping rounded-full bg-[#F4C10B]" />
                  </div>
                  <p className="text-[10px] text-[#F4C10B]">NEW</p>
                </div>
              )}
            </div>
            <div className="flex h-[40px] w-full gap-3">
              <div className="h-full w-full rounded-full border border-[#737373]/60 bg-[#D8D8D8]/20 p-1 backdrop-blur-sm">
                <div className="relative flex h-full w-full items-center overflow-hidden rounded-full bg-[#75643C]">
                  <motion.div
                    className="h-full rounded-full bg-[#F8A929]"
                    initial={false}
                    animate={{ width: `${width}%` }}
                    // transition={{ duration: 0.5, ease: "linear" }}
                  />
                  <p className="absolute left-4 text-[10px]">{timeRemaining}</p>
                </div>
              </div>
              <div className="flex h-full w-fit items-center gap-1 rounded-full border border-[#747474]/60 bg-[#D8D8D8]/20 px-3 backdrop-blur-sm">
                <div className="relative aspect-square h-[18px]">
                  <Image
                    src={"/users.svg"}
                    alt=""
                    fill
                    className="object-contain"
                  />
                </div>
                <p>{questData?.numParticipants ?? 0}</p>
              </div>
            </div>
          </>
        )}
      </div>
      <div className="flex h-[15%] w-full items-center justify-between">
        <p className="whitespace-nowrap text-[#FBFBFB]">{quest.title}</p>
        <div className="flex items-center gap-2">
          <p className="whitespace-nowrap text-sm text-[#6B6B6B]">
            Partner with
          </p>
          <div className="flex items-center gap-1">
            {quest.logo?.map((logo, id) => (
              <div
                className="relative aspect-square h-[24px] overflow-hidden rounded-full"
                key={id}
              >
                <S3Image
                  src={`${logo}`}
                  fill
                  width={128}
                  className="object-contain"
                  alt=""
                />
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

export default QuestDisplay;
