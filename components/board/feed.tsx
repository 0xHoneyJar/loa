import Image from "next/image";
import { useEffect, useState } from "react";
import { retrieveTwitterFeed } from "@/actions/retrieve-twitter-feed";
import TwitterDisplay from "../tweet-display";
import SecondaryTweetDisplay from "../secondary-tweet-display";
import { trackEvent } from "@openpanel/nextjs";

const Feed = () => {
  const [tweets, setTweets] = useState<any[]>([]);
  const [tweetNum, setTweetNum] = useState(0);

  useEffect(() => {
    async function retrieveTweets() {
      const data = await retrieveTwitterFeed();
      setTweets(data);
    }

    retrieveTweets();
  }, []);

  const swipeAction = () => {
    // setTweets((prevTweets) => {
    //   const firstElement = prevTweets[0];
    //   const newTweets = [...prevTweets.slice(1), firstElement];
    //   return newTweets;
    // });
    if (tweetNum === tweets.length - 1) {
      setTweetNum(0);
    } else {
      setTweetNum((prevNum) => prevNum + 1);
    }
  };

  return (
    <div
      className={`relative flex h-full flex-col overflow-hidden rounded-2xl border-2 border-[#121A12] bg-[#10120D]`}
    >
      <div className="absolute -top-40 h-1 w-full" id="feed" />
      <div className="flex h-2 w-full shrink-0 rounded-t-3xl bg-[#43AA77]" />
      <div className="relative flex h-16 shrink-0 items-center justify-between border-b border-dashed border-[#FFFFFF1F] px-4 md:h-[72px] md:px-6">
        <div className="flex items-center gap-2">
          <p className="text-base font-medium text-white md:text-lg">Feed</p>
        </div>
        <a
          className="relative aspect-square h-[28px] cursor-blue rounded-full border border-[#353535] md:h-[34px]"
          href={"https://twitter.com/0xhoneyjar"}
          onClick={() => {
            trackEvent(`twitter_feed`);
          }}
          target="_blank"
        >
          <Image
            src={"/twitter.svg"}
            alt="twitter"
            fill
            className="object-contain p-1.5 md:p-2"
          />
        </a>
      </div>
      <div className="flex grow overflow-hidden p-4 pt-6">
        <div className="relative h-full w-full">
          <SecondaryTweetDisplay
            text={tweets[(tweetNum + 1) % (tweets.length - 1)]?.full_text}
          />
          {tweets.map((tweet, id) => (
            <TwitterDisplay
              key={id}
              text={tweet.full_text}
              show={id === tweetNum}
              swipeAction={swipeAction}
            />
          ))}
        </div>
      </div>
    </div>
  );
};

export default Feed;
