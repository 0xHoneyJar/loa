import React, { useState, useEffect, useRef } from "react";
import AudioControls from "./audio-controls";
import Image from "next/image";
import { convertSecondsToMinutes } from "@/lib/utils";

const AudioPlayer = ({ tracks }: { tracks: any }) => {
  // State
  const [trackIndex, setTrackIndex] = useState(0);
  const [trackProgress, setTrackProgress] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);

  // Destructure for conciseness
  const { title, artist, image, audioSrc } = tracks[trackIndex];

  // Refs
  const [audio] = useState<HTMLAudioElement | null>(typeof Audio !== 'undefined' ? new Audio(audioSrc) : null)
  const audioRef = useRef(audio);
  const intervalRef = useRef();
  const isReady = useRef(false);

  // Destructure for conciseness
  // const { duration } = audioRef.current;
  const duration = audioRef.current?.duration ?? 0;

  const startTimer = () => {
    // Clear any timers already running
    clearInterval(intervalRef.current);

    (intervalRef.current as any) = setInterval(() => {
      if (audioRef.current?.ended) {
        toNextTrack();
      } else {
        // setTrackProgress(audioRef.current?.currentTime);
        setTrackProgress(audioRef.current?.currentTime ?? 0);
      }
    }, 1000); // Corrected the interval argument to be a number (milliseconds)
  };

  const onScrub = (value: any) => {
    // Clear any timers already running
    clearInterval(intervalRef.current);
    audioRef.current ? audioRef.current.currentTime = value : null;
    setTrackProgress(audioRef.current?.currentTime ?? 0);
    // audioRef.current?.currentTime = value;
    // setTrackProgress(audioRef.current.currentTime);
  };

  const onScrubEnd = () => {
    // If not already playing, start
    if (!isPlaying) {
      setIsPlaying(true);
    }
    startTimer();
  };

  const toPrevTrack = () => {
    if (trackIndex - 1 < 0) {
      setTrackIndex(tracks.length - 1);
    } else {
      setTrackIndex(trackIndex - 1);
    }
  };

  const toNextTrack = () => {
    if (trackIndex < tracks.length - 1) {
      setTrackIndex(trackIndex + 1);
    } else {
      setTrackIndex(0);
    }
  };

  useEffect(() => {
    if (isPlaying) {
      audioRef.current?.play();
      startTimer();
    } else {
      audioRef.current?.pause();
    }
  }, [isPlaying]);

  // Handles cleanup and setup when changing tracks
  useEffect(() => {
    audioRef.current?.pause();

    audioRef.current = new Audio(audioSrc);
    setTrackProgress(audioRef.current.currentTime);

    if (isReady.current) {
      audioRef.current.play();
      audioRef.current.volume = 0.1;
      setIsPlaying(true);
      startTimer();
    } else {
      // Set the isReady ref as true for the next pass
      isReady.current = true;
    }
  }, [trackIndex]);

  useEffect(() => {
    setIsPlaying(false);
    // Pause and clean up on unmount
    return () => {
      audioRef.current?.pause();
      clearInterval(intervalRef.current);
    };
  }, []);

  return (
    <div className="flex absolute inset-x-0 mx-auto w-fit">
      <div className="flex bg-[#AFAFAF1F] border border-[#A6A6A647] rounded-l-full p-2 items-center backdrop-blur-2xl">
        <div className="flex items-center">
          <div className="aspect-square h-[40px] relative border border-[#2C2C2C] rounded-full mr-3">
            <Image
              src={image}
              alt={`track artwork for ${title} by ${artist}`}
              fill
              className="object-cover"
            />
          </div>
          <div className="flex flex-col">
            <p className="text-white font-medium text-sm mb-1">
              {title.toUpperCase()}&nbsp;&nbsp;
              <span className="font-light text-[#FFFFFF4D]">by {artist}</span>
            </p>
            <div className="flex items-center gap-2 text-[#F5DA7F42] text-xs">
              <p className="text-[#F5DA7F]">
                {convertSecondsToMinutes(trackProgress)}
              </p>
              {/* <div className="h-1 w-28 bg-[#F5DA7F1F] rounded-full" /> */}
              <input
                type="range"
                value={trackProgress}
                step="1"
                min="0"
                max={duration ? duration : `${duration}`}
                onChange={(e) => onScrub(e.target.value)}
                onMouseUp={onScrubEnd}
                onKeyUp={onScrubEnd}
                className="cursor-blue appearance-none overflow-hidden [&::-webkit-slider-runnable-track]:rounded-full [&::-webkit-slider-runnable-track]:bg-[#F5DA7F1F] bg-[#171717] rounded-full"
              />
              <p className="text-[#F5DA7F]">
                -{convertSecondsToMinutes(duration - trackProgress)}
              </p>
            </div>
          </div>
        </div>
      </div>
      <AudioControls
        isPlaying={isPlaying}
        onPrevClick={toPrevTrack}
        onNextClick={toNextTrack}
        onPlayPauseClick={setIsPlaying}
      />
    </div>
  );
};

export default AudioPlayer;
