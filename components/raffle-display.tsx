import useSWR from "swr";
import fetcher from "@/lib/fetcher";
import S3Image from "./s3-image";
import Image from "next/image";
import { motion } from "framer-motion";
import { useState, useEffect } from "react";
import useUserStore from "@/state/user/useUserStore";
import { calculateTimeRemaining, convertUnixToLocalTime } from "@/lib/utils";
import { Raffle } from "@/constants/raffle";
import { ArrowUpRight } from "lucide-react";

const RaffleDisplay = ({ raffle }: { raffle: Raffle }) => {
  const { data: raffleData } = useSWR<{
    numEntries: number;
  }>(
    `/api/raffles?${new URLSearchParams({ raffleName: raffle.title })}`,
    fetcher,
  );

  const [timeRemaining, setTimeRemaining] = useState("");
  const [width, setWidth] = useState(0);
  const currentTime = useUserStore((state) => state.currentTime);
  const [newRaffle, setNewRaffle] = useState(true);
  const [hover, setHover] = useState(false);

  const upcomingRaffle = raffle.startTime - currentTime > 0;
  const endedRaffle = raffle.endTime - currentTime < 0;

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
      setNewRaffle(false);
    }

    return completedPercentage;
  };

  useEffect(() => {
    const endTimeRemaining = calculateTimeRemaining(
      raffle.endTime,
      currentTime,
    );

    if (endedRaffle) {
      setTimeRemaining("Ended on " + convertUnixToLocalTime(raffle.endTime));
    } else if (upcomingRaffle) {
      setTimeRemaining("Coming Soon");
    } else if (raffle.endTime - currentTime > 0) {
      if (endTimeRemaining == "") setTimeRemaining("Ends Soon");
      else setTimeRemaining("Ending in " + endTimeRemaining);
    }

    setWidth(calculateWidth(raffle.startTime, raffle.endTime, currentTime));
  }, [currentTime]);

  return (
    <div className="h-[210px] w-full overflow-hidden sm:h-[230px] md:h-[240px] xl:h-[250px]">
      <div
        onMouseEnter={() => !upcomingRaffle && !endedRaffle && setHover(true)}
        onMouseLeave={() => !upcomingRaffle && !endedRaffle && setHover(false)}
        className={`${endedRaffle && "bg-gradient-to-t from-black to-black/40"} relative flex h-[85%] w-full flex-col justify-between overflow-hidden rounded-lg border border-[#3A3A3A] px-2 py-4`}
      >
        <div
          className={`absolute bottom-0 left-0 h-1/2 w-full bg-gradient-to-t from-black ${endedRaffle && "hidden"}`}
        />
        {hover && (
          <div className="absolute left-0 top-0 z-10 flex size-full cursor-blue items-center justify-center bg-black/75">
            <a
              href={`https://faucet.0xhoneyjar.xyz/raffles`}
              target="_blank"
              className="cursor-blue rounded-full bg-white/25 px-4 py-2 backdrop-blur-md hover:bg-white/50"
            >
              <div className="flex items-center gap-1 text-xs font-medium md:text-sm">
                Join Now <ArrowUpRight size={20} />
              </div>
            </a>
          </div>
        )}
        <S3Image
          src={raffle.image}
          width={1000}
          fill
          alt="Quest Background"
          className="object-cover opacity-70"
        />

        {upcomingRaffle ? (
          <div className="flex size-full flex-col items-center justify-center">
            <p className="text-lg font-medium md:text-xl">{timeRemaining}</p>
            <p className="text-xs text-[#E0E0E0] md:text-sm">
              {convertUnixToLocalTime(raffle.startTime)}
            </p>
          </div>
        ) : (
          <>
            <div className="z-0 flex items-center gap-3">
              {newRaffle && (
                <div className="flex w-fit items-center gap-2 rounded-lg border border-[#F4C10B] bg-[#F4C10B]/10 px-2 py-1 backdrop-blur-sm">
                  <div className="relative aspect-square h-[12px] rounded-lg bg-[#F4C10B]">
                    <div className="absolute aspect-square size-full animate-ping rounded-lg bg-[#F4C10B]" />
                  </div>
                  <p className="text-[10px] text-[#F4C10B]">NEW</p>
                </div>
              )}
            </div>
            <div className="flex w-full flex-col-reverse gap-2 xl:h-[40px] xl:flex-row xl:gap-3">
              <div className="h-8 w-full rounded-lg border border-[#737373]/60 bg-[#D8D8D8]/20 p-1 backdrop-blur-sm xl:h-full">
                <div className="relative flex h-full w-full items-center overflow-hidden rounded-lg bg-[#75643C]">
                  <motion.div
                    className={`h-full rounded-lg ${endedRaffle ? "bg-[#444444]" : "bg-[#F8A929]"}`}
                    initial={false}
                    animate={{ width: `${width}%` }}
                    // transition={{ duration: 0.5, ease: "linear" }}
                  />
                  <p className="absolute left-3 text-[10px]">{timeRemaining}</p>
                </div>
              </div>
              <div className="flex h-8 w-fit items-center gap-1 rounded-lg border border-[#747474]/60 bg-[#D8D8D8]/20 px-2 backdrop-blur-sm xl:h-full">
                <div className="relative aspect-square h-4">
                  <Image
                    src={"/users.svg"}
                    alt=""
                    fill
                    className="object-contain"
                  />
                </div>
                <p className="text-xs">{raffleData?.numEntries ?? 0}</p>
              </div>
            </div>
          </>
        )}
      </div>
      <div className="flex h-[15%] w-full items-center justify-between">
        <p className="truncate whitespace-nowrap text-xs text-[#FBFBFB] md:text-sm">
          {raffle.title}
        </p>
        <div className="flex items-center gap-2">
          <p className="hidden whitespace-nowrap text-xs text-[#6B6B6B] xl:block">
            In partnership with
          </p>
          <div className="flex items-center gap-1">
            <div className="relative aspect-square h-5 overflow-hidden rounded-full">
              <S3Image
                src={`${raffle.logo}`}
                fill
                width={128}
                className="object-contain"
                alt=""
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default RaffleDisplay;
