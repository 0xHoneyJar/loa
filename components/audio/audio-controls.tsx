import Image from "next/image";
import React from "react";

const AudioControls = ({
  isPlaying,
  onPlayPauseClick,
  onPrevClick,
  onNextClick,
}: {
  isPlaying: boolean;
  onPlayPauseClick: React.Dispatch<React.SetStateAction<boolean>>;
  onPrevClick: () => void;
  onNextClick: () => void;
}) => (
  <div className="flex grow items-center justify-center gap-4 rounded-r-full border-y border-r border-[#A6A6A647] bg-[#AFAFAF1F] px-3 backdrop-blur-2xl">
    <button
      type="button"
      className="relative aspect-square h-[16px] opacity-30 duration-300 hover:opacity-100"
      aria-label="Previous"
      onClick={onPrevClick}
    >
      <Image
        src={"/audio/prev.svg"}
        alt="prev"
        fill
        className="object-contain"
      />
    </button>
    {isPlaying ? (
      <button
        type="button"
        className="relative aspect-square h-[20px] opacity-30 duration-300 hover:opacity-100"
        onClick={() => onPlayPauseClick(false)}
        aria-label="Pause"
      >
        <Image
          src={"/audio/pause.svg"}
          alt="play"
          fill
          className="object-contain"
        />
      </button>
    ) : (
      <button
        type="button"
        className="relative aspect-square h-[20px] opacity-30 duration-300 hover:opacity-100"
        onClick={() => onPlayPauseClick(true)}
        aria-label="Play"
      >
        <Image
          src={"/audio/play.svg"}
          alt="play"
          fill
          className="object-contain"
        />
      </button>
    )}
    <button
      type="button"
      className="relative aspect-square h-[16px] opacity-30 duration-300 hover:opacity-100"
      aria-label="Next"
      onClick={onNextClick}
    >
      <Image
        src={"/audio/next.svg"}
        alt="next"
        fill
        className="object-contain"
      />
    </button>
  </div>
);

export default AudioControls;
