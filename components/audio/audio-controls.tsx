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
  <div className="flex gap-4 px-3 items-center justify-center rounded-r-full border-r border-y bg-[#AFAFAF1F] border-[#A6A6A647] flex-grow backdrop-blur-2xl">
    <button
      type="button"
      className="aspect-square h-[16px] relative cursor-blue opacity-30 hover:opacity-100 duration-300"
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
        className="aspect-square h-[20px] relative cursor-blue opacity-30 hover:opacity-100 duration-300"
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
        className="aspect-square h-[20px] relative cursor-blue opacity-30 hover:opacity-100 duration-300"
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
      className="aspect-square h-[16px] relative cursor-blue opacity-30 hover:opacity-100 duration-300"
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
