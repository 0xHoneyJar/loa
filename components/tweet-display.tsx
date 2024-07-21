import Image from "next/image";

const TwitterDisplay = ({text}: {text:string}) => {
  return (
    <div className="flex h-full w-full flex-col divide-y divide-[#292929] rounded-lg bg-[#181818]">
      <div className="flex gap-2 px-6 py-4 items-center">
        <div className="relative aspect-square h-[40px]">
          <Image src={"/thj-logo.png"} alt="logo" fill />
        </div>
        <div className="flex flex-col">
          <p>The Honey Jar</p>
          <p className="text-sm text-[#ABABAB]">@0xhoneyjar</p>
        </div>
      </div>
      <div className="flex h-full w-full p-6 overflow-hidden">
        <p className="overflow-y-auto">
          Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc
          vulputate libero et velit interdum, ac aliquet odio mattis.
        </p>
      </div>
    </div>
  );
};

export default TwitterDisplay;
