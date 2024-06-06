"use client";

import Image from "next/image";
import { Socials, We } from "@/constants/hero";
import Marquee from "react-fast-marquee";
import { motion } from "framer-motion";
import { useRef } from "react";

const HeroSection = () => {
  const scrollRef = useRef<HTMLDivElement>(null);
  return (
    <div className="h-full w-full px-20 flex items-center flex-col">
      <div className="relative flex h-screen w-full pt-6 pb-10 flex-col gap-10">
        {/* <div className="h-1/3 w-full flex items-center flex-col"> */}
        <div className="w-full flex text-white gap-10">
          <div className="w-1/2">
            <div className="font-medium text-5xl whitespace-nowrap">
              <span className="font-normal text-3xl">The</span> <br />
              <span className="text-[#F4C10B]">Honey Jar</span> Based Community{" "}
              <br />
              <span className="flex gap-4 items-end">
                Gateway on Berachain
                <div className="relative aspect-[1.7/1] h-[44px]">
                  <Image src={"/berachain.svg"} alt="berachain" fill />
                </div>
              </span>
            </div>
          </div>
          <div className="w-1/2 flex flex-col gap-5 justify-end mt-12">
            <p>
              THJ is Berachain-native community venture studio. We're the
              creators of Honeycomb, a perks aggregator for Bera eco projects.
            </p>
            <div className="w-full flex gap-5">
              <div className="border border-dashed border-[#FFFFFF3B] p-2 rounded-xl">
                <div className="flex gap-3">
                  {Socials.map((social, id) => (
                    <a
                      className="px-6 py-3 rounded-xl bg-[#FFFFFF14] flex items-center gap-2 cursor-pointer z-10"
                      key={id}
                    >
                      <div className="relative aspect-square h-[24px]">
                        <Image src={social.image} alt={social.name} fill />
                      </div>
                      <p className="md:text-sm text-xs">{social.name}</p>
                    </a>
                  ))}
                </div>
              </div>
              <div className="w-1/5 flex items-end">
                <div className="relative aspect-square h-[55px] -top-2 scale-x-125 -right-2 scale-y-110">
                  <Image src={"/arrow-swirl.svg"} alt="arrow" fill />
                </div>
                <p className="whitespace-nowrap md:text-sm text-xs text-[#48B17DA8]">
                  Follow us for more
                </p>
              </div>
            </div>
          </div>
        </div>
        {/* </div> */}
        <div className="h-2/3 w-full bg-[#FFFFFF05] border border-[#302A19] rounded-lg relative p-3">
          {/* <div className="w-[190px] aspect-[1/1.3] mx-auto inset-x-0 absolute -top-10 left-[28rem]">
            <Image src={"/smoke.svg"} alt="smoke" fill />
          </div> */}
          <div className="h-4 aspect-square border-[#F8A929] border-l border-t absolute top-0 left-0 rounded-tl-lg" />
          <div className="h-4 aspect-square border-[#F8A929] border-r border-t absolute top-0 right-0 rounded-tr-lg" />
          <div className="h-4 aspect-square border-[#F8A929] border-r border-b absolute bottom-0 right-0 rounded-br-lg" />
          <div className="h-4 aspect-square border-[#F8A929] border-l border-b absolute bottom-0 left-0 rounded-bl-lg" />
          <div className="h-full w-full relative rounded-lg overflow-hidden">
            <Image
              src={"/hero-bg.png"}
              alt="bg"
              fill
              className="object-cover"
            />
          </div>
        </div>
      </div>
      <Marquee
        autoFill
        // speed={50}
        gradient
        gradientColor="#0E0D09"
        gradientWidth={50}
        className="mb-10"
      >
        <div className="flex py-2 border-y border-[#151515] bg-[#0C0C0C]">
          {We.map((item, id) => (
            <div
              className="flex gap-4 items-center text-white mx-2 bg-[#F4C10B0A] border border-[#F4C10B05] rounded-xl p-4 w-[260px]"
              key={id}
            >
              <div className="relative md:h-[28px] h-[24px] aspect-square">
                <Image
                  src={item.icon}
                  alt=""
                  // height={64}
                  // width={64}
                  fill
                />
              </div>
              <p className="md:text-sm text-xs font-light">
                <span className="font-medium">We</span> {item.title}
              </p>
            </div>
          ))}
        </div>
      </Marquee>
      <div className="aspect-square h-[75px] relative -mb-10 z-10">
        <Image
          src={"/arrow-down-container.svg"}
          alt="arrow-down-container"
          fill
          className="object-contain"
        />
        <motion.button
          className="h-full w-full relative"
          animate={{
            y: [-2, 6, -2],
          }}
          transition={{
            duration: 1.5,
            repeat: Infinity,
            repeatType: "loop",
          }}
          onClick={() => {
            if (scrollRef.current) {
              scrollRef.current.scrollIntoView({
                behavior: "smooth",
              });
            }
          }}
        >
          <Image
            src={"/arrow-down.svg"}
            alt="arrow-down"
            fill
            className="object-contain p-5"
          />
        </motion.button>
      </div>
      <div
        className="h-[600px] w-full relative flex justify-center overflow-hidden"
        ref={scrollRef}
      >
        <div className="h-full w-2/5 absolute -left-6">
          <Image
            src={"/octo.png"}
            alt="octo"
            fill
            className="object-contain z-10"
          />
        </div>
        <div className="h-full w-2/5 absolute -right-10">
          <Image
            src={"/bear-hands.png"}
            alt="bear"
            fill
            className="object-contain z-10"
          />
        </div>
        <div className="h-[80%] w-full absolute bottom-0 flex justify-center">
          <Image src={"/dots.png"} alt="dots" fill className="object-cover" />
          <div className="h-full aspect-square rounded-full border border-[#DADADA1F] relative p-5 -top-4">
            <div className="h-full w-full rounded-full border border-[#DADADA59] relative">
              <Image
                src={"/control-thj.png"}
                alt="control"
                fill
                className="object-contain scale-110"
              />
            </div>
          </div>
        </div>
        <div className="h-1/2 w-2/5 bg-[#F8A9291F] blur-[100px] absolute -bottom-40"></div>
        <div className="h-1/2 w-full bg-gradient-to-t from-[#0A0A0A] absolute -bottom-10" />
      </div>
    </div>
  );
};

export default HeroSection;
