import NextImage from "next/image";

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
  return (
    <NextImage
      src={
        "https://d163aeqznbc6js.cloudfront.net/images/" +
        src +
        (width ? `?${new URLSearchParams({ w: width.toString() })}` : "")
      }
      alt={alt}
      className={`${className} object-center ${fill ? "h-full w-full" : ""}`}
      fill={fill}
    />
  );
}
