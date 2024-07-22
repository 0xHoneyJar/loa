import Image from "next/image";
import { motion, useAnimate } from "framer-motion";
import { useEffect, useState } from "react";

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
        <div className="relative aspect-square md:h-[40px] h-[32px]">
          <Image src={"/thj-logo.png"} alt="logo" fill />
        </div>
        <div className="flex flex-col">
          <p className="md:text-base text-xs whitespace-nowrap">The Honey Jar</p>
          <p className="md:text-sm text-[10px] text-[#ABABAB]">@0xhoneyjar</p>
        </div>
      </div>
      <div className="flex h-full w-full overflow-hidden md:p-6 p-4">
        <p className="overflow-y-auto font-light md:text-base text-xs overflow-x-hidden">{text}</p>
      </div>
    </motion.div>
  );
};

export default TwitterDisplay;
