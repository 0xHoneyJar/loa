import NextImage from "next/image";
import { useState } from "react";

export default function BadgeImage({
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
  const [imgSrc, setImgSrc] = useState(
    "https://d163aeqznbc6js.cloudfront.net/images/" +
      src +
      (width ? `?${new URLSearchParams({ w: width.toString() })}` : ""),
  );

  const handleError = () => {
    setImgSrc(
      "https://d163aeqznbc6js.cloudfront.net/images/faucet/badges/999.png" +
        (width ? `?${new URLSearchParams({ w: width.toString() })}` : ""),
    );
  };

  return (
    <NextImage
      // initial={{ opacity: 0 }}
      // animate={{ opacity: loaded ? 1 : 0 }}
      // transition={{ duration: 0.5 }}
      // src={
      //   "https://d163aeqznbc6js.cloudfront.net/images/" +
      //   src +
      //   (width ? `?${new URLSearchParams({ w: width.toString() })}` : "")
      // }
      src={imgSrc}
      alt={alt}
      className={`${className} object-center ${fill ? "h-full w-full" : ""}`}
      onLoad={() => setLoaded(true)}
      fill={fill}
      onError={handleError}
    />
  );
}
