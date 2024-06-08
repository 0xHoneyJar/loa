"use client";

import Image from "next/image";
import { usePathname } from "next/navigation";
import Link from "next/link";
import { useState } from "react";
import { motion } from "framer-motion";
import Sidebar from "./sidebar";
import AudioPlayer from "./audio/audio-player";
import { TRACKS } from "@/constants/tracks";

const Navbar = () => {
  const pathname = usePathname();
  const moveRight = {
    hidden: {
      x: 0,
    },
    show: {
      x: 3,
      transition: {
        type: "tween",
        duration: 0.1,
        ease: "easeOut",
      },
    },
  };

  const [toggle, setToggle] = useState(false);

  return (
    <>
      <Sidebar open={toggle} setOpen={setToggle} />
      <div
        className={`z-30 w-full fixed top-0 md:h-24 h-16 border-b border-[#C8C8C842] bg-[#5050500D] backdrop-blur-xl max-w-[112rem]`}
      >
        <div className="h-full w-full flex justify-between items-center md:px-20 px-10">
          <div className="flex items-center md:gap-3 gap-2">
            <Link
              className="relative md:h-[40px] h-[30px] aspect-square"
              href="/"
            >
              <Image src={"/thj-logo.png"} alt="logo" fill />
            </Link>
            <p className="text-white md:text-base text-sm whitespace-nowrap">
              For Community
            </p>
          </div>
          <div className="flex items-center md:gap-4 gap-2">
            <AudioPlayer tracks={TRACKS} />
            <a className="md:px-8 px-4 py-3 bg-[#FFFFFF26] rounded-full text-white cursor-pointer md:text-sm text-sm whitespace-nowrap font-medium">
              Join Us
            </a>
            <a className="md:px-8 px-4 py-3 bg-[#43AA77] rounded-full text-white cursor-pointer md:text-sm text-sm whitespace-nowrap font-medium hover:shadow-evergreen">
              Delegate to THJ
            </a>
            <button
              className="md:hidden flex flex-col gap-2"
              onClick={() => setToggle(!toggle)}
            >
              <hr className="w-6 border" />
              <hr className="w-6 border" />
              <hr className="w-6 border" />
            </button>
          </div>
        </div>
      </div>
    </>
  );
};

export default Navbar;
