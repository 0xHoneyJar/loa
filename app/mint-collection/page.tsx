import ExploreMint from "@/components/explore-mint";
import { basehub } from "basehub";

const Page = async () => {
  const { community } = await basehub({ cache: "no-store" }).query({
    community: {
      mints: {
        items: {
          _title: true,
          price: true,
          supply: true,
          link: true,
          image: true,
          endDate: true,
          partner: {
            logo: true,
            _title: true,
          },
        },
      },
    },
  });

  return <ExploreMint mints={community.mints} />;
};

export default Page;
