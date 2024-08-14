import { motion, AnimatePresence } from "framer-motion";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { DASHBOARD } from "@/constants/dashboard";
import { ScrollArea } from "./ui/scroll-area";
import { trackEvent } from "@openpanel/nextjs";
import * as NavigationMenu from "@radix-ui/react-navigation-menu";
import { useState } from "react";
import { ChevronDown } from "lucide-react";
import { EXPLOREITEMS } from "@/constants/explore";
import { ListItem } from "./explore";

const Sidebar = ({
  open,
  setOpen,
}: {
  open: boolean;
  setOpen: React.Dispatch<React.SetStateAction<boolean>>;
}) => {
  const [isExploreOpen, setIsExploreOpen] = useState(false);
  const [isSectionOpen, setIsSectionOpen] = useState(false);

  const mobileNavVariants = {
    hidden: { opacity: 0, y: 10 },
    visible: (i: number) => ({
      opacity: 1,
      y: 0,
      transition: {
        delay: i * 0.05,
        duration: 0.3,
        ease: "easeOut",
      },
    }),
  };

  const closeSidebarHandler = () => {
    setOpen(false);
  };

  return (
    <>
      {open && (
        <motion.div
          initial="hidden"
          animate="visible"
          className="fixed inset-0 top-[65px] z-30 flex h-[calc(100vh-65px)] w-full flex-col overflow-y-auto bg-[#72727212] p-6 pb-32 font-switzer text-white backdrop-blur-xl transition-all duration-300 ease-linear md:hidden"
        >
          <NavigationMenu.Root>
            <NavigationMenu.List className="flex flex-col">
              <motion.div custom={0} variants={mobileNavVariants}>
                <NavigationMenu.Item className="border-b border-white/10 py-3">
                  <NavigationMenu.Trigger
                    className="group flex w-full items-center justify-between text-white"
                    onClick={() => setIsExploreOpen(!isExploreOpen)}
                  >
                    <span>Explore</span>
                    <ChevronDown
                      className="relative top-px aspect-square h-4 transition-transform duration-300 ease-in group-data-[state=open]:-rotate-180"
                      aria-hidden
                    />
                  </NavigationMenu.Trigger>
                  <AnimatePresence initial={false}>
                    {isExploreOpen && (
                      <motion.div
                        initial={{ height: 0, opacity: 0 }}
                        animate={{ height: "auto", opacity: 1 }}
                        exit={{ height: 0, opacity: 0 }}
                        transition={{ duration: 0.3, ease: "easeInOut" }}
                      >
                        <NavigationMenu.Content className="mt-2 overflow-hidden">
                          <motion.div
                            initial={{ y: -10, opacity: 0 }}
                            animate={{ y: 0, opacity: 1 }}
                            exit={{ y: -10, opacity: 0 }}
                            transition={{ duration: 0.2, delay: 0.1 }}
                          >
                            <div className="flex flex-col gap-0">
                              {EXPLOREITEMS.map((item, index) => (
                                <ListItem
                                  key={item.title}
                                  {...item}
                                  style={{
                                    transition: `opacity 0.3s ease, transform 0.3s ease ${index * 0.05}s`,
                                  }}
                                />
                              ))}
                            </div>
                          </motion.div>
                        </NavigationMenu.Content>
                      </motion.div>
                    )}
                  </AnimatePresence>
                </NavigationMenu.Item>
              </motion.div>
              <motion.div custom={1} variants={mobileNavVariants}>
                <NavigationMenu.Item className="border-b border-white/10 py-3">
                  <NavigationMenu.Trigger
                    className="group flex w-full items-center justify-between text-white"
                    onClick={() => setIsSectionOpen(!isSectionOpen)}
                  >
                    <span>Section</span>
                    <ChevronDown
                      className="relative top-px aspect-square h-4 transition-transform duration-300 ease-in group-data-[state=open]:-rotate-180"
                      aria-hidden
                    />
                  </NavigationMenu.Trigger>
                  <AnimatePresence initial={false}>
                    {isSectionOpen && (
                      <motion.div
                        initial={{ height: 0, opacity: 0 }}
                        animate={{ height: "auto", opacity: 1 }}
                        exit={{ height: 0, opacity: 0 }}
                        transition={{ duration: 0.3, ease: "easeInOut" }}
                      >
                        <NavigationMenu.Content className="mt-2 overflow-hidden">
                          <motion.div
                            initial={{ y: -10, opacity: 0 }}
                            animate={{ y: 0, opacity: 1 }}
                            exit={{ y: -10, opacity: 0 }}
                            transition={{ duration: 0.2, delay: 0.1 }}
                          >
                            <ScrollArea className="h-[350px]">
                              <div className="flex flex-col gap-2">
                                {DASHBOARD.map(
                                  (section, id) =>
                                    !section.hidden && (
                                      <button
                                        key={id}
                                        onClick={() => {
                                          const id = document?.getElementById(
                                            section.key,
                                          );
                                          id &&
                                            id.scrollIntoView({
                                              behavior: "smooth",
                                            });
                                          closeSidebarHandler();
                                        }}
                                        className="rounded-lg px-4 py-3 text-left text-sm text-white"
                                      >
                                        {section.name}
                                      </button>
                                    ),
                                )}
                              </div>
                            </ScrollArea>
                          </motion.div>
                        </NavigationMenu.Content>
                      </motion.div>
                    )}
                  </AnimatePresence>
                </NavigationMenu.Item>
              </motion.div>
              <motion.a
                custom={2}
                variants={mobileNavVariants}
                href="https://discord.com/invite/thehoneyjar"
                target="_blank"
                onClick={() => {
                  trackEvent("join_us_discord_navbar");
                }}
                className="border-b border-white/10 py-3 text-white"
              >
                Join Us
              </motion.a>

              <motion.a
                custom={3}
                variants={mobileNavVariants}
                href="https://app.0xhoneyjar.xyz/"
                target="_blank"
                onClick={() => {
                  trackEvent("open_app_navbar");
                }}
                className="border-b border-white/10 py-3 text-white"
              >
                Open App
              </motion.a>
              <motion.a
                custom={4}
                variants={mobileNavVariants}
                href="https://bartio.station.berachain.com/delegate?action=delegate&validator=0x40495A781095932e2FC8dccA69F5e358711Fdd41"
                target="_blank"
                onClick={() => {
                  trackEvent("delegate_to_thj_navbar");
                }}
                className="border-b border-white/10 py-3 text-white"
              >
                Delegate to THJ
              </motion.a>
            </NavigationMenu.List>
          </NavigationMenu.Root>
        </motion.div>
      )}
    </>
  );
};

export default Sidebar;
