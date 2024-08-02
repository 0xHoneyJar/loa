import Image from "next/image";
import { motion, useAnimate } from "framer-motion";
import { useEffect, useState } from "react";
import { ScrollArea } from "./ui/scroll-area";

const TwitterDisplay = ({
  text,
  show,
  swipeAction,
}: {
  text: string;
  show: boolean;
  swipeAction: () => void;
}) => {
  const [scope, animate] = useAnimate();
  const [drag, setDrag] = useState(false);

  function handleDragEnd(_: any, info: any) {
    const offset = info.offset.x;
    const velocity = info.velocity.x;

    if (offset < -100 || velocity < -500) {
      animate(scope.current, { x: "-100%" }, { duration: 0.2 });
      setTimeout(() => {
        swipeAction();
      }, 200);
    } else {
      animate(scope.current, { x: 0, opacity: 1 }, { duration: 0.5 });
    }
  }

  const mouseDownHandler = () => {
    setDrag(true);
  };

  useEffect(() => {
    const handleMouseUp = () => {
      setDrag(false);
    };

    window.addEventListener("mouseup", handleMouseUp);

    return () => {
      window.removeEventListener("mouseup", handleMouseUp);
    };
  }, []);

  return (
    <motion.div
      className={`relative flex h-full w-full flex-col divide-y divide-[#292929] rounded-lg bg-[#181818] ${drag ? "cursor-grabbing" : "cursor-grab"} ${!show ? "hidden" : ""}`}
      drag="x"
      animate={
        show
          ? { scale: 1, opacity: 1 }
          : { scale: 0.9, opacity: 0, x: 0, y: -24 }
      }
      transition={{ duration: 0.3 }}
      onDragEnd={handleDragEnd}
      ref={scope}
      onMouseDown={mouseDownHandler}
    >
      <div className="flex items-center gap-2 px-6 py-4">
        <div className="relative aspect-square h-[32px] md:h-[40px]">
          <Image src={"/thj-logo.png"} alt="logo" fill />
        </div>
        <div className="flex flex-col">
          <p className="whitespace-nowrap text-xs md:text-base">
            The Honey Jar
          </p>
          <p className="text-[10px] text-[#ABABAB] md:text-sm">@0xhoneyjar</p>
        </div>
      </div>
      <div className="flex h-full w-full overflow-hidden p-4 md:p-6">
        <ScrollArea>
          <p className="text-xs font-light md:text-sm">{text}</p>
        </ScrollArea>
      </div>
    </motion.div>
  );
};

export default TwitterDisplay;
