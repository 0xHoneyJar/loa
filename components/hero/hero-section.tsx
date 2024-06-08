"use client";

import Image from "next/image";
import { Socials, We } from "@/constants/hero";
import Marquee from "react-fast-marquee";
import { motion } from "framer-motion";
import { useRef } from "react";

const HeroSection = () => {
  const scrollRef = useRef<HTMLDivElement>(null);
  return (
    <div className="h-full w-full flex items-center flex-col pt-24 relative">
      <div className="md:h-24 h-16 w-full absolute top-0">
        <Image
          src={"/navbar-hero.png"}
          alt="bg"
          fill
          className="z-[-1] object-cover"
        />
      </div>
      <div className="relative flex h-[calc(100vh-6rem)] w-full pt-6 pb-10 flex-col gap-10">
        <div className="w-full h-2/5 absolute bottom-0 bg-gradient-to-t from-[#0A0601]" />
        <Image
          src={"/hero-bg.png"}
          alt="bg"
          fill
          className="object-cover z-[-1]"
        />
        {/* <div className="h-1/3 w-full flex items-center flex-col"> */}
        <div className="w-full flex text-white gap-16 justify-center">
          {/* <div className="w-1/2"> */}
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
          {/* </div> */}
          <div className="w-1/3 flex flex-col gap-5 justify-end mt-12">
            <p className="">
              THJ is Berachain-native community venture studio. We're the
              creators of Honeycomb, a perks aggregator for Bera eco projects.
            </p>
            <div className="w-full flex gap-5">
              <div className="border border-dashed border-[#FFFFFF3B] p-2 rounded-xl">
                <div className="flex gap-3">
                  {Socials.map((social, id) => (
                    <a
                      className="px-6 py-3 rounded-xl bg-[#FFFFFF26] flex items-center gap-2 cursor-blue z-10 hover:bg-[#FFFFFF3D] border border-[#FFFFFF1F]"
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
                <p className="whitespace-nowrap md:text-sm text-xs text-[#FFFFFFA8]">
                  Follow us for more
                </p>
              </div>
            </div>
          </div>
        </div>
        {/* </div> */}
      </div>
      <Marquee
        autoFill
        // speed={50}
        gradient
        gradientColor="#0A0A0A"
        gradientWidth={50}
        // className="mb-10 relative"
      >
        <div className="flex py-2 bg-[#0A0601]">
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
      <div className="h-[2px] w-1/4 bg-gradient-to-r from-[#F5D01100] via-[#F5D011] via-50% mb-10" />
      {/* <div className="h-[300px] w-1/2  bg-[#F5D011] absolute blur-[250px]" /> */}
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
      <div className="h-[600px] w-full relative flex justify-center overflow-hidden">
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
      <div
        className="flex flex-col text-white items-center mb-20"
        ref={scrollRef}
      >
        <motion.div
          className="h-[40px] aspect-square relative mb-4"
          animate={{
            x: [15, -5],
          }}
          transition={{
            duration: 2,
            repeat: Infinity,
            repeatType: "loop",
          }}
        >
          <Image
            src={"/hand-move.svg"}
            alt="hand"
            fill
            className="object-contain"
          />
        </motion.div>
        <p className="font-medium text-4xl mb-2">Control The THJ</p>
        <p className="text-[#FFFFFFB3] text-xl">
          Manage & Custom Your THJ Board
        </p>
      </div>
    </div>
  );
};

export default HeroSection;
