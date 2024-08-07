import { motion, AnimatePresence } from "framer-motion";
import { usePathname } from "next/navigation";
import { X } from "lucide-react";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { DASHBOARD } from "@/constants/dashboard";
import { ScrollArea } from "./ui/scroll-area";

const Sidebar = ({
  open,
  setOpen,
}: {
  open: boolean;
  setOpen: React.Dispatch<React.SetStateAction<boolean>>;
}) => {
  const closeSidebarHandler = () => {
    setOpen(false);
  };

  const menuVars = {
    initial: { scaleY: 0 },
    animate: {
      scaleY: 1,
      transition: { duration: 0.5, ease: [0.12, 0, 0.39, 0] },
    },
    exit: {
      scaleY: 0,
      transition: { delay: 0.5, duration: 0.5, ease: [0.22, 1, 0.36, 1] },
    },
  };

  const mobileLinkVars = {
    initial: {
      y: "20vh",
      transition: {
        duration: 0.5,
        ease: [0.37, 0, 0.63, 1],
      },
    },
    open: {
      y: 0,
      transition: { duration: 0.7, ease: [0, 0.55, 0.45, 1] },
    },
  };

  const containerVars = {
    initial: {
      transition: { staggerChildren: 0.09, staggerDirection: -1 },
    },
    open: {
      transition: {
        delayChildren: 0.4,
        staggerChildren: 0.1,
        staggerDirection: 1,
      },
    },
  };

  const pathname = usePathname();

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          variants={menuVars}
          initial="initial"
          animate="animate"
          exit="exit"
          className="fixed z-40 flex h-full w-full origin-top items-center bg-[#0e0e0f] text-white md:hidden"
        >
          <button
            className="absolute right-10 top-10 flex cursor-blue items-center justify-end text-xl"
            onClick={closeSidebarHandler}
          >
            <X size={28} />
          </button>
          <motion.div
            variants={containerVars}
            initial="initial"
            animate="open"
            exit="initial"
            className="flex size-full flex-col items-center justify-center gap-6 text-lg text-white"
          >
            {pathname === "/" ? (
              <>
                <div className="overflow-hidden">
                  <motion.div
                    onClick={closeSidebarHandler}
                    variants={mobileLinkVars}
                  >
                    <a
                      className="hover:cursor-blue hover:text-[#FFC500]"
                      href={"https://www.0xhoneyjar.xyz/"}
                      target="_blank"
                    >
                      Open App
                    </a>
                  </motion.div>
                </div>
                <div className="overflow-hidden">
                  <motion.div
                    onClick={closeSidebarHandler}
                    variants={mobileLinkVars}
                  >
                    <a
                      className="hover:cursor-blue hover:text-[#FFC500]"
                      href={
                        "https://bartio.station.berachain.com/delegate?action=delegate&validator=0x40495A781095932e2FC8dccA69F5e358711Fdd41"
                      }
                      target="_blank"
                    >
                      Delegate to THJ
                    </a>
                  </motion.div>
                </div>
                <div className="overflow-hidden">
                  <Accordion type="single" collapsible className="w-full">
                    <AccordionItem value="item-1" className="border-0">
                      <AccordionTrigger className="w-[100px] cursor-blue gap-2 py-0 hover:text-[#FFC500] hover:no-underline">
                        <motion.div
                          // onClick={closeSidebarHandler}
                          variants={mobileLinkVars}
                        >
                          <p className="">Section</p>
                        </motion.div>
                      </AccordionTrigger>
                      <AccordionContent>
                        <ScrollArea className="h-[150px]">
                          <div className="flex flex-col gap-2">
                            {DASHBOARD.map(
                              (section, id) =>
                                !section.hidden && (
                                  <button
                                    key={id}
                                    // value={section.key}
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
                                    className="cursor-blue rounded-lg px-8 py-3 text-left text-sm text-[#E7E7E7] hover:bg-[#FFFFFF2E] hover:font-medium hover:text-white"
                                  >
                                    {section.name}
                                  </button>
                                ),
                            )}
                          </div>
                        </ScrollArea>
                      </AccordionContent>
                    </AccordionItem>
                  </Accordion>
                </div>
              </>
            ) : (
              <div className="overflow-hidden">
                <motion.div
                  onClick={closeSidebarHandler}
                  variants={mobileLinkVars}
                >
                  <a href="/" className="hover:text-[#FFC500]">
                    Home
                  </a>
                </motion.div>
              </div>
            )}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};

export default Sidebar;
