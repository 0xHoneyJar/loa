import NextImage from "next/image";
import { useState } from "react";

export default function PartnerImage({
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
    setImgSrc("/partners/perk_placeholder.png");
  };

  return (
    <NextImage
      src={imgSrc}
      alt={alt}
      className={`${className} object-center ${fill ? "h-full w-full" : ""}`}
      onLoad={() => setLoaded(true)}
      fill={fill}
      onError={handleError}
    />
  );
}
