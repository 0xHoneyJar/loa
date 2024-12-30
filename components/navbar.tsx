"use client";

import Image from "next/image";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import Sidebar from "@/components/sidebar";
import SectionSelect from "./section-select";
import { AnimatePresence, motion } from "framer-motion";
import {
  NavigationMenu,
  NavigationMenuItem,
  NavigationMenuList,
} from "@/components/ui/navigation-menu";
import Explore from "./explore";
import { Copy, Menu, X, Download } from "lucide-react";
import { trackEvent } from "@openpanel/nextjs";
import { ValidatorWidget } from "@0xhoneyjar/validator-widget";
import { usePathname } from "next/navigation";

const Navbar = () => {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [contextMenu, setContextMenu] = useState({ isOpen: false });
  const pathname = usePathname();

  const handleLogoContextMenu = (e: React.MouseEvent) => {
    e.preventDefault();
    setContextMenu({
      isOpen: true,
    });
  };

  const closeContextMenu = () => {
    setContextMenu({ ...contextMenu, isOpen: false });
  };

  useEffect(() => {
    const handleClickOutside = () => closeContextMenu();
    document.addEventListener("click", handleClickOutside);
    return () => document.removeEventListener("click", handleClickOutside);
  }, []);

  return (
    <>
      <Sidebar open={mobileMenuOpen} setOpen={setMobileMenuOpen} />
      <div
        className="fixed inset-x-0 top-0 z-30 mx-auto flex w-full justify-between border-b border-[#FFFFFF14] bg-[#7272721F] backdrop-blur-xl md:top-5 md:w-fit md:rounded-full md:border lg:gap-24"
        // style={{ boxShadow: "0px 2px 56px #0000001F" }}
      >
        <div className="flex items-center gap-2 border-r border-white/10 px-4 py-3 md:gap-3 md:py-2">
          <div
            className="relative size-10 cursor-pointer"
            onContextMenu={handleLogoContextMenu}
          >
            <Link href="/" onClick={(e) => e.stopPropagation()}>
              <Image src="/globe.png" alt="" fill className="object-contain" />
            </Link>
            <LogoContextMenu
              isOpen={contextMenu.isOpen}
              onClose={closeContextMenu}
            />
          </div>
          <p className="hidden whitespace-nowrap text-[10px] text-white md:flex md:text-xs">
            For Community
          </p>
        </div>
        <div className="flex items-center px-4 py-2">
          {/* <div className=""> */}
          <NavigationMenu className="hidden items-center md:flex">
            <NavigationMenuList className="text-sm md:space-x-3">
              <Explore />
              {pathname === "/" && <SectionSelect />}
              <NavigationMenuItem>
                <a
                  href={"https://0xhoneyjar.mirror.xyz/"}
                  target="_blank"
                  className="hidden h-[38px] items-center whitespace-nowrap rounded-full bg-[#FFFFFF0F] px-6 text-white hover:bg-white/30 md:flex"
                  onClick={() => {
                    trackEvent("open_blog_navbar");
                  }}
                >
                  Blog
                </a>
              </NavigationMenuItem>
              <NavigationMenuItem>
                <a
                  href={"https://app.0xhoneyjar.xyz/"}
                  target="_blank"
                  className="hidden h-[38px] items-center whitespace-nowrap rounded-full bg-[#F4C10B]/80 px-6 text-white hover:shadow-yellow md:flex"
                  onClick={() => {
                    trackEvent("open_app_navbar");
                  }}
                >
                  Open App
                </a>
              </NavigationMenuItem>
              <NavigationMenuItem>
                {/* <a
                  href={
                    "https://bartio.station.berachain.com/delegate?action=delegate&validator=0x40495A781095932e2FC8dccA69F5e358711Fdd41"
                  }
                  target="_blank"
                  className="hidden items-center whitespace-nowrap rounded-full bg-[#43AA77] px-6 py-2.5 font-medium text-white hover:shadow-evergreen md:flex"
                  onClick={() => {
                    trackEvent("delegate_navbar");
                  }}
                >
                  Delegate to THJ
                </a> */}
                <ValidatorWidget apiUrl="/api/delegate" referrer="thj" />
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

interface LogoContextMenuProps {
  isOpen: boolean;
  onClose: () => void;
}

const LogoContextMenu: React.FC<LogoContextMenuProps> = ({
  isOpen,
  onClose,
}) => {
  const handleCopyLogo = useCallback(async () => {
    try {
      const response = await fetch("/globe.svg");
      const svgText = await response.text();

      await navigator.clipboard.writeText(svgText);
      console.log("Logo SVG copied to clipboard");
    } catch (error) {
      console.error("Failed to copy logo:", error);
    } finally {
      onClose();
    }
  }, [onClose]);

  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.95 }}
          transition={{ duration: 0.1 }}
          className="absolute -left-20 top-[calc(100%+8px)] z-50 w-48 -translate-x-1/2 overflow-hidden rounded-lg border border-[#66666632] bg-[#0D0D0D] p-1 text-white"
        >
          <div className="flex flex-col">
            <button
              onClick={handleCopyLogo}
              className="flex w-full items-center whitespace-nowrap rounded-sm p-2 text-sm text-[#D4D4D4] hover:bg-[#2B2B2B45]"
            >
              <Copy className="mr-2 size-4" />
              Copy Logo (SVG)
            </button>
            <a
              href="/thj/THJ_Brandkit.zip"
              download
              className="flex w-full items-center whitespace-nowrap rounded-sm p-2 text-sm text-[#D4D4D4] hover:bg-[#2B2B2B45]"
            >
              <Download className="mr-2 size-4" />
              Download Branding Kit
            </a>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};
