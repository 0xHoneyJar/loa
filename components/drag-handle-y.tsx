import { motion } from "framer-motion";
import Image from "next/image";

const DragHandleY = () => {
  return (
    <div className="dragHandle relative aspect-square h-[26px]">
      <Image
        src={"/drag-handle-y.svg"}
        alt="drag"
        fill
        className="object-contain"
      />
    </div>
  );
}

export default DragHandleY