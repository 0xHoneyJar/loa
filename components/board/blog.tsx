"use client";

import { ArrowUpRight } from "lucide-react";
import Image from "next/image";
import { useState } from "react";
import { BLOGS } from "@/constants/blog";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselNext,
  CarouselPrevious,
} from "../ui/carousel";
import { trackEvent } from "@openpanel/nextjs";

const Blog = () => {
  return (
    <div
      className={`relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#F8A92952] bg-gradient-to-b from-[#F8A92917] to-[#14131017]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="blog" />
      <Carousel className="flex h-full flex-col" opts={{ dragFree: true }}>
        <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#FFD700]" />
        <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#F4C10B6B] px-4 md:h-[72px] md:px-6">
          <div className="flex items-center gap-2">
            <p className="text-base font-medium text-[#FFD700] md:text-lg">
              Our Blog
            </p>
          </div>
          <div className="relative flex gap-1.5 md:gap-2 lg:hidden">
            <CarouselPrevious className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
            <CarouselNext className="h-6 w-6 border-2 border-[#848484] bg-transparent md:h-7 md:w-7" />
          </div>
        </div>
        {/* <div className="flex grow overflow-hidden p-4 md:p-6"> */}
        <CarouselContent className="flex size-full grow p-4 md:p-6 lg:-ml-0 lg:grid lg:!transform-none lg:grid-cols-4 lg:gap-5 xl:gap-6">
          {/* <div className="flex h-full lg:grid lg:w-full lg:grid-cols-4 lg:gap-5 xl:gap-6"> */}
          {BLOGS.map((blog, id) => (
            <BlogDisplay
              heading={blog.heading}
              description={blog.desc}
              link={blog.link}
              key={id}
              image={blog.image}
            />
          ))}
          <CarouselItem className="lg:pl-0">
            <div className="relative flex h-full w-[178px] items-center justify-center overflow-hidden rounded-xl border border-[#2B2B2B] md:w-[196px] lg:w-full">
              <Image
                src={"/blog.png"}
                alt="blog"
                fill
                className="object-cover"
              />
              <a
                href={"https://0xhoneyjar.mirror.xyz/"}
                target="_blank"
                className="z-10 flex items-center gap-1 whitespace-nowrap rounded-full border border-[#3B3B3B] bg-[#5A5A5A]/30 px-2 py-1 text-xs backdrop-blur-lg transition-all duration-500 ease-in-out hover:border-white/20 hover:bg-white/25 md:px-3 md:py-2 md:text-sm lg:px-4"
                onClick={() => {
                  trackEvent(`read_now_blog`);
                }}
              >
                Read Now
                <ArrowUpRight className="aspect-square h-4 md:h-5" />
              </a>
            </div>
          </CarouselItem>
          {/* </div> */}
        </CarouselContent>
        {/* </div> */}
      </Carousel>
    </div>
  );
};

export default Blog;

const BlogDisplay = ({
  heading,
  description,
  link,
  image,
}: {
  heading: string;
  description: string;
  link: string;
  image: string;
}) => {
  const [hover, setHover] = useState(false);
  return (
    <CarouselItem className="lg:pl-0">
      <div className="relative flex h-full w-[178px] flex-col gap-2 overflow-hidden md:w-[196px] md:gap-3 lg:w-full">
        <a
          onClick={() => {
            trackEvent(`${heading}_blog`);
          }}
          href={link}
          target="_blank"
          onMouseEnter={() => setHover(true)}
          onMouseLeave={() => setHover(false)}
          className={`relative flex h-2/3 w-full shrink-0 overflow-hidden rounded-xl border ${hover ? "border-[#F5D011D9]" : "border-[#2B2B2B]"}`}
        >
          <Image src={image} alt="" fill className="object-cover" />
        </a>
        <div className="flex h-1/3 flex-col gap-1">
          <div className="flex items-center justify-between">
            <p
              className={`truncate whitespace-nowrap text-xs font-medium md:text-base ${hover ? "text-[#F5D011]" : "text-white"}`}
            >
              {heading}
            </p>
            <ArrowUpRight
              className={`aspect-square h-3 shrink-0 md:h-4 lg:h-5 ${hover ? "text-[#F5D011]" : "text-white/15"} `}
            />
          </div>
          <p className="truncate text-[10px] text-[#A9A9A9] md:text-sm">
            {description}
          </p>
        </div>
      </div>
    </CarouselItem>
  );
};
