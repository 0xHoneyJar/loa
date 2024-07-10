"use client";

import Image from "next/image";
import { Socials, We } from "@/constants/hero";
import Marquee from "react-fast-marquee";
import { motion } from "framer-motion";
import { useRef } from "react";
import { ArrowDown } from "lucide-react";
import Lottie from "lottie-react";
import HeroBg from "@/public/hero-bg.json";

const HeroSection = () => {
  const scrollRef = useRef<HTMLDivElement>(null);
  return (
    <div className="relative flex h-full w-full flex-col items-center">
      <div className="relative flex h-full w-full flex-col items-center md:pt-24 pt-20">
        <Image
          src={"/sunshine.png"}
          alt="sunshine"
          fill
          className="z-10 object-cover opacity-20"
        />
        <div className="absolute top-0 h-16 w-full md:h-24">
          <Image
            src={"/navbar-hero.png"}
            alt="bg"
            fill
            className="z-[-1] object-cover"
          />
        </div>
        <div className="h-[calc(100vh-5rem)] md:h-[calc(100vh-6rem)] relative flex w-full flex-col items-center gap-10 pb-10 pt-6">
          <div className="absolute bottom-0 h-2/5 w-full bg-gradient-to-t from-[#0A0601]" />
          <div className="absolute bottom-40 z-[-2] h-[100px] w-1/3 bg-[#F5D011] blur-[250px]" />
          {/* <Image
            src={"/hero-bg.png"}
            alt="bg"
            fill
            className="z-[-1] object-cover"
          /> */}
          <Lottie
            animationData={HeroBg}
            className="absolute top-0 z-[-1] w-full h-full"
            loop={true}
            rendererSettings={{
              preserveAspectRatio: "xMidYMid slice",
            }}
          />
          {/* <div className="h-1/3 w-full flex items-center flex-col"> */}
          <div className="flex w-full justify-center gap-16 text-white">
            {/* <div className="w-1/2"> */}
            <div className="whitespace-nowrap font-clash text-5xl font-medium">
              <span className="text-3xl font-normal">The</span> <br />
              <span className="text-[#F4C10B]">Honey Jar</span> Based Community{" "}
              <br />
              <span className="flex items-end gap-4">
                Gateway on Berachain
                <div className="relative aspect-[1.7/1] h-[44px]">
                  <Image src={"/berachain.svg"} alt="berachain" fill />
                </div>
              </span>
            </div>
            {/* </div> */}
            <div className="mt-12 flex w-1/3 flex-col justify-end gap-5">
              <p className="text-xl">
                THJ is Berachain-native community venture studio. We&apos;re the
                creators of Honeycomb, a perks aggregator for Bera eco projects.
              </p>
              <div className="flex w-full gap-5">
                <div className="rounded-xl border border-dashed border-[#FFFFFF3B] p-2">
                  <div className="flex gap-3">
                    {Socials.map((social, id) => (
                      <a
                        className="z-10 flex cursor-blue items-center gap-2 rounded-xl border border-[#FFFFFF1F] bg-[#FFFFFF26] px-6 py-3 hover:bg-[#FFFFFF3D]"
                        key={id}
                      >
                        <div className="relative aspect-square h-[24px]">
                          <Image src={social.image} alt={social.name} fill />
                        </div>
                        <p className="text-xs md:text-sm">{social.name}</p>
                      </a>
                    ))}
                  </div>
                </div>
                <div className="flex w-1/5 items-end">
                  <div className="relative -right-2 -top-2 aspect-square h-[55px] scale-x-125 scale-y-110">
                    <Image src={"/arrow-swirl.svg"} alt="arrow" fill />
                  </div>
                  <p className="whitespace-nowrap text-xs text-[#FFFFFFA8] md:text-sm">
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
          className="!w-[90%]"
        >
          <div className="flex bg-[#0A0601] py-2">
            {We.map((item, id) => (
              <div
                className="mx-2 flex w-[260px] items-center gap-4 rounded-xl border border-[#F4C10B05] bg-[#F4C10B0A] p-4 text-white"
                key={id}
              >
                <div className="relative aspect-square h-[24px] md:h-[28px]">
                  <Image
                    src={item.icon}
                    alt=""
                    // height={64}
                    // width={64}
                    fill
                  />
                </div>
                <p className="text-xs font-light md:text-sm">{item.title}</p>
              </div>
            ))}
          </div>
        </Marquee>
        <div className="mb-10 h-[1px] w-1/4 bg-gradient-to-r from-[#F5D01100] via-[#F5D011] via-50%" />
        <div className="relative z-10 -mb-10 aspect-square h-[46px] rounded-full bg-white shadow-white">
          <motion.button
            className="relative h-full w-full"
            animate={{
              y: [-1, 4, -1],
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
            <ArrowDown
              className="h-full w-full p-2 text-black"
              strokeWidth={1}
            />
          </motion.button>
        </div>
        <div className="relative mb-6 flex h-[600px] w-full justify-center">
          <div className="absolute -left-6 top-10 h-full w-2/5">
            <Image
              src={"/octo.png"}
              alt="octo"
              fill
              className="z-10 object-contain"
            />
          </div>
          <div className="absolute -right-10 h-full w-2/5">
            <Image
              src={"/bear-hands.png"}
              alt="bear"
              fill
              className="z-10 object-contain"
            />
          </div>
          <div className="absolute bottom-0 flex h-[80%] w-full justify-center">
            <Image src={"/dots.png"} alt="dots" fill className="object-cover" />
            <div className="relative aspect-square h-full rounded-full border border-[#DADADA1F] p-5">
              <div className="relative h-full w-full rounded-full border border-[#DADADA59]">
                <Image
                  src={"/control-thj.png"}
                  alt="control"
                  fill
                  className="scale-110 object-contain"
                />
              </div>
            </div>
          </div>
          <div className="absolute -bottom-40 h-1/2 w-2/5 bg-[#F8A9291F] blur-[100px]" />
          {/* <div className="h-1/2 w-full bg-gradient-to-t from-[#0A0A0A] absolute -bottom-10" /> */}
        </div>
      </div>
      <div className="relative flex flex-col items-center text-white">
        <div className="absolute -top-32 h-1 w-1" ref={scrollRef} />
        <motion.div
          className="relative mb-4 aspect-square h-[40px]"
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
        <p className="mb-2 text-4xl font-medium">Customize the THJ Board</p>
        <p className="text-xl text-[#FFFFFFB3]">
          Manage & Customize your THJ Board
        </p>
      </div>
    </div>
  );
};

export default HeroSection;
