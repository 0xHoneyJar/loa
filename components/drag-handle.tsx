import Image from "next/image";
import { motion } from "framer-motion";

const DragHandle = () => {
  return (
    <motion.div
      className="dragHandle relative aspect-square h-[26px] cursor-grab"
      whileTap={{
        cursor: "url('/grabbing.svg'), grabbing",
      }}
    >
      <Image
        src={"/drag-handle.svg"}
        alt="drag"
        fill
        className="object-contain"
      />
    </motion.div>
  );
}

export default DragHandle