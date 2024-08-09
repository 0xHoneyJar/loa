"use client";

import Image from "next/image";
import Link from "next/link";
import { useState } from "react";
import Sidebar from "@/components/sidebar";
import SectionSelect from "./section-select";
import { AnimatePresence, motion } from "framer-motion";
import {
  NavigationMenu,
  NavigationMenuItem,
  NavigationMenuList,
} from "@/components/ui/navigation-menu";
import Explore from "./explore";
import { Menu, X } from "lucide-react";
import { trackEvent } from "@openpanel/nextjs";

const Navbar = () => {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  return (
    <>
      <Sidebar open={mobileMenuOpen} setOpen={setMobileMenuOpen} />
      <div
        className="fixed inset-x-0 top-0 z-30 mx-auto flex w-full justify-between border-b border-[#FFFFFF14] bg-[#7272721F] backdrop-blur-xl md:top-5 md:w-fit md:rounded-full md:border lg:gap-24"
        // style={{ boxShadow: "0px 2px 56px #0000001F" }}
      >
        <div className="flex items-center gap-2 border-r border-white/10 px-4 py-3 md:gap-3 md:py-2">
          <Link className="relative aspect-square h-10 cursor-blue" href="/">
            <Image src={"/thj-logo.png"} alt="logo" fill />
          </Link>
          <p className="hidden whitespace-nowrap text-[10px] text-white md:flex md:text-xs">
            For Community
          </p>
        </div>
        <div className="flex items-center px-4 py-2">
          {/* <div className=""> */}
          <NavigationMenu className="hidden items-center md:flex">
            <NavigationMenuList className="text-xs md:space-x-3">
              <Explore />
              <SectionSelect />
              <NavigationMenuItem>
                <a
                  href={"https://app.0xhoneyjar.xyz/"}
                  target="_blank"
                  className="hidden cursor-blue items-center whitespace-nowrap rounded-full bg-[#F4C10B]/80 px-6 py-2.5 font-medium text-white hover:shadow-yellow md:flex"
                  onClick={() => {
                    trackEvent("open_app_navbar");
                  }}
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
                  onClick={() => {
                    trackEvent("delegate_navbar");
                  }}
                >
                  Delegate to THJ
                </a>
              </NavigationMenuItem>
            </NavigationMenuList>
          </NavigationMenu>
          <button
            className="md:hidden"
            onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
          >
            <AnimatePresence mode="wait" initial={false}>
              {mobileMenuOpen ? (
                <motion.div
                  key="close"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.1 }}
                >
                  <X className="text-white" size={24} />
                </motion.div>
              ) : (
                <motion.div
                  key="menu"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.1 }}
                >
                  <Menu className="text-white" size={24} />
                </motion.div>
              )}
            </AnimatePresence>
          </button>
        </div>
      </div>
    </>
  );
};

export default Navbar;
