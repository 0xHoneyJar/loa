"use client";

import Image from "next/image";
import { Socials, We } from "@/constants/hero";
import Marquee from "react-fast-marquee";
import { motion } from "framer-motion";
import { useEffect, useRef, useMemo } from "react";
import { ArrowDown } from "lucide-react";
import Lottie from "lottie-react";
import HeroBg from "@/public/hero-bg.json";
import OctoBear from "@/public/octo-bear.json";
import { trackEvent } from "@openpanel/nextjs";

const HeroSection = () => {
  const scrollRef = useRef<HTMLDivElement>(null);
  const lottieRef = useRef(null);

  const heroBgOptions = useMemo(
    () => ({
      animationData: HeroBg,
      loop: true,
      rendererSettings: {
        preserveAspectRatio: "xMidYMid slice",
      },
    }),
    [],
  );

  const octoBearOptions = useMemo(
    () => ({
      animationData: OctoBear,
      loop: true,
      lottieRef: lottieRef,
      rendererSettings: {
        preserveAspectRatio: "xMidYMid slice",
      },
    }),
    [],
  );

  useEffect(() => {
    const handleResize = () => {
      if (window.innerWidth <= 768) {
        (lottieRef.current as any)?.pause();
      } else {
        (lottieRef.current as any)?.play();
      }
    };

    window.addEventListener("resize", handleResize);
    handleResize();

    return () => {
      window.removeEventListener("resize", handleResize);
    };
  }, []);

  return (
    <div className="relative flex size-full flex-col items-center">
      <div className="relative flex size-full flex-col items-center pt-[65px] md:pt-24">
        <Image
          src={"/sunshine.png"}
          alt="sunshine"
          fill
          className="z-0 object-cover opacity-20"
        />
        <div className="absolute top-0 h-[65px] w-full md:h-24 md:opacity-30">
          <Image
            src={"/navbar-hero.png"}
            alt="bg"
            fill
            className="z-[-1] object-cover"
          />
        </div>
        <div className="relative flex h-[calc(100vh-64px)] w-full flex-col items-center gap-10 pb-10 pt-6 md:h-[calc(100vh-96px)]">
          <div className="absolute bottom-0 h-2/5 w-full bg-gradient-to-t from-[#0A0601]" />
          <div className="absolute bottom-40 z-[-2] h-[100px] w-1/3 bg-[#F5D011] blur-[250px]" />
          <Lottie
            {...heroBgOptions}
            className="absolute top-0 z-[-1] size-full"
          />
          <div className="flex w-full flex-col justify-center gap-2 px-4 text-white sm:px-6 md:gap-4 md:px-10 2xl:flex-row 2xl:gap-16">
            <div className="whitespace-nowrap font-clash text-2xl font-medium sm:text-3xl md:text-4xl lg:text-5xl">
              <span className="text-xl font-normal md:text-2xl">The</span>{" "}
              <br />
              <span className="text-[#F4C10B]">Honey Jar</span> Based Community{" "}
              <br />
              <span className="flex items-end gap-4">
                Gateway on Berachain
                <div className="relative aspect-[1.7/1] h-[30px] sm:h-[38px] md:h-[44px]">
                  <Image src={"/berachain.svg"} alt="berachain" fill />
                </div>
              </span>
            </div>
            <div className="mt-0 flex w-[90%] flex-col justify-end gap-5 sm:w-4/5 lg:w-3/4 xl:w-3/5 2xl:mt-12 2xl:w-2/5">
              <p className="text-sm text-white/90 sm:text-base md:text-lg">
                THJ is Berachain-native community venture studio. We&apos;re the
                creators of Honeycomb, a perks aggregator for Bera eco projects.
              </p>
              <div className="flex w-full gap-1 sm:gap-3 lg:gap-5">
                <div className="h-fit rounded-xl border border-dashed border-[#FFFFFF3B] p-1 lg:p-2">
                  <div className="flex gap-1.5 md:gap-3">
                    {Socials.map((social, id) => (
                      <a
                        target="_blank"
                        href={social.link}
                        onClick={() => {
                          trackEvent(`follow_us_${social.name}_hero`);
                        }}
                        className="z-10 flex cursor-blue items-center gap-2 rounded-sm border border-[#FFFFFF1F] bg-[#FFFFFF26] px-4 py-2 backdrop-blur-sm hover:bg-[#FFFFFF3D] lg:px-6 lg:py-3"
                        key={id}
                      >
                        <div className="relative aspect-square h-[18px] md:h-[24px]">
                          <Image src={social.image} alt={social.name} fill />
                        </div>
                        <p className="hidden text-xs sm:flex md:text-sm">
                          {social.name}
                        </p>
                      </a>
                    ))}
                  </div>
                </div>
                <div className="flex items-end">
                  <div className="relative -right-2 -top-2 aspect-square h-[44px] scale-x-125 scale-y-110 md:h-[55px]">
                    <Image src={"/arrow-swirl.svg"} alt="arrow" fill />
                  </div>
                  <p className="whitespace-nowrap text-xs text-[#FFFFFFA8] md:text-sm">
                    Follow us{" "}
                    <span className="hidden md:inline-flex">for more</span>
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
        <div className="z-10 flex h-[92px] w-full items-center justify-center bg-[#0a0500]">
          <Marquee
            autoFill
            gradient
            gradientColor="#0A0A0A"
            gradientWidth={50}
            className="h-[88px] !w-[90%]"
          >
            <div className="flex bg-[#0A0601] py-2">
              {We.map((item, id) => (
                <div
                  className="mx-2 flex w-[200px] items-center gap-4 rounded-xl border border-[#F4C10B05] bg-[#F4C10B0A] p-4 text-white md:w-[260px]"
                  key={id}
                >
                  <div className="relative aspect-square h-[24px] md:h-[28px]">
                    <Image src={item.icon} alt="" fill />
                  </div>
                  <p className="text-xs font-light md:text-sm">{item.title}</p>
                </div>
              ))}
            </div>
          </Marquee>
        </div>

        <div className="mb-10 h-[1px] w-1/2 bg-gradient-to-r from-[#F5D01100] via-[#F5D011] via-50% md:w-1/4" />
        <div className="relative z-10 -mb-10 hidden aspect-square h-[38px] rounded-full bg-white shadow-white md:flex md:h-[46px]">
          <motion.button
            className="relative size-full"
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
            <ArrowDown className="size-full p-2 text-black" strokeWidth={1} />
          </motion.button>
        </div>
        <div className="relative mb-6 mt-10 hidden h-[400px] w-full items-center justify-center md:mt-20 md:flex md:h-[600px]">
          <Lottie
            {...octoBearOptions}
            className="absolute top-0 z-10 size-full scale-110 md:scale-100"
          />
          <div className="relative flex h-4/5 w-full">
            <Image src={"/dots.png"} alt="dots" fill className="object-cover" />
          </div>
          <div className="absolute -bottom-40 h-1/2 w-2/5 bg-[#F8A9291F] blur-[100px]" />
        </div>
      </div>
      {/* <div className="relative -mt-10 hidden flex-col items-center text-white md:flex">
        <div className="absolute -top-32 size-1" ref={scrollRef} />
        <motion.div
          className="relative mb-4 hidden aspect-square h-[32px] md:flex md:h-[40px]"
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
        <p className="mb-2 text-2xl font-medium md:text-4xl">
          Customize the THJ Board
        </p>
        <p className="text-lg text-[#FFFFFFB3] md:text-xl">
          Manage & Customize your THJ Board
        </p>
      </div> */}
    </div>
  );
};

export default HeroSection;
