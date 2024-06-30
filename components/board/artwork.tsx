import Image from "next/image";
import Marquee from "react-fast-marquee";

const Artwork = () => {
  const ARTWORK = [
    "/artwork/artwork-0.png",
    "/artwork/artwork-1.png",
    "/artwork/artwork-2.png",
    "/artwork/artwork-3.png",
  ];
  return (
    <div className="relative flex flex-col border-2 bg-[#0F0F0F] rounded-2xl border-[#FFFFFF0A] overflow-hidden h-full">
      <div className="absolute -top-40 w-full h-1" id="artwork" />
      <div className="w-full h-2 bg-white rounded-t-3xl" />
      <div className="flex justify-between items-center px-6 h-16 border-b border-dashed border-[#FFFFFF1F]">
        <div className="flex gap-2 items-center">
          <div className="h-[26px] aspect-square relative dragHandle">
            <Image
              src={"/drag-handle.svg"}
              alt="drag"
              fill
              className="object-contain"
            />
          </div>
          <p className="text-white text-lg">Our Arts and Memes</p>
        </div>
      </div>
      <Marquee
        autoFill
        speed={25}
        gradient
        gradientColor="#0F0F0F"
        gradientWidth={50}
        className="flex grow items-center"
      >
        <div className="flex">
          {ARTWORK.map((item, id) => (
            <div className="relative h-[200px] aspect-square mx-2 rounded-lg overflow-hidden" key={id}>
              <Image
                src={item}
                alt={"artwork-" + id}
                fill
                className="object-cover"
              />
            </div>
          ))}
        </div>
      </Marquee>
    </div>
  );
};

export default Artwork;
