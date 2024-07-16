import NextImage from "next/image";
import { useState } from "react";

export default function S3Image({
  src,
  alt,
  width,
  className,
  fill,
}: {
  src: string;
  alt: string;
  width?: number;
  height?: number;
  className?: string;
  fill?: boolean;
}) {
  const [loaded, setLoaded] = useState(false);

  return (
    <NextImage
      // initial={{ opacity: 0 }}
      // animate={{ opacity: loaded ? 1 : 0 }}
      // transition={{ duration: 0.5 }}
      src={
        "https://d163aeqznbc6js.cloudfront.net/images/" +
        src +
        (width ? `?${new URLSearchParams({ w: width.toString() })}` : "")
      }
      alt={alt}
      className={`${className} object-center ${fill ? "h-full w-full" : ""}`}
      onLoad={() => setLoaded(true)}
      fill={fill}
    />
  );
}
