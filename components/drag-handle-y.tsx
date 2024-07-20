import Image from "next/image";
import { useEffect, useState } from "react";

const DragHandleY = ({
  setGlow,
}: {
  setGlow: React.Dispatch<React.SetStateAction<boolean>>;
}) => {
  const [drag, setDrag] = useState(false);
  const mouseDownHandler = () => {
    setDrag(true);
    setTimeout(() => {
      setGlow(true);
    }, 300);
  };

  useEffect(() => {
    const handleMouseUp = () => {
      setDrag(false);
      setGlow(false);
    };

    window.addEventListener("mouseup", handleMouseUp);

    return () => {
      window.removeEventListener("mouseup", handleMouseUp);
    };
  }, []);


  return (
    <div
      onMouseDown={mouseDownHandler}
      className={`dragHandle relative aspect-square h-5 md:h-[26px] ${drag ? "cursor-grabbing" : "cursor-grab"}`}
    >
      <Image
        src={"/drag-handle-y.svg"}
        alt="drag"
        fill
        className="object-contain"
      />
    </div>
  );
};

export default DragHandleY