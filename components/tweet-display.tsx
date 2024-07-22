import Image from "next/image";
import { motion, useAnimate } from "framer-motion";
import { useEffect, useState } from "react";

const TwitterDisplay = ({
  text,
  id,
  swipeAction,
}: {
  text: string;
  id: number;
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
      className={`h-full ${id > 1 && "hidden"} ${id == 1 ? "absolute inset-x-0 -top-5 mx-auto !scale-90" : "relative z-10 w-full"}`}
      layout
      transition={{ type: "spring", stiffness: 600, damping: 30 }}
    >
      <motion.div
        className={`flex h-full w-full flex-col divide-y divide-[#292929] rounded-lg ${id == 1 ? "bg-[#1E1E1E]/30" : "bg-[#181818]"} ${drag ? "cursor-grabbing" : "cursor-grab"}`}
        drag="x"
        onDragEnd={handleDragEnd}
        ref={scope}
        onMouseDown={mouseDownHandler}
      >
        <div className="flex items-center gap-2 px-6 py-4">
          <div className="relative aspect-square h-[40px]">
            <Image src={"/thj-logo.png"} alt="logo" fill />
          </div>
          <div className="flex flex-col">
            <p>The Honey Jar</p>
            <p className="text-sm text-[#ABABAB]">@0xhoneyjar</p>
          </div>
        </div>
        <div className="flex h-full w-full overflow-hidden p-6">
          <p className="overflow-y-auto">{text}</p>
        </div>
      </motion.div>
    </motion.div>
  );
};

export default TwitterDisplay;
