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
          className="fixed z-40 flex h-screen w-screen origin-top items-center bg-[#0e0e0f] text-white md:hidden"
        >
          <button
            className="absolute right-0 top-0 flex h-20 cursor-pointer items-center justify-end px-10 text-xl"
            onClick={closeSidebarHandler}
          >
            <X size={28} />
          </button>
          <motion.div
            variants={containerVars}
            initial="initial"
            animate="open"
            exit="initial"
            className="flex h-full w-full flex-col items-center justify-center gap-6 text-lg text-white"
          >
            {pathname === "/" ? (
              <>
                <div className="overflow-hidden">
                  <Accordion type="single" collapsible className="w-full">
                    <AccordionItem value="item-1">
                      <AccordionTrigger>
                        <motion.div
                          // onClick={closeSidebarHandler}
                          variants={mobileLinkVars}
                        >
                          <p className="hover:text-[#FFC500]">Section</p>
                        </motion.div>
                      </AccordionTrigger>
                      <AccordionContent className="max-h-[100px] overflow-y-auto">
                        {DASHBOARD.map(
                          (section, id) =>
                            !section.hidden && (
                              <div
                                key={id}
                                className="rounded-lg bg-[#121212] py-3 text-sm text-[#E7E7E7] focus:bg-[#F8A9292E] focus:text-[#FFD700]"
                              >
                                {section.name}
                              </div>
                            ),
                        )}
                      </AccordionContent>
                    </AccordionItem>
                  </Accordion>
                </div>
                <div className="overflow-hidden">
                  <motion.div
                    onClick={closeSidebarHandler}
                    variants={mobileLinkVars}
                  >
                    <a className="hover:cursor-blue hover:text-[#FFC500]">
                      Join Us
                    </a>
                  </motion.div>
                </div>
                <div className="overflow-hidden">
                  <motion.div
                    onClick={closeSidebarHandler}
                    variants={mobileLinkVars}
                  >
                    <a className="hover:cursor-blue hover:text-[#FFC500]">
                      Delegate to THJ
                    </a>
                  </motion.div>
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
