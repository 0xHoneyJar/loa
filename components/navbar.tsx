"use client";

import Image from "next/image";
import Link from "next/link";
import { useState } from "react";
import { TRACKS } from "@/constants/tracks";
import { ChevronDown } from "lucide-react";
import Sidebar from "@/components/sidebar";
import SectionSelect from "./section-select";
import AudioPlayer from "@/components/audio/audio-player";
import { EXPLOREITEMS } from "@/constants/explore";
import {
  NavigationMenu,
  NavigationMenuItem,
  NavigationMenuList,
} from "@/components/ui/navigation-menu";
import Explore from "./explore";

const Navbar = () => {
  const [toggle, setToggle] = useState(false);

  return (
    <>
      <Sidebar open={toggle} setOpen={setToggle} />
      {/* <div
        className={`z-30 w-full fixed top-0 md:h-24 h-20 border-b border-[#C8C8C842] bg-[#5050500D] backdrop-blur-xl max-w-[112rem]`}
      >
        <div className="h-full w-full flex justify-between items-center md:px-20 px-10 relative">
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
          <AudioPlayer tracks={TRACKS} />
          <div className="flex items-center md:gap-4 gap-2">
            <SectionSelect />
            <a className="md:px-6 px-4 py-3 bg-[#FFFFFF26] rounded-full text-white cursor-pointer md:text-sm text-xs whitespace-nowrap font-medium">
              Join Us
            </a>
            <a className="md:px-6 px-4 py-3 bg-[#43AA77] rounded-full text-white cursor-pointer md:text-sm text-xs whitespace-nowrap font-medium hover:shadow-evergreen">
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
      </div> */}
      <div
        className="fixed inset-x-0 top-5 z-30 mx-auto flex w-fit divide-x divide-[#FFFFFF1F] rounded-full border border-[#FFFFFF14] bg-[#7272721F] backdrop-blur-xl"
        // style={{ boxShadow: "0px 2px 56px #0000001F" }}
      >
        <div className="flex items-center gap-2 px-4 py-2 md:gap-3">
          <Link
            className="relative aspect-square h-[30px] cursor-blue"
            href="/"
          >
            <Image src={"/thj-logo.png"} alt="logo" fill />
          </Link>
          <p className="whitespace-nowrap text-[10px] text-white md:text-xs">
            For Community
          </p>
        </div>
        <div className="flex items-center px-4 py-2">
          {/* <div className=""> */}
          <NavigationMenu className="ml-8 items-center md:ml-16 lg:ml-28">
            <NavigationMenuList className="text-xs md:space-x-3 lg:text-sm">
              <Explore />
              <SectionSelect />
              <NavigationMenuItem>
                <a
                  href={"https://www.0xhoneyjar.xyz/"}
                  target="_blank"
                  className="hidden cursor-blue items-center whitespace-nowrap rounded-full bg-[#F4C10B]/80 px-6 py-2.5 font-medium text-white hover:shadow-yellow md:flex"
                >
                  Open App
                </a>
              </NavigationMenuItem>
              <NavigationMenuItem>
                <a
                  href={
                    "https://bartio.station.berachain.com/delegate?action=delegate&validator=0x40495A781095932e2FC8dccA69F5e358711Fdd41"
                  }
                  target="_blank"
                  className="hidden cursor-blue items-center whitespace-nowrap rounded-full bg-[#43AA77] px-6 py-2.5 font-medium text-white hover:shadow-evergreen md:flex"
                >
                  Delegate to THJ
                </a>
              </NavigationMenuItem>
            </NavigationMenuList>
          </NavigationMenu>
          {/* <button className="flex h-[36px] items-center gap-2 rounded-full border border-[#F4C10B]/50 bg-gradient-to-b from-[#F4C10B1F] to-[#F8A9291F] px-4 text-xs font-medium text-white md:px-6 md:text-sm">
              <p>Explore</p>
              <p className="rounded-full border bg-[#FFFFFF14] px-2 text-[7px]">
                NEW
              </p>
            </button>
            <SectionSelect />
            <a className="flex h-[36px] cursor-pointer items-center whitespace-nowrap rounded-full bg-[#FFFFFF0F] px-4 text-xs font-medium text-white md:px-6 md:text-sm">
              Join Us
            </a>
            <a className="flex h-[36px] cursor-pointer items-center whitespace-nowrap rounded-full bg-[#43AA77] px-4 text-xs font-medium text-white hover:shadow-evergreen md:px-6 md:text-sm">
              Delegate to THJ
            </a> */}
          {/* </div> */}
          <button
            className="flex flex-col gap-1.5 md:hidden"
            onClick={() => setToggle(!toggle)}
          >
            <hr className="w-6 border" />
            <hr className="w-6 border" />
            <hr className="w-6 border" />
          </button>
        </div>
      </div>
    </>
  );
};

export default Navbar;
